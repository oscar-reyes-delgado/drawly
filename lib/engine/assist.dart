import 'dart:math' as math;
import 'dart:ui';

import '../model/document.dart';

Offset _projectOnLine(Offset p, Offset a, Offset dir) {
  final d2 = dir.dx * dir.dx + dir.dy * dir.dy;
  if (d2 < 1e-12) return a;
  final t = ((p.dx - a.dx) * dir.dx + (p.dy - a.dy) * dir.dy) / d2;
  return a + dir * t;
}

Offset _cubic(List<Offset> c, double t) {
  final u = 1 - t;
  return c[0] * (u * u * u) + c[1] * (3 * u * u * t) + c[2] * (3 * u * t * t) + c[3] * (t * t * t);
}

/// Constrains strokes to a drawing assistant (ruler, perspective grid…).
///
/// One instance lives for the duration of a stroke: perspective and
/// isometric guides lock onto the direction the stroke starts in.
class AssistSnapper {
  AssistSnapper(this.spec, this.start);

  final AssistSpec spec;
  final Offset start;
  Offset? _lockedDir;

  bool get enabled => spec.active && spec.snap && spec.points.isNotEmpty;

  Offset snap(Offset p) {
    if (!enabled) return p;
    final pts = spec.points;
    switch (spec.kind) {
      case AssistKind.none:
        return p;
      case AssistKind.ruler:
        if (pts.length < 2) return p;
        return _projectOnLine(p, pts[0], pts[1] - pts[0]);
      case AssistKind.parallel:
        if (pts.length < 2) return p;
        return _projectOnLine(p, start, pts[1] - pts[0]);
      case AssistKind.perspective1:
        return _locked(p, [pts[0] - start, const Offset(1, 0), const Offset(0, 1)]);
      case AssistKind.perspective2:
        if (pts.length < 2) return p;
        return _locked(p, [pts[0] - start, pts[1] - start, const Offset(0, 1)]);
      case AssistKind.perspective3:
        if (pts.length < 3) return p;
        return _locked(p, [pts[0] - start, pts[1] - start, pts[2] - start]);
      case AssistKind.isometric:
        const a = math.pi / 6;
        return _locked(p, [Offset(math.cos(a), math.sin(a)), Offset(math.cos(a), -math.sin(a)), const Offset(0, 1)]);
      case AssistKind.ellipse:
        if (pts.length < 2) return p;
        final r = Rect.fromPoints(pts[0], pts[1]);
        final rx = math.max(1.0, r.width / 2), ry = math.max(1.0, r.height / 2);
        final th = math.atan2((p.dy - r.center.dy) / ry, (p.dx - r.center.dx) / rx);
        return r.center + Offset(math.cos(th) * rx, math.sin(th) * ry);
      case AssistKind.concentric:
        final c = pts[0];
        final radius = (start - c).distance;
        final v = p - c;
        final d = v.distance;
        return d < 1e-6 ? p : c + v / d * radius;
      case AssistKind.curve:
        if (pts.length < 4) return p;
        var best = pts[0];
        var bd = double.infinity;
        for (var i = 0; i <= 200; i++) {
          final q = _cubic(pts, i / 200);
          final d = (q - p).distanceSquared;
          if (d < bd) {
            bd = d;
            best = q;
          }
        }
        return best;
    }
  }

  Offset _locked(Offset p, List<Offset> dirs) {
    final move = p - start;
    if (_lockedDir == null) {
      if (move.distance < 6) return start;
      var best = dirs.first;
      var score = -1.0;
      for (final d in dirs) {
        final len = d.distance;
        if (len < 1e-9) continue;
        final s = ((move.dx * d.dx + move.dy * d.dy) / (len * move.distance)).abs();
        if (s > score) {
          score = s;
          best = d;
        }
      }
      _lockedDir = best;
    }
    return _projectOnLine(p, start, _lockedDir!);
  }
}

/// Draws the assistant (in document space; [zoom] keeps lines hairline).
void paintAssist(Canvas canvas, AssistSpec spec, Rect docRect, double zoom) {
  if (!spec.active || !spec.visible || spec.points.isEmpty) return;
  final line = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1 / zoom
    ..color = const Color(0x9900B0FF);
  final strong = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.6 / zoom
    ..color = const Color(0xEE00B0FF);
  final pts = spec.points;
  final far = docRect.longestSide * 4;

  void ray(Offset from, Offset dir, [Paint? p]) {
    final len = dir.distance;
    if (len < 1e-9) return;
    final d = dir / len * far;
    canvas.drawLine(from - d, from + d, p ?? line);
  }

  void fan(Offset vp) {
    for (var i = 0; i < 36; i++) {
      final a = i * math.pi / 36;
      ray(vp, Offset(math.cos(a), math.sin(a)));
    }
  }

  switch (spec.kind) {
    case AssistKind.none:
      break;
    case AssistKind.ruler:
      if (pts.length >= 2) ray(pts[0], pts[1] - pts[0], strong);
    case AssistKind.parallel:
      if (pts.length >= 2) {
        final dir = pts[1] - pts[0];
        final len = dir.distance;
        if (len > 1e-6) {
          final n = Offset(-dir.dy, dir.dx) / len;
          final step = docRect.shortestSide / 12;
          for (var i = -24; i <= 24; i++) {
            ray(pts[0] + n * (i * step), dir, i == 0 ? strong : line);
          }
        }
      }
    case AssistKind.perspective1:
      fan(pts[0]);
    case AssistKind.perspective2:
      if (pts.length >= 2) {
        fan(pts[0]);
        fan(pts[1]);
        ray(pts[0], pts[1] - pts[0], strong);
      }
    case AssistKind.perspective3:
      if (pts.length >= 3) {
        fan(pts[0]);
        fan(pts[1]);
        fan(pts[2]);
        ray(pts[0], pts[1] - pts[0], strong);
      }
    case AssistKind.isometric:
      const a = math.pi / 6;
      final step = docRect.shortestSide / 10;
      for (var i = -30; i <= 30; i++) {
        final o = pts[0] + Offset(0, i * step);
        ray(o, Offset(math.cos(a), math.sin(a)));
        ray(o, Offset(math.cos(a), -math.sin(a)));
        ray(pts[0] + Offset(i * step * math.cos(a), 0), const Offset(0, 1));
      }
    case AssistKind.ellipse:
      if (pts.length >= 2) canvas.drawOval(Rect.fromPoints(pts[0], pts[1]), strong);
    case AssistKind.concentric:
      final step = docRect.shortestSide / 14;
      for (var i = 1; i <= 24; i++) {
        canvas.drawCircle(pts[0], i * step, line);
      }
    case AssistKind.curve:
      if (pts.length >= 4) {
        final path = Path()..moveTo(pts[0].dx, pts[0].dy);
        path.cubicTo(pts[1].dx, pts[1].dy, pts[2].dx, pts[2].dy, pts[3].dx, pts[3].dy);
        canvas.drawPath(path, strong);
        canvas.drawLine(pts[0], pts[1], line);
        canvas.drawLine(pts[3], pts[2], line);
      }
  }
}

/// Snaps a document point to the grid and to guides.
Offset snapPoint(
  Offset p, {
  required List<Guide> guides,
  required bool toGuides,
  required bool toGrid,
  required double gridSize,
  required double threshold,
}) {
  var x = p.dx, y = p.dy;
  var bx = threshold, by = threshold;
  if (toGrid && gridSize > 0) {
    final gx = (p.dx / gridSize).roundToDouble() * gridSize, gy = (p.dy / gridSize).roundToDouble() * gridSize;
    if ((gx - p.dx).abs() < bx) {
      bx = (gx - p.dx).abs();
      x = gx;
    }
    if ((gy - p.dy).abs() < by) {
      by = (gy - p.dy).abs();
      y = gy;
    }
  }
  if (toGuides) {
    for (final g in guides) {
      if (g.vertical) {
        if ((g.pos - p.dx).abs() < bx) {
          bx = (g.pos - p.dx).abs();
          x = g.pos;
        }
      } else if ((g.pos - p.dy).abs() < by) {
        by = (g.pos - p.dy).abs();
        y = g.pos;
      }
    }
  }
  return Offset(x, y);
}
