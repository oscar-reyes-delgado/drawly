import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui';

import '../model/vector.dart';
import 'curve_fit.dart';
import 'pixel_ops.dart';
import 'tiles.dart';

/// Boundaries of alpha >= [threshold], in pixel-corner coordinates.
List<List<Offset>> traceMask(Uint8List alpha, int width, int height, {int threshold = 128}) {
  if (width < 0 || height < 0 || alpha.length != width * height) throw ArgumentError('Invalid mask dimensions');
  final edges = <int, List<int>>{};
  final stride = width + 1;
  bool inside(int x, int y) => x >= 0 && y >= 0 && x < width && y < height && alpha[y * width + x] >= threshold;
  void edge(int a, int b) => edges.putIfAbsent(a, () => []).add(b);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      if (!inside(x, y)) continue;
      final p = y * stride + x;
      if (!inside(x, y - 1)) edge(p, p + 1);
      if (!inside(x + 1, y)) edge(p + 1, p + stride + 1);
      if (!inside(x, y + 1)) edge(p + stride + 1, p + stride);
      if (!inside(x - 1, y)) edge(p + stride, p);
    }
  }
  Offset point(int p) => Offset((p % stride).toDouble(), (p ~/ stride).toDouble());
  int direction(int a, int b) => b == a + 1 ? 0 : b == a + stride ? 1 : b == a - 1 ? 2 : 3;
  final loops = <List<Offset>>[];
  while (edges.isNotEmpty) {
    final first = edges.keys.first;
    var current = first, incoming = -1;
    final points = <Offset>[];
    do {
      points.add(point(current));
      final choices = edges[current]!;
      var next = choices.first;
      if (incoming >= 0 && choices.length > 1) {
        int rank(int end) => const [1, 0, 3, 2][(direction(current, end) - incoming) % 4];
        for (final candidate in choices) { if (rank(candidate) < rank(next)) next = candidate; }
      }
      choices.remove(next);
      if (choices.isEmpty) edges.remove(current);
      incoming = direction(current, next);
      current = next;
    } while (current != first);
    loops.add([for (var i = 0; i < points.length; i++)
      if (_cross(points[i] - points[(i + points.length - 1) % points.length], points[(i + 1) % points.length] - points[i]) != 0) points[i]]);
  }
  return loops;
}

double _cross(Offset a, Offset b) => a.dx * b.dy - a.dy * b.dx;
double _area(List<Offset> p) {
  var sum = 0.0;
  for (var i = 0; i < p.length; i++) { sum += _cross(p[i], p[(i + 1) % p.length]); }
  return sum / 2;
}

/// Palette, contour filtering and curve fitting options.
class VectorizeOptions {
  const VectorizeOptions({this.colors = 8, this.tolerance = 1.5, this.minArea = 16, this.smooth = true, this.lineArt = false});
  final int colors;
  final double tolerance;
  final int minArea;
  final bool smooth, lineArt;
}

/// Converts straight RGBA into one compound shape per color, largest first.
VectorArt vectorizeRgba(Uint8List rgba, int width, int height, {VectorizeOptions options = const VectorizeOptions(), Offset origin = Offset.zero}) {
  if (width < 0 || height < 0 || rgba.length != width * height * 4) throw ArgumentError('Invalid RGBA dimensions');
  if (options.colors < 1 || options.tolerance < 0 || options.minArea < 0) throw ArgumentError('Invalid vectorization options');
  final palette = options.lineArt ? <int>[0xff000000] : extractPalette(rgba, count: options.colors).map((c) => c | 0xff000000).toSet().toList();
  final masks = List.generate(palette.length, (_) => Uint8List(width * height));
  var red = 0, green = 0, blue = 0, count = 0;
  for (var i = 0; i < width * height; i++) {
    final o = i * 4;
    if (rgba[o + 3] < 128) continue;
    if (options.lineArt) {
      if (0.2126 * rgba[o] + 0.7152 * rgba[o + 1] + 0.0722 * rgba[o + 2] >= 128) continue;
      masks[0][i] = 255; red += rgba[o]; green += rgba[o + 1]; blue += rgba[o + 2]; count++;
    } else if (palette.isNotEmpty) {
      var best = 0, distance = 1 << 30;
      for (var c = 0; c < palette.length; c++) {
        final r = rgba[o] - ((palette[c] >> 16) & 255), g = rgba[o + 1] - ((palette[c] >> 8) & 255), b = rgba[o + 2] - (palette[c] & 255);
        final d = r * r + g * g + b * b;
        if (d < distance) { distance = d; best = c; }
      }
      masks[best][i] = 255;
    }
  }
  if (options.lineArt && count > 0) palette[0] = 0xff000000 | (red / count).round() << 16 | (green / count).round() << 8 | (blue / count).round();
  final shapes = <(VShape, double)>[];
  for (var c = 0; c < palette.length; c++) {
    final loops = traceMask(masks[c], width, height).where((p) => _area(p).abs() >= options.minArea).toList();
    final paths = <VPath>[];
    for (final loop in loops) {
      final points = loop.map((p) => p + origin).toList();
      if (options.smooth) {
        paths.add(CurveFit.fitPath(points, tolerance: options.tolerance, closed: true));
      } else {
        final simplified = simplifyPolyline([...points, points.first], options.tolerance);
        if (simplified.last == simplified.first) simplified.removeLast();
        paths.add(VPath.polyline(simplified.length >= 3 ? simplified : points, closed: true));
      }
    }
    if (paths.isNotEmpty) shapes.add((VShape(paths: paths, fill: VFill.solid(Color(palette[c])), evenOdd: true), loops.fold<double>(0, (s, p) => s + _area(p)).abs()));
  }
  shapes.sort((a, b) => b.$2.compareTo(a.$2));
  return VectorArt(shapes.map((s) => s.$1).toList());
}

/// Reads an image as straight RGBA and vectorizes it without taking ownership.
Future<VectorArt> vectorizeImage(ui.Image image, {VectorizeOptions options = const VectorizeOptions(), Offset origin = Offset.zero}) async =>
    vectorizeRgba(await imageToRgba(image, straight: true), image.width, image.height, options: options, origin: origin);
