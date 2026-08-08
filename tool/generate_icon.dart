// Generates the Android launcher icons for the app:
//   - legacy PNGs in mipmap-{mdpi..xxxhdpi}/ic_launcher.png
//   - adaptive icon: drawable/ic_launcher_foreground.png (432×432, content
//     inside the safe zone) + gradient background + mipmap-anydpi-v26 XML
//
// The design is rasterized analytically (no fonts, no Flutter engine): the
// app's sky→pink gradient with a cheerful white smiling face and sparkles.
// PNGs are written with a tiny built-in encoder (zlib from dart:io).
//
// Run: dart run tool/generate_icon.dart
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

void main() {
  const legacy = {
    'mipmap-mdpi': 48,
    'mipmap-hdpi': 72,
    'mipmap-xhdpi': 96,
    'mipmap-xxhdpi': 144,
    'mipmap-xxxhdpi': 192,
  };
  for (final entry in legacy.entries) {
    final png = encodePng(renderIcon(entry.value, foregroundOnly: false));
    File('android/app/src/main/res/${entry.key}/ic_launcher.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(png);
    stdout.writeln('wrote ${entry.key}/ic_launcher.png (${entry.value}px)');
  }

  final fg = encodePng(renderIcon(432, foregroundOnly: true));
  File('android/app/src/main/res/drawable/ic_launcher_foreground.png')
    ..createSync(recursive: true)
    ..writeAsBytesSync(fg);
  stdout.writeln('wrote drawable/ic_launcher_foreground.png (432px)');

  File('android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml')
    ..createSync(recursive: true)
    ..writeAsString(
      '''<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
  <background android:drawable="@drawable/ic_launcher_background"/>
  <foreground android:drawable="@drawable/ic_launcher_foreground"/>
</adaptive-icon>
''',
    );
  File('android/app/src/main/res/drawable/ic_launcher_background.xml')
    ..createSync(recursive: true)
    ..writeAsString(
      '''<shape xmlns:android="http://schemas.android.com/apk/res/android">
  <gradient android:angle="270" android:startColor="#7FD8FF" android:endColor="#FFC3E8"/>
</shape>
''',
    );
  stdout.writeln('wrote adaptive icon XML + gradient background');
}

// ---------------------------------------------------------------- renderer --

/// Rasterizes the icon into RGBA bytes (straight alpha).
List<int> renderIcon(int size, {required bool foregroundOnly}) {
  final rgba = List<int>.filled(size * size * 4, 0);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      // 2×2 supersampling for smooth edges.
      var r = 0.0, g = 0.0, b = 0.0, a = 0.0;
      for (final (ox, oy) in const [
        (0.25, 0.25),
        (0.75, 0.25),
        (0.25, 0.75),
        (0.75, 0.75),
      ]) {
        final c = sample((x + ox) / size, (y + oy) / size, foregroundOnly);
        r += c[0];
        g += c[1];
        b += c[2];
        a += c[3];
      }
      final i = (y * size + x) * 4;
      rgba[i] = (r / 4).round();
      rgba[i + 1] = (g / 4).round();
      rgba[i + 2] = (b / 4).round();
      rgba[i + 3] = (a / 4).round();
    }
  }
  return rgba;
}

/// Returns the [r, g, b, a] color for a unit-space point (0..1).
List<int> sample(double u, double v, bool foregroundOnly) {
  var r = 0, g = 0, b = 0, a = 0;

  if (!foregroundOnly) {
    // Sky → pink vertical gradient.
    final t = v;
    r = (0x7F + (0xFF - 0x7F) * t).round();
    g = (0xD8 + (0xC3 - 0xD8) * t).round();
    b = (0xFF + (0xE8 - 0xFF) * t).round();
    a = 255;
  }

  final dx = u - 0.5;
  final dy = v - 0.5;
  final d = math.sqrt(dx * dx + dy * dy);

  // White face.
  final faceR = foregroundOnly ? 0.24 : 0.30;
  if (d < faceR) {
    r = 255;
    g = 255;
    b = 255;
    a = 255;
  }

  void dot(double cx, double cy, double radius, List<int> color) {
    final ddx = u - (0.5 + cx);
    final ddy = v - (0.5 + cy);
    if (ddx * ddx + ddy * ddy < radius * radius) {
      r = color[0];
      g = color[1];
      b = color[2];
      a = 255;
    }
  }

  const dark = [0x4A, 0x4A, 0x6A];
  const pink = [0xFF, 0x9D, 0xB0];
  const amber = [0xFF, 0xC1, 0x07];

  // Eyes.
  dot(-0.12, -0.05, 0.035, dark);
  dot(0.12, -0.05, 0.035, dark);
  // Rosy cheeks.
  dot(-0.19, 0.07, 0.05, pink);
  dot(0.19, 0.07, 0.05, pink);

  // Smile (arc: radius 0.14 around (0.5, 0.54), stroke 0.035, 0.15π..0.85π).
  final sx = u - 0.5;
  final sy = v - 0.54;
  final arcDist = math.sqrt(sx * sx + sy * sy);
  if ((arcDist - 0.14).abs() < 0.0175) {
    var angle = math.atan2(sy, sx); // clockwise (y-down)
    if (angle < 0) angle += 2 * math.pi;
    if (angle >= 0.15 * math.pi && angle <= 0.85 * math.pi) {
      r = dark[0];
      g = dark[1];
      b = dark[2];
      a = 255;
    }
  }

  // Sparkles (4-point stars).
  final sparkles = foregroundOnly
      ? const [(-0.19, -0.19), (0.19, -0.19), (0.19, 0.19), (-0.19, 0.19)]
      : const [(-0.30, -0.30), (0.32, -0.30), (0.32, 0.30), (-0.30, 0.30)];
  for (final (scx, scy) in sparkles) {
    final pdx = u - (0.5 + scx);
    final pdy = v - (0.5 + scy);
    final pd = math.sqrt(pdx * pdx + pdy * pdy);
    final theta = math.atan2(pdy, pdx);
    // 4-point star boundary: r(θ) = rOuter · √|cos 2θ|.
    final starR =
        (foregroundOnly ? 0.035 : 0.05) *
        math.sqrt((math.cos(2 * theta)).abs());
    if (pd < starR) {
      r = amber[0];
      g = amber[1];
      b = amber[2];
      a = 255;
    }
  }

  return [r, g, b, a];
}

// ------------------------------------------------------------- PNG encoder --

final _crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

List<int> _crc32(List<int> data) {
  var c = 0xFFFFFFFF;
  for (final byte in data) {
    c = _crcTable[(c ^ byte) & 0xff] ^ (c >> 8);
  }
  c ^= 0xFFFFFFFF;
  // PNG stores CRCs big-endian (MSB first).
  return [(c >> 24) & 0xff, (c >> 16) & 0xff, (c >> 8) & 0xff, c & 0xff];
}

Uint8List encodePng(List<int> rgba, {int? width, int? height}) {
  final size = (rgba.length / 4).round();
  final w = width ?? (math.sqrt(size).round());
  final h = height ?? w;

  // Scanlines with filter byte 0.
  final raw = BytesBuilder();
  for (var y = 0; y < h; y++) {
    raw.addByte(0);
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 4;
      raw.addByte(rgba[i]);
      raw.addByte(rgba[i + 1]);
      raw.addByte(rgba[i + 2]);
      raw.addByte(rgba[i + 3]);
    }
  }
  final idat = ZLibCodec(level: 9).encode(raw.takeBytes());

  final out = BytesBuilder();
  out.add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);

  void chunk(String type, List<int> data) {
    final len = data.length;
    out.add([
      (len >> 24) & 0xff,
      (len >> 16) & 0xff,
      (len >> 8) & 0xff,
      len & 0xff,
    ]);
    final typeBytes = type.codeUnits;
    out.add(typeBytes);
    out.add(data);
    out.add(_crc32([...typeBytes, ...data]));
  }

  chunk('IHDR', [
    (w >> 24) & 0xff, (w >> 16) & 0xff, (w >> 8) & 0xff, w & 0xff,
    (h >> 24) & 0xff, (h >> 16) & 0xff, (h >> 8) & 0xff, h & 0xff,
    8, 6, 0, 0, 0, // 8-bit RGBA
  ]);
  chunk('IDAT', idat);
  chunk('IEND', const []);
  return out.takeBytes();
}
