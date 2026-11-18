import 'dart:math' as math;
import 'dart:ui';

import '../core/color_utils.dart';
import '../model/anim.dart';
import '../model/vector.dart';

/// Returns [count] points evenly spaced along the path length.
/// Closed paths omit the duplicate endpoint; empty paths use the origin.
List<Offset> resamplePath(VPath path, int count) {
  if (count < 0) throw ArgumentError.value(count, 'count');
  if (count == 0) return [];
  final metrics = path.toPath().computeMetrics().toList();
  final length = metrics.fold<double>(0, (sum, m) => sum + m.length);
  if (length == 0) return List.filled(count, path.nodes.isEmpty ? Offset.zero : path.nodes.first.p);
  final divisor = path.closed ? count : math.max(1, count - 1);
  return List.generate(count, (i) {
    var offset = length * i / divisor;
    for (final metric in metrics) {
      if (offset <= metric.length) return metric.getTangentForOffset(offset)?.position ?? path.nodes.first.p;
      offset -= metric.length;
    }
    return path.nodes.last.p;
  });
}

double _area(List<Offset> points) {
  var area = 0.0;
  for (var i = 0; i < points.length; i++) {
    final a = points[i], b = points[(i + 1) % points.length];
    area += a.dx * b.dy - b.dx * a.dy;
  }
  return area;
}

List<Offset> _align(List<Offset> a, List<Offset> b) {
  if (a.isEmpty) return b;
  if (_area(a) * _area(b) < 0) b = b.reversed.toList();
  final ca = a.fold(Offset.zero, (s, p) => s + p) / a.length.toDouble();
  final cb = b.fold(Offset.zero, (s, p) => s + p) / b.length.toDouble();
  var best = double.infinity, shift = 0;
  for (var k = 0; k < a.length; k++) {
    var score = 0.0;
    for (var i = 0; i < a.length; i++) { score += ((a[i] - ca) - (b[(i + k) % b.length] - cb)).distanceSquared; }
    if (score < best) { best = score; shift = k; }
  }
  return List.generate(b.length, (i) => b[(i + shift) % b.length]);
}

double _lerp(double a, double b, double t) => a + (b - a) * t;
Offset _point(Offset a, Offset b, double t) => a + (b - a) * t;

/// Interpolates corresponding anchors, handles and widths. Incompatible paths
/// are resampled to [samples] points, aligning closed contours before blending.
VPath lerpVPath(VPath a, VPath b, double t, {int samples = 64}) {
  if (a.nodes.length == b.nodes.length && a.closed == b.closed) {
    return VPath(List.generate(a.nodes.length, (i) {
      final x = a.nodes[i], y = b.nodes[i];
      return VNode(_point(x.p, y.p, t), hIn: _point(x.hIn, y.hIn, t), hOut: _point(x.hOut, y.hOut, t),
          width: _lerp(x.width, y.width, t), kind: t < 0.5 ? x.kind : y.kind);
    }), closed: a.closed);
  }
  if (samples < 1) throw ArgumentError.value(samples, 'samples');
  final x = resamplePath(a, samples);
  var y = resamplePath(b, samples);
  if (a.closed && b.closed) y = _align(x, y);
  return VPath.polyline(List.generate(samples, (i) => _point(x[i], y[i], t)), closed: t < 0.5 ? a.closed : b.closed);
}

/// Interpolates geometry and style, preserving the first shape's identity.
VShape lerpShape(VShape a, VShape b, double t) {
  final paths = <VPath>[];
  for (var i = 0; i < math.max(a.paths.length, b.paths.length); i++) {
    if (a.paths.isEmpty) { paths.add(b.paths[i]); }
    else if (b.paths.isEmpty) { paths.add(a.paths[i]); }
    else { paths.add(lerpVPath(a.paths[math.min(i, a.paths.length - 1)], b.paths[math.min(i, b.paths.length - 1)], t)); }
  }
  final fill = a.fill.kind == FillKind.solid && b.fill.kind == FillKind.solid
      ? VFill.solid(lerpColor(a.fill.color, b.fill.color, t)) : (t < 0.5 ? a.fill : b.fill);
  final x = a.stroke, y = b.stroke;
  VStroke? stroke;
  if (x != null && y != null) {
    stroke = (t < 0.5 ? x : y).copyWith(color: lerpColor(x.color, y.color, t), width: _lerp(x.width, y.width, t));
  } else if (x != null) { stroke = x.copyWith(width: x.width * (1 - t)); }
  else if (y != null) { stroke = y.copyWith(width: y.width * t); }
  return a.copyWith(paths: paths, fill: fill, stroke: stroke, clearStroke: stroke == null,
      opacity: _lerp(a.opacity, b.opacity, t), evenOdd: t < 0.5 ? a.evenOdd : b.evenOdd);
}

/// Pairs shapes by id, then remaining shapes by order; unpaired shapes fade.
VectorArt lerpArt(VectorArt a, VectorArt b, double t) {
  final pairs = <int, int>{}, used = <int>{};
  for (var i = 0; i < a.shapes.length; i++) {
    for (var j = 0; j < b.shapes.length; j++) {
      if (!used.contains(j) && a.shapes[i].id == b.shapes[j].id) { pairs[i] = j; used.add(j); break; }
    }
  }
  final remaining = [for (var j = 0; j < b.shapes.length; j++) if (!used.contains(j)) j];
  var next = 0;
  for (var i = 0; i < a.shapes.length; i++) {
    if (!pairs.containsKey(i) && next < remaining.length) { final j = remaining[next++]; pairs[i] = j; used.add(j); }
  }
  return VectorArt([
    for (var i = 0; i < a.shapes.length; i++)
      if (pairs.containsKey(i)) lerpShape(a.shapes[i], b.shapes[pairs[i]!], t)
      else a.shapes[i].copyWith(opacity: a.shapes[i].opacity * (1 - t)),
    for (var j = 0; j < b.shapes.length; j++) if (!used.contains(j)) b.shapes[j].copyWith(opacity: b.shapes[j].opacity * t),
  ]);
}

/// Returns [count] drawings strictly between the endpoints using [ease].
List<VectorArt> inbetweens(VectorArt a, VectorArt b, int count, {Ease ease = Ease.linear}) {
  if (count < 0) throw ArgumentError.value(count, 'count');
  return List.generate(count, (i) => lerpArt(a, b, ease.transform((i + 1) / (count + 1))));
}
