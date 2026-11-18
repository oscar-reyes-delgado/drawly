import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset;

/// A row-major grayscale image, one byte per pixel.
class GrayFrame {
  const GrayFrame(this.pixels, this.width, this.height);
  final Uint8List pixels;
  final int width, height;
}
void _validate(GrayFrame f) { if (f.width <= 0 || f.height <= 0 || f.pixels.length != f.width * f.height) throw ArgumentError('Invalid grayscale dimensions'); }

/// Converts RGBA to rounded Rec. 709 luminance.
GrayFrame grayFromRgba(Uint8List rgba, int width, int height) {
  if (width <= 0 || height <= 0 || rgba.length != width * height * 4) throw ArgumentError('Invalid RGBA dimensions');
  return GrayFrame(Uint8List.fromList([for (var i = 0; i < rgba.length; i += 4) (0.2126 * rgba[i] + 0.7152 * rgba[i + 1] + 0.0722 * rgba[i + 2]).round()]), width, height);
}

/// Finds a patch using normalized cross-correlation and parabolic refinement.
/// Windows are clipped to the common valid area; flat windows score zero.
({Offset pos, double score}) trackPatch(GrayFrame a, GrayFrame b, Offset from, {int patch = 21, int search = 24}) {
  _validate(a); _validate(b);
  if (patch < 1 || search < 0) throw ArgumentError('Invalid patch or search size');
  final cx = from.dx.round(), cy = from.dy.round(), half = patch ~/ 2;
  final x0 = math.max(0, cx - half), y0 = math.max(0, cy - half), x1 = math.min(a.width, cx - half + patch), y1 = math.min(a.height, cy - half + patch);
  double correlation(int dx, int dy) {
    final left = math.max(x0, -dx), right = math.min(x1, b.width - dx), top = math.max(y0, -dy), bottom = math.min(y1, b.height - dy);
    if (right <= left || bottom <= top) return 0;
    var sx = 0.0, sy = 0.0, xx = 0.0, yy = 0.0, xy = 0.0;
    final count = (right - left) * (bottom - top);
    for (var y = top; y < bottom; y++) {
      var i = y * a.width + left, j = (y + dy) * b.width + left + dx;
      for (var x = left; x < right; x++, i++, j++) {
        final av = a.pixels[i].toDouble(), bv = b.pixels[j].toDouble();
        sx += av; sy += bv; xx += av * av; yy += bv * bv; xy += av * bv;
      }
    }
    final vx = count * xx - sx * sx, vy = count * yy - sy * sy;
    if (vx <= 1e-9 || vy <= 1e-9) return 0;
    return ((count * xy - sx * sy) / math.sqrt(vx * vy)).clamp(0, 1);
  }
  var bx = 0, by = 0, best = 0.0;
  final side = 2 * search + 1, scores = Float64List(side * side);
  for (var dy = -search; dy <= search; dy++) {
    for (var dx = -search; dx <= search; dx++) {
      final score = correlation(dx, dy); scores[(dy + search) * side + dx + search] = score;
      if (score > best + 1e-12 || ((score - best).abs() <= 1e-12 && dx * dx + dy * dy < bx * bx + by * by)) { best = score; bx = dx; by = dy; }
    }
  }
  double refine(double l, double c, double r) { final curvature = l - 2 * c + r; return curvature >= -1e-12 ? 0 : (0.5 * (l - r) / curvature).clamp(-0.5, 0.5); }
  double score(int x, int y) => scores[(y + search) * side + x + search];
  final rx = best < 0.999999 && bx > -search && bx < search ? refine(score(bx - 1, by), best, score(bx + 1, by)) : 0.0;
  final ry = best < 0.999999 && by > -search && by < search ? refine(score(bx, by - 1), best, score(bx, by + 1)) : 0.0;
  return (pos: from + Offset(bx + rx, by + ry), score: best);
}

/// Follows a point frame by frame, repeating its position on low confidence.
List<Offset> trackPoint(List<GrayFrame> frames, Offset start, {int patch = 21, int search = 24, double minScore = 0.5}) {
  if (frames.isEmpty) return [];
  final result = [start];
  for (var i = 1; i < frames.length; i++) {
    final match = trackPatch(frames[i - 1], frames[i], result.last, patch: patch, search: search);
    result.add(match.score >= minScore ? match.pos : result.last);
  }
  return result;
}
double _median(List<double> values) { values.sort(); final n = values.length; return n.isOdd ? values[n ~/ 2] : (values[n ~/ 2 - 1] + values[n ~/ 2]) / 2; }

/// Estimates translation relative to frame zero using median grid motion.
List<Offset> estimateShake(List<GrayFrame> frames, {int grid = 4, int patch = 31, int search = 16}) {
  if (grid < 1) throw ArgumentError.value(grid, 'grid');
  if (frames.isEmpty) return [];
  final first = frames.first; _validate(first);
  final result = [Offset.zero];
  for (final frame in frames.skip(1)) {
    final dx = <double>[], dy = <double>[];
    for (var y = 0; y < grid; y++) {
      for (var x = 0; x < grid; x++) {
        final start = Offset(((x + 0.5) * first.width / grid).floorToDouble(), ((y + 0.5) * first.height / grid).floorToDouble());
        final match = trackPatch(first, frame, start, patch: patch, search: search);
        if (match.score > 0.5) { dx.add(match.pos.dx - start.dx); dy.add(match.pos.dy - start.dy); }
      }
    }
    result.add(dx.isEmpty ? Offset.zero : Offset(_median(dx), _median(dy)));
  }
  return result;
}

/// Offsets that replace shake with its centered moving average.
List<Offset> stabilizeOffsets(List<Offset> shake, {int window = 9}) {
  if (window < 1) throw ArgumentError.value(window, 'window');
  final prefix = [Offset.zero];
  for (final p in shake) { prefix.add(prefix.last + p); }
  return List.generate(shake.length, (i) {
    final from = math.max(0, i - (window - 1) ~/ 2), to = math.min(shake.length, i + window ~/ 2 + 1);
    return (prefix[to] - prefix[from]) / (to - from).toDouble() - shake[i];
  });
}
