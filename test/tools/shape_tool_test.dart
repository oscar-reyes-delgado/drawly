import 'package:drawly/app/tool_state.dart';
import 'package:drawly/tools/shape_tool.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every shape kind builds a path inside the dragged rectangle', () {
    const a = Offset(10, 20), b = Offset(210, 170);
    final r = Rect.fromPoints(a, b);
    for (final k in ShapeKind.values) {
      final p = buildShapePath(k, a, b);
      expect(p.nodes.length, greaterThanOrEqualTo(2), reason: '$k');
      expect(p.closed, k != ShapeKind.line, reason: '$k');
      final bounds = p.toPath().getBounds();
      expect(bounds.width, greaterThan(0), reason: '$k');
      // arrows follow the drag line and may stick out sideways by their head width
      if (k != ShapeKind.arrow && k != ShapeKind.line) {
        expect(r.inflate(1).contains(bounds.topLeft) && r.inflate(1).contains(bounds.bottomRight), isTrue, reason: '$k $bounds');
      }
    }
  });

  test('the speech balloon tail reaches the bottom of the drag rectangle', () {
    final p = buildShapePath(ShapeKind.bubble, Offset.zero, const Offset(100, 100));
    expect(p.nodes.any((n) => (n.p - const Offset(20, 100)).distance < 0.01), isTrue);
  });

  test('the arrow tip is at the end of the drag', () {
    final p = buildShapePath(ShapeKind.arrow, const Offset(0, 0), const Offset(120, 40));
    expect(p.nodes, hasLength(7));
    expect(p.nodes.any((n) => (n.p - const Offset(120, 40)).distance < 0.01), isTrue);
  });
}
