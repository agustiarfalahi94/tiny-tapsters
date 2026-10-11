import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:tiny_tapsters/services/speech_sink.dart';

import 'support/speech_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late NativeSpeechChannel native;
  late SpeechToText speech;
  final statuses = <String>[];
  final errors = <String>[];
  final words = <String>[];
  final levels = <double>[];

  setUp(() async {
    native = NativeSpeechChannel()..install();
    speech = SpeechToText.withMethodChannel();
    statuses.clear();
    errors.clear();
    words.clear();
    levels.clear();
    await speech.initialize(
      onStatus: statuses.add,
      onError: (error) => errors.add(error.errorMsg),
    );
  });
  tearDown(() async {
    await speech.cancel();
    native.uninstall();
    debugDefaultTargetPlatformOverride = null;
  });

  Future<void> listen() async {
    await speech.listen(
      onResult: (result) => words.add(result.recognizedWords),
      onSoundLevelChange: levels.add,
    );
    await native.emit(native.owner, 'notifyStatus', 'listening');
  }

  String result(String text, int type) => jsonEncode({
    'resultType': type,
    'alternates': [
      {'recognizedWords': text, 'recognizedPhrases': null, 'confidence': 0.9},
    ],
  });

  for (final event in <String, (String, Object)>{
    'ready': ('notifyStatus', 'readyForSpeech'),
    'done': ('notifyStatus', 'doneNoResult'),
    'quiet error': (
      'notifyError',
      jsonEncode({'errorMsg': 'error_no_match', 'permanent': true}),
    ),
    'fatal error': (
      'notifyError',
      jsonEncode({'errorMsg': 'error_permission', 'permanent': true}),
    ),
    'partial result': ('textRecognition', result('old words', 0)),
    'final result': ('textRecognition', result('old words', 2)),
    'sound level': ('soundLevelChange', 8.0),
  }.entries) {
    test('retired ${event.key} cannot mutate a successor wrapper', () async {
      await listen();
      final retired = native.owner;
      await speech.cancel();
      await listen();
      final successor = native.owner;
      statuses.clear();

      await native.emit(retired, event.value.$1, event.value.$2);

      expect(statuses, isEmpty);
      expect(errors, isEmpty);
      expect(words, isEmpty);
      expect(levels, isEmpty);
      expect(speech.isListening, isTrue);
      expect(speech.isMicReady, isFalse);
      expect(speech.lastRecognizedWords, isEmpty);
      expect(retired, isNotNull);
      expect(successor, isNot(retired));
      await native.emit(successor, 'notifyStatus', 'readyForSpeech');
      await native.emit(successor, 'textRecognition', result('new words', 0));
      await native.emit(successor, 'soundLevelChange', 4.0);
      expect(speech.isMicReady, isTrue);
      expect(words, ['new words']);
      expect(levels, [4.0]);
    });
  }

  testWidgets('late stop acknowledgement cannot arm a successor final timer', (
    tester,
  ) async {
    await listen();
    await native.emit(native.owner, 'textRecognition', result('old words', 0));
    final stopped = Completer<void>();
    native.stopping = stopped;
    final stopping = speech.stop();
    await listen();
    await native.emit(native.owner, 'textRecognition', result('new words', 0));
    words.clear();
    stopped.complete();
    await stopping;
    await tester.pump(const Duration(seconds: 3));
    expect(words, isEmpty, reason: 'old stop must not synthesize a new final');
    expect(speech.isListening, isTrue);
  });

  test(
    'production sink normal stop still delivers its terminal native result',
    () async {
      await listen();
      final owner = native.owner;
      await native.emit(owner, 'textRecognition', result('partial', 0));
      await PluginSpeechSink(speech: speech).stop();
      await native.emit(owner, 'textRecognition', result('terminal words', 2));
      expect(words, ['partial', 'terminal words']);
    },
  );

  test(
    'reopening the production sink replaces singleton status callbacks',
    () async {
      final first = <String>[];
      final second = <String>[];
      final oldSink = PluginSpeechSink(speech: speech);
      await oldSink.initialize(onError: (_) {}, onStatus: first.add);
      await oldSink.cancel();
      final newSink = PluginSpeechSink(speech: speech);
      await newSink.initialize(onError: (_) {}, onStatus: second.add);
      await newSink.listen(
        onResult: (_) {},
        onSoundLevel: (_) {},
        localeId: 'en-US',
      );
      await native.emit(native.owner, 'notifyStatus', 'listening');
      await native.emit(native.owner, 'notifyStatus', 'readyForSpeech');
      expect(first, isEmpty);
      expect(second, ['listening', 'readyForSpeech']);
    },
  );

  testWidgets('old listen acknowledgement cannot arm a successor session cap', (
    tester,
  ) async {
    final started = Completer<bool>();
    native.starting = started;
    final starting = speech.listen(
      listenOptions: SpeechListenOptions(listenFor: const Duration(seconds: 1)),
    );
    await tester.pump();
    await speech.cancel();
    native.starting = null;
    await listen();
    started.complete(true);
    await starting;
    await tester.pump(const Duration(seconds: 2));
    expect(native.calls.where((call) => call == 'stop'), isEmpty);
    expect(speech.isListening, isTrue);
  });

  test(
    'production sink waits for retirement before a successor listen',
    () async {
      final sink = PluginSpeechSink(speech: speech);
      await listen();
      final retired = native.owner;
      final cancelled = Completer<void>();
      native.cancellation = cancelled;
      final cancelling = sink.cancel();
      final starting = sink.listen(
        onResult: (_) {},
        onSoundLevel: (_) {},
        localeId: 'en-US',
      );
      await Future<void>.delayed(Duration.zero);
      expect(native.listens, hasLength(1));
      await native.emit(retired, 'notifyStatus', 'readyForSpeech');
      expect(speech.isMicReady, isFalse);
      cancelled.complete();
      await cancelling;
      await starting;
      expect(native.listens, hasLength(2));
    },
  );

  test(
    'cancel while waiting for retirement invalidates the queued listen',
    () async {
      final sink = PluginSpeechSink(speech: speech);
      await listen();
      final cancelled = Completer<void>();
      native.cancellation = cancelled;
      final cancelling = sink.cancel();
      final starting = sink.listen(
        onResult: (_) {},
        onSoundLevel: (_) {},
        localeId: 'en-US',
      );
      final secondCancellation = sink.cancel();
      cancelled.complete();
      await cancelling;
      await secondCancellation;
      await starting;
      expect(native.listens, hasLength(1));
    },
  );

  test(
    'stop invalidates a listen waiting for cancellation acknowledgement',
    () async {
      final sink = PluginSpeechSink(speech: speech);
      await listen();
      final cancelled = Completer<void>();
      native.cancellation = cancelled;
      final cancelling = sink.cancel();
      final starting = sink.listen(
        onResult: (_) {},
        onSoundLevel: (_) {},
        localeId: 'en-US',
      );
      try {
        await Future<void>.delayed(Duration.zero);
        expect(native.listens, hasLength(1));
        await sink.stop();
        cancelled.complete();
        await cancelling;
        await starting;
        expect(native.listens, hasLength(1));

        await sink.listen(
          onResult: (_) {},
          onSoundLevel: (_) {},
          localeId: 'en-US',
        );
        expect(
          native.listens,
          hasLength(2),
          reason: 'a fresh start remains allowed',
        );
      } finally {
        if (!cancelled.isCompleted) cancelled.complete();
        await cancelling;
        await starting;
      }
    },
  );

  for (final target in [
    TargetPlatform.android,
    TargetPlatform.iOS,
    TargetPlatform.macOS,
  ]) {
    test(
      '$target rejects untagged callbacks rather than inventing origin',
      () async {
        debugDefaultTargetPlatformOverride = target;
        await listen();
        statuses.clear();
        await native.emit(null, 'notifyStatus', 'readyForSpeech');
        expect(statuses, isEmpty);
        expect(speech.isMicReady, isFalse);
      },
    );
  }

  test(
    'unamended Windows channel remains compatible with raw callbacks',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      await listen();
      await native.emit(null, 'notifyStatus', 'readyForSpeech');
      expect(speech.isMicReady, isTrue);
    },
  );
}
