import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text_platform_interface/speech_to_text_platform_interface.dart';
import 'package:tiny_tapsters/services/speech_sink.dart';

/// Tests for the *vendored patch*, not for the app — see `packages/PATCH.md`.
///
/// Patch 1 (the two silence extras) genuinely could not be tested off-device,
/// which is why PATCH.md says so. Patch 2 can: it is about what reaches the
/// platform and what the Dart wrapper does with a status string, and both ends
/// are reachable through `SpeechToTextPlatform.instance`.
void main() {
  late FakeSpeechPlatform platform;
  late SpeechToText speech;

  setUp(() async {
    platform = FakeSpeechPlatform();
    SpeechToTextPlatform.instance = platform;
    // The public `SpeechToText()` is a process-wide singleton whose `_initWorked`
    // short-circuits initialize(), so tests sharing it leak state into each
    // other. The package exposes this constructor for exactly this reason.
    speech = SpeechToText.withMethodChannel();
  });

  Future<void> initialize({
    void Function(String)? onStatus,
    void Function(SpeechRecognitionError)? onError,
  }) async {
    platform.initResult = true;
    await speech.initialize(onStatus: onStatus, onError: onError);
  }

  group('the options actually reach the platform', () {
    test(
      'completeSilence is marshalled, and pauseFor can be left null',
      () async {
        await initialize();
        await speech.listen(
          listenOptions: SpeechListenOptions(
            completeSilence: const Duration(milliseconds: 6000),
            possiblyCompleteSilence: const Duration(milliseconds: 4000),
          ),
        );

        final options = platform.lastOptions!;
        expect(options.completeSilence, const Duration(milliseconds: 6000));
        expect(
          options.possiblyCompleteSilence,
          const Duration(milliseconds: 4000),
        );
        // The whole point of the option: no pauseFor means the package's
        // Dart-side _listenTimer is never armed, so nothing stops the session
        // N ms after the transcript last *changed*.
        expect(options.pauseFor, isNull);
        expect(options.minimumLength, isNull);
      },
    );

    test('copyWith carries completeSilence', () {
      // listen() re-copies the options when the deprecated positional
      // arguments are present, so a copyWith that forgets a field silently
      // discards it. PATCH.md flags this exact trap for the other two.
      final original = SpeechListenOptions(
        completeSilence: Duration(milliseconds: 6000),
        possiblyCompleteSilence: Duration(milliseconds: 4000),
        minimumLength: Duration(seconds: 1),
      );
      final copy = original.copyWith(localeId: 'id-ID');
      expect(copy.completeSilence, const Duration(milliseconds: 6000));
      expect(copy.possiblyCompleteSilence, const Duration(milliseconds: 4000));
      expect(copy.minimumLength, const Duration(seconds: 1));
    });
  });

  test('the app asks the recogniser for the right timers', () async {
    // The production sink is what actually ships; the turn tests drive a fake
    // one, so without this nothing would notice pauseFor creeping back in.
    SpeechToTextPlatform.instance = platform;
    final sink = PluginSpeechSink();
    await sink.initialize(onError: (_) {}, onStatus: (_) {});
    await sink.listen(
      onResult: (_) {},
      onSoundLevel: (_) {},
      localeId: 'en-US',
    );

    final options = platform.lastOptions!;
    // pauseFor arms the package's Dart-side timer, which stops the session N ms
    // after the transcribed text last CHANGED — the mechanism that cut a child
    // off mid-sentence. The app endpoints on real silence instead.
    expect(options.pauseFor, isNull);
    // minimumLength forced every session to run three seconds, so a one-word
    // answer waited on a timer with nothing to wait for.
    expect(options.minimumLength, isNull);
    // Both native timers sit well beyond the app's own 2.2s endpoint, so they
    // are a safety net rather than a competitor.
    expect(options.completeSilence!.inMilliseconds, greaterThan(2200));
    expect(options.possiblyCompleteSilence!.inMilliseconds, greaterThan(2200));
  });

  group('the readyForSpeech status', () {
    test('does not knock the wrapper out of the listening state', () async {
      // This is the load-bearing line of the patch. `ready` is an event, not a
      // state; if it falls through to `_listening = status == listeningStatus`
      // then isListening goes false while the mic is hot, which silently kills
      // sound levels and every isListening guard in callers.
      final seen = <String>[];
      await initialize(onStatus: seen.add);
      await speech.listen(listenOptions: SpeechListenOptions());
      platform.emitStatus(SpeechToText.listeningStatus);
      expect(speech.isListening, isTrue);

      platform.emitStatus(SpeechToText.readyStatus);

      expect(speech.isListening, isTrue, reason: 'the mic is hot, not stopped');
      expect(speech.isMicReady, isTrue);
      expect(speech.lastStatus, SpeechToText.listeningStatus);
      expect(seen, contains(SpeechToText.readyStatus));
    });

    test('still lets sound levels through afterwards', () async {
      // The consequence of the bug above, stated as its own test: levels are
      // gated on isNotListening, and the new endpointing is built on them.
      await initialize();
      final levels = <double>[];
      await speech.listen(
        listenOptions: SpeechListenOptions(),
        onSoundLevelChange: levels.add,
      );
      platform.emitStatus(SpeechToText.listeningStatus);
      platform.emitStatus(SpeechToText.readyStatus);

      platform.emitSoundLevel(4.5);

      expect(levels, [4.5]);
    });

    test(
      'is reset by the next listen, so it never reports a stale mic',
      () async {
        await initialize();
        await speech.listen(listenOptions: SpeechListenOptions());
        platform.emitStatus(SpeechToText.readyStatus);
        expect(speech.isMicReady, isTrue);

        await speech.listen(listenOptions: SpeechListenOptions());

        expect(speech.isMicReady, isFalse);
      },
    );

    test('arriving out of order breaks nothing', () async {
      // No ordering is guaranteed across a platform channel, and some OEM
      // recognisers never emit it at all.
      await initialize();
      await speech.listen(listenOptions: SpeechListenOptions());
      platform.emitStatus(SpeechToText.readyStatus);
      platform.emitStatus(SpeechToText.listeningStatus);
      expect(speech.isListening, isTrue);
      expect(speech.isMicReady, isTrue);
    });
  });

  test('done still means done, exactly once', () async {
    // The app restarts its recogniser session on 'done'. A final result plus a
    // done status must still collapse into one done and no more, or the turn
    // machine restarts twice and races into "recognizer busy".
    final seen = <String>[];
    await initialize(onStatus: seen.add);
    await speech.listen(listenOptions: SpeechListenOptions(), onResult: (_) {});
    platform.emitStatus(SpeechToText.listeningStatus);
    platform.emitStatus(SpeechToText.readyStatus);
    platform.emitResult('all done', finalResult: true);
    platform.emitStatus(SpeechToText.doneStatus);

    expect(seen.where((s) => s == SpeechToText.doneStatus), hasLength(1));
  });
}

/// Drives the wrapper through the public platform seam.
class FakeSpeechPlatform extends SpeechToTextPlatform {
  bool initResult = true;
  SpeechListenOptions? lastOptions;
  int listenCalls = 0;
  int stopCalls = 0;
  int cancelCalls = 0;

  void emitStatus(String status) => onStatus?.call(status);
  void emitSoundLevel(double level) => onSoundLevel?.call(level);

  void emitResult(String words, {required bool finalResult}) {
    onTextRecognition?.call(
      jsonEncode({
        // resultType, not finalResult: 0 partial, 1 intermediate, 2 final.
        'resultType': finalResult ? 2 : 0,
        'alternates': [
          {
            'recognizedWords': words,
            'recognizedPhrases': null,
            'confidence': 0.9,
          },
        ],
      }),
    );
  }

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<bool> initialize({
    debugLogging = false,
    List<SpeechConfigOption>? options,
  }) async => initResult;

  @override
  Future<void> stop() async => stopCalls++;

  @override
  Future<void> cancel() async => cancelCalls++;

  @override
  Future<bool> listen({
    String? localeId,
    @Deprecated('Use options instead') partialResults = true,
    @Deprecated('Use options instead') onDevice = false,
    @Deprecated('Use options instead') int listenMode = 0,
    @Deprecated('Use options instead') sampleRate = 0,
    SpeechListenOptions? options,
  }) async {
    listenCalls++;
    lastOptions = options;
    return true;
  }

  @override
  Future<List<dynamic>> locales() async => [];
}
