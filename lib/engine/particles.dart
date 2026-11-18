import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../core/color_utils.dart';
import '../model/specs.dart';
import 'brush/tips.dart';

class Particle {
  Particle(this.x, this.y, this.vx, this.vy, this.size, this.alpha, this.angle, this.color);
  final double x, y, vx, vy, size, alpha, angle;
  final Color color;
}

/// Tiny deterministic generator (no shared state, identical on every run).
class _Rand {
  _Rand(int seed) : _s = (seed & 0x7FFFFFFF) | 1;
  int _s;
  double next() {
    // xorshift31
    _s ^= (_s << 13) & 0x7FFFFFFF;
    _s ^= _s >> 17;
    _s ^= (_s << 5) & 0x7FFFFFFF;
    return (_s & 0xFFFFFF) / 0x1000000;
  }
}

/// Evaluates the particle system at [frame]. Stateless: every particle is a
/// pure function of (seed, birth frame, index), so scrubbing and exporting
/// never need to step the simulation.
List<Particle> simulateParticles(ParticleSpec s, double frame) {
  final out = <Particle>[];
  if (s.rate <= 0 || s.life <= 0) return out;
  final maxLife = s.life;
  final first = (frame - maxLife).floor();
  final last = frame.floor();
  final needsStepping = s.drag > 0 || s.floorY != null;
  for (var e = first; e <= last; e++) {
    final count = ((e + 1) * s.rate).floor() - (e * s.rate).floor();
    final age = frame - e;
    if (age < 0) continue;
    for (var i = 0; i < count; i++) {
      final r = _Rand(s.seed * 7919 + e * 104729 + i * 1299709);
      // burn a few values to decorrelate neighbouring seeds
      r.next();
      r.next();
      final life = maxLife * (1 - s.lifeVar * r.next());
      if (age > life) continue;
      final t = age / life;
      final px = s.emitter.left + s.emitter.width * r.next();
      final py = s.emitter.top + s.emitter.height * r.next();
      final speed = s.speed * (1 - s.speedVar * r.next());
      final ang = (s.angle + (r.next() - 0.5) * 2 * s.spread) * math.pi / 180;
      var vx = math.cos(ang) * speed, vy = math.sin(ang) * speed;
      var x = px, y = py;
      if (needsStepping) {
        final steps = age.floor();
        for (var k = 0; k < steps; k++) {
          vx += s.gravityX;
          vy += s.gravityY;
          if (s.drag > 0) {
            vx *= 1 - s.drag;
            vy *= 1 - s.drag;
          }
          x += vx;
          y += vy;
          final floor = s.floorY;
          if (floor != null && y > floor) {
            y = floor - (y - floor) * s.bounce;
            vy = -vy * s.bounce;
            vx *= 0.75;
          }
        }
        final frac = age - steps;
        x += vx * frac;
        y += vy * frac;
      } else {
        x += vx * age + 0.5 * s.gravityX * age * age;
        y += vy * age + 0.5 * s.gravityY * age * age;
        vx += s.gravityX * age;
        vy += s.gravityY * age;
      }
      final phase = r.next() * math.pi * 2;
      if (s.turbulence > 0) {
        x += math.sin(age * 0.11 + phase) * s.turbulence * 9 * math.min(1.0, age / 12);
        y += math.cos(age * 0.07 + phase * 1.7) * s.turbulence * 3 * math.min(1.0, age / 12);
      }
      final size = s.size * (1 - s.sizeVar * r.next()) * (1 + (s.sizeEnd - 1) * t);
      final fadeIn = (t / 0.08).clamp(0.0, 1.0);
      final alpha = ((s.alphaStart + (s.alphaEnd - s.alphaStart) * t) * fadeIn).clamp(0.0, 1.0);
      final rc = r.next();
      Color color;
      if (s.colorVar > 0) {
        final base = lerpColor(s.colorStart, s.colorEnd, rc);
        final hsv = Hsv.fromColor(base);
        color = hsv.copyWith(h: (hsv.h + (r.next() - 0.5) * 360 * s.colorVar) % 360).toColor();
      } else {
        color = lerpColor(s.colorStart, s.colorEnd, t);
      }
      final spin = phase + s.spin * age * (rc > 0.5 ? 1 : -1);
      if (size <= 0 || alpha <= 0) continue;
      out.add(Particle(x, y, vx, vy, size, alpha, spin, color));
    }
  }
  return out;
}

void paintParticles(Canvas canvas, ParticleSpec s, double frame) {
  final ps = simulateParticles(s, frame);
  if (ps.isEmpty) return;
  final blend = s.additive ? BlendMode.plus : BlendMode.srcOver;
  if (s.shape == ParticleShape.streak) {
    final p = Paint()
      ..strokeCap = StrokeCap.round
      ..blendMode = blend
      ..isAntiAlias = true;
    for (final q in ps) {
      p.color = q.color.withValues(alpha: q.color.a * q.alpha);
      p.strokeWidth = math.max(0.5, q.size);
      canvas.drawLine(Offset(q.x, q.y), Offset(q.x - q.vx * 1.6, q.y - q.vy * 1.6), p);
    }
    return;
  }
  final tips = BrushTips.instance;
  if (!tips.isLoaded) {
    final p = Paint()..blendMode = blend;
    for (final q in ps) {
      p.color = q.color.withValues(alpha: q.color.a * q.alpha);
      canvas.drawCircle(Offset(q.x, q.y), q.size / 2, p);
    }
    return;
  }
  final tip = switch (s.shape) {
    ParticleShape.soft => tips.tip('round', 0),
    ParticleShape.square => tips.tip('square', 1),
    ParticleShape.star || ParticleShape.flake => tips.tip('star', 1),
    _ => tips.tip('round', 1),
  };
  final n = ps.length;
  final rst = Float32List(n * 4), rects = Float32List(n * 4);
  final colors = Int32List(n);
  final rotates = s.shape == ParticleShape.square || s.shape == ParticleShape.star || s.shape == ParticleShape.flake;
  for (var i = 0; i < n; i++) {
    final q = ps[i];
    final lvl = BrushTip.levelFor(q.size);
    final ls = BrushTip.sizes[lvl].toDouble(), lx = BrushTip.offsets[lvl].toDouble();
    final scale = q.size / ls;
    final a = rotates ? q.angle : 0.0;
    final scos = math.cos(a) * scale, ssin = math.sin(a) * scale;
    rst[i * 4] = scos;
    rst[i * 4 + 1] = ssin;
    rst[i * 4 + 2] = q.x - scos * ls / 2 + ssin * ls / 2;
    rst[i * 4 + 3] = q.y - ssin * ls / 2 - scos * ls / 2;
    rects[i * 4] = lx;
    rects[i * 4 + 1] = 0;
    rects[i * 4 + 2] = lx + ls;
    rects[i * 4 + 3] = ls;
    final c = q.color;
    colors[i] = ((c.a * q.alpha * 255).round() << 24) | (c.r8 << 16) | (c.g8 << 8) | c.b8;
  }
  canvas.drawRawAtlas(
    tip.atlas,
    rst,
    rects,
    colors,
    BlendMode.modulate,
    null,
    Paint()
      ..filterQuality = FilterQuality.low
      ..blendMode = blend,
  );
}
