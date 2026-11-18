import 'dart:typed_data';
import 'dart:ui';
import 'package:drawly/engine/vectorize.dart';
import 'package:drawly/engine/tiles.dart';
import 'package:flutter_test/flutter_test.dart';

double area(List<Offset> p) { var a = 0.0; for (var i = 0; i < p.length; i++) { final q = p[(i + 1) % p.length]; a += p[i].dx * q.dy - p[i].dy * q.dx; } return a / 2; }
Uint8List mask(int w, int h, bool Function(int, int) inside) => Uint8List.fromList([for (var y = 0; y < h; y++) for (var x = 0; x < w; x++) inside(x, y) ? 255 : 0]);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('square boundaries are four pixel corners', () {
    final p = traceMask(mask(10, 10, (x, y) => x >= 3 && x < 7 && y >= 3 && y < 7), 10, 10).single;
    expect(p.toSet(), {const Offset(3, 3), const Offset(7, 3), const Offset(7, 7), const Offset(3, 7)}); expect(area(p), 16);
  });
  test('holes have opposite winding', () {
    final p = traceMask(mask(6, 6, (x, y) => !(x >= 2 && x < 4 && y >= 2 && y < 4)), 6, 6);
    expect(p.map(area).toSet(), {36.0, -4.0});
  });
  test('diagonal pixels remain separate', () { final p = traceMask(Uint8List.fromList([255, 0, 0, 255]), 2, 2); expect(p.length, 2); expect(p.map((p) => p.length), [4, 4]); });
  test('full and empty masks', () { expect(area(traceMask(mask(5, 3, (_, _) => true), 5, 3).single), 15); expect(traceMask(Uint8List(15), 5, 3), isEmpty); });
  test('two colors cover their respective halves and origin shifts', () {
    final rgba = Uint8List.fromList([for (var y = 0; y < 32; y++) for (var x = 0; x < 32; x++) ...[x < 16 ? 255 : 0, 0, x < 16 ? 0 : 255, 255]]);
    final art = vectorizeRgba(rgba, 32, 32, options: const VectorizeOptions(colors: 2, smooth: false), origin: const Offset(5, 7));
    expect(art.shapes.length, 2);
    for (final s in art.shapes) { expect(s.path.contains(Offset(s.fill.color.r > 0.5 ? 13 : 29, 23)), isTrue); }
    expect(art.shapes.map((s) => s.fill.color.toARGB32()).toSet(), {0xffff0000, 0xff0000ff});
    expect(art.bounds!.contains(const Offset(5, 7)), isTrue); expect(art.bounds!.contains(const Offset(37, 39)), isTrue);
  });
  test('minArea drops specks and line art uses mean dark color', () {
    final rgba = Uint8List.fromList([for (var i = 0; i < 16; i++) ...[20, 30, 40, i == 0 || i >= 8 ? 255 : 0]]);
    final art = vectorizeRgba(rgba, 4, 4, options: const VectorizeOptions(lineArt: true, smooth: false, minArea: 2));
    expect(art.shapes.length, 1); expect(art.shapes.single.paths.length, 1); expect(art.shapes.single.fill.color.toARGB32(), 0xff141e28);
    expect(art.shapes.single.path.contains(const Offset(0.5, 0.5)), isFalse);
  });
  test('image wrapper and smooth paths retain opaque content', () async {
    final image = renderToImage(16, 16, (c) => c.drawCircle(const Offset(8, 8), 6, Paint()..color = const Color(0xff000000)));
    try { final art = await vectorizeImage(image); expect(art.shapes, isNotEmpty); expect(art.shapes.single.path.contains(const Offset(8, 8)), isTrue); } finally { image.dispose(); }
  });
}
