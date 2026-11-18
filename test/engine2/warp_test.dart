import 'dart:ui';
import 'package:drawly/engine/warp.dart';
import 'package:drawly/engine/tiles.dart';
import 'package:flutter_test/flutter_test.dart';
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const bounds = Rect.fromLTWH(0, 0, 64, 64);
  test('identity rendering preserves pixels with nonzero document origin', () async {
    final source = renderToImage(64, 64, (c) { c.drawRect(bounds, Paint()..color = const Color(0xffff0000)); c.drawRect(const Rect.fromLTWH(20, 10, 25, 40), Paint()..color = const Color(0xff00ffff)); });
    final result = renderWarped(source, WarpGrid.forSize(bounds.shift(const Offset(13, 21))));
    try { final a = await imageToRgba(source), b = await imageToRgba(result); for (var y = 1; y < 63; y++) { for (var x = 1; x < 63; x++) { for (var k = 0; k < 4; k++) { expect((a[(y * 64 + x) * 4 + k] - b[(y * 64 + x) * 4 + k]).abs(), lessThanOrEqualTo(2)); } } } } finally { source.dispose(); result.dispose(); }
  });
  test('push moves alpha centroid to the right', () async {
    final source = renderToImage(64, 64, (c) => c.drawCircle(const Offset(32, 32), 2, Paint()..color = const Color(0xffffffff)));
    final grid = WarpGrid.forSize(bounds, cell: 4)..push(const Offset(32, 32), const Offset(10, 0), 20, 1);
    final result = renderWarped(source, grid);
    try { final rgba = await imageToRgba(result); var sum = 0.0, xsum = 0.0; for (var i = 0; i < 4096; i++) { sum += rgba[i * 4 + 3]; xsum += (i % 64 + 0.5) * rgba[i * 4 + 3]; } expect(xsum / sum - 32, inInclusiveRange(5, 10)); } finally { source.dispose(); result.dispose(); }
  });
  test('brush bounds contain changed vertices and copy is independent', () {
    final g = WarpGrid.forSize(bounds, cell: 8), before = g.copy();
    final changed = g.push(const Offset(32, 32), const Offset(10, 0), 20, 1);
    for (var r = 0; r <= g.rows; r++) { for (var c = 0; c <= g.cols; c++) { if (g.at(c, r) != before.at(c, r)) { expect(changed.contains(g.at(c, r)), isTrue); } else if ((g.rest(c, r) - const Offset(32, 32)).distance >= 20) { expect(g.at(c, r), before.at(c, r)); } } }
    expect(before.isIdentity, isTrue);
  });
  test('twirl pinch bloat restore and reset', () {
    final g = WarpGrid.forSize(bounds, cell: 8), p = g.at(5, 4), radial = p - const Offset(32, 32);
    g.twirl(const Offset(32, 32), 0.001, 20, 1); final delta = g.at(5, 4) - p;
    expect((delta.dx * radial.dx + delta.dy * radial.dy).abs(), lessThan(0.001));
    g.reset(); g.pinch(const Offset(32, 32), 20, 1); expect((g.at(5, 4) - const Offset(32, 32)).distance, lessThan(8));
    g.reset(); g.bloat(const Offset(32, 32), 20, 1); expect((g.at(5, 4) - const Offset(32, 32)).distance, greaterThan(8));
    final d = g.displacementAt(p).distance; g.restore(const Offset(32, 32), 20, 0.5); expect(g.displacementAt(p).distance, lessThan(d)); g.reset(); expect(g.isIdentity, isTrue);
  });
  test('bilinear displacement and patch corners', () {
    final g = WarpGrid(bounds, 1, 1); g.dx[3] = 8; g.dy[3] = 4;
    expect(g.displacementAt(const Offset(64, 64)), const Offset(8, 4)); expect(g.displacementAt(const Offset(32, 32)), const Offset(2, 1));
    final controls = identityPatch(bounds); expect(gridFromPatch(bounds, controls).isIdentity, isTrue);
    controls[0] += const Offset(7, 9); expect(gridFromPatch(bounds, controls).at(0, 0), const Offset(7, 9));
  });
}
