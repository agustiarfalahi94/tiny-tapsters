import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiny_tapsters/services/tts_service.dart';

/// Which *engine* speaks, as opposed to which voice.
///
/// `pickBestVoice` can only rank what `getVoices` returns, and `getVoices`
/// returns the voices of the currently bound engine. So a careful voice score
/// over a bad engine still sounds like a robot — it is picking the best of a
/// bad set. Nothing here used to choose an engine at all.
void main() {
  late FakeEngineTts sink;

  TtsService serviceWith(List<String> engines, {String? defaultEngine}) {
    sink = FakeEngineTts(engines: engines, defaultEngine: defaultEngine);
    return TtsService.withSink(sink);
  }

  test(
    'Google TTS is selected when it is installed but not the default',
    () async {
      final service = serviceWith([
        'com.svox.pico',
        'com.google.android.tts',
      ], defaultEngine: 'com.svox.pico');

      await service.acquire(Object(), queueMode: 0);

      expect(sink.enginesSet, ['com.google.android.tts']);
    },
  );

  test('an engine already on Google is left alone', () async {
    final service = serviceWith([
      'com.google.android.tts',
    ], defaultEngine: 'com.google.android.tts');

    await service.acquire(Object(), queueMode: 0);

    expect(
      sink.enginesSet,
      isEmpty,
      reason:
          'switching rebuilds the platform '
          'engine and drops language, voice, pitch and rate with it — there is '
          'no reason to pay that to arrive where we already are',
    );
  });

  test('an unknown engine is not gambled on', () async {
    // The same rule voice selection already follows: never trade a working
    // default for something we know nothing about. Google's is the one engine
    // we can name that reliably ships neural voices.
    final service = serviceWith([
      'com.samsung.SMT',
      'com.svox.pico',
    ], defaultEngine: 'com.samsung.SMT');

    await service.acquire(Object(), queueMode: 0);

    expect(sink.enginesSet, isEmpty);
  });

  test('the engine is chosen once, not on every acquisition', () async {
    final service = serviceWith([
      'com.google.android.tts',
    ], defaultEngine: 'com.svox.pico');

    await service.acquire(Object(), queueMode: 0);
    await service.acquire(Object(), queueMode: 1);
    await service.acquire(Object(), queueMode: 0);

    expect(sink.enginesSet, ['com.google.android.tts']);
    expect(
      sink.getEnginesCalls,
      1,
      reason:
          'the installed engines cannot '
          'change while the app is running',
    );
  });

  test('the engine is switched before anything is configured on it', () async {
    // Switching engines builds a new platform TextToSpeech, which starts on
    // its own defaults. Anything set first is silently discarded.
    final service = serviceWith([
      'com.google.android.tts',
    ], defaultEngine: 'com.svox.pico');

    final session = await service.acquire(Object(), queueMode: 1);
    await session.setLanguage('en-US');

    expect(
      sink.calls.indexOf('setEngine'),
      lessThan(sink.calls.indexOf('setQueueMode')),
    );
    expect(
      sink.calls.indexOf('setEngine'),
      lessThan(sink.calls.indexOf('setLanguage')),
    );
  });

  test('an engine that cannot be queried never blocks speaking', () async {
    // Pollie going quiet is far worse than Pollie sounding thin.
    final service = serviceWith([]);
    sink.throwOnEngineCalls = true;

    final session = await service.acquire(Object(), queueMode: 0);
    await session.speak('hello');

    expect(sink.spoken, ['hello']);
  });

  test('a malformed engine list is survived', () async {
    // getEngines comes back over a platform channel as List<Object?>; the
    // voice loader already exists because casting that shape blindly threw.
    final service = serviceWith([]);
    sink.rawEngines = <Object?>[null, 42, 'com.google.android.tts'];

    final session = await service.acquire(Object(), queueMode: 0);
    await session.speak('hello');

    expect(sink.enginesSet, ['com.google.android.tts']);
    expect(sink.spoken, ['hello']);
  });
}

class FakeEngineTts implements TtsSink {
  FakeEngineTts({required this.engines, this.defaultEngine});

  final List<String> engines;
  final String? defaultEngine;

  /// Set to hand back something `getEngines` could really return.
  Object? rawEngines;
  bool throwOnEngineCalls = false;

  final List<String> enginesSet = [];
  final List<String> spoken = [];
  final List<String> calls = [];
  int getEnginesCalls = 0;

  @override
  Future<dynamic> getEngines() async {
    calls.add('getEngines');
    getEnginesCalls++;
    if (throwOnEngineCalls) throw StateError('no engine');
    return rawEngines ?? engines;
  }

  @override
  Future<dynamic> getDefaultEngine() async {
    calls.add('getDefaultEngine');
    if (throwOnEngineCalls) throw StateError('no engine');
    return defaultEngine;
  }

  @override
  Future<void> setEngine(String engine) async {
    calls.add('setEngine');
    if (throwOnEngineCalls) throw StateError('no engine');
    enginesSet.add(engine);
  }

  @override
  Future<void> setQueueMode(int mode) async => calls.add('setQueueMode');
  @override
  Future<void> speak(String text) async {
    calls.add('speak');
    spoken.add(text);
  }

  @override
  Future<void> stop() async => calls.add('stop');
  @override
  Future<void> setLanguage(String locale) async => calls.add('setLanguage');
  @override
  Future<void> setPitch(double pitch) async => calls.add('setPitch');
  @override
  Future<void> setSpeechRate(double rate) async => calls.add('setSpeechRate');
  @override
  Future<void> setVoice(Map<String, String> voice) async =>
      calls.add('setVoice');
  @override
  Future<dynamic> getVoices() async => <dynamic>[];

  @override
  void setCompletionHandler(VoidCallback handler) {}
  @override
  void setCancelHandler(VoidCallback handler) {}
  @override
  void setErrorHandler(void Function(dynamic message) handler) {}
}
