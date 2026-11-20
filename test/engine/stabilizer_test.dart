import 'dart:math' as math;

import 'package:drawly/engine/brush/stabilizer.dart';
import 'package:flutter_test/flutter_test.dart';

/// A shaky horizontal line: y jitters ±3 px around 50.
List<Offset> _shaky() {
  final r = math.Random(3);
  return [for (var x = 0; x <= 200; x += 2) Offset(x.toDouble(), 50 + (r.nextDouble() * 6 - 3))];
}

double _jitter(List<Offset> pts) {
  var sum = 0.0;
  for (var i = 1; i < pts.length - 1; i++) {
    sum += (pts[i].dy - (pts[i - 1].dy + pts[i + 1].dy) / 2).abs();
  }
  return sum / math.max(1, pts.length - 2);
}

List<Offset> _run(Stabilizer s, List<Offset> input) => [for (final p in input) ...s.add(p), ...s.finish()];

void main() {
  test('per-brush mode and strength 0 pass points through unchanged', () {
    final input = _shaky();
    expect(_run(Stabilizer(mode: StabilizerMode.brush), input), input);
    expect(_run(Stabilizer(mode: StabilizerMode.smooth, strength: 0), input), input);
  });

  test('smooth and average reduce tremor; stronger smooths more', () {
    final input = _shaky();
    final raw = _jitter(input);
    final soft = _jitter(_run(Stabilizer(mode: StabilizerMode.smooth, strength: 0.3), input));
    final hard = _jitter(_run(Stabilizer(mode: StabilizerMode.smooth, strength: 0.9), input));
    final avg = _jitter(_run(Stabilizer(mode: StabilizerMode.average, strength: 0.7), input));
    expect(soft, lessThan(raw));
    expect(hard, lessThan(soft));
    expect(avg, lessThan(raw * 0.5));
  });

  test('rope: nothing is drawn inside the radius; the pen trails at exactly the radius', () {
    final s = Stabilizer(mode: StabilizerMode.rope, strength: 1, ropeRadius: 20);
    expect(s.add(Offset.zero), [Offset.zero]);
    expect(s.add(const Offset(10, 0)), isEmpty);
    expect(s.add(const Offset(19, 0)), isEmpty);
    final out = s.add(const Offset(50, 0));
    expect(out.single.dx, closeTo(30, 1e-9));
    expect((s.raw! - s.pen!).distance, closeTo(20, 1e-9));
  });

  test('finish catches up to the pointer in small steps, or not at all when disabled', () {
    final s = Stabilizer(mode: StabilizerMode.rope, strength: 1, ropeRadius: 20);
    s.add(Offset.zero);
    s.add(const Offset(50, 0));
    final tail = s.finish(step: 2);
    expect(tail.last, const Offset(50, 0));
    expect(tail.length, 10);
    final off = Stabilizer(mode: StabilizerMode.rope, strength: 1, ropeRadius: 20, catchUp: false);
    off.add(Offset.zero);
    off.add(const Offset(50, 0));
    expect(off.finish(), isEmpty);
  });

  test('average window grows with strength', () {
    expect(Stabilizer(mode: StabilizerMode.average, strength: 0).windowSize, 1);
    expect(Stabilizer(mode: StabilizerMode.average, strength: 1).windowSize, 25);
  });

  test('levels 0–10 map to strength and back', () {
    expect(stabilizerStrengthOf(0), 0);
    expect(stabilizerStrengthOf(10), 1);
    expect(stabilizerStrengthOf(15), 1);
    expect(stabilizerLevel(0.73), 7);
    for (var l = 0; l <= 10; l++) {
      expect(stabilizerLevel(stabilizerStrengthOf(l)), l);
    }
  });

  test('super stable is the steadiest mode at the same level', () {
    final input = _shaky();
    final smooth = _jitter(_run(Stabilizer(mode: StabilizerMode.smooth, strength: 0.8, ropeRadius: 30), input));
    final average = _jitter(_run(Stabilizer(mode: StabilizerMode.average, strength: 0.8, ropeRadius: 30), input));
    final superStable = _jitter(_run(Stabilizer(mode: StabilizerMode.superStable, strength: 0.8, ropeRadius: 30), input));
    expect(superStable, lessThan(smooth));
    expect(superStable, lessThan(average));
    // and it still ends where the pointer was lifted
    final s = Stabilizer(mode: StabilizerMode.superStable, strength: 1, ropeRadius: 30);
    final out = _run(s, input);
    expect(out.last, input.last);
  });

  test('super stable shows its string: nothing moves inside the radius', () {
    final s = Stabilizer(mode: StabilizerMode.superStable, strength: 1, ropeRadius: 20);
    s.add(Offset.zero);
    expect(s.add(const Offset(10, 0)), isEmpty);
    expect(s.ropeLength, closeTo(16, 1e-9));
    expect(s.add(const Offset(60, 0)), hasLength(1));
    expect((s.raw! - s.ropeAnchor!).distance, closeTo(16, 1e-9));
    expect(StabilizerMode.superStable.usesRope, isTrue);
    expect(StabilizerMode.dynamic.usesRope, isFalse);
  });

  test('dynamic: fast moves follow closely, slow moves are smoothed', () {
    double lag(double step) {
      final s = Stabilizer(mode: StabilizerMode.dynamic, strength: 1);
      var x = 0.0;
      s.add(Offset.zero);
      for (var i = 0; i < 10; i++) {
        x += step;
        s.add(Offset(x, 0));
      }
      return x - s.pen!.dx;
    }

    final slowRatio = lag(1) / (10 * 1);
    final fastRatio = lag(40) / (10 * 40);
    expect(slowRatio, greaterThan(0.5), reason: 'slow strokes lag a lot (smoothed)');
    expect(fastRatio, lessThan(0.05), reason: 'fast strokes follow the pointer');
  });

  test('slow: the line moves at a limited speed and keeps going while the pointer rests', () {
    var t = 0.0;
    Stabilizer make(double strength) => Stabilizer(mode: StabilizerMode.slow, strength: strength, clock: () => t);
    final heavy = make(1.0), light = make(0.2);
    for (final s in [heavy, light]) {
      t = 0;
      s.add(Offset.zero);
      t = 16;
      s.add(const Offset(400, 0));
    }
    // after one frame the heavy line is far behind the light one, within its speed limit
    expect(heavy.pen!.dx, lessThanOrEqualTo(heavy.maxSpeed * 0.016 + 1e-6));
    expect(heavy.pen!.dx, lessThan(light.pen!.dx));
    // the pointer rests: pumping keeps advancing until it reaches it
    var last = heavy.pen!.dx;
    for (var i = 0; i < 400 && heavy.lagging; i++) {
      t += 16;
      final pts = heavy.pump();
      expect(pts, isNotEmpty);
      expect(pts.last.dx, greaterThan(last));
      last = pts.last.dx;
    }
    expect(heavy.lagging, isFalse);
    expect(heavy.pen!.dx, closeTo(400, 1));
    expect(heavy.pump(), isEmpty);
  });

  test('slow is off at level 0 and smooths tremor', () {
    final input = _shaky();
    var t = 0.0;
    final off = Stabilizer(mode: StabilizerMode.slow, strength: 0, clock: () => t);
    expect([for (final p in input) ...off.add(p)], input);
    final s = Stabilizer(mode: StabilizerMode.slow, strength: 0.5, clock: () => t, catchUp: false);
    final out = <Offset>[];
    for (final p in input) {
      t += 8;
      out.addAll(s.add(p));
    }
    expect(_jitter(out), lessThan(_jitter(input)));
  });
}
