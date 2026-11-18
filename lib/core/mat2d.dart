import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

/// Immutable 2D affine transform.
///
///     | a c tx |
///     | b d ty |
///     | 0 0 1  |
class Mat2D {
  const Mat2D(this.a, this.b, this.c, this.d, this.tx, this.ty);

  final double a, b, c, d, tx, ty;

  static const Mat2D identity = Mat2D(1, 0, 0, 1, 0, 0);

  factory Mat2D.translation(double x, double y) => Mat2D(1, 0, 0, 1, x, y);

  factory Mat2D.scale(double sx, [double? sy]) => Mat2D(sx, 0, 0, sy ?? sx, 0, 0);

  factory Mat2D.rotation(double radians) {
    final cs = math.cos(radians), sn = math.sin(radians);
    return Mat2D(cs, sn, -sn, cs, 0, 0);
  }

  factory Mat2D.skew(double kx, double ky) => Mat2D(1, math.tan(ky), math.tan(kx), 1, 0, 0);

  /// Translate * pivot * rotate * scale * -pivot.
  factory Mat2D.trs({
    double x = 0,
    double y = 0,
    double rotation = 0,
    double sx = 1,
    double sy = 1,
    double ax = 0,
    double ay = 0,
  }) {
    final cs = math.cos(rotation), sn = math.sin(rotation);
    final a = cs * sx, b = sn * sx, c = -sn * sy, d = cs * sy;
    return Mat2D(a, b, c, d, x + ax - (a * ax + c * ay), y + ay - (b * ax + d * ay));
  }

  /// Maps the unit square corners (0,0),(1,0),(0,1) to p0,p1,p2.
  factory Mat2D.fromTriangle(Offset p0, Offset p1, Offset p2) =>
      Mat2D(p1.dx - p0.dx, p1.dy - p0.dy, p2.dx - p0.dx, p2.dy - p0.dy, p0.dx, p0.dy);

  /// `this * o`: applies [o] first, then this.
  Mat2D operator *(Mat2D o) => Mat2D(
        a * o.a + c * o.b,
        b * o.a + d * o.b,
        a * o.c + c * o.d,
        b * o.c + d * o.d,
        a * o.tx + c * o.ty + tx,
        b * o.tx + d * o.ty + ty,
      );

  Offset apply(Offset p) => Offset(a * p.dx + c * p.dy + tx, b * p.dx + d * p.dy + ty);

  Offset applyVector(Offset v) => Offset(a * v.dx + c * v.dy, b * v.dx + d * v.dy);

  double get determinant => a * d - b * c;

  bool get isIdentity => a == 1 && b == 0 && c == 0 && d == 1 && tx == 0 && ty == 0;

  bool get isTranslation => a == 1 && b == 0 && c == 0 && d == 1;

  /// Uniform-ish scale factor (geometric mean of both axes).
  double get scaleFactor => math.sqrt(determinant.abs());

  double get rotationAngle => math.atan2(b, a);

  Mat2D get inverse {
    final det = determinant;
    if (det.abs() < 1e-12) return identity;
    final ia = d / det, ib = -b / det, ic = -c / det, id = a / det;
    return Mat2D(ia, ib, ic, id, -(ia * tx + ic * ty), -(ib * tx + id * ty));
  }

  Mat2D translated(double x, double y) => Mat2D.translation(x, y) * this;

  /// Column-major 4x4 storage for [Canvas.transform].
  Float64List get storage => Float64List(16)
    ..[0] = a
    ..[1] = b
    ..[4] = c
    ..[5] = d
    ..[10] = 1
    ..[12] = tx
    ..[13] = ty
    ..[15] = 1;

  static Mat2D fromStorage(Float64List m) => Mat2D(m[0], m[1], m[4], m[5], m[12], m[13]);

  Rect mapRect(Rect r) {
    final p0 = apply(r.topLeft), p1 = apply(r.topRight), p2 = apply(r.bottomLeft), p3 = apply(r.bottomRight);
    final l = math.min(math.min(p0.dx, p1.dx), math.min(p2.dx, p3.dx));
    final t = math.min(math.min(p0.dy, p1.dy), math.min(p2.dy, p3.dy));
    final rr = math.max(math.max(p0.dx, p1.dx), math.max(p2.dx, p3.dx));
    final bb = math.max(math.max(p0.dy, p1.dy), math.max(p2.dy, p3.dy));
    return Rect.fromLTRB(l, t, rr, bb);
  }

  static Mat2D lerp(Mat2D m, Mat2D n, double t) => Mat2D(
        m.a + (n.a - m.a) * t,
        m.b + (n.b - m.b) * t,
        m.c + (n.c - m.c) * t,
        m.d + (n.d - m.d) * t,
        m.tx + (n.tx - m.tx) * t,
        m.ty + (n.ty - m.ty) * t,
      );

  List<double> toJson() => [a, b, c, d, tx, ty];

  static Mat2D fromJson(dynamic j) {
    final l = (j as List).map((e) => (e as num).toDouble()).toList();
    return Mat2D(l[0], l[1], l[2], l[3], l[4], l[5]);
  }

  @override
  bool operator ==(Object other) =>
      other is Mat2D && a == other.a && b == other.b && c == other.c && d == other.d && tx == other.tx && ty == other.ty;

  @override
  int get hashCode => Object.hash(a, b, c, d, tx, ty);

  @override
  String toString() => 'Mat2D($a, $b, $c, $d, $tx, $ty)';
}

/// 3x3 projective transform used by the distort / perspective tools.
class Homography {
  const Homography(this.m);

  /// Row-major 3x3.
  final List<double> m;

  /// Maps the rectangle [src] onto the quad q0..q3 (TL, TR, BR, BL).
  factory Homography.rectToQuad(Rect src, Offset q0, Offset q1, Offset q2, Offset q3) {
    // unit square -> quad (Heckbert)
    final dx1 = q1.dx - q2.dx, dx2 = q3.dx - q2.dx, dx3 = q0.dx - q1.dx + q2.dx - q3.dx;
    final dy1 = q1.dy - q2.dy, dy2 = q3.dy - q2.dy, dy3 = q0.dy - q1.dy + q2.dy - q3.dy;
    double a, b, c, d, e, f, g, h;
    if (dx3.abs() < 1e-9 && dy3.abs() < 1e-9) {
      a = q1.dx - q0.dx;
      b = q2.dx - q1.dx;
      c = q0.dx;
      d = q1.dy - q0.dy;
      e = q2.dy - q1.dy;
      f = q0.dy;
      g = 0;
      h = 0;
    } else {
      final det = dx1 * dy2 - dx2 * dy1;
      final safe = det.abs() < 1e-12 ? 1e-12 : det;
      g = (dx3 * dy2 - dx2 * dy3) / safe;
      h = (dx1 * dy3 - dx3 * dy1) / safe;
      a = q1.dx - q0.dx + g * q1.dx;
      b = q3.dx - q0.dx + h * q3.dx;
      c = q0.dx;
      d = q1.dy - q0.dy + g * q1.dy;
      e = q3.dy - q0.dy + h * q3.dy;
      f = q0.dy;
    }
    // pre-multiply by rect -> unit square
    final sx = 1 / src.width, sy = 1 / src.height;
    final ox = -src.left * sx, oy = -src.top * sy;
    return Homography([
      a * sx, b * sy, a * ox + b * oy + c,
      d * sx, e * sy, d * ox + e * oy + f,
      g * sx, h * sy, g * ox + h * oy + 1,
    ]);
  }

  Offset apply(Offset p) {
    final w = m[6] * p.dx + m[7] * p.dy + m[8];
    final sw = w.abs() < 1e-12 ? 1e-12 : w;
    return Offset((m[0] * p.dx + m[1] * p.dy + m[2]) / sw, (m[3] * p.dx + m[4] * p.dy + m[5]) / sw);
  }

  /// Column-major 4x4 for [Canvas.transform].
  Float64List get storage => Float64List(16)
    ..[0] = m[0]
    ..[1] = m[3]
    ..[3] = m[6]
    ..[4] = m[1]
    ..[5] = m[4]
    ..[7] = m[7]
    ..[10] = 1
    ..[12] = m[2]
    ..[13] = m[5]
    ..[15] = m[8];
}

extension RectX on Rect {
  /// Smallest integer rect containing this one.
  Rect get roundedOut => Rect.fromLTRB(left.floorToDouble(), top.floorToDouble(), right.ceilToDouble(), bottom.ceilToDouble());

  Rect unionNullable(Rect? o) => o == null ? this : expandToInclude(o);
}

Rect? unionRects(Rect? a, Rect? b) => a == null ? b : (b == null ? a : a.expandToInclude(b));

double lerpD(double a, double b, double t) => a + (b - a) * t;

double clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);

double degToRad(double d) => d * math.pi / 180.0;

double radToDeg(double r) => r * 180.0 / math.pi;
