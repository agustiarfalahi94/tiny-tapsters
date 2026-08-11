import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

export 'package:speech_to_text/speech_recognition_error.dart';
export 'package:speech_to_text/speech_recognition_result.dart';

/// Where listening actually happens.
///
/// Exists for the same reason [MusicSink] and [TtsSink] do, plus one specific
/// to this plugin: `SpeechToText()` is a **process-wide singleton** whose
/// `initialize()` short-circuits after the first success. Tests sharing it leak
/// `_listening`, `_notifyFinalTimer` and friends into each other and become
/// order-dependent, which is why the turn machine had no coverage at all until
/// this seam existed.
abstract interface class SpeechSink {
  Future<bool> initialize({
    required void Function(SpeechRecognitionError) onError,
    required void Function(String) onStatus,
  });

  Future<List<String>> localeIds();

  Future<void> listen({
    required void Function(SpeechRecognitionResult) onResult,
    required void Function(double) onSoundLevel,
    required String localeId,
  });

  Future<void> stop();

  bool get isListening;
}

/// The real recogniser, driving the vendored plugin.
class PluginSpeechSink implements SpeechSink {
  final _speech = SpeechToText();

  /// How long a session may run before Android ends it by itself. A cap, not
  /// an endpointer: a session ending no longer ends the child's turn.
  static const _sessionCap = Duration(seconds: 30);

  /// Android's *short* "probably finished" guess. Pushed out past the app's
  /// own 2.2s endpoint so the app always decides first and this stays a
  /// safety net rather than a competitor.
  static const _possiblyComplete = Duration(milliseconds: 4000);

  /// Android's *long* "definitely finished" timer. Set through the patched
  /// `completeSilence` rather than `pauseFor`, because `pauseFor` also arms a
  /// Dart-side timer that stops the session N ms after the transcribed text
  /// last *changed* — which cuts off a child who is still speaking. See
  /// `packages/PATCH.md`.
  static const _completeSilence = Duration(milliseconds: 6000);

  @override
  bool get isListening => _speech.isListening;

  @override
  Future<bool> initialize({
    required void Function(SpeechRecognitionError) onError,
    required void Function(String) onStatus,
  }) => _speech.initialize(onError: onError, onStatus: onStatus);

  @override
  Future<List<String>> localeIds() async {
    final locales = await _speech.locales();
    return locales.map((l) => l.localeId).toList();
  }

  @override
  Future<void> listen({
    required void Function(SpeechRecognitionResult) onResult,
    required void Function(double) onSoundLevel,
    required String localeId,
  }) => _speech.listen(
    onResult: onResult,
    onSoundLevelChange: onSoundLevel,
    listenOptions: SpeechListenOptions(
      localeId: localeId,
      possiblyCompleteSilence: _possiblyComplete,
      completeSilence: _completeSilence,
      listenFor: _sessionCap,
      // Deliberately null. `pauseFor` would arm the package's Dart-side timer
      // (see _completeSilence above); `minimumLength` forced every session to
      // run at least three seconds, which made a one-word answer wait for a
      // timer that had nothing to wait for.
      pauseFor: null,
      minimumLength: null,
    ),
  );

  @override
  Future<void> stop() => _speech.stop();

  /// The status the patched plugin sends when the microphone is genuinely
  /// recording — as opposed to `listening`, which the plugin reports before it
  /// has even asked the recogniser to start.
  static const readyStatus = SpeechToText.readyStatus;

  /// The status for a recogniser session ending. Not the end of a turn.
  static const doneStatus = SpeechToText.doneStatus;
}

/// Kept out of the interface because only the production sink needs it.
@visibleForTesting
const speechReadyStatus = SpeechToText.readyStatus;
