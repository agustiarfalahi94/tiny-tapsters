import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../services/app_language.dart';
import '../services/kid_safety.dart';
import '../services/pollie_service.dart';
import '../widgets/game_background.dart';
import '../widgets/pollie_bird.dart';
import '../widgets/round_button.dart';

enum _PollieStatus { sleeping, awake, listening, thinking, speaking }

/// Pollie 🦜 — a talking companion powered by Gemini.
///
/// Pollie sleeps 😴 while offline and smiles 😊 once Gemini answers a
/// connectivity probe, then greets the child. Tap the 🎤 to talk: speech is
/// transcribed (Google speech-to-text), answered by Gemini, and spoken aloud
/// (system TTS) — then Pollie listens again automatically, so a toddler can
/// just keep chatting like in the Gemini app. Toddlers can also tap the big
/// chips; grown-ups can type.
/// Joins what a recogniser session produced onto what earlier sessions did.
///
/// A session ending must not lose its words: the next session assigns to the
/// partial rather than appending, so anything not banked here disappears. That
/// is how "do you know about minecraft?" became "know minecraft".
///
/// Skips a restatement, because some recognisers repeat the whole utterance in
/// the following session and appending both would stutter.
String appendHeard(String banked, String pending) {
  final tail = pending.trim();
  if (tail.isEmpty) return banked;
  if (banked.isEmpty) return tail;
  if (banked.endsWith(tail)) return banked;
  // The next session often restarts from a word or two back; drop the overlap
  // rather than repeat it.
  final words = tail.split(RegExp(r'\s+'));
  for (var take = words.length; take > 0; take--) {
    final overlap = words.take(take).join(' ');
    if (banked.endsWith(overlap)) {
      final rest = words.skip(take).join(' ');
      return rest.isEmpty ? banked : '$banked $rest';
    }
  }
  return '$banked $tail';
}

/// End of a sentence: terminal punctuation, any closing quote or bracket,
/// then whitespace or the end of the text. Requiring that trailing whitespace
/// is what keeps "3.5" in one piece.
final _sentenceEnd = RegExp(r'[.!?…]+["\u2019\u201d)\]]*(\s|$)');

/// Index just past the last *complete* sentence at or after [from], or [from]
/// itself when nothing new has finished.
///
/// This is what lets Pollie start talking while the rest of her reply is still
/// being generated, instead of the child waiting for generation and synthesis
/// one after the other.
int lastSentenceEnd(String text, int from) {
  var cut = from;
  for (final match in _sentenceEnd.allMatches(text, from)) {
    cut = match.end;
  }
  return cut;
}

class CompanionScreen extends StatefulWidget {
  const CompanionScreen({super.key, this.pollie});

  /// Injectable for tests; production builds its own, pointed at the proxy.
  final PollieService? pollie;

  @override
  State<CompanionScreen> createState() => _CompanionScreenState();
}

class _CompanionScreenState extends State<CompanionScreen>
    with WidgetsBindingObserver {
  /// Rebuilt per read, because the language can change under it.
  List<String> get _chips => [
    strings.chipStory,
    strings.chipSong,
    strings.chipCow,
    strings.chipHow,
    strings.chipFact,
    strings.chipLove,
  ];

  /// Emoji (and symbol) ranges, stripped before speaking so the TTS only
  /// reads plain text. Includes variation selectors and ZWJ sequences.
  static final _emojiPattern = RegExp(
    r'[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}'
    r'\u{2190}-\u{21FF}\u{25A0}-\u{25FF}\u{FE0F}\u{200D}\u{20E3}'
    r'\u{1F1E6}-\u{1F1FF}\u{00A9}\u{00AE}\u{2122}\u{203C}\u{2049}'
    r'\u{3030}\u{303D}]',
    unicode: true,
  );

  late final _pollie = widget.pollie ?? PollieService();
  final _history = <ChatMessage>[];
  final _bubbles = <_Bubble>[];
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _tts = FlutterTts();
  final _speech = SpeechToText();
  _PollieStatus _status = _PollieStatus.sleeping;
  bool _waking = false;
  bool _busy = false;
  bool _speechAvailable = false;
  String _localeId = 'en-US';
  String _partial = '';
  double _soundLevel = 0;
  int _listenRetries = 0;

  // --- one listening "turn" -------------------------------------------------
  //
  // Android's recogniser has two silence timers. `pauseFor` sets the long
  // "definitely finished" one; the short "possibly finished" one — around
  // 500ms on most devices — is set by an intent extra
  // (EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS) that
  // speech_to_text never sets and does not expose. That short timer is what
  // ends a session while a child is still thinking mid-sentence.
  //
  // So a turn is no longer one recogniser session. A session ending banks its
  // words and re-arms the mic; the turn itself ends only when the child taps
  // the mic, the 45s cap fires, a real error arrives, or the app goes to the
  // background.
  //
  // An earlier version of this tried the same thing and was reverted, because
  // `onResult(finalResult: true)` and `onStatus('done')` both fire for one
  // session ending and both called restart — racing each other into
  // "recognizer busy" and leaving the mic dead. `_restarting` is the missing
  // piece: only the first of the two callers gets to restart, and it clears
  // the flag once `listen()` has resolved. Do not remove that guard.
  //
  // The restart costs a few hundred milliseconds of dead air. That is a real
  // cost, but it is only paid where the recogniser decided the child had
  // stopped talking — which is exactly where there is least speech to lose.

  static const _quietWindow = Duration(seconds: 3);

  /// Hard stop, so a turn can never leave the mic live forever.
  static const _maxTurn = Duration(seconds: 45);

  /// How long the child has to be quiet, *after saying something*, before the
  /// turn ends by itself and gets an answer.
  ///
  /// Long enough to think mid-sentence — the recogniser's own half-second
  /// guess is what caused the cutting-off — and short enough that the
  /// conversation still feels hands-free.
  static const _quietEndsTurn = Duration(seconds: 4);

  /// How long the mic waits when it has understood *nothing at all* before
  /// giving up and closing.
  ///
  /// The recogniser reports plenty of activity while transcribing nothing —
  /// on the test device it restarted every second or two with empty results.
  /// Arming the timer only on recognised words meant that in a noisy room, or
  /// with a child who mumbles, the timer never started and the mic sat open
  /// until the 45-second cap. This closes it quietly instead, with nothing
  /// sent, so the child can simply tap and try again.
  static const _silenceGivesUp = Duration(seconds: 12);

  /// Everything the turn's finished sessions have produced so far. A turn now
  /// spans however many sessions the recogniser decides to end, so this
  /// accumulates across all of them; `_partial` holds whatever the live
  /// session is still guessing.
  String _heard = '';
  Timer? _turnTimer;
  Timer? _quietTimer;

  /// One-shot: fires if the whole turn goes by without a single recognised
  /// word. Deliberately *not* re-armed — the recogniser reports activity
  /// constantly while transcribing nothing, so anything re-armed by activity
  /// is postponed forever and the mic never closes.
  Timer? _nothingHeardTimer;
  bool _turnActive = false;

  /// Single-flight guard around re-arming the mic. Both `onResult`'s final
  /// branch and `onStatus('done')` fire for one session ending; without this
  /// they race into "recognizer busy" and the turn goes deaf.
  bool _restarting = false;

  /// What the child has said so far this turn: banked words plus whatever the
  /// recogniser is currently guessing.
  String get _transcript =>
      [_heard, _partial].where((s) => s.isNotEmpty).join(' ');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initTts();
    _initSpeechLocale();
    if (_pollie.isConfigured) {
      _bubbles.add(_Bubble(role: 'model', text: ''));
      _wakeUp();
    } else {
      _bubbles.add(
        _Bubble(
          role: 'model',
          text:
              "Hi! I'm Pollie! 🦜 I can't talk yet — ask a grown-up to "
              'give me my magic key! 🔑',
        ),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Never leave the mic, a pending turn, or the TTS engine running after
    // leaving Pollie.
    _turnActive = false;
    _turnTimer?.cancel();
    _quietTimer?.cancel();
    _nothingHeardTimer?.cancel();
    try {
      _speech.stop();
      _tts.stop();
    } catch (_) {}
    _pollie.dispose();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      // No mic/TTS while the app is in the background. Drop the turn rather
      // than sending half a sentence the child never finished.
      _turnActive = false;
      _turnTimer?.cancel();
      _quietTimer?.cancel();
      _nothingHeardTimer?.cancel();
      _heard = '';
      try {
        _speech.stop();
        _tts.stop();
      } catch (_) {}
      if (mounted && _status == _PollieStatus.listening) {
        setState(() {
          _status = _PollieStatus.awake;
          _busy = false;
          _partial = '';
        });
      }
    }
  }

  /// Queue mode 1 is "add to the queue" — without it every new sentence
  /// would interrupt the one before, which is precisely what speaking
  /// sentence by sentence must not do.
  Future<void> _initTts() async {
    try {
      await _tts.setQueueMode(1);
      _tts.setCompletionHandler(_onUtteranceComplete);
      _tts.setCancelHandler(_onUtteranceComplete);
      _tts.setErrorHandler((message) {
        debugPrint('Pollie TTS error: $message');
        _onUtteranceComplete();
      });
    } catch (e) {
      debugPrint('Pollie TTS setup failed: $e');
    }
  }

  /// Picks the speech recognition locale from the device language
  /// (Indonesian or English), falling back to en-US.
  Future<void> _initSpeechLocale() async {
    try {
      _localeId = AppLanguageService.instance.current.value.localeId;
      final available = await _speech.initialize(
        onError: _onSpeechError,
        onStatus: (status) {
          if (status != 'done' || !mounted) return;
          // A session ended, not the turn. Re-arm and keep listening; the
          // child decides when they are finished, not the recogniser.
          if (_turnActive) {
            _restartSession();
            return;
          }
          _listenRetries = 0;
          setState(() {
            if (_status == _PollieStatus.listening) {
              _status = _PollieStatus.awake;
              _busy = false;
              _partial = '';
            }
          });
        },
      );
      if (!mounted) return;
      setState(() => _speechAvailable = available);
      if (available) {
        final lang = (await _speech.systemLocale())?.localeId ?? '';
        if (lang.startsWith('id') || lang.startsWith('in')) {
          _localeId = 'id-ID';
        } else if (lang.startsWith('en')) {
          _localeId = 'en-US';
        }
      }
    } catch (_) {
      _speechAvailable = false;
    }
  }

  /// Probes Gemini and flips Pollie's mood: smiling 😊 + greeting on
  /// success, sleeping 😴 + an honest reason on failure.
  Future<void> _wakeUp() async {
    if (_waking) return;
    setState(() {
      _waking = true;
      _status = _PollieStatus.sleeping;
    });
    // Skip the network call when a successful ping happened recently.
    final result = _pollie.recentlyAwake ? PolliePing.ok : await _pollie.ping();
    if (!mounted) return;
    final awake = result == PolliePing.ok;
    setState(() {
      _waking = false;
      _status = awake ? _PollieStatus.awake : _PollieStatus.sleeping;
      _bubbles
        ..clear()
        ..add(
          _Bubble(
            role: 'model',
            text: awake
                ? strings.pollieGreeting
                : result == PolliePing.quota
                ? 'Pollie is all out of words for today! '
                      "He'll be back ${_pollie.quotaResetLabel()} 😴"
                : strings.pollieAsleep,
          ),
        );
    });
    if (awake) {
      _speak(strings.pollieGreetingSpoken);
    }
  }

  /// Pollie's gentle response when the child (or the model) says something
  /// inappropriate.
  void _gentleRedirect() {
    setState(() {
      _bubbles.add(_Bubble(role: 'model', text: strings.pollieNotNice));
    });
    _scrollToBottom();
    _speak(strings.pollieNotNice);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final position = _scroll.position;
      final atBottom = position.maxScrollExtent - position.pixels < 60;
      if (atBottom) {
        // Jump (not animate) while the reply streams in — restarting a
        // scroll animation on every chunk would jitter.
        position.jumpTo(position.maxScrollExtent);
      } else {
        position.animateTo(
          position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// Starts a listening turn; the mic button toggles it off.
  Future<void> _startListening() async {
    if (_status != _PollieStatus.awake || _busy) return;
    if (!_speechAvailable) {
      _bubbles.add(_Bubble(role: 'model', text: strings.pollieNoMic));
      _scrollToBottom();
      return;
    }
    _heard = '';
    _listenRetries = 0;
    _restarting = false;
    _turnActive = true;
    _turnTimer?.cancel();
    _turnTimer = Timer(_maxTurn, () => _endTurn(send: true));
    setState(() {
      _status = _PollieStatus.listening;
      _busy = true;
      _partial = '';
      _soundLevel = 0;
    });
    // Absolute, from the moment the mic opened. If nothing is ever
    // understood, close it rather than sit open for the full 45s cap.
    _nothingHeardTimer?.cancel();
    _nothingHeardTimer = Timer(_silenceGivesUp, () {
      if (_turnActive && _transcript.trim().isEmpty) _endTurn(send: false);
    });
    await _listenOnce();
  }

  /// The turn's one and only recogniser session — see the comment above
  /// [_quietWindow] for why there is no restart loop here.
  Future<void> _listenOnce() async {
    if (!_turnActive || !mounted) return;
    try {
      await _speech.listen(
        onResult: (result) {
          if (!_turnActive) return;
          setState(() => _partial = result.recognizedWords);
          _armQuietTimer();
          if (!result.finalResult) return;

          final words = result.recognizedWords.trim();
          if (words.isNotEmpty) {
            _heard = _heard.isEmpty ? words : '$_heard $words';
          }
          setState(() => _partial = '');
          // This session is done; the turn is not. Bank and listen again.
          _restartSession();
        },
        onSoundLevelChange: (level) {
          // Same guard as onResult above: dispose() flips `_turnActive`
          // to false before firing-and-forgetting `_speech.stop()`, so a
          // sound-level event already in flight when the child leaves the
          // Pollie screen must not call setState on a defunct State.
          if (!_turnActive) return;
          // Throttle: only rebuild when the level actually moved, so the
          // mic pulse never rebuilds the whole screen dozens of times a
          // second.
          final l = level.clamp(0.0, 1.0);
          if ((l - _soundLevel).abs() > 0.015) {
            setState(() => _soundLevel = l);
          }
        },
        listenOptions: SpeechListenOptions(
          localeId: _localeId,
          // The patched options (see packages/PATCH.md). Android's own
          // "probably finished" guess is about half a second — shorter than
          // the pause between words — and ending a session mid-sentence is
          // what dropped words, because each restart leaves a gap nothing is
          // captured in. Two and a half seconds lets a child think.
          possiblyCompleteSilence: const Duration(milliseconds: 2500),
          minimumLength: const Duration(seconds: 3),
          // Long enough for a full toddler sentence; pauseFor (not a
          // restart) is what actually absorbs mid-sentence pauses.
          listenFor: const Duration(seconds: 30),
          pauseFor: _quietWindow,
        ),
      );
    } catch (e) {
      // Speech engine hiccup starting the session: a couple of quiet
      // retries, then end the turn.
      debugPrint('Listening failed: $e');
      if (_turnActive && _listenRetries < 2) {
        _listenRetries++;
        await Future<void>.delayed(const Duration(milliseconds: 600));
        if (mounted && _turnActive) await _listenOnce();
      } else {
        _endTurn(send: true);
      }
    }
  }

  /// Moves whatever the recogniser is currently guessing into the banked
  /// transcript, so a session ending cannot lose it.
  ///
  /// Skips a repeat: some recognisers restate the whole utterance in the next
  /// session, and appending both would stutter — "do you do you know".
  void _bankPartial() {
    final pending = _partial.trim();
    if (pending.isEmpty) return;
    _heard = appendHeard(_heard, pending);
    if (mounted) setState(() => _partial = '');
  }

  /// Restarts the "have they finished?" clock.
  ///
  /// Called on *every* sign of life from the recogniser, not only on
  /// recognised words. On the test device the recogniser reported plenty of
  /// activity while transcribing nothing — empty partials, and a session
  /// ending every second or two. Arming this only on recognised words meant
  /// that in a noisy room, or with a child who mumbles, it never started at
  /// all and the mic sat open until the 45-second cap.
  ///
  /// The wait is short once there are words to answer and long while there are
  /// none, so a pause mid-sentence is respected but an open mic still closes.
  void _armQuietTimer() {
    if (!_turnActive || _transcript.trim().isEmpty) return;
    _quietTimer?.cancel();
    _quietTimer = Timer(_quietEndsTurn, () {
      if (_turnActive && _transcript.trim().isNotEmpty) _endTurn(send: true);
    });
  }

  /// Re-arms the mic for the same turn after a session ends.
  ///
  /// Guarded so the two callbacks that fire for one session ending cannot
  /// both restart — see the comment above [_quietWindow].
  Future<void> _restartSession() async {
    if (!_turnActive || !mounted || _restarting) return;
    _restarting = true;
    // Bank whatever the dying session was still guessing, *before* the next
    // one starts. Its first result assigns to `_partial`, overwriting rather
    // than appending — so without this the words from the session that just
    // ended are simply gone. That is why "do you know about minecraft?" came
    // back as "know minecraft": "do you" belonged to a session that ended
    // without ever producing a final result.
    _bankPartial();
    try {
      // A session that ended on its own is already torn down; calling stop()
      // again only adds dead air, and every millisecond here is speech nobody
      // captures. Stop only when we are interrupting a live session.
      if (_speech.isListening) {
        try {
          await _speech.stop();
        } catch (_) {}
      }
      await Future<void>.delayed(const Duration(milliseconds: 60));
      if (!_turnActive || !mounted) return;
      await _listenOnce();
    } finally {
      _restarting = false;
    }
  }

  /// Ends the turn, optionally sending everything banked during it.
  void _endTurn({required bool send}) {
    if (!_turnActive && _heard.isEmpty) {
      // Already finished; still make sure the UI is idle.
      if (mounted && _status == _PollieStatus.listening) {
        setState(() {
          _status = _PollieStatus.awake;
          _busy = false;
          _partial = '';
        });
      }
      return;
    }
    _turnActive = false;
    _restarting = false;
    _turnTimer?.cancel();
    _turnTimer = null;
    _quietTimer?.cancel();
    _quietTimer = null;
    _nothingHeardTimer?.cancel();
    _nothingHeardTimer = null;
    try {
      _speech.stop();
    } catch (_) {}

    // Capture the full transcript — every finished session's words plus
    // whatever the live one was still guessing. On a mic tap mid-sentence,
    // `_partial` is the only place the last few words exist.
    final words = _transcript.trim();
    _heard = '';
    if (!mounted) return;
    setState(() {
      _status = _PollieStatus.awake;
      _busy = false;
      _partial = '';
      _soundLevel = 0;
    });
    if (send && words.isNotEmpty) _send(words);
  }

  /// Tapping the mic while it is live means "I'm done" — send the full
  /// transcript captured so far (banked words plus whatever was still
  /// being guessed).
  void _stopListening() => _endTurn(send: true);

  void _onSpeechError(SpeechRecognitionError error) {
    if (!mounted) return;
    // "No match" / timeout / silence is normal when nobody speaks — stay
    // quiet instead of popping an error bubble.
    final message = error.errorMsg.toLowerCase();
    final quiet =
        message.contains('no match') ||
        message.contains('timeout') ||
        message.contains('no speech') ||
        error.permanent;

    // Mid-turn, a "no match"/timeout just means that session heard nothing
    // worth transcribing — a child thinking, not a child finished. Re-arm
    // quietly. A permanent error is different: that mic is not coming back.
    if (_turnActive && quiet && !error.permanent) {
      _restartSession();
      return;
    }

    if (!quiet) {
      _bubbles.add(
        _Bubble(
          role: 'model',
          text: "Oops, I didn't catch that! 😅 Tap the mic and try again?",
        ),
      );
      _scrollToBottom();
    }
    if (_turnActive) {
      _endTurn(send: true);
      return;
    }
    setState(() {
      _status = _PollieStatus.awake;
      _busy = false;
      _partial = '';
    });
  }

  /// Sends something the grown-up typed or tapped.
  ///
  /// Closes an open microphone first. `_send` refuses while `_busy`, and
  /// listening sets `_busy` — so with the hands-free loop re-opening the mic
  /// after every reply, typed messages were silently dropped.
  void _sendTyped(String raw) {
    if (raw.trim().isEmpty) return;
    if (_turnActive) _endTurn(send: false);
    _send(raw);
  }

  Future<void> _send(String raw) async {
    final text = raw.trim();
    if (text.isEmpty || _busy) return;

    // Local safety guard: inappropriate words never reach Gemini (or the
    // conversation history).
    if (KidSafety.containsBlocked(text)) {
      _input.clear();
      _gentleRedirect();
      return;
    }

    setState(() {
      _bubbles.add(_Bubble(role: 'user', text: text));
      _bubbles.add(_Bubble(role: 'model', text: '', streaming: true));
      _busy = true;
      _status = _PollieStatus.thinking;
    });
    _history.add(ChatMessage(role: 'user', text: text));
    _input.clear();
    _scrollToBottom();

    try {
      final buffer = StringBuffer();
      // Sentences already handed to the TTS engine, as an index into the
      // reply built so far.
      var spoken = 0;
      var voiceReady = false;
      await _beginSpeaking(thenListen: true, more: true);
      await for (final chunk in _pollie.reply(
        _history,
        language:
            AppLanguageService.instance.current.value == AppLanguage.indonesian
            ? 'id'
            : 'en',
      )) {
        buffer.write(chunk);
        if (mounted) {
          setState(() => _bubbles.last.text = buffer.toString());
          _scrollToBottom();
        }
        final full = buffer.toString();
        final cut = lastSentenceEnd(full, spoken);
        if (cut <= spoken) continue;
        final sentence = full.substring(spoken, cut);
        spoken = cut;
        // The voice is chosen once, from the first sentence: switching
        // language mid-reply cuts off whatever is speaking.
        if (!voiceReady) {
          voiceReady = true;
          await _applyVoiceFor(sentence);
        }
        await _enqueueSpeech(sentence);
      }
      final reply = buffer.toString().trim();
      if (reply.isEmpty) {
        _moreComing = false;
        throw StateError('Pollie said nothing — maybe try again?');
      }
      // Output safety guard: if anything inappropriate slipped through the
      // model filters, the child never sees or hears it.
      if (KidSafety.containsBlocked(reply)) {
        _moreComing = false;
        if (mounted) {
          setState(() {
            _bubbles.removeLast();
            _bubbles.add(_Bubble(role: 'model', text: strings.pollieNotNice));
            _busy = false;
          });
        }
        _speak(strings.pollieNotNice);
        return;
      }
      _history.add(ChatMessage(role: 'model', text: reply));
      if (mounted) {
        setState(() {
          _bubbles.last
            ..text = reply
            ..streaming = false;
          _busy = false;
        });
      }
      // Whatever never ended in punctuation still has to be said.
      final tail = reply.length > spoken ? reply.substring(spoken) : '';
      if (tail.trim().isNotEmpty) {
        if (!voiceReady) await _applyVoiceFor(tail);
        await _enqueueSpeech(tail);
      }
      _moreComing = false;
      _finishSpeakingIfDone();
    } catch (e) {
      debugPrint('Pollie reply failed: $e');
      _moreComing = false;
      if (!mounted) return;
      // A brief rate limit is a pause, not the end of the day. Telling a
      // child to come back tomorrow when the answer is seconds away is a lie,
      // and it also made a temporary hiccup look permanent.
      final brief = e is PollieQuotaException && e.isBrief;
      final quota = e is PollieQuotaException && !e.isBrief;
      setState(() {
        _bubbles.removeLast();
        _bubbles.add(
          _Bubble(
            role: 'model',
            text: brief
                ? strings.pollieBreath
                : quota
                ? strings.pollieOutOfWords(_pollie.quotaResetLabel())
                : _pollie.isConfigured
                ? strings.pollieLost
                : strings.pollieNoKey,
          ),
        );
        // A pause leaves Pollie awake; only a real failure puts him to sleep.
        _status = brief ? _PollieStatus.awake : _PollieStatus.sleeping;
        _busy = false;
      });
    }
    _scrollToBottom();
  }

  /// Plain text for the TTS: emojis and roleplay markers removed.
  String _cleanForSpeech(String text) {
    return text
        .replaceAll(_emojiPattern, '')
        .replaceAll('*', '')
        .replaceAll('…', '.')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  List<Map<dynamic, dynamic>>? _cachedVoices;

  /// `getVoices` hands back the raw platform-channel value: a `List<Object?>`
  /// of `Map<Object?, Object?>`. Casting that straight to
  /// `List<Map<dynamic, dynamic>>` throws — `Object?` is not a `Map` — which
  /// is how voice selection silently did nothing for so long. Rebuild the
  /// list element by element instead of asserting a shape it never has.
  Future<List<Map<dynamic, dynamic>>> _loadVoices() async {
    final raw = await _tts.getVoices;
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map<Map<dynamic, dynamic>>(Map<dynamic, dynamic>.from)
        .toList();
  }

  /// Picks the most natural available voice for the locale.
  Future<void> _applyBestVoice(String lang) async {
    try {
      _cachedVoices ??= await _loadVoices();
      final best = pickBestVoice(_cachedVoices, lang);
      if (best == null) return;
      // Never trade a working engine default for a voice we know nothing
      // about: without a quality rating there is no reason to think ours is
      // an improvement. (Checking the rating itself, not the score — bonuses
      // alone can lift an unrated voice past any threshold.)
      final quality = (best['quality'] ?? '').toString().toLowerCase();
      if (!_qualityRank.containsKey(quality)) return;
      debugPrint(
        'Pollie voice: ${best['name']} (${best['locale']}, '
        'quality=${best['quality']}, network=${best['network_required']}, '
        'score=${voiceScore(best, lang)})',
      );
      await _tts.setVoice(best.cast<String, String>());
    } catch (e) {
      // The engine default is a fine fallback — but say so, rather than
      // swallowing the reason the way the two earlier bugs here were.
      debugPrint('Pollie voice selection failed: $e');
    }
  }

  // --- speaking ------------------------------------------------------------
  //
  // Pollie speaks sentence by sentence as the reply streams in, rather than
  // waiting for the whole thing. Generating two sentences and then
  // synthesising them are both slow; doing them one after the other made the
  // child wait for the sum. Now she starts talking as soon as the first
  // sentence lands, and the rest is queued behind it.

  /// Utterances handed to the TTS engine that have not finished yet.
  int _pending = 0;

  /// True while a reply is still streaming and may add more sentences.
  bool _moreComing = false;

  /// Whether to re-arm the mic once everything queued has been spoken.
  bool _relisten = false;

  /// Starts a spoken response. [more] is true when sentences are still
  /// arriving, false for a one-shot line.
  Future<void> _beginSpeaking({
    required bool thenListen,
    required bool more,
  }) async {
    _relisten = thenListen;
    _moreComing = more;
    if (mounted) setState(() => _status = _PollieStatus.speaking);
  }

  /// Queues one sentence behind whatever is already speaking.
  Future<void> _enqueueSpeech(String text) async {
    final clean = _cleanForSpeech(text);
    if (clean.isEmpty) return;
    _pending++;
    try {
      await _tts.speak(clean);
    } catch (_) {
      // TTS unavailable: the text bubble is still there.
      _pending--;
      _finishSpeakingIfDone();
    }
  }

  /// Applies the voice for [text]'s language. Called once per reply, before
  /// the first sentence — switching voice mid-reply would cut it off.
  Future<String> _applyVoiceFor(String text) async {
    // The chosen language decides the voice. This used to guess from stop
    // words in the reply, which got it wrong whenever Pollie answered briefly
    // or with a name; now the app already knows.
    final lang = AppLanguageService.instance.current.value.localeId;
    try {
      await _tts.setLanguage(lang);
      await _applyBestVoice(lang);
      // Just above natural: enough to read as friendly, not so high that the
      // synthesiser starts to sound like a chipmunk. Pushing pitch hard is
      // what made Pollie sound robotic, not the speed.
      await _tts.setPitch(1.1);
      await _tts.setSpeechRate(0.45);
    } catch (e) {
      debugPrint('Pollie voice setup failed: $e');
    }
    return lang;
  }

  void _onUtteranceComplete() {
    _pending = _pending > 0 ? _pending - 1 : 0;
    _finishSpeakingIfDone();
  }

  void _finishSpeakingIfDone() {
    if (_pending > 0 || _moreComing || !mounted) return;
    setState(() => _status = _PollieStatus.awake);
    if (_relisten && _speechAvailable && _pollie.isConfigured) {
      _relisten = false;
      Future<void>.delayed(const Duration(milliseconds: 1200), () {
        if (mounted && _status == _PollieStatus.awake) _startListening();
      });
    }
  }

  /// Says one complete line — the greeting, a gentle redirect, an apology.
  Future<void> _speak(String text, {bool thenListen = false}) async {
    await _beginSpeaking(thenListen: thenListen, more: false);
    await _applyVoiceFor(text);
    await _enqueueSpeech(text);
    _finishSpeakingIfDone();
  }

  void _reset() {
    _history.clear();
    _stopListening();
    setState(() {
      _bubbles.clear();
      if (_pollie.isConfigured) {
        _bubbles.add(_Bubble(role: 'model', text: ''));
        _status = _PollieStatus.sleeping;
      } else {
        _bubbles.add(
          _Bubble(
            role: 'model',
            text:
                "Hi! I'm Pollie! 🦜 I can't talk yet — ask a grown-up to "
                'give me my magic key! 🔑',
          ),
        );
      }
    });
    if (_pollie.isConfigured) _wakeUp();
  }

  String get _statusText {
    if (_waking) return strings.wakingUp;
    switch (_status) {
      case _PollieStatus.sleeping:
        return strings.sleeping;
      case _PollieStatus.awake:
        return strings.awake;
      case _PollieStatus.listening:
        return strings.listeningStatus;
      case _PollieStatus.thinking:
        return strings.thinking;
      case _PollieStatus.speaking:
        return strings.speaking;
    }
  }

  String get _statusFace {
    switch (_status) {
      case _PollieStatus.sleeping:
        return '😴';
      case _PollieStatus.awake:
        return '😊';
      case _PollieStatus.listening:
        return '👂';
      case _PollieStatus.thinking:
        return '🤔';
      case _PollieStatus.speaking:
        return '🗣️';
    }
  }

  void _onMicTap() {
    switch (_status) {
      case _PollieStatus.listening:
        _stopListening();
      case _PollieStatus.sleeping:
        // The mic always responds: tapping it while Pollie sleeps wakes him.
        _wakeUp();
      case _PollieStatus.awake:
        _startListening();
      case _PollieStatus.thinking:
      case _PollieStatus.speaking:
        // Momentarily busy — the dimmed mic shows this; ignore quietly.
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          GameBackground(
            child: Column(
              children: [
                // Header: home button + Pollie status avatar + name.
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      RoundButton(
                        emoji: '🏠',
                        onTap: () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(width: 12),
                      // The face shows Pollie's mood; tap it to wake him up.
                      GestureDetector(
                        onTap: _status == _PollieStatus.sleeping
                            ? _wakeUp
                            : null,
                        child: CircleAvatar(
                          radius: 26,
                          backgroundColor: Colors.white,
                          child: PollieBird(
                            emoji: _statusFace,
                            fontSize: 30,
                            // Still while asleep; leaning toward the child
                            // while listening; a gentle bob otherwise.
                            active: _status != _PollieStatus.sleeping,
                            bob: _status == _PollieStatus.listening ? 2 : 3,
                            lean: _status == _PollieStatus.listening ? 0.12 : 0,
                            period: _status == _PollieStatus.speaking
                                ? const Duration(milliseconds: 900)
                                : const Duration(milliseconds: 2400),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Pollie',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                shadows: [
                                  Shadow(color: Colors.black26, blurRadius: 6),
                                ],
                              ),
                            ),
                            Text(
                              _statusText,
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                      RoundButton(emoji: '🔁', onTap: _reset),
                    ],
                  ),
                ),
                // Chat area.
                Expanded(
                  child: ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    itemCount: _bubbles.length,
                    itemBuilder: (context, index) =>
                        _buildBubble(_bubbles[index]),
                  ),
                ),
                // Live listening transcript.
                if (_status == _PollieStatus.listening)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          const Text('👂', style: TextStyle(fontSize: 20)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _transcript.isEmpty
                                  ? strings.listening
                                  : '$_transcript …',
                              style: const TextStyle(
                                fontSize: 16,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                // Quick chips for toddlers.
                SizedBox(
                  height: 52,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _chips.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final chip = _chips[index];
                      return ActionChip(
                        onPressed: () => _sendTyped(chip),
                        label: Text(chip, style: const TextStyle(fontSize: 15)),
                        backgroundColor: Colors.white,
                        disabledColor: Colors.white60,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      );
                    },
                  ),
                ),
                // Input bar: mic (talk) + text field + send.
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Row(
                    children: [
                      // The mic pulses with the sound level while listening.
                      // It dims when Pollie can't listen right now (sleeping,
                      // thinking, speaking) so it never looks broken.
                      GestureDetector(
                        onTap: _onMicTap,
                        child: AnimatedScale(
                          scale: _status == _PollieStatus.listening
                              ? 1 + _soundLevel * 0.6
                              : 1.0,
                          duration: const Duration(milliseconds: 100),
                          child: Opacity(
                            opacity:
                                (_status == _PollieStatus.awake ||
                                    _status == _PollieStatus.listening)
                                ? 1.0
                                : 0.45,
                            child: Material(
                              color: _status == _PollieStatus.listening
                                  ? const Color(0xFFFF5252)
                                  : Colors.white,
                              shape: const CircleBorder(),
                              elevation: 3,
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Text(
                                  '🎤',
                                  style: TextStyle(
                                    fontSize: 26,
                                    color: _status == _PollieStatus.listening
                                        ? Colors.white
                                        : null,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _input,
                          enabled: !_busy,
                          onSubmitted: _sendTyped,
                          textInputAction: TextInputAction.send,
                          style: const TextStyle(fontSize: 17),
                          decoration: InputDecoration(
                            hintText: strings.saySomething,
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 12,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      RoundButton(
                        emoji: '➡️',
                        fontSize: 26,
                        onTap: () => _sendTyped(_input.text),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBubble(_Bubble bubble) {
    final isUser = bubble.role == 'user';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            const CircleAvatar(
              radius: 18,
              backgroundColor: Colors.white,
              child: Text('🦜', style: TextStyle(fontSize: 20)),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser
                    ? const Color(0xFFFFC107)
                    : Colors.white.withValues(alpha: 0.95),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isUser ? 18 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 18),
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 6,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: Text(
                bubble.streaming && bubble.text.isEmpty
                    ? '…'
                    : bubble.streaming
                    ? '${bubble.text} …'
                    : bubble.text,
                style: const TextStyle(fontSize: 17, height: 1.3),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble {
  _Bubble({required this.role, required this.text, this.streaming = false});

  final String role; // 'user' | 'model'
  String text;
  bool streaming;
}

/// Android reports a voice's quality as a word, not a number. An earlier
/// `as num?` cast therefore scored every voice zero, so the "pick the best
/// voice" loop never actually picked anything and Pollie was left on whatever
/// voice came first — usually a tinny local one. Hence the string table.
const _qualityRank = {
  'very high': 5,
  'high': 4,
  'normal': 3,
  'low': 2,
  'very low': 1,
};

/// Scores a `flutter_tts` voice map for how human it is likely to sound:
/// quality first, then an exact locale match, then network (neural) voices,
/// which are the ones that actually sound like a person, then female — warmer
/// for a toddler. eSpeak is pushed to last; it is the most robotic engine on
/// any device.
///
/// [wantedLocale] is the full locale being requested (e.g. `en-US`). Voices
/// are shortlisted by language alone, so without this an `en-GB` voice could
/// outrank the `en-US` one the conversation is actually in.
int voiceScore(Map<dynamic, dynamic> voice, [String? wantedLocale]) {
  final name = (voice['name'] ?? '').toString().toLowerCase();
  final locale = (voice['locale'] ?? '').toString().toLowerCase();
  final quality =
      _qualityRank[(voice['quality'] ?? '').toString().toLowerCase()] ?? 0;
  final networkVoice =
      (voice['network_required'] ?? '').toString() == '1' ||
      name.contains('network');
  final female = name.contains('female') || name.contains('#f');
  final espeak = name.contains('espeak');
  final exactLocale =
      wantedLocale != null && locale == wantedLocale.toLowerCase();

  var score = quality * 100;
  // Outweighs network + female together, so the right accent wins ties.
  if (exactLocale) score += 60;
  if (networkVoice) score += 40;
  if (female) score += 10;
  if (espeak) score -= 1000;
  return score;
}

/// The best-sounding voice for [lang] out of [voices], or null when the list
/// is empty or has nothing for that language.
Map<dynamic, dynamic>? pickBestVoice(
  List<Map<dynamic, dynamic>>? voices,
  String lang,
) {
  if (voices == null || voices.isEmpty) return null;
  final langCode = lang.split('-').first.toLowerCase();
  final candidates = voices
      .where(
        (v) =>
            (v['locale'] ?? '').toString().toLowerCase().startsWith(langCode),
      )
      .toList();
  if (candidates.isEmpty) return null;

  var best = candidates.first;
  var bestScore = voiceScore(best, lang);
  for (final voice in candidates.skip(1)) {
    final score = voiceScore(voice, lang);
    if (score > bestScore) {
      best = voice;
      bestScore = score;
    }
  }
  return best;
}
