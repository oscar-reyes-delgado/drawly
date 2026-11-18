import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../model/anim.dart';
import '../model/specs.dart';

/// Lays out and paints [TextSpec]s: plain blocks, outlined text, text on a
/// path and per letter / word / line animation.
class TextRender {
  static TextStyle _style(TextSpec t, {Paint? foreground, Color? color}) => TextStyle(
        fontFamily: t.font.isEmpty ? null : t.font,
        fontSize: t.size,
        color: foreground == null ? (color ?? t.color) : null,
        foreground: foreground,
        fontWeight: t.bold ? FontWeight.w700 : FontWeight.w400,
        fontStyle: t.italic ? FontStyle.italic : FontStyle.normal,
        letterSpacing: t.letterSpacing,
        height: t.lineHeight,
        decoration: t.underline ? TextDecoration.underline : TextDecoration.none,
        decorationColor: color ?? t.color,
      );

  static TextAlign _align(TextSpec t) => switch (t.align) {
        1 => TextAlign.center,
        2 => TextAlign.right,
        _ => TextAlign.left,
      };

  static TextPainter _painter(String text, TextSpec t, {Paint? foreground, Color? color, bool wrap = true}) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: _style(t, foreground: foreground, color: color)),
      textAlign: _align(t),
      textDirection: TextDirection.ltr,
    );
    tp.layout(maxWidth: wrap && t.boxWidth > 0 ? t.boxWidth : double.infinity);
    return tp;
  }

  static Paint _strokePaint(TextSpec t, double alpha) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = t.strokeWidth
    ..strokeJoin = StrokeJoin.round
    ..color = t.strokeColor.withValues(alpha: t.strokeColor.a * alpha);

  /// Bounding box in layer space.
  static Rect bounds(TextSpec t) {
    if (t.path != null) {
      final b = t.path!.toPath().getBounds();
      return b.inflate(t.size * 1.5);
    }
    final tp = _painter(t.text.isEmpty ? ' ' : t.text, t);
    final w = t.boxWidth > 0 ? t.boxWidth : tp.width;
    final r = Rect.fromLTWH(t.pos.dx, t.pos.dy, w, tp.height).inflate(t.strokeWidth + 2);
    tp.dispose();
    return r.inflate(t.anim == TextAnimKind.none ? 0 : t.animAmount * 3);
  }

  static void paint(Canvas canvas, TextSpec t, double frame) {
    if (t.text.isEmpty) return;
    if (t.path != null) {
      _paintOnPath(canvas, t, frame);
      return;
    }
    if (t.anim == TextAnimKind.none) {
      if (t.strokeWidth > 0) {
        final sp = _painter(t.text, t, foreground: _strokePaint(t, 1));
        sp.paint(canvas, t.pos);
        sp.dispose();
      }
      final tp = _painter(t.text, t);
      tp.paint(canvas, t.pos);
      tp.dispose();
      return;
    }
    _paintAnimated(canvas, t, frame);
  }

  /// Character ranges of the animation units.
  static List<(int, int)> _units(TextSpec t, TextPainter full) {
    final s = t.text;
    final out = <(int, int)>[];
    switch (t.animUnit) {
      case TextUnit.letter:
        for (var i = 0; i < s.length; i++) {
          if (s[i] == '\n') continue;
          out.add((i, i + 1));
        }
      case TextUnit.word:
        final re = RegExp(r'\S+');
        for (final m in re.allMatches(s)) {
          out.add((m.start, m.end));
        }
      case TextUnit.line:
        var start = 0;
        for (final line in full.computeLineMetrics()) {
          final pos = full.getPositionForOffset(Offset(full.width + 1, line.baseline - 1));
          final end = math.max(start, math.min(s.length, pos.offset));
          if (end > start) out.add((start, end));
          start = end;
        }
        if (start < s.length) out.add((start, s.length));
    }
    return out;
  }

  static void _paintAnimated(Canvas canvas, TextSpec t, double frame) {
    final full = _painter(t.text, t);
    final units = _units(t, full);
    for (var k = 0; k < units.length; k++) {
      final (a, b) = units[k];
      final boxes = full.getBoxesForSelection(TextSelection(baseOffset: a, extentOffset: b));
      if (boxes.isEmpty) continue;
      var box = boxes.first.toRect();
      for (final bx in boxes.skip(1)) {
        box = box.expandToInclude(bx.toRect());
      }
      final local = frame - t.animStart - k * t.animStagger;
      final p = t.animDuration <= 0 ? (local >= 0 ? 1.0 : 0.0) : (local / t.animDuration).clamp(0.0, 1.0);
      var alpha = 1.0, dx = 0.0, dy = 0.0, scale = 1.0;
      switch (t.anim) {
        case TextAnimKind.none:
          break;
        case TextAnimKind.typewriter:
          alpha = local >= 0 ? 1 : 0;
        case TextAnimKind.fadeIn:
          alpha = p;
        case TextAnimKind.wave:
          dy = math.sin(frame * 0.35 - k * 0.7) * t.animAmount;
        case TextAnimKind.bounce:
          alpha = local >= 0 ? 1 : 0;
          dy = -(1 - const Ease(EaseType.bounce).transform(p)) * t.animAmount * 3;
        case TextAnimKind.scaleIn:
          alpha = local >= 0 ? 1 : 0;
          scale = const Ease(EaseType.backOut).transform(p);
        case TextAnimKind.slideUp:
          alpha = p;
          dy = (1 - const Ease(EaseType.cubicOut).transform(p)) * t.animAmount * 2;
        case TextAnimKind.shake:
          final ph = frame.floor() * 12.9898 + k * 78.233;
          dx = (math.sin(ph) * 43758.5453 % 1 - 0.5) * t.animAmount * 0.6;
          dy = (math.sin(ph * 1.7) * 43758.5453 % 1 - 0.5) * t.animAmount * 0.6;
      }
      if (alpha <= 0 || scale <= 0) continue;
      final text = t.text.substring(a, b);
      final origin = t.pos + box.topLeft + Offset(dx, dy);
      canvas.save();
      if (scale != 1) {
        final c = origin + Offset(box.width / 2, box.height / 2);
        canvas.translate(c.dx, c.dy);
        canvas.scale(scale);
        canvas.translate(-c.dx, -c.dy);
      }
      if (t.strokeWidth > 0) {
        final sp = _painter(text, t, foreground: _strokePaint(t, alpha), wrap: false);
        sp.paint(canvas, origin);
        sp.dispose();
      }
      final tp = _painter(text, t, color: t.color.withValues(alpha: t.color.a * alpha), wrap: false);
      tp.paint(canvas, origin);
      tp.dispose();
      canvas.restore();
    }
    full.dispose();
  }

  static void _paintOnPath(Canvas canvas, TextSpec t, double frame) {
    final metrics = t.path!.toPath().computeMetrics().toList();
    if (metrics.isEmpty) return;
    final total = metrics.fold<double>(0, (a, m) => a + m.length);
    ui.Tangent? at(double d) {
      var dist = d;
      for (final m in metrics) {
        if (dist <= m.length) return m.getTangentForOffset(dist);
        dist -= m.length;
      }
      return null;
    }

    final line = t.text.replaceAll('\n', ' ');
    final full = _painter(line, t, wrap: false);
    var start = t.pathOffset;
    if (t.align == 1) start += (total - full.width) / 2;
    if (t.align == 2) start += total - full.width;
    for (var i = 0; i < line.length; i++) {
      final boxes = full.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1));
      if (boxes.isEmpty) continue;
      final box = boxes.first.toRect();
      final tan = at(start + box.left + box.width / 2);
      if (tan == null) continue;
      var alpha = 1.0;
      if (t.anim == TextAnimKind.typewriter || t.anim == TextAnimKind.fadeIn) {
        final local = frame - t.animStart - i * t.animStagger;
        alpha = t.anim == TextAnimKind.typewriter ? (local >= 0 ? 1 : 0) : (local / math.max(1, t.animDuration)).clamp(0.0, 1.0);
      }
      if (alpha <= 0) continue;
      canvas.save();
      canvas.translate(tan.position.dx, tan.position.dy);
      canvas.rotate(-tan.angle);
      final ch = line[i];
      final origin = Offset(-box.width / 2, -box.height);
      if (t.strokeWidth > 0) {
        final sp = _painter(ch, t, foreground: _strokePaint(t, alpha), wrap: false);
        sp.paint(canvas, origin);
        sp.dispose();
      }
      final tp = _painter(ch, t, color: t.color.withValues(alpha: t.color.a * alpha), wrap: false);
      tp.paint(canvas, origin);
      tp.dispose();
      canvas.restore();
    }
    full.dispose();
  }
}
