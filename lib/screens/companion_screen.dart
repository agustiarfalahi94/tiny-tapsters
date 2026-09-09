import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_language.dart';
import '../services/kid_safety.dart';
import '../services/narrator.dart';
import '../services/pollie_service.dart';
import '../services/speech_sink.dart';
import '../services/vad_gate.dart';
import '../services/tts_service.dart';
import '../widgets/game_background.dart';
import '../widgets/pollie_bird.dart';
import '../widgets/round_button.dart';

/// Where a listening turn is.
///
/// `arming` and `warming` used to be invisible: the app said "listening" from
/// the moment it asked, which is up to half a second before the microphone is
/// actually recording. Naming them is what lets the child be told the truth.
enum TurnState { idle, arming, warming, open, closing }

/// Who decides when the child has finished.
///
/// `tap` leaves it to silence detection; `hold` leaves it to the finger, which
/// is the one path that cannot misjudge.
enum TurnMode { tap, hold }

enum _PollieStatus { sleeping, awake, listening, thinking, speaking }

/// Pollie 🦜 — a talking companion powered by Gemini.
///
/// Pollie sleeps 😴 while offline and smiles 😊 once Gemini answers a
/// connectivity probe, then greets the child. Tap the 🎤 to talk: speech is
/// transcribed (Google speech-to-text), answered by Gemini, and spoken aloud
/// (system TTS) — then Pollie listens again automatically, so a toddler can
/// just keep chatting like in the Gemini app. Toddlers can also tap the big
/// chips; grown-ups can type.
/// Finds the device's own name for [wanted] among the recognisers it has.
///
/// Android reports these inconsistently — `id_ID` as often as `id-ID`, and
/// sometimes only a bare `id` — so an exact string comparison misses a
/// recogniser that is actually installed. Falls back to matching on the
/// language alone, which is what a child is speaking anyway.
///
/// Returns null when the device genuinely has nothing for that language.
String? matchLocale(String wanted, List<String> available) {
  String normalise(String id) => id.replaceAll('_', '-').toLowerCase();
  final target = normalise(wanted);
  final language = target.split('-').first;
  for (final id in available) {
    if (normalise(id) == target) return id;
  }
  for (final id in available) {
    if (normalise(id).split('-').first == language) return id;
  }
  return null;
}

/// Joins what a recogniser session produced onto what earlier sessions did.
///
/// A session ending must not lose its words: the next session assigns to the
/// partial rather than appending, so anything not banked here disappears. That
/// is how "do you know about minecraft?" became "know minecraft".
///
/// Skips a restatement, because some recognisers repeat the whole utterance in
/// the following session and appending both would stutter.
/// The words a child repeats when a short answer does not seem to land.
///
/// Both languages, because the recogniser runs in whichever one is chosen.
const _answerWords = {
  'yes',
  'yeah',
  'yep',
  'yup',
  'no',
  'nope',
  'ok',
  'okay',
  'ya',
  'iya',
  'tidak',
  'nggak',
  'enggak',
  'oke',
};

/// Collapses "no no" back to "no".
///
/// A very short answer is often below what the recogniser will commit to, so
/// the child says it again — and Google, once it has heard the second one,
/// re-scores the first and returns **both** as a single guess. The transcript
/// is not wrong (they did say it twice) but it is not what they meant.
///
/// Deliberately narrow: only when the *whole* utterance is one answer word
/// repeated. Reduplication is meaningful elsewhere — "bye bye", "night night",
/// "knock knock" — and collapsing those would be worse than the problem.
String collapseRepeatedAnswer(String text) {
  final raw = text.trim().split(RegExp(r'\s+'));
  if (raw.length < 2) return text;
  final words = _spokenWords(text);
  if (!_answerWords.contains(words.first)) return text;
  if (words.any((w) => w != words.first)) return text;
  return raw.first;
}

String appendHeard(String banked, String pending) {
  final tail = pending.trim();
  if (tail.isEmpty) return banked;
  if (banked.isEmpty) return tail;

  final bankedWords = _spokenWords(banked);
  final tailWords = _spokenWords(tail);
  final rawTail = tail.split(RegExp(r'\s+'));

  // The longest run of leading `pending` words that `banked` already ends
  // with, compared **lowercased and without punctuation**. The recogniser
  // capitalises the first word of every fresh guess, so a child who repeats
  // themselves produces "No" then "no" — the same word said once, which a
  // literal comparison turned into "No no".
  for (var take = tailWords.length; take > 0; take--) {
    if (_endsWithRun(bankedWords, tailWords.take(take).toList())) {
      final rest = rawTail.skip(take).join(' ');
      return rest.isEmpty ? banked : '$banked $rest';
    }
  }
  return '$banked $tail';
}

/// One entry per whitespace-separated token, lowercased and stripped of
/// punctuation, so positions still line up with the original text.
List<String> _spokenWords(String text) => text
    .trim()
    .split(RegExp(r'\s+'))
    .map((w) => w.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), ''))
    .toList();

bool _endsWithRun(List<String> whole, List<String> run) {
  if (run.isEmpty || run.length > whole.length) return false;
  final offset = whole.length - run.length;
  for (var i = 0; i < run.length; i++) {
    if (whole[offset + i] != run[i]) return false;
  }
  return true;
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
/// Removes Pollie's own voice from the front of what the microphone heard.
///
/// The mic only opens after she has finished, but Android reports an utterance
/// complete a little before the audio has actually drained, and a room with any
/// reverb hands the tail back. Without this, Pollie occasionally transcribes
/// herself and then answers it.
///
/// Deliberately timid. It only strips a run of at least [minEchoWords] words
/// that Pollie really did just say, from the very start of what was heard — so
/// a child answering "yes" to "…do you want a story, yes or no?" is never
/// mistaken for an echo.
const minEchoWords = 3;

/// Whether [next] is the same hypothesis as [previous], still growing.
///
/// Android's recogniser does not only *extend* its guess. At a pause it wipes
/// it and starts a new one **inside the same session** — measured on a Xiaomi
/// 15, "tell me a story" was followed by an empty partial and then
/// " about a big dinosaur". Nothing marks that moment: no final result, no
/// session end, no error. Assigning the new text over the old one therefore
/// loses everything said before the pause, which is exactly what turned
/// "in minecraft how do you create a tnt" into half a question.
///
/// A shrinking guess is normal backtracking and is *not* a reset.
bool continuesHypothesis(String previous, String next) {
  final before = previous.trim().toLowerCase();
  final after = next.trim().toLowerCase();
  if (before.isEmpty) return true;
  // The empty partial is the recogniser announcing it has started over.
  if (after.isEmpty) return false;
  return after.startsWith(before) || before.startsWith(after);
}

String stripEcho(String spoken, String heard) {
  final said = _echoWords(spoken);
  final got = _echoWords(heard);
  if (said.isEmpty || got.length < minEchoWords) return heard;

  // Longest prefix of `heard` that Pollie's last line contains as a run.
  var strip = 0;
  for (var take = got.length; take >= minEchoWords; take--) {
    final run = got.take(take).join(' ');
    if (said.join(' ').contains(run)) {
      strip = take;
      break;
    }
  }
  if (strip == 0) return heard;
  final rest = heard.trim().split(RegExp(r'\s+')).skip(strip).join(' ');
  return rest;
}

List<String> _echoWords(String text) {
  final clean = text
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .trim();
  if (clean.isEmpty) return const [];
  return clean.split(RegExp(r'\s+'));
}

int lastSentenceEnd(String text, int from) {
  var cut = from;
  for (final match in _sentenceEnd.allMatches(text, from)) {
    cut = match.end;
  }
  return cut;
}

class CompanionScreen extends StatefulWidget {
  const CompanionScreen({super.key, this.pollie, this.ttsService, this.speech});

  /// Injectable for tests; production builds its own, pointed at the proxy.
  final PollieService? pollie;

  /// Injectable for tests; production shares the app's one TTS engine.
  final TtsService? ttsService;

  /// Injectable for tests; production drives the patched recogniser.
  final SpeechSink? speech;

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
  late final TtsService _ttsService = widget.ttsService ?? TtsService.instance;
  TtsSession? _tts;
  late final SpeechSink _speech = widget.speech ?? PluginSpeechSink();
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
  // A turn is the child's, not the recogniser's. The recogniser ends sessions
  // whenever it likes; a session ending banks its words and re-arms the mic.
  // The turn ends only when the child stops speaking, releases a held mic,
  // taps the mic, hits the 45s cap, or hits a real error.
  //
  // **The app decides when the child stopped, from the sound level.** Every
  // other clock in this stack measures the wrong thing:
  //
  //   - the package's `pauseFor` stops the session N ms after the transcribed
  //     *text last changed*, which is not silence at all — a child still
  //     talking while the guess is stable gets cut off, and the words spoken
  //     during the restart are gone. That is what turned "in minecraft how do
  //     you create a tnt?" into "in minecraft how do you". It is now null.
  //   - Android's own two silence timers are set past ours, so they are a
  //     safety net rather than a competitor.
  //   - the old `_armQuietTimer` re-armed on any recogniser activity, which in
  //     a noisy room meant never.
  //
  // The other half is knowing when the mic is actually recording. The plugin
  // reports `listening` before it has even asked the recogniser to start, so
  // the child was being invited to speak into a dead mic — which is why the
  // first words went missing from the second turn on, and why a word as short
  // as "yes" could vanish entirely. The patched plugin now forwards Android's
  // `onReadyForSpeech`, and nothing tells the child to speak until it arrives.
  //
  // `_restarting` stays: `onResult(finalResult: true)` and `onStatus('done')`
  // both fire for one session ending, and without the guard they race into
  // "recognizer busy" and the turn goes deaf. That bug has been fixed once
  // already. Do not remove it.

  /// Hard stop, so a turn can never leave the mic live forever.
  static const _maxTurn = Duration(seconds: 45);

  /// Real silence, measured by us, that ends a turn once there is something to
  /// answer.
  ///
  /// This is the single most important number in the feature. It is now
  /// *acoustic* silence rather than "the transcript stopped moving", so it can
  /// be far shorter than the four seconds it replaces — but it still has to
  /// survive a four-year-old thinking mid-sentence, which reaches about two
  /// seconds ("in minecraft how do you … create a tnt"). Two seconds of
  /// tolerance plus a tick plus jitter.
  static const _endTurnOnSilence = Duration(milliseconds: 2200);

  /// The same, once the recogniser has also declared the utterance finished.
  ///
  /// Two independent endpointers agreeing is worth 1.3 seconds: it is what
  /// makes a one-word answer feel like an answer instead of a wait.
  static const _endTurnAfterFinal = Duration(milliseconds: 900);

  /// How long an open mic waits when it has heard no *voice* at all.
  ///
  /// Shorter than the twelve seconds it replaces because the signal is now
  /// trustworthy: this is silence, not "the recogniser said nothing useful".
  static const _noVoiceGivesUp = Duration(seconds: 8);

  /// How long it waits when it *has* heard a voice but transcribed nothing.
  ///
  /// A different failure from silence and it gets a different answer: the
  /// child is told to say it again rather than left wondering.
  static const _noWordsGivesUp = Duration(seconds: 12);

  /// How long to wait for the "microphone is recording" signal before assuming
  /// it arrived.
  ///
  /// Nothing may *depend* on that signal: iOS, macOS and web have no
  /// equivalent, and an OEM Android may not send it. It is an improvement when
  /// present and invisible when absent.
  static const _readyTimeout = Duration(milliseconds: 1200);

  /// Below this, a press was a tap; above it, a deliberate hold.
  ///
  /// Under Flutter's 500ms long-press threshold, because a four-year-old's
  /// "tap" is slow and a long-press gesture would lose the first half second
  /// of a held turn.
  static const _holdIsDeliberate = Duration(milliseconds: 250);

  /// How long the mic stays open after a held button is released.
  ///
  /// Android's audio pipeline lags the finger by a couple of hundred
  /// milliseconds; closing on the release itself clips the last syllable.
  static const _holdReleaseTail = Duration(milliseconds: 350);

  /// Gap between stopping one session and starting the next.
  static const _restartGap = Duration(milliseconds: 60);

  /// Consecutive turns that hear nothing before the mic stops re-opening
  /// itself, so a noisy room cannot leave it hot forever.
  static const _emptyTurnsBeforeStop = 2;

  /// Everything the turn's finished sessions have produced so far. A turn
  /// spans however many sessions the recogniser decides to end, so this
  /// accumulates across all of them; `_partial` holds whatever the live
  /// session is still guessing.
  String _heard = '';
  Timer? _turnTimer;
  Timer? _readyTimer;
  Timer? _holdReleaseTimer;

  /// Ticks while the microphone is genuinely recording, accumulating silence.
  ///
  /// Deliberately an accumulator rather than `now - lastVoiceAt`. A restart
  /// produces no sound-level events, so a wall-clock measure would count our
  /// own plumbing as the child being quiet and could end the turn on it. Some
  /// recognisers also stop reporting levels in true silence, which would stall
  /// a reset-on-event scheme. And `Timer` is controllable inside a widget test
  /// while `DateTime.now()` is not — without this choice none of the turn
  /// machine could be tested at all.
  Timer? _vadTicker;
  int _silenceMs = 0;
  int _openMs = 0;
  final VadGate _vad = VadGate();

  /// True between the mic actually recording and the session ending. Gates the
  /// ticker, so restart gaps contribute no silence.
  bool _micLive = false;

  /// Runs when the recogniser has declared the utterance finished *and* the
  /// room is quiet — the fast path that makes a one-word answer feel like an
  /// answer.
  ///
  /// It has to be its own timer rather than a branch in the tick, because a
  /// final result restarts the session and the microphone goes cold for a few
  /// hundred milliseconds; the silence accumulator is deliberately paused for
  /// exactly that window, so it cannot be the thing that notices.
  ///
  /// Cancelled the moment anything is heard again, so a child who was only
  /// drawing breath is never cut off.
  Timer? _finalQuietTimer;

  /// Whether a voice has been heard at any point in *this turn*.
  ///
  /// Tracked here rather than read from [VadGate], because the gate is reset
  /// on every session restart to re-measure the room — which also wiped this,
  /// so "they spoke but I could not make it out" almost never fired and a
  /// child whose short answer failed got no feedback at all.
  bool _turnHeardVoice = false;

  /// Set when the device reports no sound levels at all, so the whole VAD is
  /// unavailable and endpointing falls back to transcript stability.
  bool _vadUnavailable = false;
  int _levelEvents = 0;

  TurnState _turn = TurnState.idle;
  TurnMode _mode = TurnMode.tap;
  int _emptyTurns = 0;

  /// Set once the press has lasted long enough to count as a deliberate hold.
  ///
  /// A [Timer] rather than comparing `DateTime.now()` at press and release:
  /// wall-clock time does not advance inside a widget test, so a held button
  /// would always look like an instant tap and none of the hold behaviour
  /// could be tested.
  Timer? _holdTimer;
  bool _heldLongEnough = false;

  bool get _turnActive => _turn != TurnState.idle && _turn != TurnState.closing;

  /// Single-flight guard around re-arming the mic. Both `onResult`'s final
  /// branch and `onStatus('done')` fire for one session ending; without this
  /// they race into "recognizer busy" and the turn goes deaf.
  bool _restarting = false;

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
    _turn = TurnState.idle;
    _micLive = false;
    _turnTimer?.cancel();
    _readyTimer?.cancel();
    _holdReleaseTimer?.cancel();
    _finalQuietTimer?.cancel();
    _vadTicker?.cancel();
    _speakWatchdog?.cancel();
    try {
      _speech.stop();
      _tts?.stop();
    } catch (_) {}
    _tts?.release();
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
      _turn = TurnState.idle;
      _micLive = false;
      _turnTimer?.cancel();
      _readyTimer?.cancel();
      _holdReleaseTimer?.cancel();
      _finalQuietTimer?.cancel();
      _vadTicker?.cancel();
      _heard = '';
      try {
        _speech.stop();
        _tts?.stop();
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
      // A game-name announcement still in flight would talk over the greeting,
      // and its completion would land on the wrong owner.
      await Narrator.instance.stop();
      _tts = await _ttsService.acquire(this, queueMode: 1);
      _tts!.onComplete = _onUtteranceComplete;
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
          if (!mounted) return;
          // The patched plugin's "the microphone is really recording now".
          // Everything that invites the child to speak hangs off this.
          if (status == PluginSpeechSink.readyStatus) {
            _onMicReady();
            return;
          }
          if (status != PluginSpeechSink.doneStatus) return;
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
      // The *app's* language decides what Pollie listens for, not the phone's.
      // This used to read the system locale here and overwrite the choice
      // above, so on an English phone Pollie answered in Indonesian while
      // still listening in English — the child could not be understood.
      if (available) await _useAppLocale();
    } catch (_) {
      _speechAvailable = false;
    }
  }

  /// Points the recogniser at the chosen language.
  ///
  /// Only ever *narrows* to the device's own spelling of that language —
  /// Android reports `id_ID` as often as `id-ID`. It never falls back to a
  /// different language: listening in one the child is not speaking is worse
  /// than trying and failing. No offline pack is required, because the app
  /// does not force on-device recognition and Pollie needs the internet
  /// regardless.
  Future<void> _useAppLocale() async {
    final wanted = AppLanguageService.instance.current.value.localeId;
    try {
      final ids = await _speech.localeIds();
      final match = matchLocale(wanted, ids) ?? '';
      if (match.isEmpty) {
        // Not listed is not the same as not supported: this list often covers
        // only the *downloaded* offline packs, while Google's online
        // recogniser handles far more. Pollie needs the internet anyway, so
        // keep the chosen language and let the online recogniser take it.
        debugPrint(
          'Pollie: $wanted is not in this device\'s locale list, trying it '
          'anyway (online recognition usually covers it). '
          'Listed: ${ids.take(12).join(", ")}',
        );
        return;
      }
      _localeId = match;
      debugPrint('Pollie listening in $_localeId');
    } catch (e) {
      debugPrint('Pollie could not list speech locales: $e');
      _localeId = wanted;
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

  /// Opens the mic for a new turn.
  ///
  /// [hold] means the finger is still down: the child owns the endpoint, so
  /// silence detection is not allowed to end this turn.
  Future<void> _startListening({bool hold = false}) async {
    if (_turn != TurnState.idle) return;
    if (_status != _PollieStatus.awake || _busy) return;
    if (!_speechAvailable) {
      _bubbles.add(_Bubble(role: 'model', text: strings.pollieNoMic));
      _scrollToBottom();
      return;
    }
    _heard = '';
    _listenRetries = 0;
    _restarting = false;
    _micLive = false;
    _finalQuietTimer?.cancel();
    _silenceMs = 0;
    _openMs = 0;
    _levelEvents = 0;
    _vadUnavailable = false;
    _turnHeardVoice = false;
    _vad.reset();
    trace('turn_start', hold ? 'hold' : 'tap');
    _mode = hold ? TurnMode.hold : TurnMode.tap;
    _turn = TurnState.arming;
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

  /// Opens one recogniser session. The turn spans as many as it takes.
  Future<void> _listenOnce() async {
    if (!_turnActive || !mounted) return;
    try {
      await _speech.listen(
        localeId: _localeId,
        onResult: _onResult,
        onSoundLevel: _onSoundLevel,
      );
      if (!_turnActive || !mounted) return;
      _turn = TurnState.warming;
      // The plugin says "listening" before it has asked the recogniser to
      // start, so we wait for the patched `ready`. But never forever: a
      // platform without it must still work.
      _readyTimer?.cancel();
      _readyTimer = Timer(_readyTimeout, () => _onMicReady(guessed: true));
    } catch (e) {
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

  /// The microphone is now genuinely recording.
  ///
  /// Only here does the child get told to speak, and only here does the
  /// silence clock start — everything before this point is dead air that the
  /// old code counted as listening.
  void _onMicReady({bool guessed = false}) {
    _readyTimer?.cancel();
    _readyTimer = null;
    if (!_turnActive || !mounted) return;
    if (_micLive) return;
    trace('ready', guessed ? 'guessed' : 'real');
    _micLive = true;
    // Only the silence clock restarts with a session: nothing was captured
    // during the changeover, so that stretch is not evidence about the child.
    // `_openMs` deliberately does not, because it is what gives up on a turn
    // nobody is speaking into — resetting it per session meant a recogniser
    // that times out every few seconds kept the microphone open until the
    // 45-second cap.
    _silenceMs = 0;
    _vad.reset();
    if (_turn == TurnState.warming) _turn = TurnState.open;
    // Felt, not heard: a "go" beep would either land inside the recording or
    // have to play before the mic was hot, which is the bug being fixed.
    if (!guessed) HapticFeedback.selectionClick();
    _startVadTicker();
    setState(() {});
  }

  void _startVadTicker() {
    _vadTicker?.cancel();
    _vadTicker = Timer.periodic(VadGate.tick, (_) => _onVadTick());
  }

  void _onVadTick() {
    if (!_turnActive || !mounted) return;
    final ms = VadGate.tick.inMilliseconds;
    if (!_micLive) return; // a restart gap is not the child being quiet
    _openMs += ms;

    // A device that never reports levels cannot be endpointed acoustically.
    if (!_vadUnavailable && _levelEvents == 0 && _openMs >= 1000) {
      _vadUnavailable = true;
      debugPrint('Pollie: no sound levels from this device; using text timing');
    }

    if (_vad.isVoice) {
      _silenceMs = 0;
    } else {
      _silenceMs += ms;
    }

    // A held mic belongs to the finger. Nothing below may end it.
    if (_mode == TurnMode.hold) return;

    final hasWords = _transcript.trim().isNotEmpty;
    if (hasWords) {
      // Without levels there is nothing to measure, so fall back to the old
      // "transcript stopped moving" rule with a longer, safer window.
      final quietEnough = _vadUnavailable
          ? _silenceMs >= 3500
          : _silenceMs >= _endTurnOnSilence.inMilliseconds;
      if (quietEnough) {
        _endTurn(send: true);
        return;
      }
    }

    if (!_turnHeardVoice && _openMs >= _noVoiceGivesUp.inMilliseconds) {
      // Nobody spoke. Close quietly; there is nothing to apologise for.
      _emptyTurns++;
      _endTurn(send: false);
      return;
    }
    if (_turnHeardVoice &&
        !hasWords &&
        _openMs >= _noWordsGivesUp.inMilliseconds) {
      // They did speak and we could not make it out. Say so, rather than
      // closing silently and leaving them to guess why nothing happened.
      _emptyTurns++;
      _endTurn(send: false, sayAgain: true);
    }
  }

  void _onSoundLevel(double level) {
    if (!_turnActive) return;
    _levelEvents++;
    if (!_micLive) return;
    final voice = _vad.feed(level);
    if (voice) {
      _turnHeardVoice = true;
      // They are talking again: whatever the recogniser thought, this turn is
      // not over.
      _finalQuietTimer?.cancel();
      _finalQuietTimer = null;
    }
    final meter = _vad.normalised;
    if ((meter - _soundLevel).abs() > 0.02) {
      setState(() => _soundLevel = meter);
    }
  }

  void _onResult(SpeechRecognitionResult result) {
    if (!_turnActive) return;
    trace(result.finalResult ? 'final' : 'partial', result.recognizedWords);
    // Trimmed: a fresh hypothesis arrives with a leading space on the device,
    // which would otherwise show up as a double space once it is joined onto
    // the banked text.
    final words = stripEcho(_lastSpoken, result.recognizedWords).trim();
    // Bank the old hypothesis before it is overwritten by an unrelated one.
    if (!continuesHypothesis(_partial, words)) {
      _heard = appendHeard(_heard, _partial);
      trace('hypothesis_reset', _heard);
    }
    setState(() => _partial = words);
    if (!result.finalResult) return;

    final trimmed = words.trim();
    if (trimmed.isNotEmpty) {
      // Through appendHeard, not a raw concat: a recogniser that restates its
      // utterance in the next session would otherwise stutter — "do you do
      // you know". The de-duplicating join already existed and this path
      // simply never used it.
      _heard = appendHeard(_heard, trimmed);
    }
    setState(() => _partial = '');
    // A final means Android's own endpointer decided the utterance ended —
    // which, with the silence timers now set to four and six seconds, it does
    // not say lightly. If the room agrees, answer rather than making the child
    // wait for a fresh session to warm up just so the tick can notice.
    if (_mode == TurnMode.tap &&
        !_vad.isVoice &&
        _transcript.trim().isNotEmpty) {
      _finalQuietTimer?.cancel();
      _finalQuietTimer = Timer(_endTurnAfterFinal, () {
        if (_turnActive && !_vad.isVoice) _endTurn(send: true);
      });
    }
    // This session is done; the turn is not.
    _restartSession();
  }

  /// Moves whatever the recogniser is currently guessing into the banked
  /// transcript, so a session ending cannot lose it.
  void _bankPartial() {
    final pending = _partial.trim();
    if (pending.isEmpty) return;
    _heard = appendHeard(_heard, pending);
    if (mounted) setState(() => _partial = '');
  }

  /// Re-arms the mic for the same turn after a session ends.
  Future<void> _restartSession() async {
    if (!_turnActive || !mounted || _restarting) return;
    trace('restart', 'heard=$_heard partial=$_partial');
    _restarting = true;
    // The dying session's guess would otherwise be overwritten by the next
    // session's first result rather than appended, and simply disappear.
    _bankPartial();
    // Nothing is being captured from here until `ready` arrives again, so the
    // silence clock must not run.
    _micLive = false;
    _turn = TurnState.warming;
    if (mounted) setState(() {});
    try {
      if (_speech.isListening) {
        try {
          await _speech.stop();
        } catch (_) {}
      }
      await Future<void>.delayed(_restartGap);
      if (!_turnActive || !mounted) return;
      await _listenOnce();
    } finally {
      _restarting = false;
    }
  }

  /// Ends the turn, optionally sending everything banked during it.
  void _endTurn({required bool send, bool sayAgain = false}) {
    if (_turn == TurnState.idle && _heard.isEmpty) {
      if (mounted && _status == _PollieStatus.listening) {
        setState(() {
          _status = _PollieStatus.awake;
          _busy = false;
          _partial = '';
        });
      }
      return;
    }
    trace('endturn', 'send=$send transcript=${_transcript.trim()}');
    _turn = TurnState.closing;
    _restarting = false;
    _micLive = false;
    _turnTimer?.cancel();
    _turnTimer = null;
    _readyTimer?.cancel();
    _readyTimer = null;
    _holdReleaseTimer?.cancel();
    _holdReleaseTimer = null;
    _finalQuietTimer?.cancel();
    _finalQuietTimer = null;
    _vadTicker?.cancel();
    _vadTicker = null;
    try {
      _speech.stop();
    } catch (_) {}

    // Banked words plus whatever the live session was still guessing — on a
    // mic tap mid-sentence, `_partial` is the only place the last few words
    // exist.
    final words = collapseRepeatedAnswer(_transcript.trim());
    _heard = '';
    _turn = TurnState.idle;
    if (!mounted) return;
    setState(() {
      _status = _PollieStatus.awake;
      _busy = false;
      _partial = '';
      _soundLevel = 0;
    });
    if (send && words.isNotEmpty) {
      _emptyTurns = 0;
      _send(words);
    } else if (sayAgain) {
      _bubbles.add(_Bubble(role: 'model', text: strings.pollieSayAgain));
      _scrollToBottom();
      // One retry, then stop: a room that is simply too noisy must not leave
      // the mic cycling open forever.
      if (_emptyTurns < _emptyTurnsBeforeStop) {
        Future<void>.delayed(const Duration(milliseconds: 400), () {
          if (mounted && _status == _PollieStatus.awake) _startListening();
        });
      }
    }
  }

  /// Tapping the mic while it is live means "I'm done".
  void _stopListening() => _endTurn(send: true);

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

  /// Recogniser errors that just mean "that session heard nothing useful".
  ///
  /// A four-year-old pausing to think produces these constantly. They are not
  /// failures, they are the recogniser shrugging.
  static const _recoverableSpeechErrors = {
    'error_no_match',
    'error_speech_timeout',
  };

  /// Errors worth one quiet retry: the engine was momentarily unavailable.
  static const _retryableSpeechErrors = {
    'error_busy',
    'error_client',
    'error_audio_error',
    'error_server',
    'error_server_disconnected',
    'error_network',
    'error_network_timeout',
  };

  void _onSpeechError(SpeechRecognitionError error) {
    if (!mounted) return;
    final name = error.errorMsg.toLowerCase().trim();

    // `error.permanent` is deliberately ignored. The Android plugin hardcodes
    // it to true for *every* error it sends, including error_no_match — so
    // trusting it meant a child pausing mid-sentence ended the whole turn and
    // sent half a question. Classify by name instead.
    trace('speech_error', name);
    if (_turnActive && _recoverableSpeechErrors.contains(name)) {
      _restartSession();
      return;
    }

    if (_turnActive &&
        _retryableSpeechErrors.contains(name) &&
        _listenRetries < 2) {
      _listenRetries++;
      _restartSession();
      return;
    }

    if (!_recoverableSpeechErrors.contains(name)) {
      debugPrint('Pollie speech error: $name');
      _bubbles.add(_Bubble(role: 'model', text: strings.pollieDidntCatch));
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
        throw const PollieEmptyReplyException();
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
      // An empty reply and a short pause are both hiccups, not breakdowns.
      // Sleeping on them greyed out the mic and stranded the child.
      final hiccup = brief || e is PollieEmptyReplyException;
      setState(() {
        _bubbles.removeLast();
        _bubbles.add(
          _Bubble(
            role: 'model',
            text: e is PollieEmptyReplyException
                ? strings.pollieSayAgain
                : brief
                ? strings.pollieBreath
                : quota
                ? strings.pollieOutOfWords(_pollie.quotaResetLabel())
                : _pollie.isConfigured
                ? strings.pollieLost
                : strings.pollieNoKey,
          ),
        );
        // A hiccup leaves Pollie awake; only a real failure puts him to
        // sleep. A sleeping Pollie disables the mic, and a child cannot work
        // out that they must tap his face to bring it back.
        _status = hiccup ? _PollieStatus.awake : _PollieStatus.sleeping;
        _busy = false;
      });
      // Keep the conversation going rather than making the child restart it.
      if (hiccup && _speechAvailable) {
        Future<void>.delayed(const Duration(milliseconds: 900), () {
          if (mounted && _status == _PollieStatus.awake) _startListening();
        });
      }
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

  /// The voice dump is a diagnostic, not a running commentary — once a session.
  bool _loggedVoices = false;

  /// `getVoices` hands back the raw platform-channel value: a `List<Object?>`
  /// of `Map<Object?, Object?>`. Casting that straight to
  /// `List<Map<dynamic, dynamic>>` throws — `Object?` is not a `Map` — which
  /// is how voice selection silently did nothing for so long. Rebuild the
  /// list element by element instead of asserting a shape it never has.
  Future<List<Map<dynamic, dynamic>>> _loadVoices() async {
    final raw = await _tts?.getVoices();
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
      // The whole shortlist, once. Without it a thin-sounding Pollie is
      // indistinguishable from a device that genuinely has nothing better —
      // and the two have completely different fixes. Read it from a --profile
      // build; debugPrint does not reach logcat in release (golden rule 11).
      if (!_loggedVoices) {
        _loggedVoices = true;
        final shortlist = (_cachedVoices ?? const [])
            .where(
              (v) => (v['locale'] ?? '').toString().toLowerCase().startsWith(
                lang.split('-').first.toLowerCase(),
              ),
            )
            .map(
              (v) =>
                  '${v['name']} [${v['locale']}] q=${v['quality']} '
                  'net=${v['network_required']} score=${voiceScore(v, lang)}',
            );
        debugPrint(
          'TTS| ${_cachedVoices?.length ?? 0} voices total, '
          '${shortlist.length} for $lang:',
        );
        for (final line in shortlist) {
          debugPrint('TTS|   $line');
        }
      }
      final best = pickBestVoice(_cachedVoices, lang);
      if (best == null) {
        debugPrint('TTS| no voice for $lang — keeping the engine default');
        return;
      }
      // Never trade a working engine default for a voice we know nothing
      // about: without a quality rating there is no reason to think ours is
      // an improvement. (Checking the rating itself, not the score — bonuses
      // alone can lift an unrated voice past any threshold.)
      final quality = (best['quality'] ?? '').toString().toLowerCase();
      if (!_qualityRank.containsKey(quality)) {
        debugPrint(
          'TTS| best for $lang is ${best['name']} but its quality is '
          '"${best['quality']}" — unrated, so keeping the engine default',
        );
        return;
      }
      debugPrint(
        'TTS| voice: ${best['name']} (${best['locale']}, '
        'quality=${best['quality']}, network=${best['network_required']}, '
        'score=${voiceScore(best, lang)})',
      );
      await _tts?.setVoice(best.cast<String, String>());
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

  /// The last thing Pollie said, for the echo guard.
  String _lastSpoken = '';

  /// Utterances handed to the TTS engine that have not finished yet.
  int _pending = 0;

  /// True while a reply is still streaming and may add more sentences.
  bool _moreComing = false;

  /// Whether to re-arm the mic once everything queued has been spoken.
  bool _relisten = false;

  /// Last resort for a TTS engine that never reports a completion.
  ///
  /// Everything downstream of "Pollie finished talking" hangs off [_pending]
  /// reaching zero — including re-opening the microphone. One dropped
  /// `onDone` used to mean the mic never came back for the rest of the
  /// session, with nothing on screen to say why. Owning the engine (see
  /// [TtsService]) removes the known cause; this makes the *symptom*
  /// impossible whatever the cause.
  Timer? _speakWatchdog;
  static const _speakWatchdogAfter = Duration(seconds: 10);

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
    trace('tts_speak', clean);
    _lastSpoken = clean;
    _pending++;
    _armSpeakWatchdog();
    try {
      await _tts?.speak(clean);
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
      await _tts?.setLanguage(lang);
      await _applyBestVoice(lang);
      // Just above natural: enough to read as friendly, not so high that the
      // synthesiser starts to sound like a chipmunk. Pushing pitch hard is
      // what made Pollie sound robotic, not the speed.
      await _tts?.setPitch(1.1);
      await _tts?.setSpeechRate(0.45);
    } catch (e) {
      debugPrint('Pollie voice setup failed: $e');
    }
    return lang;
  }

  void _armSpeakWatchdog() {
    _speakWatchdog?.cancel();
    _speakWatchdog = Timer(_speakWatchdogAfter, () {
      if (!mounted || _pending == 0) return;
      debugPrint('Pollie TTS never reported done; releasing the mic anyway');
      _pending = 0;
      _moreComing = false;
      _finishSpeakingIfDone();
    });
  }

  void _onUtteranceComplete() {
    trace('tts_done', _pending);
    _pending = _pending > 0 ? _pending - 1 : 0;
    if (_pending == 0) {
      _speakWatchdog?.cancel();
      _speakWatchdog = null;
    } else {
      _armSpeakWatchdog();
    }
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

  /// True while the mic has been asked for but is not yet recording.
  bool get _micWarming =>
      _turn == TurnState.arming || _turn == TurnState.warming;

  /// Amber means "nearly", red means "talk now".
  ///
  /// The distinction is the whole point: the plugin reports "listening" up to
  /// half a second before the microphone is actually capturing, and a child
  /// invited to speak in that window loses their first words.
  Color get _micColor {
    if (_micWarming) return const Color(0xFFFFB300);
    if (_status == _PollieStatus.listening) return const Color(0xFFFF5252);
    return Colors.white;
  }

  /// Finger down on the mic.
  ///
  /// The turn starts here rather than on the tap, for two reasons: it opens
  /// the microphone roughly a tenth of a second earlier even for a plain tap,
  /// and it means hold and tap share one path. Only the *release* differs,
  /// which is what makes "released before the mic was even ready" behave.
  void _onMicDown() {
    _heldLongEnough = false;
    _holdTimer?.cancel();
    _holdTimer = Timer(_holdIsDeliberate, () => _heldLongEnough = true);
    switch (_status) {
      case _PollieStatus.listening:
        // Already live: this press is the child saying "I'm done", handled on
        // release so a hold-to-continue still works.
        break;
      case _PollieStatus.sleeping:
        _wakeUp();
      case _PollieStatus.awake:
        _startListening(hold: true);
      case _PollieStatus.thinking:
        break;
      case _PollieStatus.speaking:
        // Interrupting is allowed by pressing the button — that is the one
        // barge-in the design keeps, because it cannot be confused with the
        // microphone hearing Pollie herself.
        _relisten = false;
        _moreComing = false;
        _pending = 0;
        _speakWatchdog?.cancel();
        _tts?.stop();
        setState(() => _status = _PollieStatus.awake);
        _startListening(hold: true);
    }
  }

  /// Finger up. The length of the press decides who owns the endpoint.
  void _onMicUp() {
    _holdTimer?.cancel();
    _holdTimer = null;
    final wasHeld = _heldLongEnough;
    _heldLongEnough = false;
    if (_turn == TurnState.idle) return;

    if (!wasHeld) {
      // That was a tap. If a turn was already running it means "I'm done";
      // otherwise the mic stays open and silence detection takes over.
      if (_mode == TurnMode.tap) {
        _stopListening();
        return;
      }
      setState(() => _mode = TurnMode.tap);
      return;
    }

    // A deliberate hold. Keep recording briefly: Android's audio pipeline lags
    // the finger, so closing on the release itself clips the last syllable.
    _holdReleaseTimer?.cancel();
    _holdReleaseTimer = Timer(_holdReleaseTail, () {
      if (_turnActive) _endTurn(send: true);
    });
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
                      Listener(
                        // Listener, not GestureDetector: onLongPressStart only
                        // fires after Flutter's 500ms threshold, which would
                        // lose the first half-second of a held turn, and a
                        // four-year-old's "tap" is slow enough to trip it.
                        onPointerDown: (_) => _onMicDown(),
                        onPointerUp: (_) => _onMicUp(),
                        // A finger dragged off the button must not strand a
                        // hot microphone.
                        onPointerCancel: (_) => _onMicUp(),
                        child: Semantics(
                          button: true,
                          label: strings.talkToPollie,
                          child: Opacity(
                            opacity:
                                (_status == _PollieStatus.awake ||
                                    _status == _PollieStatus.listening)
                                ? 1.0
                                : 0.45,
                            // Colour and padding only — never a transform.
                            // This button used to sit inside an AnimatedScale
                            // driven by the sound level, which re-rasterises
                            // the emoji glyph every frame and eventually stops
                            // emoji painting app-wide (golden rule 4). The
                            // level now moves a bar's *width*, which is
                            // layout, not a transform.
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _micColor,
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.black26,
                                    blurRadius: 4,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                              // Amber "wait" shifts the emoji 2px down, so the
                              // button reads as pressed-in even before it goes
                              // red. A traffic light is a convention a
                              // four-year-old already knows.
                              padding: _micWarming
                                  ? const EdgeInsets.fromLTRB(12, 14, 12, 10)
                                  : const EdgeInsets.all(12),
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
