import 'dart:ui';

import 'package:drawly/engine/shape_paths.dart';
import 'package:drawly/model/vector.dart';
import 'package:flutter_test/flutter_test.dart';

void expectInsideAndLarge(VPath vp, Rect r, String label) {
  final b = vp.toPath().getBounds();
  expect(b.left, greaterThanOrEqualTo(r.left - 1), reason: '$label left');
  expect(b.top, greaterThanOrEqualTo(r.top - 1), reason: '$label top');
  expect(b.right, lessThanOrEqualTo(r.right + 1), reason: '$label right');
  expect(b.bottom, lessThanOrEqualTo(r.bottom + 1), reason: '$label bottom');
  expect(b.width, greaterThanOrEqualTo(r.width * 0.9), reason: '$label width');
  expect(b.height, greaterThanOrEqualTo(r.height * 0.9), reason: '$label height');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const rect = Rect.fromLTWH(20, 40, 200, 120);

  test('all generated paths are closed and have at least 3 nodes', () {
    final all = <VPath>[
      arrowPath(const Offset(10, 10), const Offset(110, 10)),
      heartPath(rect),
      speechBubblePath(rect),
      roundedBubblePath(rect),
      burstPath(rect),
      cloudPath(rect),
      ...thoughtTrail(rect, const Offset(40, 220)),
    ];
    for (final p in all) {
      expect(p.closed, isTrue);
      expect(p.nodes.length, greaterThanOrEqualTo(3));
    }
  });

  test('heartPath is symmetric, inside r, >= 90% size and contains r.center', () {
    final h = heartPath(rect);
    expectInsideAndLarge(h, rect, 'heart');
    final path = h.toPath();
    final b = path.getBounds();
    expect(b.center.dx, closeTo(rect.center.dx, 0.5));
    expect(path.contains(rect.center), isTrue);
  });

  test('arrowPath has 7 nodes, reaches to, handles diagonal and from == to', () {
    const from = Offset(10, 20);
    const to = Offset(150, 90);
    final arrow = arrowPath(from, to);
    expect(arrow.nodes.length, 7);
    expect(arrow.nodes.any((n) => (n.p - to).distance < 1e-6), isTrue);
    final b = arrow.toPath().getBounds();
    expect(b.inflate(1e-6).contains(from), isTrue);
    expect(b.inflate(1e-6).contains(to), isTrue);

    final zero = arrowPath(from, from);
    expect(zero.nodes.length, 7);
    expect(zero.closed, isTrue);
  });

  test('speechBubblePath and roundedBubblePath contain r.center and pass through tailTip', () {
    const tip = Offset(60, 210);
    for (final b in [
      speechBubblePath(rect, tailTip: tip),
      roundedBubblePath(rect, tailTip: tip),
    ]) {
      expect(b.toPath().contains(rect.center), isTrue);
      expect(b.nodes.any((n) => (n.p - tip).distance < 1e-6), isTrue);
    }
  });

  test('burstPath has 2*spikes nodes, fits r and is deterministic by seed', () {
    final b1 = burstPath(rect, spikes: 14, seed: 42);
    final b2 = burstPath(rect, spikes: 14, seed: 42);
    final b3 = burstPath(rect, spikes: 14, seed: 99);

    expect(b1.nodes.length, 28);
    expectInsideAndLarge(b1, rect, 'burst');

    for (var i = 0; i < b1.nodes.length; i++) {
      expect(b1.nodes[i].p, b2.nodes[i].p);
    }
    final anyDiff = Iterable<int>.generate(b1.nodes.length).any((i) => b1.nodes[i].p != b3.nodes[i].p);
    expect(anyDiff, isTrue);
  });

  test('cloudPath fits inside r and occupies >= 90% of width and height', () {
    final c = cloudPath(rect, lobes: 9);
    expectInsideAndLarge(c, rect, 'cloud');
    expect(c.toPath().contains(rect.center), isTrue);
  });

  test('thoughtTrail returns count circles with shrinking radii towards tailTip', () {
    const tip = Offset(50, 240);
    final trail = thoughtTrail(rect, tip, count: 3);
    expect(trail.length, 3);
    final widths = trail.map((p) => p.toPath().getBounds().width).toList();
    expect(widths[0], greaterThan(widths[1]));
    expect(widths[1], greaterThan(widths[2]));

    final centers = trail.map((p) => p.toPath().getBounds().center).toList();
    expect((centers.last - tip).distance, lessThan((centers.first - tip).distance));
  });
}
