import 'dart:math' as math;
import 'dart:ui';

import '../model/vector.dart';

/// Arrow from [from] to [to]: closed 7-node polygon. Zero sizes pick
/// defaults proportional to the length (head 30 %, head width 24 %, shaft 9 %).
VPath arrowPath(
  Offset from,
  Offset to, {
  double headLength = 0,
  double headWidth = 0,
  double shaftWidth = 0,
}) {
  final d = to - from;
  final len = d.distance;
  if (len < 1e-6) {
    return VPath([
      VNode(from),
      VNode(from),
      VNode(from),
      VNode(to),
      VNode(from),
      VNode(from),
      VNode(from),
    ], closed: true);
  }

  final dir = d / len;
  final perp = Offset(-dir.dy, dir.dx);
  final hl = headLength > 0 ? math.min(headLength, len) : len * 0.30;
  final hw = headWidth > 0 ? headWidth : len * 0.24;
  final sw = shaftWidth > 0 ? shaftWidth : len * 0.09;

  final neck = to - dir * hl;
  final halfShaft = sw / 2;
  final halfHead = hw / 2;

  return VPath([
    VNode(from + perp * halfShaft),
    VNode(neck + perp * halfShaft),
    VNode(neck + perp * halfHead),
    VNode(to),
    VNode(neck - perp * halfHead),
    VNode(neck - perp * halfShaft),
    VNode(from - perp * halfShaft),
  ], closed: true);
}

VPath heartPath(Rect r) {
  Offset pt(double nx, double ny) => Offset(r.left + nx * r.width, r.top + ny * r.height);
  return VPath([
    VNode(pt(0.50, 0.24), hIn: pt(0.42, 0.00), hOut: pt(0.58, 0.00)),
    VNode(pt(1.00, 0.32), hIn: pt(0.90, 0.00), hOut: pt(1.00, 0.56)),
    VNode(pt(0.50, 1.00), hIn: pt(0.80, 0.78), hOut: pt(0.20, 0.78)),
    VNode(pt(0.00, 0.32), hIn: pt(0.00, 0.56), hOut: pt(0.10, 0.00)),
  ], closed: true);
}

/// Oval speech balloon with a tail whose tip is [tailTip] (default: below the
/// bottom-left of [r]). [tailWidth] is a fraction of r.width.
VPath speechBubblePath(Rect r, {Offset? tailTip, double tailWidth = 0.18}) {
  final tip = tailTip ?? Offset(r.left + r.width * 0.22, r.bottom + r.height * 0.25);
  final cx = r.center.dx;
  final cy = r.center.dy;
  final rx = math.max(1e-3, r.width / 2);
  final ry = math.max(1e-3, r.height / 2);
  const k = 0.5522847498;
  final ox = rx * k;
  final oy = ry * k;

  final halfTw = (r.width * tailWidth.clamp(0.04, 0.5)) / 2;
  final baseX = tip.dx.clamp(cx - rx * 0.6 + halfTw, cx + rx * 0.6 - halfTw);
  final xR = (baseX + halfTw).clamp(cx - rx * 0.75, cx + rx * 0.75);
  final xL = (baseX - halfTw).clamp(cx - rx * 0.75, cx + rx * 0.75);

  final theta1 = math.acos(((xR - cx) / rx).clamp(-0.9, 0.9));
  final theta2 = math.acos(((xL - cx) / rx).clamp(-0.9, 0.9));

  Offset arcPt(double a) => Offset(cx + rx * math.cos(a), cy + ry * math.sin(a));
  Offset arcTan(double a) => Offset(-rx * math.sin(a), ry * math.cos(a));

  final alphaRight = (4.0 / 3.0) * math.tan(theta1 / 4.0);
  final alphaLeft = (4.0 / 3.0) * math.tan((math.pi - theta2) / 4.0);

  final p1 = arcPt(theta1);
  final p2 = arcPt(theta2);

  return VPath([
    VNode(Offset(cx, cy - ry), hIn: Offset(cx - ox, cy - ry), hOut: Offset(cx + ox, cy - ry), kind: NodeKind.symmetric),
    VNode(Offset(cx + rx, cy), hIn: Offset(cx + rx, cy - oy), hOut: Offset(cx + rx, cy) + arcTan(0) * alphaRight),
    VNode(p1, hIn: p1 - arcTan(theta1) * alphaRight),
    VNode(tip),
    VNode(p2, hOut: p2 + arcTan(theta2) * alphaLeft),
    VNode(Offset(cx - rx, cy), hIn: Offset(cx - rx, cy) - arcTan(math.pi) * alphaLeft, hOut: Offset(cx - rx, cy - oy)),
  ], closed: true);
}

/// Rounded-rectangle balloon with a tail.
VPath roundedBubblePath(
  Rect r, {
  double radius = 24,
  Offset? tailTip,
  double tailWidth = 0.18,
}) {
  final tip = tailTip ?? Offset(r.left + r.width * 0.22, r.bottom + r.height * 0.25);
  final rad = math.min(radius, math.min(r.width, r.height) / 2);
  const k = 0.5522847498;
  final c = rad * k;
  final l = r.left;
  final t = r.top;
  final rt = r.right;
  final b = r.bottom;

  final avail = math.max(0.0, r.width - 2 * rad);
  final tw = math.min(r.width * tailWidth.clamp(0.04, 0.5), avail * 0.8);
  final halfTw = tw / 2;
  final baseX = tip.dx.clamp(l + rad + halfTw, rt - rad - halfTw);
  final tailRight = Offset(baseX + halfTw, b);
  final tailLeft = Offset(baseX - halfTw, b);

  return VPath([
    VNode(Offset(l + rad, t), hIn: Offset(l + rad - c, t)),
    VNode(Offset(rt - rad, t), hOut: Offset(rt - rad + c, t)),
    VNode(Offset(rt, t + rad), hIn: Offset(rt, t + rad - c)),
    VNode(Offset(rt, b - rad), hOut: Offset(rt, b - rad + c)),
    VNode(Offset(rt - rad, b), hIn: Offset(rt - rad + c, b)),
    VNode(tailRight),
    VNode(tip),
    VNode(tailLeft),
    VNode(Offset(l + rad, b), hOut: Offset(l + rad - c, b)),
    VNode(Offset(l, b - rad), hIn: Offset(l, b - rad + c)),
    VNode(Offset(l, t + rad), hOut: Offset(l, t + rad - c)),
  ], closed: true);
}

/// Shout balloon: jagged star whose spike lengths vary with [seed].
VPath burstPath(Rect r, {int spikes = 14, double depth = 0.28, int seed = 1}) {
  final n = math.max(3, spikes);
  final rng = math.Random(seed);
  final cx = r.center.dx;
  final cy = r.center.dy;
  final rx = r.width / 2;
  final ry = r.height / 2;
  final total = n * 2;

  return VPath([
    for (var i = 0; i < total; i++)
      () {
        final angle = i * math.pi / n;
        final scale = i.isEven
            ? 1.0
            : (1.0 - depth * (0.8 + rng.nextDouble() * 0.4)).clamp(0.05, 0.98);
        return VNode(Offset(cx + rx * scale * math.cos(angle), cy + ry * scale * math.sin(angle)));
      }(),
  ], closed: true);
}

/// Thought balloon: scalloped outline made of [lobes] arcs.
VPath cloudPath(Rect r, {int lobes = 9}) {
  final n = math.max(3, lobes);
  final cx = r.center.dx;
  final cy = r.center.dy;
  final rx = r.width / 2;
  final ry = r.height / 2;
  const baseScale = 0.81;
  const bulge = 0.20;

  final pts = <Offset>[
    for (var i = 0; i < n; i++)
      Offset(
        cx + rx * baseScale * math.cos(i * 2 * math.pi / n),
        cy + ry * baseScale * math.sin(i * 2 * math.pi / n),
      ),
  ];

  Offset midNormal(int seg) {
    final m = (seg + 0.5) * 2 * math.pi / n;
    return Offset(rx * bulge * math.cos(m), ry * bulge * math.sin(m));
  }

  return VPath([
    for (var i = 0; i < n; i++)
      VNode(
        pts[i],
        hIn: pts[i] + midNormal((i - 1 + n) % n),
        hOut: pts[i] + midNormal(i),
      ),
  ], closed: true);
}

/// Shrinking circles from the balloon towards [tailTip].
List<VPath> thoughtTrail(Rect r, Offset tailTip, {int count = 3}) {
  if (count <= 0) return const <VPath>[];
  final minSide = math.min(r.width, r.height);
  final dir = tailTip - r.center;
  final dist = dir.distance;
  final unit = dist > 1e-6 ? dir / dist : const Offset(0, 1);
  // Start just outside the balloon along the direction to tailTip.
  final rx = r.width / 2;
  final ry = r.height / 2;
  final edgeDist = dist > 1e-6
      ? 1.0 / math.sqrt(math.pow(unit.dx / math.max(1e-3, rx), 2) + math.pow(unit.dy / math.max(1e-3, ry), 2))
      : ry;
  final start = r.center + unit * edgeDist;

  final maxRadius = math.max(2.0, minSide * 0.11);
  final minRadius = math.max(1.0, minSide * 0.035);

  return [
    for (var i = 0; i < count; i++)
      () {
        final t = (i + 1) / (count + 0.2);
        final center = Offset.lerp(start, tailTip, t)!;
        final frac = count == 1 ? 0.0 : i / (count - 1);
        final radius = maxRadius + (minRadius - maxRadius) * frac;
        return VPath.ellipse(Rect.fromCircle(center: center, radius: radius));
      }(),
  ];
}
