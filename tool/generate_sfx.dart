import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// Generates `assets/sfx/pop.wav` — a short, playful bubble "pop":
/// a fast downward pitch sweep with a tiny noise attack, ~0.12 s.
/// Deterministic (fixed seed) so the asset is reproducible.
///
/// Run: dart run tool/generate_sfx.dart
void main() {
  const sampleRate = 22050;
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

  var peak = 0.0;
  for (final s in samples) {
    if (s.abs() > peak) peak = s.abs();
  }
  final scale = peak > 0.85 ? 0.85 / peak : 1.0;

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
  writeU32(sampleRate);
  writeU32(sampleRate * 2);
  writeU16(2);
  writeU16(16);
  writeString('data');
  writeU32(count * 2);
  for (final sample in samples) {
    final v = (sample.clamp(-1.0, 1.0) * scale * 32767).round();
    writeU16(v & 0xffff);
  }

  File('assets/sfx/pop.wav')
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes.takeBytes());
  stdout.writeln('wrote assets/sfx/pop.wav (${(seconds * 1000).round()}ms)');
}
