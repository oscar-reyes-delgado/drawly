import 'dart:math' as math;
import 'dart:ui';

import 'package:drawly/core/mat2d.dart';
import 'package:flutter_test/flutter_test.dart';

void expectOffset(Offset actual, Offset expected, [double eps = 1e-9]) {
  expect(actual.dx, closeTo(expected.dx, eps), reason: 'dx of $actual vs $expected');
  expect(actual.dy, closeTo(expected.dy, eps), reason: 'dy of $actual vs $expected');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Mat2D', () {
    final a = Mat2D.trs(x: 3, y: -2, rotation: 0.4, sx: 1.5, sy: 0.75, ax: 4, ay: 1);
    final b = Mat2D.trs(x: -7, y: 11, rotation: -1.2, sx: 0.5, sy: 2, ax: -3, ay: 6);
    const points = [Offset.zero, Offset(1, 0), Offset(0, 1), Offset(12.5, -3.25), Offset(-100, 42)];

    test('(A * B).apply(p) == A.apply(B.apply(p))', () {
      final ab = a * b;
      for (final p in points) {
        expectOffset(ab.apply(p), a.apply(b.apply(p)));
      }
    });

    test('m * m.inverse is the identity', () {
      final m = Mat2D.trs(x: 25, y: -13, rotation: 2.1, sx: 3, sy: 0.4, ax: 7, ay: -5);
      for (final r in [m * m.inverse, m.inverse * m]) {
        expect(r.a, closeTo(1, 1e-9));
        expect(r.b, closeTo(0, 1e-9));
        expect(r.c, closeTo(0, 1e-9));
        expect(r.d, closeTo(1, 1e-9));
        expect(r.tx, closeTo(0, 1e-9));
        expect(r.ty, closeTo(0, 1e-9));
      }
    });

    test('trs keeps the anchor and then translates it', () {
      final m = Mat2D.trs(x: 5, y: 7, rotation: 1, sx: 2, sy: 3, ax: 10, ay: 20);
      expectOffset(m.apply(const Offset(10, 20)), const Offset(15, 27));
    });

    test('mapRect of a 90° rotation swaps width and height', () {
      final r = Mat2D.rotation(math.pi / 2).mapRect(const Rect.fromLTWH(0, 0, 100, 40));
      expect(r.width, closeTo(40, 1e-9));
      expect(r.height, closeTo(100, 1e-9));
    });

    test('toJson / fromJson round trip', () {
      final m = Mat2D.trs(x: 1.25, y: -9.5, rotation: 0.33, sx: 1.1, sy: 0.9, ax: 2, ay: 3);
      final back = Mat2D.fromJson(m.toJson());
      expect(back, m);
      expect(back.hashCode, m.hashCode);
    });
  });

  group('Homography', () {
    test('rectToQuad maps the rect corners onto a non-parallelogram quad', () {
      const src = Rect.fromLTWH(10, 20, 200, 100);
      const q0 = Offset(0, 0), q1 = Offset(300, 30), q2 = Offset(250, 260), q3 = Offset(-20, 200);
      final h = Homography.rectToQuad(src, q0, q1, q2, q3);
      expectOffset(h.apply(src.topLeft), q0, 1e-6);
      expectOffset(h.apply(src.topRight), q1, 1e-6);
      expectOffset(h.apply(src.bottomRight), q2, 1e-6);
      expectOffset(h.apply(src.bottomLeft), q3, 1e-6);
    });

    test('rectToQuad also works for a parallelogram (affine case)', () {
      const src = Rect.fromLTWH(0, 0, 50, 80);
      const q0 = Offset(10, 10), q1 = Offset(110, 30), q2 = Offset(130, 130), q3 = Offset(30, 110);
      final h = Homography.rectToQuad(src, q0, q1, q2, q3);
      expectOffset(h.apply(src.topLeft), q0, 1e-6);
      expectOffset(h.apply(src.topRight), q1, 1e-6);
      expectOffset(h.apply(src.bottomRight), q2, 1e-6);
      expectOffset(h.apply(src.bottomLeft), q3, 1e-6);
    });
  });

  group('RectX', () {
    test('roundedOut grows to the enclosing integer rect', () {
      expect(const Rect.fromLTRB(1.2, -3.7, 5.5, 8.0).roundedOut, const Rect.fromLTRB(1, -4, 6, 8));
      expect(const Rect.fromLTRB(0, 0, 10, 10).roundedOut, const Rect.fromLTRB(0, 0, 10, 10));
    });
  });
}
