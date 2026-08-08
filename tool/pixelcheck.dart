import 'dart:io';
import 'dart:typed_data';

/// Verifies that a screen region actually contains painted content by
/// counting near-white pixels in a raw Android screencap.
///
/// Usage:
///   dart run tool/pixelcheck.dart `file` `x1` `y1` `x2` `y2`
///
/// The file must be a raw screencap (`adb exec-out screencap > file`, NOT
/// `-p`), which is a 16-byte header (width, height, format, colorspace as
/// little-endian uint32s) followed by RGBA pixels.
void main(List<String> args) {
  if (args.length != 5) {
    stderr.writeln(
      'usage: dart run tool/pixelcheck.dart <file> <x1> <y1> <x2> <y2>',
    );
    exit(1);
  }
  final bytes = File(args[0]).readAsBytesSync();
  final data = ByteData.sublistView(bytes);
  final w = data.getUint32(0, Endian.little);
  final h = data.getUint32(4, Endian.little);
  final format = data.getUint32(8, Endian.little);
  final x1 = int.parse(args[1]);
  final y1 = int.parse(args[2]);
  final x2 = int.parse(args[3]);
  final y2 = int.parse(args[4]);

  if (format != 1) {
    stderr.writeln('unexpected pixel format: $format (expected 1 = RGBA_8888)');
    exit(1);
  }

  var white = 0;
  var sampled = 0;
  for (var y = y1; y <= y2; y++) {
    for (var x = x1; x <= x2; x++) {
      final i = 16 + (y * w + x) * 4;
      final r = bytes[i];
      final g = bytes[i + 1];
      final b = bytes[i + 2];
      sampled++;
      // Near-white = painted white text/icon on the gradient background.
      if (r > 235 && g > 235 && b > 235) white++;
    }
  }
  stdout.writeln('size=${w}x$h white=$white sampled=$sampled');
}
