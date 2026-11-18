import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

/// Result of a mask producing pixel operation.
class MaskResult {
  MaskResult(this.alpha, this.width, this.height, this.bounds);

  /// One byte per pixel, 0..255.
  final Uint8List alpha;
  final int width, height;

  /// Tight bounds of non-zero alpha in pixel coordinates, or null if empty.
  final Rect? bounds;

  bool get isEmpty => bounds == null;

  /// White, premultiplied RGBA with [alpha] as coverage.
  Uint8List toRgba() {
    final out = Uint8List(width * height * 4);
    for (var i = 0, o = 0; i < alpha.length; i++, o += 4) {
      final a = alpha[i];
      if (a == 0) continue;
      out[o] = a;
      out[o + 1] = a;
      out[o + 2] = a;
      out[o + 3] = a;
    }
    return out;
  }
}

Rect? _maskBounds(Uint8List alpha, int w, int h) {
  var x0 = w, y0 = h, x1 = -1, y1 = -1;
  for (var y = 0; y < h; y++) {
    final row = y * w;
    for (var x = 0; x < w; x++) {
      if (alpha[row + x] != 0) {
        if (x < x0) x0 = x;
        if (x > x1) x1 = x;
        if (y < y0) y0 = y;
        if (y > y1) y1 = y;
      }
    }
  }
  if (x1 < 0) return null;
  return Rect.fromLTRB(x0.toDouble(), y0.toDouble(), x1 + 1.0, y1 + 1.0);
}

/// Per-pixel similarity (0..255 coverage) to the colour at the seed.
///
/// [rgba] is straight (un-premultiplied) RGBA. A pixel matches fully when
/// its largest channel difference is <= [tolerance]; between tolerance and
/// tolerance + [softness] the coverage falls off linearly (anti-aliasing).
Uint8List _similarity(Uint8List rgba, int w, int h, int sr, int sg, int sb, int sa, int tolerance, int softness) {
  final out = Uint8List(w * h);
  final soft = math.max(1, softness);
  for (var i = 0, o = 0; i < out.length; i++, o += 4) {
    final a = rgba[o + 3];
    int d;
    if (a == 0 && sa == 0) {
      d = 0;
    } else {
      final dr = (rgba[o] - sr).abs(), dg = (rgba[o + 1] - sg).abs(), db = (rgba[o + 2] - sb).abs(), da = (a - sa).abs();
      d = math.max(math.max(dr, dg), math.max(db, da));
    }
    if (d <= tolerance) {
      out[i] = 255;
    } else if (d < tolerance + soft) {
      out[i] = (255 * (1 - (d - tolerance) / soft)).round();
    }
  }
  return out;
}

/// Box erosion of a coverage mask by [radius] pixels (closes small gaps in
/// line art before a flood fill).
Uint8List erodeMask(Uint8List src, int w, int h, int radius) {
  if (radius <= 0) return src;
  final tmp = Uint8List(w * h), out = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    final row = y * w;
    for (var x = 0; x < w; x++) {
      var m = 255;
      final x0 = math.max(0, x - radius), x1 = math.min(w - 1, x + radius);
      for (var k = x0; k <= x1; k++) {
        final v = src[row + k];
        if (v < m) {
          m = v;
          if (m == 0) break;
        }
      }
      tmp[row + x] = m;
    }
  }
  for (var x = 0; x < w; x++) {
    for (var y = 0; y < h; y++) {
      var m = 255;
      final y0 = math.max(0, y - radius), y1 = math.min(h - 1, y + radius);
      for (var k = y0; k <= y1; k++) {
        final v = tmp[k * w + x];
        if (v < m) {
          m = v;
          if (m == 0) break;
        }
      }
      out[y * w + x] = m;
    }
  }
  return out;
}

Uint8List dilateMask(Uint8List src, int w, int h, int radius) {
  if (radius <= 0) return src;
  final tmp = Uint8List(w * h), out = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    final row = y * w;
    for (var x = 0; x < w; x++) {
      var m = 0;
      final x0 = math.max(0, x - radius), x1 = math.min(w - 1, x + radius);
      for (var k = x0; k <= x1; k++) {
        final v = src[row + k];
        if (v > m) {
          m = v;
          if (m == 255) break;
        }
      }
      tmp[row + x] = m;
    }
  }
  for (var x = 0; x < w; x++) {
    for (var y = 0; y < h; y++) {
      var m = 0;
      final y0 = math.max(0, y - radius), y1 = math.min(h - 1, y + radius);
      for (var k = y0; k <= y1; k++) {
        final v = tmp[k * w + x];
        if (v > m) {
          m = v;
          if (m == 255) break;
        }
      }
      out[y * w + x] = m;
    }
  }
  return out;
}

/// Scan-line flood fill over a coverage map: grows from (sx, sy) through
/// every pixel whose coverage is non-zero.
Uint8List _flood(Uint8List sim, int w, int h, int sx, int sy) {
  final out = Uint8List(w * h);
  if (sx < 0 || sy < 0 || sx >= w || sy >= h || sim[sy * w + sx] == 0) return out;
  final stack = <int>[sx, sy];
  while (stack.isNotEmpty) {
    final y = stack.removeLast();
    var x = stack.removeLast();
    var row = y * w;
    if (out[row + x] != 0 || sim[row + x] == 0) continue;
    while (x > 0 && sim[row + x - 1] != 0 && out[row + x - 1] == 0) {
      x--;
    }
    var up = false, down = false;
    while (x < w && sim[row + x] != 0 && out[row + x] == 0) {
      out[row + x] = sim[row + x];
      if (y > 0) {
        final a = sim[row - w + x] != 0 && out[row - w + x] == 0;
        if (a && !up) {
          stack
            ..add(x)
            ..add(y - 1);
        }
        up = a;
      }
      if (y < h - 1) {
        final b = sim[row + w + x] != 0 && out[row + w + x] == 0;
        if (b && !down) {
          stack
            ..add(x)
            ..add(y + 1);
        }
        down = b;
      }
      x++;
    }
  }
  return out;
}

/// Magic wand / paint bucket region.
///
/// * [contiguous] false selects every similar pixel in the image.
/// * [gap] closes openings of up to that many pixels in the outline.
MaskResult floodSelect(
  Uint8List rgba,
  int w,
  int h,
  int sx,
  int sy, {
  int tolerance = 32,
  int softness = 24,
  bool contiguous = true,
  int gap = 0,
}) {
  if (sx < 0 || sy < 0 || sx >= w || sy >= h) return MaskResult(Uint8List(w * h), w, h, null);
  final o = (sy * w + sx) * 4;
  final sim = _similarity(rgba, w, h, rgba[o], rgba[o + 1], rgba[o + 2], rgba[o + 3], tolerance, softness);
  Uint8List out;
  if (!contiguous) {
    out = sim;
  } else if (gap > 0) {
    final eroded = erodeMask(sim, w, h, gap);
    final core = _flood(eroded, w, h, sx, sy);
    final grown = dilateMask(core, w, h, gap + 1);
    out = Uint8List(w * h);
    for (var i = 0; i < out.length; i++) {
      out[i] = math.min(grown[i], sim[i]);
    }
    // fall back to a plain fill when the seed sits in a region thinner than the gap
    if (_maskBounds(out, w, h) == null) out = _flood(sim, w, h, sx, sy);
  } else {
    out = _flood(sim, w, h, sx, sy);
  }
  return MaskResult(out, w, h, _maskBounds(out, w, h));
}

/// Selects pixels similar to [color] anywhere in the image.
MaskResult selectColorRange(Uint8List rgba, int w, int h, Color color, {int tolerance = 40, int softness = 30}) {
  final sim = _similarity(
    rgba,
    w,
    h,
    (color.r * 255).round(),
    (color.g * 255).round(),
    (color.b * 255).round(),
    (color.a * 255).round(),
    tolerance,
    softness,
  );
  return MaskResult(sim, w, h, _maskBounds(sim, w, h));
}

/// Selects pixels whose luminance lies in [low, high] (0..255) with a soft edge.
MaskResult selectLuminosity(Uint8List rgba, int w, int h, {int low = 128, int high = 255, int softness = 20}) {
  final out = Uint8List(w * h);
  final soft = math.max(1, softness);
  for (var i = 0, o = 0; i < out.length; i++, o += 4) {
    final a = rgba[o + 3];
    if (a == 0) continue;
    final l = (0.2126 * rgba[o] + 0.7152 * rgba[o + 1] + 0.0722 * rgba[o + 2]).round();
    double c;
    if (l >= low && l <= high) {
      c = 1;
    } else if (l < low) {
      c = 1 - (low - l) / soft;
    } else {
      c = 1 - (l - high) / soft;
    }
    if (c > 0) out[i] = (c * a).round().clamp(0, 255);
  }
  return MaskResult(out, w, h, _maskBounds(out, w, h));
}

/// Coverage mask of pixel alpha (selection from layer transparency).
MaskResult alphaMask(Uint8List rgba, int w, int h) {
  final out = Uint8List(w * h);
  for (var i = 0, o = 3; i < out.length; i++, o += 4) {
    out[i] = rgba[o];
  }
  return MaskResult(out, w, h, _maskBounds(out, w, h));
}

/// Per-channel 256-bin histogram (r, g, b, luminance) of straight RGBA.
List<Int32List> histogram(Uint8List rgba) {
  final r = Int32List(256), g = Int32List(256), b = Int32List(256), l = Int32List(256);
  for (var o = 0; o < rgba.length; o += 4) {
    if (rgba[o + 3] == 0) continue;
    r[rgba[o]]++;
    g[rgba[o + 1]]++;
    b[rgba[o + 2]]++;
    l[(0.2126 * rgba[o] + 0.7152 * rgba[o + 1] + 0.0722 * rgba[o + 2]).round().clamp(0, 255)]++;
  }
  return [r, g, b, l];
}

class _Box {
  _Box(this.colors);
  final List<int> colors; // packed 0xRRGGBB, one entry per sampled pixel

  int get count => colors.length;

  (int axis, int range) widest() {
    var r0 = 255, r1 = 0, g0 = 255, g1 = 0, b0 = 255, b1 = 0;
    for (final c in colors) {
      final r = (c >> 16) & 255, g = (c >> 8) & 255, b = c & 255;
      if (r < r0) r0 = r;
      if (r > r1) r1 = r;
      if (g < g0) g0 = g;
      if (g > g1) g1 = g;
      if (b < b0) b0 = b;
      if (b > b1) b1 = b;
    }
    final dr = r1 - r0, dg = g1 - g0, db = b1 - b0;
    if (dr >= dg && dr >= db) return (16, dr);
    if (dg >= db) return (8, dg);
    return (0, db);
  }

  int average() {
    var r = 0, g = 0, b = 0;
    for (final c in colors) {
      r += (c >> 16) & 255;
      g += (c >> 8) & 255;
      b += c & 255;
    }
    final n = math.max(1, colors.length);
    return 0xFF000000 | ((r ~/ n) << 16) | ((g ~/ n) << 8) | (b ~/ n);
  }
}

/// Median-cut palette extraction. Returns up to [count] ARGB colours ordered
/// by how much of the image they cover.
List<int> extractPalette(Uint8List rgba, {int count = 8, int maxSamples = 40000}) {
  final total = rgba.length ~/ 4;
  final step = math.max(1, total ~/ maxSamples);
  final samples = <int>[];
  for (var i = 0; i < total; i += step) {
    final o = i * 4;
    if (rgba[o + 3] < 128) continue;
    samples.add((rgba[o] << 16) | (rgba[o + 1] << 8) | rgba[o + 2]);
  }
  if (samples.isEmpty) return const [];
  final boxes = <_Box>[_Box(samples)];
  while (boxes.length < count) {
    // split the box with the widest colour range
    var bi = -1, best = 0, axis = 0;
    for (var i = 0; i < boxes.length; i++) {
      if (boxes[i].count < 2) continue;
      final (ax, range) = boxes[i].widest();
      if (range * math.sqrt(boxes[i].count) > best) {
        best = (range * math.sqrt(boxes[i].count)).round();
        bi = i;
        axis = ax;
      }
    }
    if (bi < 0 || best == 0) break;
    final box = boxes.removeAt(bi);
    box.colors.sort((a, b) => ((a >> axis) & 255).compareTo((b >> axis) & 255));
    final mid = box.colors.length ~/ 2;
    boxes
      ..add(_Box(box.colors.sublist(0, mid)))
      ..add(_Box(box.colors.sublist(mid)));
  }
  boxes.sort((a, b) => b.count.compareTo(a.count));
  return boxes.map((b) => b.average()).toList();
}

/// Maps every pixel of straight RGBA to the nearest [palette] colour
/// (optionally with Floyd-Steinberg dithering). Works in place.
void quantizeToPalette(Uint8List rgba, int w, int h, List<int> palette, {bool dither = false}) {
  if (palette.isEmpty) return;
  final pr = [for (final c in palette) (c >> 16) & 255];
  final pg = [for (final c in palette) (c >> 8) & 255];
  final pb = [for (final c in palette) c & 255];
  int nearest(int r, int g, int b) {
    var best = 0, bd = 1 << 30;
    for (var i = 0; i < pr.length; i++) {
      final dr = r - pr[i], dg = g - pg[i], db = b - pb[i];
      final d = dr * dr * 3 + dg * dg * 4 + db * db * 2;
      if (d < bd) {
        bd = d;
        best = i;
      }
    }
    return best;
  }

  if (!dither) {
    for (var o = 0; o < rgba.length; o += 4) {
      if (rgba[o + 3] == 0) continue;
      final i = nearest(rgba[o], rgba[o + 1], rgba[o + 2]);
      rgba[o] = pr[i];
      rgba[o + 1] = pg[i];
      rgba[o + 2] = pb[i];
    }
    return;
  }
  final err = Float32List(w * h * 3);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final o = (y * w + x) * 4, e = (y * w + x) * 3;
      if (rgba[o + 3] == 0) continue;
      final r = (rgba[o] + err[e]).round().clamp(0, 255);
      final g = (rgba[o + 1] + err[e + 1]).round().clamp(0, 255);
      final b = (rgba[o + 2] + err[e + 2]).round().clamp(0, 255);
      final i = nearest(r, g, b);
      final er = (r - pr[i]).toDouble(), eg = (g - pg[i]).toDouble(), eb = (b - pb[i]).toDouble();
      rgba[o] = pr[i];
      rgba[o + 1] = pg[i];
      rgba[o + 2] = pb[i];
      void spread(int dx, int dy, double f) {
        final nx = x + dx, ny = y + dy;
        if (nx < 0 || nx >= w || ny >= h) return;
        final ne = (ny * w + nx) * 3;
        err[ne] += er * f;
        err[ne + 1] += eg * f;
        err[ne + 2] += eb * f;
      }

      spread(1, 0, 7 / 16);
      spread(-1, 1, 3 / 16);
      spread(0, 1, 5 / 16);
      spread(1, 1, 1 / 16);
    }
  }
}
