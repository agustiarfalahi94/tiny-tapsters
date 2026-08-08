import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// Generates `assets/music/lullaby.wav` — a cozy music-box arrangement of
/// "Twinkle Twinkle Little Star":
///   - chime-like melody (sine + bright partials, fast attack, long decay)
///   - a soft harmony line a third below the melody
///   - a deep C drone underneath (C2 + C3)
///   - a gentle two-tap echo for space
///   - structure: bell intro → solo pass → full duet pass → quiet outro
/// Loops cleanly with a trailing pause.
///
/// Run: dart run tool/generate_music.dart
void main() {
  const sampleRate = 22050;
  const quarter = 0.62; // seconds per beat — slow lullaby tempo

  // Frequencies (Hz).
  const c2 = 65.41, c3 = 130.81;
  const a3 = 220.0, b3 = 246.94;
  const c4 = 261.63,
      d4 = 293.66,
      e4 = 329.63,
      f4 = 349.23,
      g4 = 392.0,
      a4 = 440.0;
  const c5 = 523.25, e5 = 659.25, g5 = 783.99;

  // Melody: [frequency, beats]. Twinkle Twinkle, C major.
  const melody = <(double, int)>[
    (c4, 1),
    (c4, 1),
    (g4, 1),
    (g4, 1),
    (a4, 1),
    (a4, 1),
    (g4, 2),
    (f4, 1),
    (f4, 1),
    (e4, 1),
    (e4, 1),
    (d4, 1),
    (d4, 1),
    (c4, 2),
    (g4, 1),
    (g4, 1),
    (f4, 1),
    (f4, 1),
    (e4, 1),
    (e4, 1),
    (d4, 2),
    (g4, 1),
    (g4, 1),
    (f4, 1),
    (f4, 1),
    (e4, 1),
    (e4, 1),
    (d4, 2),
    (c4, 1),
    (c4, 1),
    (g4, 1),
    (g4, 1),
    (a4, 1),
    (a4, 1),
    (g4, 2),
    (f4, 1),
    (f4, 1),
    (e4, 1),
    (e4, 1),
    (d4, 1),
    (d4, 1),
    (c4, 4),
  ];
  // Harmony: each melody note a third below (C-major scale degrees).
  final thirdBelow = {c4: a3, d4: b3, e4: c4, f4: d4, g4: e4, a4: f4};

  // --- render helpers -------------------------------------------------------
  // Chime tone: fast attack + exponential decay (music-box character).
  double toneAt(double t, double freq, double dur) {
    const attack = 0.008;
    final env = t < attack ? t / attack : math.exp(-(t - attack) * 5.5 / dur);
    return (math.sin(2 * math.pi * freq * t) +
            math.sin(4 * math.pi * freq * t) * 0.22 +
            math.sin(6 * math.pi * freq * t) * 0.06) *
        env;
  }

  // Adds a note to the buffer (dry only — echo is applied later).
  void renderNote(
    List<double> buffer,
    double startTime,
    double freq,
    double dur,
    double gain,
  ) {
    final start = (startTime * sampleRate).round();
    final count = (dur * sampleRate).round();
    for (var i = 0; i < count && start + i < buffer.length; i++) {
      buffer[start + i] += toneAt(i / sampleRate, freq, dur) * gain;
    }
  }

  void renderMelody(
    List<double> buffer,
    double start,
    List<(double, int)> notes, {
    bool harmony = false,
    double melodyGain = 0.55,
    double harmonyGain = 0.3,
  }) {
    var t = start;
    for (final (freq, beats) in notes) {
      final dur = beats * quarter;
      renderNote(buffer, t, freq, dur, melodyGain);
      if (harmony) {
        renderNote(buffer, t, thirdBelow[freq]!, dur, harmonyGain);
      }
      t += dur;
    }
  }

  // --- timeline -------------------------------------------------------------
  var total = 0.0;
  void use(double s) => total += s;

  use(0.2); // leading breath
  final introStart = total; // 4 bell notes
  use(0.5 * 4);
  final pass1Start = total; // melody only, first two phrases (28 notes)
  for (final (_, beats) in melody.take(28)) {
    use(beats * quarter);
  }
  final pass2Start = total; // full melody + harmony
  for (final (_, beats) in melody) {
    use(beats * quarter);
  }
  final outroStart = total; // held high C fading out
  use(2.6);
  use(1.2); // trailing pause before the loop

  final buffer = List<double>.filled((total * sampleRate).round(), 0);

  // Bells (intro).
  final bells = [c5, e5, g5, c5];
  for (var i = 0; i < bells.length; i++) {
    renderNote(buffer, introStart + i * 0.5, bells[i], 1.8, 0.2);
  }
  // Pass 1: solo melody.
  renderMelody(buffer, pass1Start, melody.take(28).toList());
  // Pass 2: melody + harmony.
  renderMelody(buffer, pass2Start, melody, harmony: true);
  // Outro: held high C, fading.
  renderNote(buffer, outroStart, c5, 2.6, 0.28);

  // Deep drone (C2 + C3) under everything, gently fading in/out.
  final droneFadeIn = (2.0 * sampleRate).round();
  final droneFadeOutStart = buffer.length - (2.0 * sampleRate).round();
  for (var i = 0; i < buffer.length; i++) {
    var droneEnv = 1.0;
    if (i < droneFadeIn) droneEnv = i / droneFadeIn;
    if (i > droneFadeOutStart) {
      droneEnv = (buffer.length - i) / (buffer.length - droneFadeOutStart);
    }
    final t = i / sampleRate;
    buffer[i] +=
        (math.sin(2 * math.pi * c2 * t) * 0.06 +
            math.sin(2 * math.pi * c3 * t) * 0.05) *
        droneEnv;
  }

  // Gentle two-tap echo on everything (adds space; no feedback loop).
  final delay = (0.26 * sampleRate).round();
  final echoed = List<double>.filled(buffer.length, 0);
  for (var i = 0; i < buffer.length; i++) {
    var v = buffer[i];
    if (i >= delay) v += buffer[i - delay] * 0.3;
    if (i >= 2 * delay) v += buffer[i - 2 * delay] * 0.16;
    echoed[i] = v;
  }

  // Normalize to a safe peak (the player additionally plays at 0.35 volume).
  var peak = 0.0;
  for (final v in echoed) {
    final a = v.abs();
    if (a > peak) peak = a;
  }
  final scale = peak > 0.75 ? 0.75 / peak : 1.0;
  for (var i = 0; i < echoed.length; i++) {
    echoed[i] *= scale;
  }

  // --- WAV writer -----------------------------------------------------------
  final bytes = BytesBuilder();
  void writeString(String s) => bytes.add(s.codeUnits);
  void writeU32(int v) => bytes.add([
    v & 0xff,
    (v >> 8) & 0xff,
    (v >> 16) & 0xff,
    (v >> 24) & 0xff,
  ]);
  void writeU16(int v) => bytes.add([v & 0xff, (v >> 8) & 0xff]);

  writeString('RIFF');
  writeU32(36 + echoed.length * 2);
  writeString('WAVE');
  writeString('fmt ');
  writeU32(16);
  writeU16(1); // PCM
  writeU16(1); // mono
  writeU32(sampleRate);
  writeU32(sampleRate * 2);
  writeU16(2);
  writeU16(16);
  writeString('data');
  writeU32(echoed.length * 2);
  for (final sample in echoed) {
    final v = (sample.clamp(-1.0, 1.0) * 32767).round();
    writeU16(v & 0xffff);
  }

  File('assets/music/lullaby.wav')
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes.takeBytes());
  stdout.writeln(
    'wrote assets/music/lullaby.wav '
    '(${echoed.length ~/ sampleRate}s, peak=${peak.toStringAsFixed(2)})',
  );
}
