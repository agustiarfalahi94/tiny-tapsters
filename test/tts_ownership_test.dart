import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiny_tapsters/services/tts_service.dart';

/// The bug these guard against never reproduced on demand, which is exactly
/// why it needs tests rather than another round of device testing.
///
/// `flutter_tts` speaks over a `static const MethodChannel`, and every
/// `FlutterTts()` constructor re-points that channel's handler at itself. Two
/// instances therefore means one of them silently stops receiving
/// `speak.onComplete` — and for Pollie that callback is the only thing that
/// re-opens the microphone.
void main() {
  late FakeTts sink;
  late TtsService service;

  setUp(() {
    sink = FakeTts();
    service = TtsService.withSink(sink);
  });

  test(
    'the newest owner gets the callbacks, the previous one is stopped',
    () async {
      final narrator = Object();
      final pollie = Object();

      final first = await service.acquire(narrator, queueMode: 0);
      var narratorCompletions = 0;
      first.onComplete = () => narratorCompletions++;

      final second = await service.acquire(pollie, queueMode: 1);
      var pollieCompletions = 0;
      second.onComplete = () => pollieCompletions++;

      sink.fireComplete();

      expect(pollieCompletions, 1);
      expect(
        narratorCompletions,
        0,
        reason: 'the released owner must go quiet',
      );
      expect(
        sink.stopCalls,
        1,
        reason: 'taking the engine stops the previous speaker',
      );
      expect(first.isCurrent, isFalse);
      expect(second.isCurrent, isTrue);
    },
  );

  test('a late callback from a released session is dropped', () async {
    // The dangerous version of the bug: a stale completion decrementing
    // somebody else's pending counter, which desynchronises "everything I
    // queued has been said" from reality in the direction that opens the mic
    // too early — or, one utterance later, never.
    final first = await service.acquire(Object(), queueMode: 0);
    var strayCompletions = 0;
    first.onComplete = () => strayCompletions++;

    await service.acquire(Object(), queueMode: 1);
    sink.fireComplete();

    expect(strayCompletions, 0);
  });

  test('each owner re-applies its own queue mode', () async {
    // Queue mode is global engine state. The Narrator needs 0 so tapping
    // through three games speaks only the last; Pollie needs 1 so
    // sentence-by-sentence replies do not cut each other off. Setting it once
    // at startup is what let one of them silently inherit the other's.
    await service.acquire(Object(), queueMode: 0);
    await service.acquire(Object(), queueMode: 1);
    await service.acquire(Object(), queueMode: 0);

    expect(sink.queueModes, [0, 1, 0]);
  });

  test(
    're-acquiring for the same owner does not stop it mid-sentence',
    () async {
      final owner = Object();
      await service.acquire(owner, queueMode: 1);
      await service.acquire(owner, queueMode: 1);

      expect(sink.stopCalls, 0);
    },
  );

  test('a released session cannot speak', () async {
    final session = await service.acquire(Object(), queueMode: 1);
    session.release();

    await session.speak('hello');

    expect(sink.spoken, isEmpty);
  });

  test('an engine that throws does not take the caller down', () async {
    final session = await service.acquire(Object(), queueMode: 1);
    sink.throwOnEverything = true;

    await session.setLanguage('id-ID');
    await session.setPitch(1.1);
    await session.stop();

    expect(await session.getVoices(), isNull);
  });

  test('cancel and error both count as a completion', () async {
    // Pollie decrements one pending utterance per completion. If a cancelled
    // or failed utterance never reports, the count never reaches zero.
    final session = await service.acquire(Object(), queueMode: 1);
    var completions = 0;
    session.onComplete = () => completions++;

    sink.fireCancel();
    sink.fireError('no voice');

    expect(completions, 2);
  });

  test('there is exactly one FlutterTts in the whole app', () {
    // A source scan, because the hazard is structural: the second instance
    // does not fail, it just quietly takes the callbacks. Anyone adding one
    // should land here rather than on a phone three weeks later.
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      for (final line in entity.readAsLinesSync()) {
        final code = line.trim();
        if (code.startsWith('//') || code.startsWith('///')) continue;
        if (code.contains('FlutterTts(')) offenders.add(entity.path);
      }
    }
    expect(
      offenders,
      ['lib/services/tts_service.dart'],
      reason:
          'flutter_tts uses a static MethodChannel whose handler is re-pointed '
          'by every constructor, so a second instance silently steals '
          "speak.onComplete — and Pollie's mic never re-opens. Go through "
          'TtsService.instance.acquire() instead.',
    );
  });
}

class FakeTts implements TtsSink {
  final List<int> queueModes = [];
  final List<String> spoken = [];
  int stopCalls = 0;
  bool throwOnEverything = false;

  VoidCallback? _onComplete;
  VoidCallback? _onCancel;
  void Function(dynamic)? _onError;

  void fireComplete() => _onComplete?.call();
  void fireCancel() => _onCancel?.call();
  void fireError(dynamic message) => _onError?.call(message);

  void _maybeThrow() {
    if (throwOnEverything) throw StateError('engine unavailable');
  }

  @override
  Future<void> setQueueMode(int mode) async {
    _maybeThrow();
    queueModes.add(mode);
  }

  @override
  Future<void> speak(String text) async {
    _maybeThrow();
    spoken.add(text);
  }

  @override
  Future<void> stop() async {
    _maybeThrow();
    stopCalls++;
  }

  @override
  Future<void> setLanguage(String locale) async => _maybeThrow();
  @override
  Future<void> setPitch(double pitch) async => _maybeThrow();
  @override
  Future<void> setSpeechRate(double rate) async => _maybeThrow();
  @override
  Future<void> setVoice(Map<String, String> voice) async => _maybeThrow();
  @override
  Future<dynamic> getVoices() async {
    _maybeThrow();
    return <dynamic>[];
  }

  @override
  void setCompletionHandler(VoidCallback handler) => _onComplete = handler;
  @override
  void setCancelHandler(VoidCallback handler) => _onCancel = handler;
  @override
  void setErrorHandler(void Function(dynamic message) handler) =>
      _onError = handler;
}
