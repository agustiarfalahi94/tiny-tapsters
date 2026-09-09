import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Where spoken words actually go.
///
/// Exists for the same reason [MusicSink] does: everything below this line is
/// a plugin call, and the ownership logic above it is worth testing.
abstract interface class TtsSink {
  Future<void> setQueueMode(int mode);
  Future<void> setLanguage(String locale);
  Future<void> setPitch(double pitch);
  Future<void> setSpeechRate(double rate);
  Future<void> setVoice(Map<String, String> voice);
  Future<dynamic> getVoices();
  Future<dynamic> getEngines();
  Future<dynamic> getDefaultEngine();
  Future<void> setEngine(String engine);
  Future<void> speak(String text);
  Future<void> stop();

  void setCompletionHandler(VoidCallback handler);
  void setCancelHandler(VoidCallback handler);
  void setErrorHandler(void Function(dynamic message) handler);
}

/// The app's one and only text-to-speech engine.
///
/// **Why this exists at all.** `flutter_tts` talks over a `static const
/// MethodChannel('flutter_tts')`, and every `FlutterTts()` constructor calls
/// `setMethodCallHandler` on it. So the last instance constructed anywhere in
/// the process silently owns *every* callback — including `speak.onComplete`.
///
/// The app used to build two: one in [Narrator] and one in Pollie's screen.
/// Whichever lost the race stopped hearing its own completions. For Pollie
/// that is not cosmetic: `_pending` never reaches zero, the "everything I
/// queued has been said" condition never fires, and **the microphone never
/// re-opens**. It presented as "sometimes Pollie just stops listening", which
/// is exactly the kind of bug that is impossible to reproduce on demand.
///
/// One engine, one set of handlers, installed once. Callers take a
/// [TtsSession]; the newest one wins, and a late callback from a released
/// session is dropped rather than decrementing somebody else's counter.
class TtsService {
  TtsService._() : _sink = _PluginTts() {
    _wire();
  }

  @visibleForTesting
  TtsService.withSink(TtsSink sink) : _sink = sink {
    _wire();
  }

  static final TtsService instance = TtsService._();

  final TtsSink _sink;
  TtsSession? _current;

  /// The one engine-selection pass. Installed engines cannot change while the
  /// app is running, and switching costs a rebuilt platform engine, so this
  /// runs once and every later acquisition awaits the same result.
  Future<void>? _engineChosen;

  /// Google's is the only Android engine we can name that reliably ships
  /// neural voices — the `network_required` ones `voiceScore` already ranks
  /// highest. Everything else is a gamble, and the rule voice selection
  /// follows applies here too: never trade a working default for something we
  /// know nothing about.
  static const _preferredEngine = 'com.google.android.tts';

  /// Moves to [_preferredEngine] when it is installed and not already in use.
  ///
  /// **Why this is needed at all.** `pickBestVoice` can only rank what
  /// `getVoices` returns, and that is the voices of the *bound* engine. On a
  /// device whose default is a basic engine, careful scoring picks the best of
  /// a bad set and Pollie sounds like a robot with no sign anything is wrong.
  ///
  /// This depends on `android.intent.action.TTS_SERVICE` being declared in the
  /// manifest's `<queries>`: without it Android 11+ package visibility hides
  /// every engine from `getEngines`, and the list comes back empty.
  Future<void> _ensureEngine() {
    return _engineChosen ??= () async {
      try {
        final raw = await _sink.getEngines();
        final engines = raw is List
            ? raw.whereType<String>().toList()
            : <String>[];
        final current = (await _sink.getDefaultEngine())?.toString();
        debugPrint('TTS| engines: $engines (default: $current)');
        if (!engines.contains(_preferredEngine)) return;
        if (current == _preferredEngine) return;
        await _sink.setEngine(_preferredEngine);
        debugPrint('TTS| engine switched to $_preferredEngine');
      } catch (e) {
        // Pollie going quiet is far worse than Pollie sounding thin.
        debugPrint('TTS| engine selection failed: $e');
      }
    }();
  }

  void _wire() {
    _sink.setCompletionHandler(() => _current?._complete());
    _sink.setCancelHandler(() => _current?._complete());
    _sink.setErrorHandler((message) {
      debugPrint('TTS error: $message');
      _current?._complete();
    });
  }

  /// Takes the engine for [owner], stopping whoever had it.
  ///
  /// [queueMode] is applied per acquisition rather than once at startup: the
  /// Narrator wants 0 (replace, so tapping through three games speaks only the
  /// last), Pollie wants 1 (queue, so sentence-by-sentence replies do not cut
  /// each other off). It is global engine state, so it has to be re-applied by
  /// whoever is speaking rather than assumed.
  Future<TtsSession> acquire(Object owner, {required int queueMode}) async {
    final previous = _current;
    if (previous != null && !identical(previous.owner, owner)) {
      await previous.stop();
      previous._released = true;
    }
    final session = TtsSession._(this, owner);
    _current = session;
    // Before anything is configured: switching engines builds a new platform
    // TextToSpeech on its own defaults, discarding whatever was set first.
    await _ensureEngine();
    try {
      await _sink.setQueueMode(queueMode);
    } catch (e) {
      debugPrint('TTS queue mode failed: $e');
    }
    return session;
  }
}

/// One caller's handle on the shared engine.
class TtsSession {
  TtsSession._(this._service, this.owner);

  final TtsService _service;
  final Object owner;
  bool _released = false;

  /// Called once per utterance that finishes, is cancelled, or errors.
  VoidCallback? onComplete;

  /// False once somebody else has taken the engine. Callbacks stop arriving.
  bool get isCurrent => !_released && identical(_service._current, this);

  void _complete() {
    if (!isCurrent) return;
    onComplete?.call();
  }

  Future<void> setLanguage(String locale) =>
      _guard(_service._sink.setLanguage(locale));
  Future<void> setPitch(double pitch) => _guard(_service._sink.setPitch(pitch));
  Future<void> setSpeechRate(double rate) =>
      _guard(_service._sink.setSpeechRate(rate));
  Future<void> setVoice(Map<String, String> voice) =>
      _guard(_service._sink.setVoice(voice));

  Future<dynamic> getVoices() async {
    try {
      return await _service._sink.getVoices();
    } catch (e) {
      debugPrint('TTS getVoices failed: $e');
      return null;
    }
  }

  Future<void> speak(String text) async {
    if (!isCurrent) return;
    await _service._sink.speak(text);
  }

  Future<void> stop() => _guard(_service._sink.stop());

  /// Gives the engine back. Safe to call twice.
  void release() {
    _released = true;
    if (identical(_service._current, this)) _service._current = null;
  }

  Future<void> _guard(Future<void> call) async {
    if (!isCurrent) return;
    try {
      await call;
    } catch (e) {
      debugPrint('TTS call failed: $e');
    }
  }
}

/// The real engine. The **only** `FlutterTts` in the app — see the class
/// comment on [TtsService], and the test that enforces it.
class _PluginTts implements TtsSink {
  final _tts = FlutterTts();

  @override
  Future<void> setQueueMode(int mode) => _tts.setQueueMode(mode);
  @override
  Future<void> setLanguage(String locale) async => _tts.setLanguage(locale);
  @override
  Future<void> setPitch(double pitch) async => _tts.setPitch(pitch);
  @override
  Future<void> setSpeechRate(double rate) async => _tts.setSpeechRate(rate);
  @override
  Future<void> setVoice(Map<String, String> voice) async =>
      _tts.setVoice(voice);
  @override
  Future<dynamic> getVoices() => _tts.getVoices;
  @override
  Future<dynamic> getEngines() => _tts.getEngines;
  @override
  Future<dynamic> getDefaultEngine() => _tts.getDefaultEngine;
  @override
  Future<void> setEngine(String engine) async => _tts.setEngine(engine);
  @override
  Future<void> speak(String text) async => _tts.speak(text);
  @override
  Future<void> stop() async => _tts.stop();
  @override
  void setCompletionHandler(VoidCallback handler) =>
      _tts.setCompletionHandler(handler);
  @override
  void setCancelHandler(VoidCallback handler) => _tts.setCancelHandler(handler);
  @override
  void setErrorHandler(void Function(dynamic message) handler) =>
      _tts.setErrorHandler(handler);
}
