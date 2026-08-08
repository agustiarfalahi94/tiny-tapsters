import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// Generates `assets/music/lullaby.wav` — a soft music-box style lullaby
/// ("Twinkle Twinkle Little Star") synthesized as gentle sine tones with a
/// slow attack/decay envelope and a warm sub-octave layer. Loops cleanly.
///
/// Run: dart run tool/generate_music.dart
void main() {
  const sampleRate = 22050;
  const c4 = 261.63,
      d4 = 293.66,
      e4 = 329.63,
      f4 = 349.23,
      g4 = 392.0,
      a4 = 440.0;
  // [frequency (Hz), duration (s)]
  const melody = <(double, double)>[
    (c4, 0.9),
    (c4, 0.9),
    (g4, 0.9),
    (g4, 0.9),
    (a4, 0.9),
    (a4, 0.9),
    (g4, 1.8),
    (f4, 0.9),
    (f4, 0.9),
    (e4, 0.9),
    (e4, 0.9),
    (d4, 0.9),
    (d4, 0.9),
    (c4, 1.8),
    (g4, 0.9),
    (g4, 0.9),
    (f4, 0.9),
    (f4, 0.9),
    (e4, 0.9),
    (e4, 0.9),
    (d4, 1.8),
    (g4, 0.9),
    (g4, 0.9),
    (f4, 0.9),
    (f4, 0.9),
    (e4, 0.9),
    (e4, 0.9),
    (d4, 1.8),
    (c4, 0.9),
    (c4, 0.9),
    (g4, 0.9),
    (g4, 0.9),
    (a4, 0.9),
    (a4, 0.9),
    (g4, 1.8),
    (f4, 0.9),
    (f4, 0.9),
    (e4, 0.9),
    (e4, 0.9),
    (d4, 0.9),
    (d4, 0.9),
    (c4, 2.7),
  ];

  var totalSamples = 0;
  for (final (_, seconds) in melody) {
    totalSamples += (seconds * sampleRate).round();
  }
  totalSamples += (0.9 * sampleRate).round(); // trailing pause before the loop

  final samples = List<double>.filled(totalSamples, 0);
  var cursor = 0;
  for (final (freq, seconds) in melody) {
    final noteSamples = (seconds * sampleRate).round();
    final attack = (0.06 * sampleRate).round();
    final release = (0.45 * sampleRate).round();
    for (var i = 0; i < noteSamples; i++) {
      final t = i / sampleRate;
      var envelope = 1.0;
      if (i < attack) envelope = i / attack;
      if (i > noteSamples - release) {
        envelope *= (noteSamples - i) / release;
      }
      final tone =
          math.sin(2 * math.pi * freq * t) * 0.55 +
          math.sin(2 * math.pi * freq * 2 * t) * 0.12 +
          math.sin(2 * math.pi * freq / 2 * t) * 0.35;
      samples[cursor + i] = tone * envelope * 0.45;
    }
    cursor += noteSamples;
  }

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
  writeU32(36 + totalSamples * 2);
  writeString('WAVE');
  writeString('fmt ');
  writeU32(16);
  writeU16(1); // PCM
  writeU16(1); // mono
  writeU32(sampleRate);
  writeU32(sampleRate * 2); // byte rate
  writeU16(2); // block align
  writeU16(16); // bits per sample
  writeString('data');
  writeU32(totalSamples * 2);
  for (final sample in samples) {
    final v = (sample.clamp(-1.0, 1.0) * 32767).round();
    writeU16(v & 0xffff);
  }

  File('assets/music/lullaby.wav')
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes.takeBytes());
  stdout.writeln(
    'wrote assets/music/lullaby.wav (${totalSamples ~/ sampleRate}s)',
  );
}
