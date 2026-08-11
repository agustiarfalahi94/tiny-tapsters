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
