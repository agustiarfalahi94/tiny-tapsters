import 'package:flutter_test/flutter_test.dart';
import 'package:tiny_tapsters/services/vad_gate.dart';

/// The gate is pure, so every acoustic situation that used to need a phone and
/// a quiet room is a list of numbers here.
void main() {
  late VadGate gate;

  setUp(() => gate = VadGate());

  /// Feeds [count] frames at [level], returning how many read as voice.
  int feedAll(VadGate g, double level, int count) {
    var voiced = 0;
    for (var i = 0; i < count; i++) {
      if (g.feed(level)) voiced++;
    }
    return voiced;
  }

  test('nothing is decided until the floor is measured', () {
    expect(gate.isCalibrating, isTrue);
    // Even a shout during calibration is not yet a decision — the gate has no
    // idea what quiet sounds like in this room.
    expect(gate.feed(9.0), isFalse);
    expect(gate.feed(9.0), isFalse);
    expect(gate.feed(9.0), isFalse);
    expect(gate.feed(9.0), isFalse);
    expect(gate.isCalibrating, isFalse);
  });

  test(
    'the floor is a median, so one slam during calibration cannot poison it',
    () {
      // Three quiet frames and one door slam. A mean would put the floor at
      // 6.5 dB and make the child inaudible for the entire turn.
      gate.feed(-1.0);
      gate.feed(-1.0);
      gate.feed(-1.0);
      gate.feed(30.0);
      expect(gate.floor, lessThan(0.0));

      feedAll(gate, 4.0, 3);
      expect(gate.isVoice, isTrue, reason: 'normal speech must still register');
    },
  );

  test('a quiet room stays silent', () {
    feedAll(gate, -1.0, 4);
    expect(feedAll(gate, -1.0, 30), 0);
    expect(gate.heardVoice, isFalse);
  });

  test('speech registers, and one borderline frame does not', () {
    feedAll(gate, 0.0, 4);

    // A single frame only a little over the floor is a tap, a door, the mic
    // button itself — it has to persist. (A frame that is *unambiguously*
    // loud counts at once; see the short-word test above.)
    expect(gate.feed(4.5), isFalse);
    expect(gate.isVoice, isFalse);

    // Two in a row is speech.
    expect(gate.feed(4.5), isTrue);
    expect(gate.isVoice, isTrue);
    expect(gate.heardVoice, isTrue);
  });

  test('a single clear word registers without waiting out the debounce', () {
    // A four-year-old's "no" can be shorter than the 200ms debounce. Being
    // missed is what makes them repeat themselves, and the repeat is what
    // produced "no no".
    feedAll(gate, 0.0, 4);
    expect(gate.feed(9.0), isTrue, reason: 'one loud frame is enough');
    expect(gate.heardVoice, isTrue);
  });

  test('a merely-above-threshold frame still waits for the debounce', () {
    // Loudness stands in for duration only when it is unambiguous; a quiet
    // blip still has to persist, or room noise would read as speech.
    feedAll(gate, 0.0, 4);
    expect(gate.feed(3.5), isFalse);
    expect(gate.feed(3.5), isTrue);
  });

  test('hysteresis keeps a syllable boundary from reading as silence', () {
    feedAll(gate, 0.0, 4);
    feedAll(gate, 8.0, 2);
    expect(gate.isVoice, isTrue);

    // Between syllables the level dips well below the onset threshold but
    // stays above the release one. A single-threshold gate would flicker here
    // and reset the silence clock on every word.
    expect(gate.feed(2.0), isTrue);
    expect(gate.feed(2.0), isTrue);

    // A real gap drops below release.
    expect(gate.feed(0.2), isFalse);
    expect(gate.isVoice, isFalse);
  });

  test(
    'the floor follows a room that gets noisier, without chasing speech',
    () {
      feedAll(gate, 0.0, 4);
      final quietFloor = gate.floor;

      // Someone turns a fan on: sustained, but not speech-shaped.
      feedAll(gate, 1.0, 60);
      expect(gate.floor, greaterThan(quietFloor));
      expect(gate.isVoice, isFalse, reason: 'a fan is not a voice');

      // Speech still clears the raised floor.
      feedAll(gate, 9.0, 3);
      expect(gate.isVoice, isTrue);
    },
  );

  test('sustained speech does not drag the floor up under itself', () {
    feedAll(gate, 0.0, 4);
    final before = gate.floor;
    // A long uninterrupted sentence. If the floor tracked loud frames, the
    // speaker would gradually mute themselves and the turn would end mid-word.
    feedAll(gate, 8.0, 80);
    expect(gate.floor, closeTo(before, 0.001));
    expect(gate.isVoice, isTrue);
  });

  test('heardVoice separates an empty room from an unintelligible one', () {
    // The two failures need different answers: silence means the child never
    // spoke, voice-without-transcript means they did and were not understood.
    feedAll(gate, 0.0, 4);
    feedAll(gate, 0.0, 20);
    expect(gate.heardVoice, isFalse);

    feedAll(gate, 7.0, 3);
    feedAll(gate, 0.0, 40);
    expect(gate.heardVoice, isTrue, reason: 'it latches for the whole turn');
    expect(gate.isVoice, isFalse);
  });

  test('reset clears everything for the next turn', () {
    feedAll(gate, 0.0, 4);
    feedAll(gate, 9.0, 3);
    expect(gate.heardVoice, isTrue);

    gate.reset();

    expect(gate.isCalibrating, isTrue);
    expect(gate.heardVoice, isFalse);
    expect(gate.isVoice, isFalse);
  });

  test('the meter reads 0..1 whatever the raw dB does', () {
    feedAll(gate, 0.0, 4);
    gate.feed(-5.0);
    expect(gate.normalised, 0.0);
    gate.feed(40.0);
    expect(gate.normalised, 1.0);
  });
}
