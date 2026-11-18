import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:ui';
import '../model/vector.dart';
import 'curve_fit.dart';

/// Set operations on filled shapes.
enum BoolOp { union, subtract, intersect, exclude }

double _dot(Offset a, Offset b) => a.dx * b.dx + a.dy * b.dy;

/// Converts a path into editable contours, preserving sharp tangent changes.
List<VPath> pathToVPaths(ui.Path path, {double tolerance = 0.4, double cornerAngle = 35}) {
  if (tolerance <= 0 || cornerAngle <= 0 || cornerAngle >= 180) throw ArgumentError('Invalid path fitting options');
  final result = <VPath>[];
  for (final metric in path.computeMetrics()) {
    final length = metric.length;
    if (length <= 0) continue;
    final n = length.ceil().clamp(8, 4000), step = length / n;
    Tangent tangent(double d) => metric.getTangentForOffset(d.clamp(0, length))!;
    final corners = <double>[];
    final cosine = math.cos(cornerAngle * math.pi / 180);
    for (var i = 0; i < n; i++) {
      final lo = i * step, hi = (i + 1) * step;
      final before = tangent(lo).vector, after = tangent(hi).vector;
      if (_dot(before, after) >= cosine) continue;
      var l = lo, r = hi;
      for (var k = 0; k < 24; k++) {
        final mid = (l + r) / 2;
        if (_dot(before, tangent(mid).vector) >= cosine) { l = mid; } else { r = mid; }
      }
      corners.add((l + r) / 2);
    }
    if (metric.isClosed && _dot(tangent(0).vector, tangent(length).vector) < cosine) corners.insert(0, 0);
    if (metric.isClosed && corners.isEmpty) {
      result.add(CurveFit.fitPath(List.generate(n, (i) => tangent(i * step).position), tolerance: tolerance * 0.5, closed: true));
      continue;
    }
    final cuts = metric.isClosed ? [...corners, corners.first + length] : [0.0, ...corners.where((c) => c > 1e-5 && c < length - 1e-5), length];
    Offset point(double d) => tangent(d > length ? d - length : d).position;
    final segments = <List<Offset>>[], sharp = <int>{};
    for (var k = 0; k + 1 < cuts.length; k++) {
      final a = cuts[k], b = cuts[k + 1];
      final count = math.max(2, ((b - a) / step).ceil() + 1);
      final points = List.generate(count, (i) => point(a + (b - a) * i / (count - 1)));
      sharp.add(segments.length);
      final chord = points.last - points.first;
      final straight = chord.distance > 0 && points.every((p) => ((p.dx - points.first.dx) * chord.dy - (p.dy - points.first.dy) * chord.dx).abs() / chord.distance < 0.05);
      if (straight) { segments.add([points.first, points.first, points.last, points.last]); }
      else { segments.addAll(CurveFit.fit(points, tolerance)); }
    }
    final fitted = CurveFit.toPath(segments, closed: metric.isClosed);
    result.add(fitted.copyWith(nodes: [for (var i = 0; i < fitted.nodes.length; i++) fitted.nodes[i].copyWith(
      hIn: (fitted.nodes[i].hIn - fitted.nodes[i].p).distance < 1e-4 ? fitted.nodes[i].p : fitted.nodes[i].hIn,
      hOut: (fitted.nodes[i].hOut - fitted.nodes[i].p).distance < 1e-4 ? fitted.nodes[i].p : fitted.nodes[i].hOut,
      kind: sharp.contains(i) ? NodeKind.corner : NodeKind.smooth)]));
  }
  return result;
}

/// Combines the lower [a] with upper [b], preserving the style and identity of [a].
VShape? booleanShapes(VShape a, VShape b, BoolOp op, {double tolerance = 0.4}) {
  final operation = switch (op) { BoolOp.union => PathOperation.union, BoolOp.subtract => PathOperation.difference, BoolOp.intersect => PathOperation.intersect, BoolOp.exclude => PathOperation.xor };
  final path = ui.Path.combine(operation, a.path, b.path);
  if (path.getBounds().isEmpty) return null;
  final paths = pathToVPaths(path, tolerance: tolerance);
  return paths.isEmpty ? null : a.copyWith(paths: paths, evenOdd: path.fillType == PathFillType.evenOdd);
}

/// Folds shapes in order, retaining an empty intermediate set where necessary.
VShape? booleanAll(List<VShape> shapes, BoolOp op, {double tolerance = 0.4}) {
  if (shapes.isEmpty) return null;
  VShape? result = shapes.first;
  for (final shape in shapes.skip(1)) {
    result = booleanShapes(result ?? shapes.first.copyWith(paths: []), shape, op, tolerance: tolerance);
  }
  return result;
}
