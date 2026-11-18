import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui';
import '../core/mat2d.dart';
import 'tiles.dart';

/// Mutable displacement grid in document coordinates.
class WarpGrid {
  WarpGrid(this.bounds, this.cols, this.rows, [Float32List? dx, Float32List? dy])
      : dx = dx ?? Float32List((cols + 1) * (rows + 1)), dy = dy ?? Float32List((cols + 1) * (rows + 1)) {
    if (cols < 1 || rows < 1 || bounds.isEmpty || this.dx.length != (cols + 1) * (rows + 1) || this.dy.length != this.dx.length) throw ArgumentError('Invalid warp grid');
  }
  factory WarpGrid.forSize(Rect bounds, {double cell = 16}) {
    if (cell <= 0 || !cell.isFinite) throw ArgumentError.value(cell, 'cell');
    return WarpGrid(bounds, math.max(1, (bounds.width / cell).ceil()), math.max(1, (bounds.height / cell).ceil()));
  }
  final Rect bounds;
  final int cols, rows;
  final Float32List dx, dy;
  bool get isIdentity => dx.every((v) => v.abs() < 1e-4) && dy.every((v) => v.abs() < 1e-4);
  Offset rest(int c, int r) => bounds.topLeft + Offset(c * bounds.width / cols, r * bounds.height / rows);
  Offset at(int c, int r) { final i = r * (cols + 1) + c; return rest(c, r) + Offset(dx[i], dy[i]); }
  Offset displacementAt(Offset docPoint) {
    final x = ((docPoint.dx - bounds.left) / bounds.width * cols).clamp(0.0, cols.toDouble());
    final y = ((docPoint.dy - bounds.top) / bounds.height * rows).clamp(0.0, rows.toDouble());
    final c = math.min(cols - 1, x.floor()), r = math.min(rows - 1, y.floor()), fx = x - c, fy = y - r;
    Offset d(int c, int r) { final i = r * (cols + 1) + c; return Offset(dx[i], dy[i]); }
    return d(c, r) * ((1 - fx) * (1 - fy)) + d(c + 1, r) * (fx * (1 - fy)) + d(c, r + 1) * ((1 - fx) * fy) + d(c + 1, r + 1) * (fx * fy);
  }
  WarpGrid copy() => WarpGrid(bounds, cols, rows, Float32List.fromList(dx), Float32List.fromList(dy));
  void reset() { dx.fillRange(0, dx.length, 0); dy.fillRange(0, dy.length, 0); }
  Rect _brush(Offset center, double radius, double strength, Offset Function(Offset p, Offset rest, double weight) move) {
    if (radius <= 0 || strength == 0) return Rect.zero;
    Rect? changed;
    for (var r = 0; r <= rows; r++) {
      for (var c = 0; c <= cols; c++) {
        final p = at(c, r), base = rest(c, r), distance = (p - center).distance;
        if (distance >= radius) continue;
        final falloff = 1 - distance * distance / (radius * radius), q = move(p, base, strength * falloff * falloff);
        if (q == p) continue;
        final i = r * (cols + 1) + c;
        dx[i] = q.dx - base.dx; dy[i] = q.dy - base.dy;
        final rect = Rect.fromPoints(p, q).expandToInclude(Rect.fromPoints(base, base)).inflate(1e-4);
        changed = changed?.expandToInclude(rect) ?? rect;
      }
    }
    return changed ?? Rect.zero;
  }
  Rect push(Offset center, Offset delta, double radius, double strength) => _brush(center, radius, strength, (p, _, w) => p + delta * w);
  Rect twirl(Offset center, double radians, double radius, double strength) => _brush(center, radius, strength, (p, _, w) => center + Mat2D.rotation(radians * w).applyVector(p - center));
  Rect pinch(Offset center, double radius, double strength) => _brush(center, radius, strength, (p, _, w) => p + (center - p) * (w * 0.5));
  Rect bloat(Offset center, double radius, double strength) => _brush(center, radius, strength, (p, _, w) => p + (p - center) * (w * 0.5));
  Rect restore(Offset center, double radius, double strength) => _brush(center, radius, strength, (p, base, w) => base + (p - base) * (1 - w));
}

/// Paints the image through the grid using image-local texture coordinates.
void paintWarped(Canvas canvas, ui.Image image, WarpGrid grid, {FilterQuality quality = FilterQuality.medium}) {
  final shader = ImageShader(image, TileMode.clamp, TileMode.clamp, Mat2D.identity.storage, filterQuality: quality);
  final paint = Paint()..shader = shader;
  // Batch cells to keep every index within the unsigned 16-bit vertex range.
  for (var first = 0; first < grid.cols * grid.rows; first += 16000) {
    final count = math.min(16000, grid.cols * grid.rows - first), positions = Float32List(count * 8), texture = Float32List(count * 8), indices = Uint16List(count * 6);
    for (var i = 0; i < count; i++) {
      final cell = first + i, c = cell % grid.cols, r = cell ~/ grid.cols;
      for (var k = 0; k < 4; k++) {
        final p = grid.at(c + k % 2, r + k ~/ 2), t = grid.rest(c + k % 2, r + k ~/ 2) - grid.bounds.topLeft;
        positions[i * 8 + k * 2] = p.dx; positions[i * 8 + k * 2 + 1] = p.dy;
        texture[i * 8 + k * 2] = t.dx; texture[i * 8 + k * 2 + 1] = t.dy;
      }
      for (var k = 0; k < 6; k++) { indices[i * 6 + k] = i * 4 + const [0, 1, 2, 1, 3, 2][k]; }
    }
    final vertices = Vertices.raw(VertexMode.triangles, positions, textureCoordinates: texture, indices: indices);
    canvas.drawVertices(vertices, BlendMode.srcOver, paint);
    vertices.dispose();
  }
  shader.dispose();
}

/// Creates a deformed image of the same dimensions as the source.
ui.Image renderWarped(ui.Image image, WarpGrid grid) => renderToImage(image.width, image.height, (c) {
  c.translate(-grid.bounds.left, -grid.bounds.top); paintWarped(c, image, grid);
});

/// Sixteen row-major control points for an identity bicubic patch.
List<Offset> identityPatch(Rect bounds) => [for (var r = 0; r < 4; r++) for (var c = 0; c < 4; c++) bounds.topLeft + Offset(bounds.width * c / 3, bounds.height * r / 3)];

/// Evaluates a bicubic patch into displacement samples.
WarpGrid gridFromPatch(Rect bounds, List<Offset> controlPoints, {int cols = 24, int rows = 24}) {
  if (controlPoints.length != 16) throw ArgumentError('A patch requires sixteen control points');
  final grid = WarpGrid(bounds, cols, rows);
  List<double> basis(double t) => [(1 - t) * (1 - t) * (1 - t), 3 * t * (1 - t) * (1 - t), 3 * t * t * (1 - t), t * t * t];
  for (var r = 0; r <= rows; r++) {
    for (var c = 0; c <= cols; c++) {
      final u = basis(c / cols), v = basis(r / rows);
      var p = Offset.zero;
      for (var y = 0; y < 4; y++) { for (var x = 0; x < 4; x++) { p += controlPoints[y * 4 + x] * (u[x] * v[y]); } }
      final d = p - grid.rest(c, r), i = r * (cols + 1) + c;
      grid.dx[i] = d.dx; grid.dy[i] = d.dy;
    }
  }
  return grid;
}
