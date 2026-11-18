import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui';

import '../model/vector.dart';
import 'tiles.dart';

/// Splits [source] into dashes following the on/off pattern [dash].
Path dashPath(Path source, List<double> dash) {
  final pattern = dash.where((d) => d > 0).toList();
  if (pattern.isEmpty) return source;
  final out = Path();
  for (final metric in source.computeMetrics()) {
    var dist = 0.0;
    var i = 0;
    var on = true;
    while (dist < metric.length) {
      final end = math.min(metric.length, dist + pattern[i % pattern.length]);
      if (on) out.addPath(metric.extractPath(dist, end), Offset.zero);
      dist = end;
      i++;
      on = !on;
    }
  }
  return out;
}

double _profileAt(WidthProfile p, double t, List<double> nodeWidths) {
  switch (p) {
    case WidthProfile.uniform:
      return 1;
    case WidthProfile.taperEnd:
      return math.max(0.02, 1 - t);
    case WidthProfile.taperStart:
      return math.max(0.02, t);
    case WidthProfile.taperBoth:
      return math.max(0.02, math.sin(t * math.pi));
    case WidthProfile.bulge:
      return 0.35 + 0.65 * math.sin(t * math.pi);
    case WidthProfile.nodes:
      if (nodeWidths.length < 2) return nodeWidths.isEmpty ? 1 : nodeWidths.first;
      final f = t * (nodeWidths.length - 1);
      final i = f.floor().clamp(0, nodeWidths.length - 2);
      final u = f - i;
      return math.max(0.02, nodeWidths[i] + (nodeWidths[i + 1] - nodeWidths[i]) * u);
  }
}

/// Outline polygon of a stroke whose width follows a [WidthProfile].
Path variableWidthOutline(VShape shape) {
  final st = shape.stroke!;
  final out = Path();
  var contour = 0;
  for (final metric in shape.path.computeMetrics()) {
    final len = metric.length;
    if (len <= 0) continue;
    final vp = contour < shape.paths.length ? shape.paths[contour] : null;
    final widths = vp == null ? const <double>[] : vp.nodes.map((n) => n.width).toList();
    contour++;
    final steps = math.max(2, (len / 2).ceil());
    final left = <Offset>[], right = <Offset>[];
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      final tan = metric.getTangentForOffset(len * t);
      if (tan == null) continue;
      final n = Offset(-tan.vector.dy, tan.vector.dx);
      final hw = st.width * _profileAt(st.profile, t, widths) / 2;
      left.add(tan.position + n * hw);
      right.add(tan.position - n * hw);
    }
    if (left.length < 2) continue;
    out.moveTo(left.first.dx, left.first.dy);
    for (final p in left.skip(1)) {
      out.lineTo(p.dx, p.dy);
    }
    for (final p in right.reversed) {
      out.lineTo(p.dx, p.dy);
    }
    out.close();
  }
  return out;
}

final Map<String, ui.Image> _patternCache = {};

/// 32px tileable pattern in [color] on transparent.
ui.Image patternImage(PatternKind kind, Color color) {
  final key = '${kind.name}:${color.toARGB32()}';
  return _patternCache[key] ??= renderToImage(32, 32, (c) {
    final p = Paint()
      ..color = color
      ..isAntiAlias = true;
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    switch (kind) {
      case PatternKind.stripes:
        for (var i = -32.0; i < 64; i += 16) {
          c.drawLine(Offset(i, 32), Offset(i + 32, 0), line);
        }
      case PatternKind.dots:
        c.drawCircle(const Offset(8, 8), 4, p);
        c.drawCircle(const Offset(24, 24), 4, p);
      case PatternKind.checker:
        c.drawRect(const Rect.fromLTWH(0, 0, 16, 16), p);
        c.drawRect(const Rect.fromLTWH(16, 16, 16, 16), p);
      case PatternKind.crosshatch:
        for (var i = -32.0; i < 64; i += 16) {
          c.drawLine(Offset(i, 32), Offset(i + 32, 0), line..strokeWidth = 1.5);
          c.drawLine(Offset(i, 0), Offset(i + 32, 32), line);
        }
      case PatternKind.grid:
        c.drawLine(const Offset(0, 0), const Offset(32, 0), line..strokeWidth = 2);
        c.drawLine(const Offset(0, 0), const Offset(0, 32), line);
        c.drawLine(const Offset(0, 16), const Offset(32, 16), line);
        c.drawLine(const Offset(16, 0), const Offset(16, 32), line);
      case PatternKind.waves:
        final path = Path()..moveTo(0, 8);
        path.cubicTo(8, 0, 8, 16, 16, 8);
        path.cubicTo(24, 0, 24, 16, 32, 8);
        c.drawPath(path, line..strokeWidth = 2.5);
        c.drawPath(path.shift(const Offset(0, 16)), line);
    }
  });
}

Paint _fillPaint(VFill fill, double opacity) {
  final p = Paint()..isAntiAlias = true;
  switch (fill.kind) {
    case FillKind.none:
      break;
    case FillKind.solid:
      p.color = fill.color.withValues(alpha: fill.color.a * opacity);
    case FillKind.gradient:
      p.shader = fill.gradient!.toShader();
      if (opacity < 1) p.color = Color.fromRGBO(0, 0, 0, opacity);
    case FillKind.pattern:
      final m = Float64List(16)
        ..[0] = fill.patternScale
        ..[5] = fill.patternScale
        ..[10] = 1
        ..[15] = 1;
      p.shader = ImageShader(patternImage(fill.pattern, fill.color), TileMode.repeated, TileMode.repeated, m, filterQuality: FilterQuality.low);
      if (opacity < 1) p.color = Color.fromRGBO(0, 0, 0, opacity);
  }
  return p;
}

void paintShape(Canvas canvas, VShape s) {
  final path = s.path;
  final hasFill = !s.fill.isNone, st = s.stroke;
  final hasStroke = st != null && st.width > 0 && st.color.a > 0;
  if (!hasFill && !hasStroke) return;
  final group = s.opacity < 1 && hasFill && hasStroke;
  var opacity = s.opacity;
  if (group) {
    canvas.saveLayer(s.bounds, Paint()..color = Color.fromRGBO(0, 0, 0, s.opacity.clamp(0.0, 1.0)));
    opacity = 1;
  }
  if (hasFill) {
    final g = s.fill.gradient;
    if (s.fill.kind == FillKind.gradient && g != null && g.kind.name == 'diamond') {
      canvas.save();
      canvas.clipPath(path);
      g.paint(canvas, path.getBounds(), base: opacity < 1 ? (Paint()..color = Color.fromRGBO(0, 0, 0, opacity)) : null);
      canvas.restore();
    } else {
      canvas.drawPath(path, _fillPaint(s.fill, opacity));
    }
  }
  if (hasStroke) {
    final col = st.color.withValues(alpha: st.color.a * opacity);
    if (st.profile != WidthProfile.uniform) {
      canvas.drawPath(variableWidthOutline(s), Paint()..color = col);
    } else {
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = st.width
        ..strokeCap = st.cap
        ..strokeJoin = st.join
        ..strokeMiterLimit = st.miterLimit
        ..color = col
        ..isAntiAlias = true;
      canvas.drawPath(st.dash.isEmpty ? path : dashPath(path, st.dash), p);
    }
  }
  if (group) canvas.restore();
}

void paintVectorArt(Canvas canvas, VectorArt art, {Rect? cull}) {
  for (final s in art.shapes) {
    if (cull != null && !s.bounds.overlaps(cull)) continue;
    paintShape(canvas, s);
  }
}

/// Topmost shape under [p], or null.
VShape? hitTestArt(VectorArt art, Offset p, {double tolerance = 4}) {
  for (final s in art.shapes.reversed) {
    if (!s.bounds.inflate(tolerance).contains(p)) continue;
    if (!s.fill.isNone && s.path.contains(p)) return s;
    final st = s.stroke;
    final w = math.max(tolerance, (st?.width ?? 0) / 2 + tolerance);
    for (final m in s.path.computeMetrics()) {
      final steps = math.max(4, (m.length / 3).ceil());
      for (var i = 0; i <= steps; i++) {
        final t = m.getTangentForOffset(m.length * i / steps);
        if (t != null && (t.position - p).distance <= w) return s;
      }
    }
  }
  return null;
}
