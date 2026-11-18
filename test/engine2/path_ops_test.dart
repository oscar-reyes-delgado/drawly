import 'dart:ui';
import 'package:drawly/engine/path_ops.dart';
import 'package:drawly/model/vector.dart';
import 'package:flutter_test/flutter_test.dart';

VShape square(double x, double y) => VShape(id: 'lower', paths: [VPath.rect(Rect.fromLTWH(x, y, 100, 100))], fill: const VFill.solid(Color(0xffff0000)), stroke: const VStroke(width: 3));
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('rectangle has exactly four corner nodes without handles', () {
    final p = pathToVPaths(Path()..addRect(const Rect.fromLTWH(3.4, 5.8, 100.3, 73.2))).single;
    expect(p.closed, isTrue); expect(p.nodes.length, 4);
    const corners = [Offset(3.4, 5.8), Offset(103.7, 5.8), Offset(103.7, 79), Offset(3.4, 79)];
    for (final n in p.nodes) { expect(n.hasIn || n.hasOut, isFalse); expect(corners.any((c) => (c - n.p).distance < 0.05), isTrue); }
  });
  test('circle fitting stays within half a pixel and sixteen nodes', () {
    final p = pathToVPaths(Path()..addOval(const Rect.fromLTWH(-50, -50, 100, 100))).single;
    expect(p.closed, isTrue); expect(p.nodes.length, lessThanOrEqualTo(16));
    final m = p.toPath().computeMetrics().single;
    for (var i = 0; i < 100; i++) { expect(m.getTangentForOffset(m.length * i / 100)!.position.distance, closeTo(50, 0.5)); }
  });
  test('rounded rectangle preserves its contour', () {
    final original = Path()..addRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(0, 0, 100, 80), const Radius.circular(15)));
    final a = original.computeMetrics().single, b = pathToVPaths(original).single.toPath().computeMetrics().single;
    for (var i = 0; i < 200; i++) { expect((a.getTangentForOffset(a.length * i / 200)!.position - b.getTangentForOffset(b.length * i / 200)!.position).distance, lessThan(0.5)); }
  });
  test('booleans have expected areas and preserve lower style', () {
    final a = square(0, 0), b = square(50, 50);
    for (final (op, expected) in [(BoolOp.union, 17500), (BoolOp.subtract, 7500), (BoolOp.intersect, 2500), (BoolOp.exclude, 15000)]) {
      final r = booleanShapes(a, b, op)!;
      var area = 0;
      for (var y = 2.5; y < 150; y += 5) { for (var x = 2.5; x < 150; x += 5) { if (r.path.contains(Offset(x, y))) area += 25; } }
      expect(area, closeTo(expected, expected * 0.03)); expect(r.id, a.id); expect(r.fill, same(a.fill)); expect(r.stroke, same(a.stroke));
    }
  });
  test('empty intersections and folds retain set semantics', () {
    expect(booleanShapes(square(0, 0), square(200, 0), BoolOp.intersect), isNull);
    expect(booleanAll([], BoolOp.union), isNull);
    final r = booleanAll([square(0, 0), square(200, 0), square(400, 0)], BoolOp.union)!;
    for (final x in [50.0, 250.0, 450.0]) { expect(r.path.contains(Offset(x, 50)), isTrue); }
    expect(booleanAll([square(0, 0), square(200, 0), square(400, 0)], BoolOp.intersect), isNull);
  });
  test('open line remains open and straight', () { final p = pathToVPaths(Path()..moveTo(2, 3)..lineTo(99, 44)).single; expect(p.closed, isFalse); expect(p.nodes.length, 2); });
}
