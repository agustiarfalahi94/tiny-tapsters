import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiny_tapsters/screens/companion_screen.dart';
import 'package:tiny_tapsters/services/pollie_service.dart';
import 'package:tiny_tapsters/services/speech_sink.dart';
import 'package:tiny_tapsters/services/tts_service.dart';
import 'package:tiny_tapsters/services/vad_gate.dart';

import 'tts_ownership_test.dart' show FakeTts;

/// Every acoustic situation a child can put the microphone in.
///
/// None of this could be tested before: `SpeechToText()` is a process-wide
/// singleton, `FlutterTts` owns a static channel, and the endpointing was
/// measured with `DateTime.now()`. All three are now seams or timers, so a
/// four-year-old pausing mid-sentence is a `tester.pump`.
void main() {
  late FakeSpeech speech;
  late FakeTts tts;
  late FakePollie pollie;

  setUp(() async {
    speech = FakeSpeech();
    tts = FakeTts();
    pollie = FakePollie();
  });

  /// Opens Pollie, awake and able to listen.
  Future<void> openPollie(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: CompanionScreen(
          pollie: pollie,
          speech: speech,
          ttsService: TtsService.withSink(tts),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  /// Presses and releases the mic quickly — a tap.
  Future<void> tapMic(WidgetTester tester) async {
    final mic = find.text('🎤');
    final gesture = await tester.startGesture(tester.getCenter(mic));
    await tester.pump(const Duration(milliseconds: 60));
    await gesture.up();
    await tester.pump();
  }

  /// Feeds [ms] of quiet, one VAD frame at a time.
  Future<void> silence(WidgetTester tester, int ms) async {
    for (var i = 0; i < ms ~/ 100; i++) {
      speech.emitLevel(-1.0);
      await tester.pump(VadGate.tick);
    }
  }

  /// Feeds [ms] of speech.
  Future<void> speaking(WidgetTester tester, int ms) async {
    for (var i = 0; i < ms ~/ 100; i++) {
      speech.emitLevel(8.0);
      await tester.pump(VadGate.tick);
    }
  }

  /// Opens a turn and gets the microphone genuinely hot.
  Future<void> startTurn(WidgetTester tester) async {
    await tapMic(tester);
    await tester.pump();
    speech.emitReady();
    await tester.pump();
    // The gate measures the room before it decides anything.
    await silence(tester, 400);
  }

  group('the mic never claims to be listening before it is', () {
    testWidgets('warming is amber, recording is red', (tester) async {
      await openPollie(tester);
      await tapMic(tester);
      await tester.pump();

      expect(speech.listenCalls, 1);
      expect(
        micColour(tester),
        const Color(0xFFFFB300),
        reason: 'amber: not hot yet',
      );

      speech.emitReady();
      await tester.pump();

      expect(
        micColour(tester),
        const Color(0xFFFF5252),
        reason: 'red: talk now',
      );
    });

    testWidgets('a platform that never says ready still works', (tester) async {
      // iOS, macOS and web have no equivalent signal, and an OEM Android may
      // not send it. Nothing may hard-depend on it.
      await openPollie(tester);
      await tapMic(tester);
      await tester.pump(const Duration(milliseconds: 1100));
      expect(micColour(tester), const Color(0xFFFFB300));

      await tester.pump(const Duration(milliseconds: 200));

      expect(micColour(tester), const Color(0xFFFF5252));
    });

    testWidgets('words arriving before ready are still kept', (tester) async {
      // Gating readiness must never gate the child's actual words.
      await openPollie(tester);
      await tapMic(tester);
      await tester.pump();
      speech.emitPartial('hello pollie');
      await tester.pump();

      expect(find.textContaining('hello pollie'), findsWidgets);
    });
  });

  group('endpointing measures silence, not the transcript', () {
    testWidgets('a two-second thinking pause does not end the turn', (
      tester,
    ) async {
      // The reported bug, as a test: "in minecraft how do you [pause] create a
      // tnt" came back as "in minecraft how do you" because the package stops
      // the session when the transcribed text stops changing.
      await openPollie(tester);
      await startTurn(tester);

      speech.emitPartial('in minecraft how do you');
      await speaking(tester, 500);
      await silence(tester, 2000);

      expect(pollie.sent, isEmpty, reason: 'nothing sent yet');

      await speaking(tester, 400);
      speech.emitPartial('in minecraft how do you create a tnt');
      await silence(tester, 2300);
      await tester.pump(const Duration(milliseconds: 50));

      expect(pollie.sent, hasLength(1));
      expect(pollie.sent.last, contains('create a tnt'));
    });

    testWidgets(
      'an unchanging transcript does not end the turn while they speak',
      (tester) async {
        // The recogniser often repeats the same partial for seconds. The old
        // rule read that as "finished"; the room says otherwise.
        await openPollie(tester);
        await startTurn(tester);
        speech.emitPartial('aaaaaa');

        for (var i = 0; i < 30; i++) {
          speech.emitPartial('aaaaaa');
          await speaking(tester, 100);
        }

        expect(pollie.sent, isEmpty, reason: 'still talking');
      },
    );

    testWidgets('silence ends the turn once there are words', (tester) async {
      await openPollie(tester);
      await startTurn(tester);
      await speaking(tester, 300);
      speech.emitPartial('hello');

      await silence(tester, 2000);
      expect(pollie.sent, isEmpty, reason: 'not yet at 2.2s');

      await silence(tester, 400);
      await tester.pump(const Duration(milliseconds: 50));
      expect(pollie.sent, hasLength(1));
    });

    testWidgets('a final result shortens the wait, so "yes" is quick', (
      tester,
    ) async {
      await openPollie(tester);
      await startTurn(tester);
      await speaking(tester, 300);
      // Android only declares an utterance final after seconds of silence, so
      // by the time one arrives the room is genuinely quiet. That agreement
      // between the recogniser and the room is what earns the fast path.
      await silence(tester, 600);
      speech.emitFinal('yes');
      await tester.pump();

      await tester.pump(const Duration(milliseconds: 950));

      expect(pollie.sent, hasLength(1));
      expect(pollie.sent.last, contains('yes'));
    });

    testWidgets('a restart gap is not counted as the child being quiet', (
      tester,
    ) async {
      // No sound levels arrive between sessions. A wall-clock measure would
      // bank our own plumbing as silence and could end the turn on it.
      await openPollie(tester);
      await startTurn(tester);
      await speaking(tester, 300);
      speech.emitFinal('do you know');
      await tester.pump();

      // The session ended; the next one takes half a second to get hot.
      await tester.pump(const Duration(milliseconds: 500));
      expect(pollie.sent, isEmpty, reason: 'the gap is not silence');

      speech.emitReady();
      await tester.pump();
      await silence(tester, 400);
      await speaking(tester, 300);
      await silence(tester, 2300);
      await tester.pump(const Duration(milliseconds: 50));

      expect(pollie.sent, hasLength(1));
    });

    testWidgets('a session ending mid-sentence does not end the turn', (
      tester,
    ) async {
      // The recogniser ends sessions whenever it likes. Nothing is captured
      // during the changeover, so that stretch is not evidence about the
      // child — the silence clock is gated on the mic actually recording, and
      // the 1.2s ready-timeout keeps the blind window shorter than the 2.2s
      // endpoint so a slow restart can never look like a finished sentence.
      await openPollie(tester);
      await startTurn(tester);
      await speaking(tester, 300);
      speech.emitPartial('tell me about');

      // Session dies without ever producing a final result.
      speech.emitStatus(PluginSpeechSink.doneStatus);
      await tester.pump(const Duration(milliseconds: 100));
      for (var i = 0; i < 8; i++) {
        await tester.pump(VadGate.tick);
      }

      expect(pollie.sent, isEmpty, reason: 'the changeover is not an answer');

      speech.emitReady();
      await tester.pump();
      await silence(tester, 400);
      await speaking(tester, 300);
      speech.emitPartial('tell me about dinosaurs');
      await silence(tester, 2400);
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        pollie.sent.last,
        contains('dinosaurs'),
        reason: 'the words from before the changeover survive it',
      );
    });

    testWidgets('nobody speaking closes the mic quietly', (tester) async {
      await openPollie(tester);
      await startTurn(tester);

      await silence(tester, 8200);
      await tester.pump(const Duration(milliseconds: 50));

      expect(pollie.sent, isEmpty, reason: 'nothing to send');
      expect(find.textContaining('again'), findsNothing);
    });

    testWidgets('speaking but not being understood asks them to try again', (
      tester,
    ) async {
      // A different failure from silence, and the one behind "yes takes five
      // tries": the child gets no feedback at all today and cannot tell
      // whether to repeat themselves.
      await openPollie(tester);
      await startTurn(tester);

      await speaking(tester, 600);
      await silence(tester, 12000);
      await tester.pump(const Duration(milliseconds: 50));

      expect(pollie.sent, isEmpty);
      expect(find.textContaining(sayAgainFragment), findsWidgets);
    });
  });

  group('nothing is lost at a session boundary', () {
    testWidgets('a final result is merged, not concatenated', (tester) async {
      // A recogniser that restates its utterance used to stutter, because the
      // final path did a raw string join while only the partial path used the
      // de-duplicating one.
      await openPollie(tester);
      await startTurn(tester);
      await speaking(tester, 200);
      speech.emitPartial('do you');
      speech.emitFinal('do you');
      await tester.pump();
      speech.emitReady();
      await tester.pump();
      await silence(tester, 400);
      await speaking(tester, 200);
      speech.emitFinal('do you know');
      await tester.pump();
      speech.emitReady();
      await tester.pump();
      await silence(tester, 400);
      await silence(tester, 2400);
      await tester.pump(const Duration(milliseconds: 50));

      expect(pollie.sent.last, contains('do you know'));
      expect(pollie.sent.last, isNot(contains('do you do you know')));
    });

    testWidgets('a session ending without a final keeps its guess', (
      tester,
    ) async {
      await openPollie(tester);
      await startTurn(tester);
      await speaking(tester, 200);
      speech.emitPartial('tell me a story');

      // The session dies with only a partial on the table.
      speech.emitStatus(PluginSpeechSink.doneStatus);
      await tester.pump(const Duration(milliseconds: 100));
      speech.emitReady();
      await tester.pump();
      await silence(tester, 400);
      await silence(tester, 2300);
      await tester.pump(const Duration(milliseconds: 50));

      expect(pollie.sent.last, contains('tell me a story'));
    });

    testWidgets('a quiet error restarts without an apology', (tester) async {
      await openPollie(tester);
      await startTurn(tester);
      await speaking(tester, 200);
      speech.emitPartial('hello');
      speech.emitError('error_no_match', permanent: false);
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.textContaining("didn't catch"), findsNothing);
      expect(speech.listenCalls, greaterThan(1));
    });

    testWidgets('a fatal error ends the turn and says so', (tester) async {
      await openPollie(tester);
      await startTurn(tester);
      final before = speech.listenCalls;

      speech.emitError('error_permission', permanent: true);
      await tester.pump(const Duration(milliseconds: 500));

      expect(speech.listenCalls, before, reason: 'no restart loop');
      expect(find.textContaining("didn't catch"), findsWidgets);
    });

    testWidgets('a busy recogniser is retried, but not forever', (
      tester,
    ) async {
      // Android reports every error as permanent, including the transient
      // ones, so the app classifies by name and bounds the retries itself.
      await openPollie(tester);
      await startTurn(tester);

      for (var i = 0; i < 5; i++) {
        speech.emitError('error_busy', permanent: true);
        await tester.pump(const Duration(milliseconds: 200));
      }

      expect(
        speech.listenCalls,
        lessThanOrEqualTo(4),
        reason: 'two retries, then give up',
      );
    });

    testWidgets('a no-match mid-turn does not end the turn', (tester) async {
      // The shipped behaviour: the plugin sends error_no_match with
      // permanent:true, the app looked for the string "no match" (with a
      // space) and fell through to ending the turn. A child pausing to think
      // therefore had their half-finished question sent.
      await openPollie(tester);
      await startTurn(tester);
      await speaking(tester, 300);
      speech.emitPartial('in minecraft how do you');

      speech.emitError('error_no_match', permanent: true);
      await tester.pump(const Duration(milliseconds: 200));

      expect(pollie.sent, isEmpty, reason: 'they are still thinking');
    });
  });

  group('hold to talk', () {
    testWidgets('a held mic ignores silence entirely', (tester) async {
      // The guaranteed path: while the finger is down, nothing may decide the
      // child has finished.
      await openPollie(tester);
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('🎤')),
      );
      await tester.pump(const Duration(milliseconds: 300));
      speech.emitReady();
      await tester.pump();
      await silence(tester, 400);

      await speaking(tester, 300);
      speech.emitPartial('um');
      await silence(tester, 4000);

      expect(pollie.sent, isEmpty, reason: 'the finger is still down');

      await speaking(tester, 300);
      speech.emitPartial('um a dinosaur');
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 400));

      expect(pollie.sent, hasLength(1));
      expect(pollie.sent.last, contains('dinosaur'));
    });

    testWidgets(
      'releasing keeps recording briefly, so the last word survives',
      (tester) async {
        await openPollie(tester);
        final gesture = await tester.startGesture(
          tester.getCenter(find.text('🎤')),
        );
        await tester.pump(const Duration(milliseconds: 300));
        speech.emitReady();
        await tester.pump();
        await silence(tester, 400);
        speech.emitPartial('a cat');

        await gesture.up();
        await tester.pump(const Duration(milliseconds: 200));
        // Android's audio lags the finger; this word arrives after the release.
        speech.emitPartial('a cat and a dog');
        await tester.pump(const Duration(milliseconds: 300));

        expect(pollie.sent.last, contains('and a dog'));
      },
    );

    testWidgets('a quick press is a tap, not a zero-length hold', (
      tester,
    ) async {
      await openPollie(tester);
      await tapMic(tester);
      speech.emitReady();
      await tester.pump();
      await silence(tester, 400);

      // The mic must still be open, with silence detection in charge.
      await speaking(tester, 300);
      speech.emitPartial('hi');
      await silence(tester, 2300);
      await tester.pump(const Duration(milliseconds: 50));

      expect(pollie.sent, hasLength(1));
    });

    testWidgets('a finger dragged off the button does not strand the mic', (
      tester,
    ) async {
      await openPollie(tester);
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('🎤')),
      );
      await tester.pump(const Duration(milliseconds: 300));
      speech.emitReady();
      await tester.pump();
      await silence(tester, 400);
      speech.emitPartial('wait');

      await gesture.cancel();
      await tester.pump(const Duration(milliseconds: 400));

      expect(pollie.sent, hasLength(1), reason: 'cancel is a release');
    });

    testWidgets('releasing before the mic was ever ready still closes it', (
      tester,
    ) async {
      await openPollie(tester);
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('🎤')),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(seconds: 1));

      expect(micColour(tester), Colors.white, reason: 'back to idle');
    });
  });

  group('the microphone always comes back', () {
    testWidgets('a TTS engine that never reports done releases it anyway', (
      tester,
    ) async {
      // The failure that presents as "sometimes Pollie just stops listening".
      await openPollie(tester);
      await startTurn(tester);
      await speaking(tester, 300);
      speech.emitPartial('hello');
      await silence(tester, 2400);
      await tester.pump(const Duration(milliseconds: 200));

      expect(tts.spoken, isNotEmpty, reason: 'she replied');
      final before = speech.listenCalls;

      // The engine never calls back. Ten seconds later the mic opens regardless.
      await tester.pump(const Duration(seconds: 11));

      expect(speech.listenCalls, greaterThan(before));
    });

    testWidgets('backgrounding drops the turn without sending', (tester) async {
      await openPollie(tester);
      await startTurn(tester);
      await speaking(tester, 300);
      speech.emitPartial('secret');

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 5));

      expect(
        pollie.sent,
        isEmpty,
        reason: 'nothing is sent from the background',
      );
    });

    testWidgets('leaving the screen mid-turn does not explode', (tester) async {
      await openPollie(tester);
      await startTurn(tester);
      await speaking(tester, 200);
      speech.emitPartial('bye');

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump(const Duration(seconds: 3));

      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('the mic emoji is never inside an animated transform', (
    tester,
  ) async {
    // Golden rule 4. This button used to sit in an AnimatedScale driven by the
    // sound level, which re-rasterises the glyph every frame and eventually
    // stops emoji painting app-wide. The level meter moves a width instead.
    await openPollie(tester);
    for (final type in [AnimatedScale, ScaleTransition, Transform]) {
      expect(
        find.ancestor(of: find.text('🎤'), matching: find.byType(type)),
        findsNothing,
        reason: '$type over an emoji exhausts the glyph raster cache',
      );
    }
  });

  test('the echo guard strips Pollie, but never the child', () {
    // She finishes a sentence, the audio tail reaches the mic.
    expect(
      stripEcho(
        'It is made of sand and gunpowder.',
        'sand and gunpowder how do you',
      ),
      'how do you',
    );
    // A child answering a question that repeats one of her words is not an echo.
    expect(stripEcho('Do you want a story, yes or no?', 'yes'), 'yes');
    expect(stripEcho('Do you like cats?', 'cats'), 'cats');
    // Unrelated speech is untouched.
    expect(
      stripEcho('I love Minecraft.', 'tell me about dinosaurs'),
      'tell me about dinosaurs',
    );
    expect(stripEcho('', 'hello there friend'), 'hello there friend');
  });
}

/// Reads the mic button's current colour.
Color micColour(WidgetTester tester) {
  final container = tester.widget<AnimatedContainer>(
    find
        .ancestor(of: find.text('🎤'), matching: find.byType(AnimatedContainer))
        .first,
  );
  return (container.decoration! as BoxDecoration).color!;
}

/// Keeps the "say it again" assertion from hard-coding a whole sentence that
/// exists in two languages.
const sayAgainFragment = 'again';

/// Drives the turn machine the way a recogniser would.
class FakeSpeech implements SpeechSink {
  int listenCalls = 0;
  int stopCalls = 0;
  String? lastLocale;
  bool available = true;

  void Function(SpeechRecognitionResult)? _onResult;
  void Function(double)? _onLevel;
  void Function(String)? _onStatus;
  void Function(SpeechRecognitionError)? _onError;
  bool _listening = false;

  void emitReady() => _onStatus?.call(PluginSpeechSink.readyStatus);
  void emitStatus(String status) {
    if (status == PluginSpeechSink.doneStatus) _listening = false;
    _onStatus?.call(status);
  }

  void emitLevel(double level) => _onLevel?.call(level);

  void emitPartial(String words) => _emit(words, false);
  void emitFinal(String words) {
    _listening = false;
    _emit(words, true);
  }

  void emitError(String message, {required bool permanent}) =>
      _onError?.call(SpeechRecognitionError(message, permanent));

  void _emit(String words, bool isFinal) {
    _onResult?.call(
      SpeechRecognitionResult([
        SpeechRecognitionWords(words, null, 0.9),
      ], isFinal ? 2 : 0),
    );
  }

  @override
  bool get isListening => _listening;

  @override
  Future<bool> initialize({
    required void Function(SpeechRecognitionError) onError,
    required void Function(String) onStatus,
  }) async {
    _onError = onError;
    _onStatus = onStatus;
    return available;
  }

  @override
  Future<List<String>> localeIds() async => ['en-US', 'id-ID'];

  @override
  Future<void> listen({
    required void Function(SpeechRecognitionResult) onResult,
    required void Function(double) onSoundLevel,
    required String localeId,
  }) async {
    listenCalls++;
    lastLocale = localeId;
    _onResult = onResult;
    _onLevel = onSoundLevel;
    _listening = true;
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    _listening = false;
  }
}

/// Pollie's brain, without a network.
///
/// A widget test's binding makes every real HTTP request return 400, so the
/// loopback server the pure-Dart tests use cannot be reached from here. This
/// is the seam `CompanionScreen` already had for exactly this reason.
class FakePollie extends PollieService {
  FakePollie() : super(endpoint: 'http://fake');

  /// Everything the child has been heard to say, in order.
  final sent = <String>[];
  List<String> replyChunks = const ['Hi there!'];

  @override
  bool get isConfigured => true;

  @override
  bool get recentlyAwake => true;

  @override
  Future<PolliePing> ping() async => PolliePing.ok;

  @override
  Stream<String> reply(List<ChatMessage> history, {String language = 'en'}) {
    sent.add(history.lastWhere((m) => m.role == 'user').text);
    return Stream.fromIterable(replyChunks);
  }

  @override
  void dispose() {}
}
