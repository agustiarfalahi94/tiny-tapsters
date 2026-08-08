// Generates the Android launcher icons for Tiny Tapsters from the master
// artwork in assets/branding/tiny-tapsters-logo.png:
//   - legacy PNGs in mipmap-{mdpi..xxxhdpi}/ic_launcher.png (badge only,
//     rounded corners knocked out to transparent)
//   - adaptive icon: drawable/ic_launcher_foreground.png (432×432, the baby
//     fitted inside the safe zone) + a solid mint background colour
//
// Pure Dart: no Flutter engine, no packages. The PNG decoder and encoder are
// both built in (zlib comes from dart:io).
//
// The master artwork is the full Canva logo — a mint badge on white with the
// "Tiny Tapsters" wordmark underneath. The wordmark is deliberately dropped:
// at 48dp it is an illegible smudge and the launcher prints the app name
// below the icon anyway.
//
// Run: dart run tool/generate_icon.dart
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

const _source = 'assets/branding/tiny-tapsters-logo.png';
const _res = 'android/app/src/main/res';

void main() {
  final src = decodePng(File(_source).readAsBytesSync());
  stdout.writeln('read $_source (${src.width}×${src.height})');

  // The artwork is two ink clusters stacked on white: the badge, then the
  // wordmark. Take the first one.
  final badge = _firstInkCluster(src);
  stdout.writeln(
    'badge at (${badge.left},${badge.top}) ${badge.width}×${badge.height}',
  );

  final mint = _dominantFill(src, badge);
  final mintHex =
      '#${mint[0].toRadixString(16).padLeft(2, '0')}'
              '${mint[1].toRadixString(16).padLeft(2, '0')}'
              '${mint[2].toRadixString(16).padLeft(2, '0')}'
          .toUpperCase();
  stdout.writeln('badge background $mintHex');

  // --- legacy icons: the badge, with the white outside knocked out --------
  final cut = _crop(src, badge);
  _knockOutBackground(cut);
  const legacy = {
    'mipmap-mdpi': 48,
    'mipmap-hdpi': 72,
    'mipmap-xhdpi': 96,
    'mipmap-xxhdpi': 144,
    'mipmap-xxxhdpi': 192,
  };
  for (final entry in legacy.entries) {
    final scaled = _resample(cut, entry.value, entry.value);
    _write('$_res/${entry.key}/ic_launcher.png', encodePng(scaled));
    stdout.writeln('wrote ${entry.key}/ic_launcher.png (${entry.value}px)');
  }

  // --- adaptive foreground: the baby, fitted to the safe zone -------------
  //
  // Android renders a 108dp canvas but only guarantees the centre 72dp is
  // visible (the launcher masks the rest). Scaling the whole badge to fill
  // the canvas would push the baby's face outside that circle, so measure
  // the baby itself and fit *it* to the safe zone. The body is allowed to
  // bleed off the bottom edge, exactly as it does in the master artwork.
  final baby = _subjectBounds(cut, mint);
  stdout.writeln(
    'baby at (${baby.bounds.left},${baby.bounds.top}) '
    '${baby.bounds.width}×${baby.bounds.height}',
  );
  final fg = _fitToSafeZone(_isolate(cut, baby), baby.bounds, 432);
  _write('$_res/drawable/ic_launcher_foreground.png', encodePng(fg));
  stdout.writeln('wrote drawable/ic_launcher_foreground.png (432px)');

  _write(
    '$_res/mipmap-anydpi-v26/ic_launcher.xml',
    '''<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
  <background android:drawable="@drawable/ic_launcher_background"/>
  <foreground android:drawable="@drawable/ic_launcher_foreground"/>
</adaptive-icon>
'''
        .codeUnits,
  );
  // Solid mint, sampled from the artwork: a flat colour survives any mask
  // shape the launcher applies without showing a seam.
  _write(
    '$_res/drawable/ic_launcher_background.xml',
    '''<shape xmlns:android="http://schemas.android.com/apk/res/android">
  <solid android:color="$mintHex"/>
</shape>
'''
        .codeUnits,
  );
  stdout.writeln('wrote adaptive icon XML + $mintHex background');
}

void _write(String path, List<int> bytes) {
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes);
}

// ------------------------------------------------------------------ image --

/// A simple RGBA image buffer.
class Img {
  Img(this.width, this.height) : pixels = Uint8List(width * height * 4);
  Img.from(this.width, this.height, this.pixels);

  final int width;
  final int height;
  final Uint8List pixels;

  int idx(int x, int y) => (y * width + x) * 4;
  bool opaqueAt(int x, int y) => pixels[idx(x, y) + 3] > 8;
}

class Rect {
  const Rect(this.left, this.top, this.width, this.height);
  final int left, top, width, height;
  int get right => left + width;
  int get bottom => top + height;
}

/// True when a pixel is close enough to white to count as page background.
bool _isPaper(int r, int g, int b) => r > 244 && g > 244 && b > 244;

/// Finds the bounding box of the first (topmost) band of non-white content,
/// stopping at the first fully white gap — which separates badge from
/// wordmark.
Rect _firstInkCluster(Img im) {
  bool rowHasInk(int y) {
    for (var x = 0; x < im.width; x++) {
      final i = im.idx(x, y);
      if (!_isPaper(im.pixels[i], im.pixels[i + 1], im.pixels[i + 2])) {
        return true;
      }
    }
    return false;
  }

  var top = 0;
  while (top < im.height && !rowHasInk(top)) {
    top++;
  }
  var bottom = top;
  while (bottom < im.height && rowHasInk(bottom)) {
    bottom++;
  }
  if (top >= im.height) {
    throw StateError('$_source looks blank — no non-white pixels found');
  }

  var left = im.width, right = 0;
  for (var y = top; y < bottom; y++) {
    for (var x = 0; x < im.width; x++) {
      final i = im.idx(x, y);
      if (!_isPaper(im.pixels[i], im.pixels[i + 1], im.pixels[i + 2])) {
        if (x < left) left = x;
        if (x > right) right = x;
      }
    }
  }
  return Rect(left, top, right - left + 1, bottom - top);
}

/// The badge's flat background colour: the most common non-white colour in
/// the whole badge. Sampling the edges instead would be fooled by the hair
/// tuft, which pokes above the badge into the white page.
List<int> _dominantFill(Img im, Rect r) {
  final counts = <int, int>{};
  for (var y = r.top; y < r.bottom; y++) {
    for (var x = r.left; x < r.right; x++) {
      final i = im.idx(x, y);
      if (_isPaper(im.pixels[i], im.pixels[i + 1], im.pixels[i + 2])) continue;
      final key =
          (im.pixels[i] << 16) | (im.pixels[i + 1] << 8) | im.pixels[i + 2];
      counts[key] = (counts[key] ?? 0) + 1;
    }
  }
  var best = 0, bestCount = -1;
  counts.forEach((k, v) {
    if (v > bestCount) {
      best = k;
      bestCount = v;
    }
  });
  return [(best >> 16) & 0xff, (best >> 8) & 0xff, best & 0xff];
}

Img _crop(Img im, Rect r) {
  final out = Img(r.width, r.height);
  for (var y = 0; y < r.height; y++) {
    for (var x = 0; x < r.width; x++) {
      final s = im.idx(r.left + x, r.top + y);
      final d = out.idx(x, y);
      out.pixels[d] = im.pixels[s];
      out.pixels[d + 1] = im.pixels[s + 1];
      out.pixels[d + 2] = im.pixels[s + 2];
      out.pixels[d + 3] = 255;
    }
  }
  return out;
}

/// Flood-fills the white page colour inward from the corners and makes it
/// transparent, so the badge keeps its rounded corners. Flooding (rather than
/// testing every pixel) protects the white highlights *inside* the artwork —
/// the sparkles, the eyes, the teeth — because they are enclosed by ink.
void _knockOutBackground(Img im) {
  final seen = List<bool>.filled(im.width * im.height, false);
  final queue = <int>[];
  void push(int x, int y) {
    if (x < 0 || y < 0 || x >= im.width || y >= im.height) return;
    final p = y * im.width + x;
    if (seen[p]) return;
    final i = p * 4;
    if (!_isPaper(im.pixels[i], im.pixels[i + 1], im.pixels[i + 2])) return;
    seen[p] = true;
    queue.add(p);
  }

  for (var x = 0; x < im.width; x++) {
    push(x, 0);
    push(x, im.height - 1);
  }
  for (var y = 0; y < im.height; y++) {
    push(0, y);
    push(im.width - 1, y);
  }
  while (queue.isNotEmpty) {
    final p = queue.removeLast();
    im.pixels[p * 4 + 3] = 0;
    final x = p % im.width, y = p ~/ im.width;
    push(x - 1, y);
    push(x + 1, y);
    push(x, y - 1);
    push(x, y + 1);
  }
}

/// Bounds of the main subject — the baby.
///
/// Two things make this less trivial than "find the non-background pixels".
/// The badge edge is anti-aliased, so there is a ring of mint/white blends
/// that belongs to no shape; and the sparkles are separate specks out near
/// the corners. So: discount anything sitting on the mint→white blend line,
/// then keep only the largest connected blob, which is the baby.
class Subject {
  Subject(this.bounds, this.mask);

  /// Bounding box of the blob.
  final Rect bounds;

  /// One flag per pixel: true where the blob actually covers.
  final List<bool> mask;
}

Subject _subjectBounds(Img im, List<int> bg) {
  /// Distance from the mint→white gradient, which is what anti-aliased badge
  /// edges are made of.
  bool isBlend(int i) {
    final r = im.pixels[i].toDouble();
    final g = im.pixels[i + 1].toDouble();
    final b = im.pixels[i + 2].toDouble();
    final dr = 255 - bg[0], dg = 255 - bg[1], db = 255 - bg[2];
    final lenSq = (dr * dr + dg * dg + db * db).toDouble();
    var t = 0.0;
    if (lenSq > 0) {
      t = ((r - bg[0]) * dr + (g - bg[1]) * dg + (b - bg[2]) * db) / lenSq;
      t = t.clamp(0.0, 1.0);
    }
    final pr = bg[0] + dr * t, pg = bg[1] + dg * t, pb = bg[2] + db * t;
    final d2 = (r - pr) * (r - pr) + (g - pg) * (g - pg) + (b - pb) * (b - pb);
    return d2 < 18 * 18;
  }

  final isSubject = List<bool>.filled(im.width * im.height, false);
  for (var p = 0; p < isSubject.length; p++) {
    final i = p * 4;
    isSubject[p] = im.pixels[i + 3] > 8 && !isBlend(i);
  }

  // Largest 4-connected blob wins.
  final seen = List<bool>.filled(isSubject.length, false);
  var best = const Rect(0, 0, 0, 0);
  var bestArea = 0;
  var bestMask = List<bool>.filled(isSubject.length, false);
  final stack = <int>[];
  for (var start = 0; start < isSubject.length; start++) {
    if (!isSubject[start] || seen[start]) continue;
    seen[start] = true;
    stack
      ..clear()
      ..add(start);
    final mask = List<bool>.filled(isSubject.length, false);
    var area = 0;
    var left = im.width, right = 0, top = im.height, bottom = 0;
    while (stack.isNotEmpty) {
      final p = stack.removeLast();
      final x = p % im.width, y = p ~/ im.width;
      mask[p] = true;
      area++;
      if (x < left) left = x;
      if (x > right) right = x;
      if (y < top) top = y;
      if (y > bottom) bottom = y;
      void visit(int nx, int ny) {
        if (nx < 0 || ny < 0 || nx >= im.width || ny >= im.height) return;
        final q = ny * im.width + nx;
        if (seen[q] || !isSubject[q]) return;
        seen[q] = true;
        stack.add(q);
      }

      visit(x - 1, y);
      visit(x + 1, y);
      visit(x, y - 1);
      visit(x, y + 1);
    }
    if (area > bestArea) {
      bestArea = area;
      best = Rect(left, top, right - left + 1, bottom - top + 1);
      bestMask = mask;
    }
  }
  return Subject(best, bestMask);
}

/// A copy of [im] keeping only the pixels [subject] covers, everything else
/// transparent. Edge pixels of the blob are left at full opacity; the badge
/// colour behind them matches the adaptive background, so no halo shows.
Img _isolate(Img im, Subject subject) {
  final out = Img(im.width, im.height);
  for (var p = 0; p < subject.mask.length; p++) {
    if (!subject.mask[p]) continue;
    final i = p * 4;
    out.pixels[i] = im.pixels[i];
    out.pixels[i + 1] = im.pixels[i + 1];
    out.pixels[i + 2] = im.pixels[i + 2];
    out.pixels[i + 3] = im.pixels[i + 3];
  }
  return out;
}

/// Places [subject] (a region of [im]) on a transparent [size]² canvas so it
/// fits the adaptive-icon safe zone — the centre 2/3 that every launcher mask
/// keeps. Anything taller than the safe zone bleeds off the bottom rather
/// than shrinking the face.
Img _fitToSafeZone(Img im, Rect subject, int size) {
  const safeFraction = 0.68;
  final safe = size * safeFraction;
  final scale = math.min(safe / subject.width, safe / subject.height);

  final drawW = subject.width * scale;
  final drawH = subject.height * scale;
  final originX = (size - drawW) / 2;
  final originY = (size - drawH) / 2;

  final out = Img(size, size);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      // Map back into source space, sampling a scale-sized box for smoothness.
      final sx0 = subject.left + (x - originX) / scale;
      final sy0 = subject.top + (y - originY) / scale;
      final sx1 = sx0 + 1 / scale;
      final sy1 = sy0 + 1 / scale;
      // Outside the subject stays empty. Without this the sampler's clamping
      // would smear the subject's edge rows across the rest of the canvas.
      if (sx1 <= subject.left ||
          sy1 <= subject.top ||
          sx0 >= subject.right ||
          sy0 >= subject.bottom) {
        continue;
      }
      final c = _boxSample(im, sx0, sy0, sx1, sy1);
      final d = out.idx(x, y);
      out.pixels[d] = c[0];
      out.pixels[d + 1] = c[1];
      out.pixels[d + 2] = c[2];
      out.pixels[d + 3] = c[3];
    }
  }
  return out;
}

/// Area-averaged downscale — keeps small artwork crisp instead of aliased.
Img _resample(Img im, int w, int h) {
  final out = Img(w, h);
  final fx = im.width / w, fy = im.height / h;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final c = _boxSample(im, x * fx, y * fy, (x + 1) * fx, (y + 1) * fy);
      final d = out.idx(x, y);
      out.pixels[d] = c[0];
      out.pixels[d + 1] = c[1];
      out.pixels[d + 2] = c[2];
      out.pixels[d + 3] = c[3];
    }
  }
  return out;
}

/// Averages the source box, weighting colour by alpha so transparent pixels
/// do not drag dark fringes into the result.
List<int> _boxSample(Img im, double x0, double y0, double x1, double y1) {
  final ix0 = x0.floor().clamp(0, im.width - 1);
  final iy0 = y0.floor().clamp(0, im.height - 1);
  final ix1 = (x1.ceil()).clamp(ix0 + 1, im.width);
  final iy1 = (y1.ceil()).clamp(iy0 + 1, im.height);

  var r = 0.0, g = 0.0, b = 0.0, a = 0.0, n = 0;
  for (var y = iy0; y < iy1; y++) {
    for (var x = ix0; x < ix1; x++) {
      final i = im.idx(x, y);
      final alpha = im.pixels[i + 3] / 255;
      r += im.pixels[i] * alpha;
      g += im.pixels[i + 1] * alpha;
      b += im.pixels[i + 2] * alpha;
      a += alpha;
      n++;
    }
  }
  if (n == 0 || a == 0) return const [0, 0, 0, 0];
  return [
    (r / a).round().clamp(0, 255),
    (g / a).round().clamp(0, 255),
    (b / a).round().clamp(0, 255),
    (a / n * 255).round().clamp(0, 255),
  ];
}

// ---------------------------------------------------------------- decoder --

/// Minimal PNG reader: 8-bit truecolour, with or without alpha, no
/// interlacing — which is what the exported artwork is.
Img decodePng(Uint8List bytes) {
  const signature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  for (var i = 0; i < signature.length; i++) {
    if (bytes[i] != signature[i]) throw StateError('not a PNG');
  }

  var offset = 8;
  int? width, height, colourType;
  final idat = BytesBuilder();
  while (offset < bytes.length) {
    final len =
        (bytes[offset] << 24) |
        (bytes[offset + 1] << 16) |
        (bytes[offset + 2] << 8) |
        bytes[offset + 3];
    final type = String.fromCharCodes(bytes.sublist(offset + 4, offset + 8));
    final data = bytes.sublist(offset + 8, offset + 8 + len);
    if (type == 'IHDR') {
      width = (data[0] << 24) | (data[1] << 16) | (data[2] << 8) | data[3];
      height = (data[4] << 24) | (data[5] << 16) | (data[6] << 8) | data[7];
      final depth = data[8];
      colourType = data[9];
      if (depth != 8 || (colourType != 2 && colourType != 6)) {
        throw StateError(
          'unsupported PNG: depth $depth, colour type $colourType '
          '(need 8-bit RGB or RGBA)',
        );
      }
      if (data[12] != 0) throw StateError('interlaced PNGs are not supported');
    } else if (type == 'IDAT') {
      idat.add(data);
    } else if (type == 'IEND') {
      break;
    }
    offset += 12 + len; // length + type + data + CRC
  }
  if (width == null || height == null) throw StateError('PNG has no IHDR');

  final channels = colourType == 6 ? 4 : 3;
  final raw = Uint8List.fromList(ZLibCodec().decode(idat.takeBytes()));
  final stride = width * channels;
  final out = Img(width, height);

  // Undo the per-scanline filters (PNG spec §9).
  final prior = Uint8List(stride);
  final line = Uint8List(stride);
  var p = 0;
  for (var y = 0; y < height; y++) {
    final filter = raw[p++];
    for (var i = 0; i < stride; i++) {
      final rawByte = raw[p + i];
      final a = i >= channels ? line[i - channels] : 0; // left
      final b = prior[i]; // up
      final c = i >= channels ? prior[i - channels] : 0; // up-left
      final int value;
      switch (filter) {
        case 0:
          value = rawByte;
        case 1:
          value = rawByte + a;
        case 2:
          value = rawByte + b;
        case 3:
          value = rawByte + ((a + b) >> 1);
        case 4:
          final pp = a + b - c;
          final pa = (pp - a).abs(), pb = (pp - b).abs(), pc = (pp - c).abs();
          value = rawByte + (pa <= pb && pa <= pc ? a : (pb <= pc ? b : c));
        default:
          throw StateError('bad PNG filter $filter on row $y');
      }
      line[i] = value & 0xff;
    }
    p += stride;

    for (var x = 0; x < width; x++) {
      final s = x * channels;
      final d = out.idx(x, y);
      out.pixels[d] = line[s];
      out.pixels[d + 1] = line[s + 1];
      out.pixels[d + 2] = line[s + 2];
      out.pixels[d + 3] = channels == 4 ? line[s + 3] : 255;
    }
    prior.setAll(0, line);
  }
  return out;
}

// ---------------------------------------------------------------- encoder --

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

Uint8List encodePng(Img im) {
  final w = im.width, h = im.height;

  // Scanlines with filter byte 0.
  final raw = BytesBuilder();
  for (var y = 0; y < h; y++) {
    raw.addByte(0);
    raw.add(im.pixels.sublist(im.idx(0, y), im.idx(0, y) + w * 4));
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
