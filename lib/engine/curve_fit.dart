import 'dart:math' as math;
import 'dart:ui';

import '../model/vector.dart';

/// Least-squares cubic Bézier fitting of a digitised stroke
/// (Schneider, "An Algorithm for Automatically Fitting Digitized Curves").
class CurveFit {
  /// Fits [points] within [tolerance] pixels. Returns cubic segments as
  /// lists of four control points.
  static List<List<Offset>> fit(List<Offset> points, double tolerance) {
    final pts = <Offset>[];
    for (final p in points) {
      if (pts.isEmpty || (p - pts.last).distanceSquared > 1e-6) pts.add(p);
    }
    if (pts.length < 2) return const [];
    final out = <List<Offset>>[];
    final t1 = _norm(pts[1] - pts[0]);
    final t2 = _norm(pts[pts.length - 2] - pts[pts.length - 1]);
    _fit(pts, 0, pts.length - 1, t1, t2, tolerance * tolerance, out, 0);
    return out;
  }

  static Offset _norm(Offset v) {
    final d = v.distance;
    return d < 1e-12 ? const Offset(1, 0) : v / d;
  }

  static void _fit(List<Offset> d, int first, int last, Offset tHat1, Offset tHat2, double error, List<List<Offset>> out, int depth) {
    final nPts = last - first + 1;
    if (nPts == 2) {
      final dist = (d[last] - d[first]).distance / 3;
      out.add([d[first], d[first] + tHat1 * dist, d[last] + tHat2 * dist, d[last]]);
      return;
    }
    var u = _chordLength(d, first, last);
    var bez = _generate(d, first, last, u, tHat1, tHat2);
    var (maxError, split) = _maxError(d, first, last, bez, u);
    if (maxError < error) {
      out.add(bez);
      return;
    }
    if (maxError < error * 16) {
      for (var i = 0; i < 4; i++) {
        final up = _reparameterize(d, first, last, u, bez);
        bez = _generate(d, first, last, up, tHat1, tHat2);
        final r = _maxError(d, first, last, bez, up);
        maxError = r.$1;
        split = r.$2;
        if (maxError < error) {
          out.add(bez);
          return;
        }
        u = up;
      }
    }
    if (depth > 48 || split <= first || split >= last) {
      out.add(bez);
      return;
    }
    final tc = _norm((d[split - 1] - d[split]) + (d[split] - d[split + 1]));
    _fit(d, first, split, tHat1, tc, error, out, depth + 1);
    _fit(d, split, last, -tc, tHat2, error, out, depth + 1);
  }

  static List<double> _chordLength(List<Offset> d, int first, int last) {
    final u = List<double>.filled(last - first + 1, 0);
    for (var i = first + 1; i <= last; i++) {
      u[i - first] = u[i - first - 1] + (d[i] - d[i - 1]).distance;
    }
    final total = u.last;
    if (total > 0) {
      for (var i = 1; i < u.length; i++) {
        u[i] /= total;
      }
    }
    return u;
  }

  static double _b0(double u) => (1 - u) * (1 - u) * (1 - u);
  static double _b1(double u) => 3 * u * (1 - u) * (1 - u);
  static double _b2(double u) => 3 * u * u * (1 - u);
  static double _b3(double u) => u * u * u;

  static double _dot(Offset a, Offset b) => a.dx * b.dx + a.dy * b.dy;

  static List<Offset> _generate(List<Offset> d, int first, int last, List<double> u, Offset tHat1, Offset tHat2) {
    final n = last - first + 1;
    double c00 = 0, c01 = 0, c11 = 0, x0 = 0, x1 = 0;
    final p0 = d[first], p3 = d[last];
    for (var i = 0; i < n; i++) {
      final a0 = tHat1 * _b1(u[i]), a1 = tHat2 * _b2(u[i]);
      c00 += _dot(a0, a0);
      c01 += _dot(a0, a1);
      c11 += _dot(a1, a1);
      final tmp = d[first + i] - (p0 * (_b0(u[i]) + _b1(u[i])) + p3 * (_b2(u[i]) + _b3(u[i])));
      x0 += _dot(a0, tmp);
      x1 += _dot(a1, tmp);
    }
    final det = c00 * c11 - c01 * c01;
    final segLength = (p3 - p0).distance;
    final eps = 1e-6 * segLength;
    double al, ar;
    if (det.abs() < 1e-12) {
      al = ar = segLength / 3;
    } else {
      al = (x0 * c11 - x1 * c01) / det;
      ar = (c00 * x1 - c01 * x0) / det;
    }
    if (al < eps || ar < eps || al > segLength * 4 || ar > segLength * 4) {
      al = ar = segLength / 3;
    }
    return [p0, p0 + tHat1 * al, p3 + tHat2 * ar, p3];
  }

  static Offset _eval(List<Offset> b, double t) => b[0] * _b0(t) + b[1] * _b1(t) + b[2] * _b2(t) + b[3] * _b3(t);

  static (double, int) _maxError(List<Offset> d, int first, int last, List<Offset> bez, List<double> u) {
    var maxDist = 0.0;
    var split = (last - first + 1) ~/ 2 + first;
    for (var i = first + 1; i < last; i++) {
      final dist = (_eval(bez, u[i - first]) - d[i]).distanceSquared;
      if (dist >= maxDist) {
        maxDist = dist;
        split = i;
      }
    }
    return (maxDist, split);
  }

  static List<double> _reparameterize(List<Offset> d, int first, int last, List<double> u, List<Offset> bez) {
    final out = List<double>.filled(last - first + 1, 0);
    for (var i = first; i <= last; i++) {
      out[i - first] = _newton(bez, d[i], u[i - first]);
    }
    return out;
  }

  static double _newton(List<Offset> q, Offset p, double u) {
    final qu = _eval(q, u);
    // first and second derivative control points
    final q1 = [(q[1] - q[0]) * 3.0, (q[2] - q[1]) * 3.0, (q[3] - q[2]) * 3.0];
    final q2 = [(q1[1] - q1[0]) * 2.0, (q1[2] - q1[1]) * 2.0];
    final q1u = q1[0] * ((1 - u) * (1 - u)) + q1[1] * (2 * u * (1 - u)) + q1[2] * (u * u);
    final q2u = q2[0] * (1 - u) + q2[1] * u;
    final num = _dot(qu - p, q1u);
    final den = _dot(q1u, q1u) + _dot(qu - p, q2u);
    if (den.abs() < 1e-12) return u;
    return (u - num / den).clamp(0.0, 1.0);
  }

  /// Converts fitted segments into an editable path.
  static VPath toPath(List<List<Offset>> segs, {bool closed = false, List<double>? widths}) {
    if (segs.isEmpty) return const VPath([]);
    final nodes = <VNode>[];
    for (var i = 0; i < segs.length; i++) {
      final s = segs[i];
      final hIn = i == 0 ? (closed ? segs.last[2] : s[0]) : segs[i - 1][2];
      nodes.add(VNode(s[0], hIn: hIn, hOut: s[1], kind: i == 0 && !closed ? NodeKind.corner : NodeKind.smooth, width: _w(widths, i, segs.length)));
    }
    if (!closed) {
      final lastSeg = segs.last;
      nodes.add(VNode(lastSeg[3], hIn: lastSeg[2], width: _w(widths, segs.length, segs.length)));
    }
    return VPath(nodes, closed: closed);
  }

  static double _w(List<double>? widths, int node, int segCount) {
    if (widths == null || widths.isEmpty) return 1;
    final t = segCount == 0 ? 0.0 : node / segCount;
    final f = t * (widths.length - 1);
    final i = f.floor().clamp(0, widths.length - 1);
    final j = math.min(widths.length - 1, i + 1);
    return widths[i] + (widths[j] - widths[i]) * (f - i);
  }

  /// Fits a freehand stroke and returns a ready-to-use path.
  static VPath fitPath(List<Offset> points, {double tolerance = 1.5, bool closed = false, List<double>? widths}) {
    if (points.length == 1) return VPath([VNode(points.first)]);
    final pts = closed && points.length > 2 ? [...points, points.first] : points;
    return toPath(fit(pts, tolerance), closed: closed, widths: widths);
  }
}

/// Ramer-Douglas-Peucker polyline simplification.
List<Offset> simplifyPolyline(List<Offset> pts, double epsilon) {
  if (pts.length < 3) return pts;
  final keep = List<bool>.filled(pts.length, false);
  keep[0] = true;
  keep[pts.length - 1] = true;
  final stack = <(int, int)>[(0, pts.length - 1)];
  while (stack.isNotEmpty) {
    final (a, b) = stack.removeLast();
    var maxD = 0.0;
    var idx = -1;
    final ab = pts[b] - pts[a];
    final len = ab.distance;
    for (var i = a + 1; i < b; i++) {
      final ap = pts[i] - pts[a];
      final d = len < 1e-9 ? ap.distance : (ab.dx * ap.dy - ab.dy * ap.dx).abs() / len;
      if (d > maxD) {
        maxD = d;
        idx = i;
      }
    }
    if (idx >= 0 && maxD > epsilon) {
      keep[idx] = true;
      stack
        ..add((a, idx))
        ..add((idx, b));
    }
  }
  return [
    for (var i = 0; i < pts.length; i++)
      if (keep[i]) pts[i],
  ];
}
