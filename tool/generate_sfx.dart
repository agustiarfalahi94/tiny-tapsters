import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// Generates the app's two synthesised sound effects. Both are deterministic
/// (fixed seed) so the assets are reproducible.
///
///   assets/sfx/pop.wav   — a short, playful bubble "pop": a fast downward
///                          pitch sweep with a tiny noise attack, ~0.12 s.
///   assets/sfx/wrong.wav — the "tetot": two descending tones, the sound every
///                          child already reads as "not that one". Kept soft
///                          and short; this plays on a four-year-old's mistake,
///                          so it must correct without scolding.
///
/// Run: dart run tool/generate_sfx.dart
void main() {
  writeWav('assets/sfx/pop.wav', buildPop(), sampleRate);
  writeWav('assets/sfx/wrong.wav', buildWrong(), sampleRate);
}

const sampleRate = 22050;

List<double> buildPop() {
  const seconds = 0.12;
  final count = (seconds * sampleRate).round();
  final samples = List<double>.filled(count, 0);
  final rnd = math.Random(7);

  for (var i = 0; i < count; i++) {
    final t = i / sampleRate;
    final progress = i / count; // 0..1 across the pop
    // Pitch sweep 900 Hz → 140 Hz.
    final freq = 900 * math.pow(140 / 900, progress);
    // Fast exponential decay envelope.
    final env = math.exp(-progress * 7);
    final tone = math.sin(2 * math.pi * freq * t) * 0.7;
    // Tiny noise burst in the first ~12 ms for the "p" attack.
    final attackSamples = (0.012 * sampleRate).round();
    final noise = i < attackSamples
        ? (rnd.nextDouble() * 2 - 1) * 0.35 * (1 - i / attackSamples)
        : 0.0;
    samples[i] = (tone + noise) * env * 0.85;
  }
  return samples;
}

/// Two short tones, the second a fourth below the first — the classic
/// "eh-ehh". Sine waves with a soft attack and release: a square wave or a
/// hard edge would read as a harsh buzzer, and nothing here should punish.
List<double> buildWrong() {
  const toneSeconds = 0.16;
  const gapSeconds = 0.03;
  const frequencies = [440.0, 330.0]; // A4 then E4
  final toneCount = (toneSeconds * sampleRate).round();
  final gapCount = (gapSeconds * sampleRate).round();
  final total = toneCount * 2 + gapCount;
  final samples = List<double>.filled(total, 0);

  for (var tone = 0; tone < frequencies.length; tone++) {
    final start = tone * (toneCount + gapCount);
    for (var i = 0; i < toneCount; i++) {
      final t = i / sampleRate;
      // 6 ms fade in and out, so neither tone clicks.
      final edge = (0.006 * sampleRate).round();
      var env = 1.0;
      if (i < edge) {
        env = i / edge;
      } else if (i > toneCount - edge) {
        env = math.max(0, (toneCount - i) / edge);
      }
      // A quiet second harmonic gives it a little body without buzzing.
      final wave =
          math.sin(2 * math.pi * frequencies[tone] * t) +
          0.18 * math.sin(4 * math.pi * frequencies[tone] * t);
      samples[start + i] = wave * env * 0.5;
    }
  }
  return samples;
}

void writeWav(String path, List<double> samples, int rate) {
  var peak = 0.0;
  for (final s in samples) {
    if (s.abs() > peak) peak = s.abs();
  }
  final scale = peak > 0.85 ? 0.85 / peak : 1.0;
  final count = samples.length;

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
  writeU32(36 + count * 2);
  writeString('WAVE');
  writeString('fmt ');
  writeU32(16);
  writeU16(1);
  writeU16(1);
  writeU32(rate);
  writeU32(rate * 2);
  writeU16(2);
  writeU16(16);
  writeString('data');
  writeU32(count * 2);
  for (final sample in samples) {
    final v = (sample.clamp(-1.0, 1.0) * scale * 32767).round();
    writeU16(v & 0xffff);
  }

  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes.takeBytes());
  stdout.writeln('wrote $path (${(count / rate * 1000).round()}ms)');
}
