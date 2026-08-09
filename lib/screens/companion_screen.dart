import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../services/kid_safety.dart';
import '../services/pollie_service.dart';
import '../widgets/game_background.dart';
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
class CompanionScreen extends StatefulWidget {
  const CompanionScreen({super.key});

  @override
  State<CompanionScreen> createState() => _CompanionScreenState();
}

class _CompanionScreenState extends State<CompanionScreen>
    with WidgetsBindingObserver {
  static const _chips = [
    'Tell me a story! 🐰',
    'Sing a song! 🎵',
    'What does a cow say? 🐮',
    'How are you? 😊',
    'Fun fact! 🦕',
    'I love you! ❤️',
  ];
  static const _idStopWords = [
    'apa',
    'kenapa',
    'bagaimana',
    'cerita',
    'nyanyi',
    'aku',
    'saya',
    'kamu',
    'kenal',
    'boleh',
    'tolong',
  ];
  static const _greeting = 'Hi kids! Let\'s talk with me 🦜';
  static const _gentleMessage =
      "Hmm, that's not a nice thing to say! Let's talk about something fun "
      'instead 😊';

  /// Emoji (and symbol) ranges, stripped before speaking so the TTS only
  /// reads plain text. Includes variation selectors and ZWJ sequences.
  static final _emojiPattern = RegExp(
    r'[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}'
    r'\u{2190}-\u{21FF}\u{25A0}-\u{25FF}\u{FE0F}\u{200D}\u{20E3}'
    r'\u{1F1E6}-\u{1F1FF}\u{00A9}\u{00AE}\u{2122}\u{203C}\u{2049}'
    r'\u{3030}\u{303D}]',
    unicode: true,
  );

  final _pollie = PollieService();
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
  // Android's recogniser has two silence timers: a "definitely finished" one,
  // which is the only one the plugin exposes (as `pauseFor`), and a much
  // shorter "possibly finished" one we cannot configure at all. A previous
  // version tried to dodge both by treating a turn as *ours*, not the
  // recogniser's: every time a session ended, its words were banked and the
  // mic was immediately re-armed, only really ending the turn once the child
  // had been quiet for a while.
  //
  // That restart made things worse, not better. `onResult`'s final-result
  // branch and `onStatus('done')` both fire for the same session ending, so
  // two restarts raced each other into a "recognizer busy" error; and every
  // restart — even the ones that didn't race — cost a few hundred
  // milliseconds of dead air in which nothing was captured at all. A child
  // talking continuously lost most of a sentence to those gaps, not to the
  // recogniser's endpointing.
  //
  // So a turn is exactly one recogniser session again. The pause tolerance is
  // bought directly from the recogniser via `pauseFor: _quietWindow` instead
  // of being rebuilt out of restarts. Do not reintroduce a restart loop here:
  // restarting to dodge a short silence timer loses more speech to the
  // restart gap than the timer ever cut off.
  static const _quietWindow = Duration(seconds: 3);

  /// Hard stop, so a turn can never leave the mic live forever.
  static const _maxTurn = Duration(seconds: 45);

  /// Words banked from the turn's recogniser session. A single session can
  /// still emit more than one final result, so this keeps accumulating —
  /// it just never triggers another `listen()` call.
  String _heard = '';
  Timer? _turnTimer;
  bool _turnActive = false;

  /// What the child has said so far this turn: banked words plus whatever the
  /// recogniser is currently guessing.
  String get _transcript =>
      [_heard, _partial].where((s) => s.isNotEmpty).join(' ');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
    try {
      _speech.stop();
      _tts.stop();
    } catch (_) {}
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

  /// Picks the speech recognition locale from the device language
  /// (Indonesian or English), falling back to en-US.
  Future<void> _initSpeechLocale() async {
    try {
      final available = await _speech.initialize(
        onError: _onSpeechError,
        onStatus: (status) {
          if (status != 'done' || !mounted) return;
          // The turn's one session just ended — that is the whole turn
          // ending, too. Send whatever got banked, which may be nothing.
          if (_turnActive) {
            _endTurn(send: true);
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
                ? _greeting
                : result == PolliePing.quota
                ? 'Pollie is all out of words for today! '
                      "He'll be back ${_pollie.quotaResetLabel()} 😴"
                : 'Zzz… I can\'t reach the internet yet. '
                      'Tap me to try waking up again! 😴',
          ),
        );
    });
    if (awake) {
      _speak('Hi kids! Let\'s talk with me!');
    }
  }

  /// Pollie's gentle response when the child (or the model) says something
  /// inappropriate.
  void _gentleRedirect() {
    setState(() {
      _bubbles.add(_Bubble(role: 'model', text: _gentleMessage));
    });
    _scrollToBottom();
    _speak(
      "Hmm, that's not a nice thing to say! Let's talk about "
      'something fun instead.',
    );
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
      _bubbles.add(
        _Bubble(
          role: 'model',
          text:
              "I can't hear you! 🎤 Ask a grown-up to allow the "
              'microphone, then tap the mic again.',
        ),
      );
      _scrollToBottom();
      return;
    }
    _heard = '';
    _listenRetries = 0;
    _turnActive = true;
    _turnTimer?.cancel();
    _turnTimer = Timer(_maxTurn, () => _endTurn(send: true));
    setState(() {
      _status = _PollieStatus.listening;
      _busy = true;
      _partial = '';
      _soundLevel = 0;
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
          if (!result.finalResult) return;

          final words = result.recognizedWords.trim();
          if (words.isNotEmpty) {
            _heard = _heard.isEmpty ? words : '$_heard $words';
          }
          setState(() => _partial = '');
          // The one session just gave its final result — that's the turn
          // done; send whatever was banked.
          _endTurn(send: true);
        },
        onSoundLevelChange: (level) {
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
    _turnTimer?.cancel();
    _turnTimer = null;
    try {
      _speech.stop();
    } catch (_) {}

    final words = _heard.trim();
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

  /// Tapping the mic while it is live means "I'm done" — send what we have.
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

    // Mid-turn, a "no match"/timeout just means the single session found
    // nothing worth transcribing (or the child never spoke) — end the turn
    // quietly and send whatever was banked, rather than treating it as a
    // real error.
    if (_turnActive && quiet) {
      _endTurn(send: true);
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
      await for (final chunk in _pollie.reply(_history)) {
        buffer.write(chunk);
        if (mounted) {
          setState(() => _bubbles.last.text = buffer.toString());
          _scrollToBottom();
        }
      }
      final reply = buffer.toString().trim();
      if (reply.isEmpty) {
        throw StateError('Pollie said nothing — maybe try again?');
      }
      // Output safety guard: if anything inappropriate slipped through the
      // model filters, the child never sees or hears it.
      if (KidSafety.containsBlocked(reply)) {
        if (mounted) {
          setState(() {
            _bubbles.removeLast();
            _bubbles.add(_Bubble(role: 'model', text: _gentleMessage));
            _busy = false;
          });
        }
        _speak(
          "Hmm, that's not a nice thing to say! Let's talk about "
          'something fun instead.',
        );
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
      _speak(reply, thenListen: true);
    } catch (e) {
      debugPrint('Pollie reply failed: $e');
      if (!mounted) return;
      final quota = e.toString().toLowerCase().contains('quota');
      setState(() {
        _bubbles.removeLast();
        _bubbles.add(
          _Bubble(
            role: 'model',
            text: quota
                ? 'Pollie is all out of words for today! '
                      "He'll be back ${_pollie.quotaResetLabel()} 😴"
                : _pollie.isConfigured
                ? 'Oops, I got lost for a moment! 😅 '
                      'Can you ask me again?'
                : "I can't talk yet — ask a grown-up for my magic key! 🔑",
          ),
        );
        _status = _PollieStatus.sleeping;
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

  Future<void> _speak(String text, {bool thenListen = false}) async {
    if (mounted) setState(() => _status = _PollieStatus.speaking);
    try {
      // Simple language guess so the TTS voice matches the conversation.
      final lower = text.toLowerCase();
      final indonesian = _idStopWords.any(lower.contains);
      final lang = indonesian ? 'id-ID' : 'en-US';
      await _tts.setLanguage(lang);
      await _applyBestVoice(lang);
      // Just above natural: enough to read as friendly, not so high that the
      // synthesiser starts to sound like a chipmunk. Pushing pitch hard is
      // what made Pollie sound robotic, not the speed.
      await _tts.setPitch(1.1);
      await _tts.setSpeechRate(0.45);
      // Once the reply is spoken, re-arm the microphone for a hands-free
      // conversation loop.
      _tts.setCompletionHandler(() async {
        if (!mounted) return;
        setState(() => _status = _PollieStatus.awake);
        if (thenListen && _speechAvailable && _pollie.isConfigured) {
          await Future<void>.delayed(const Duration(milliseconds: 1200));
          if (mounted) _startListening();
        }
      });
      _tts.setErrorHandler((message) {
        if (mounted) setState(() => _status = _PollieStatus.awake);
      });
      await _tts.speak(_cleanForSpeech(text));
    } catch (_) {
      // TTS unavailable: the text bubble is still there.
      if (mounted) {
        setState(() => _status = _PollieStatus.awake);
        if (thenListen && _speechAvailable && _pollie.isConfigured) {
          await Future<void>.delayed(const Duration(milliseconds: 1200));
          if (mounted) _startListening();
        }
      }
    }
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
    if (_waking) return 'waking up…';
    switch (_status) {
      case _PollieStatus.sleeping:
        return 'sleeping… 😴';
      case _PollieStatus.awake:
        return 'awake! 😊';
      case _PollieStatus.listening:
        return 'listening… 👂';
      case _PollieStatus.thinking:
        return 'thinking… 🤔';
      case _PollieStatus.speaking:
        return 'speaking… 🗣️';
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
                          child: Text(
                            _statusFace,
                            style: const TextStyle(fontSize: 30),
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
                                  ? 'Listening…'
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
                        onPressed: _busy ? null : () => _send(chip),
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
                          onSubmitted: _send,
                          textInputAction: TextInputAction.send,
                          style: const TextStyle(fontSize: 17),
                          decoration: InputDecoration(
                            hintText: 'Say something…',
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
                        onTap: () => _send(_input.text),
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
