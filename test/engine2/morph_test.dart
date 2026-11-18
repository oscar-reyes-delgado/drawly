import 'dart:ui';

import 'package:drawly/core/mat2d.dart';
import 'package:drawly/engine/morph.dart';
import 'package:drawly/model/anim.dart';
import 'package:drawly/model/vector.dart';
import 'package:flutter_test/flutter_test.dart';

void near(Offset actual, Offset expected, [double tolerance = 1e-6]) => expect((actual - expected).distance, lessThanOrEqualTo(tolerance));
VShape shape(String id, {double x = 0, double opacity = 1}) => VShape(id: id, paths: [VPath.rect(Rect.fromLTWH(x, 0, 20, 20))], opacity: opacity);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('matching paths preserve endpoint nodes, handles and widths', () {
    final a = VPath([const VNode(Offset(1, 2), hIn: Offset(-1, 2), hOut: Offset(4, 3), width: 2), const VNode(Offset(10, 5))]);
    final b = VPath([const VNode(Offset(20, 30), hIn: Offset(15, 20), hOut: Offset(25, 35), width: 4), const VNode(Offset(40, 50))]);
    for (final t in [0.0, 1.0]) {
      final actual = lerpVPath(a, b, t), expected = t == 0 ? a : b;
      for (var i = 0; i < actual.nodes.length; i++) {
        near(actual.nodes[i].p, expected.nodes[i].p); near(actual.nodes[i].hIn, expected.nodes[i].hIn); near(actual.nodes[i].hOut, expected.nodes[i].hOut);
        expect(actual.nodes[i].width, expected.nodes[i].width);
      }
    }
    final mid = lerpVPath(a, b, 0.5).nodes.first;
    near(mid.hIn, const Offset(7, 11)); expect(mid.width, 3);
  });
  test('translated rectangle moves halfway', () {
    final a = VPath.rect(const Rect.fromLTWH(0, 0, 40, 20));
    final b = a.transformed(Mat2D.translation(100, 0)), mid = lerpVPath(a, b, 0.5);
    for (var i = 0; i < 4; i++) { near(mid.nodes[i].p, a.nodes[i].p + const Offset(50, 0)); }
    expect(mid.toPath().getBounds(), const Rect.fromLTWH(50, 0, 40, 20));
  });
  test('rectangle to ellipse blends corresponding four-node geometry', () {
    final a = VPath.rect(const Rect.fromLTWH(0, 0, 100, 80)), b = VPath.ellipse(const Rect.fromLTWH(20, 10, 120, 100));
    final mid = lerpVPath(a, b, 0.5);
    expect(mid.nodes.length, 4); expect(mid.closed, isTrue);
    for (var i = 0; i < 4; i++) {
      near(mid.nodes[i].p, (a.nodes[i].p + b.nodes[i].p) / 2);
      near(mid.nodes[i].hOut, (a.nodes[i].hOut + b.nodes[i].hOut) / 2);
    }
    final bounds = mid.toPath().getBounds();
    expect(bounds.width, inInclusiveRange(80, 120)); expect(bounds.height, inInclusiveRange(60, 100));
  });
  test('triangle to square resamples closed contours and preserves endpoints', () {
    final a = VPath.polyline([Offset.zero, const Offset(100, 0), const Offset(50, 100)], closed: true);
    final b = VPath.rect(const Rect.fromLTWH(20, 20, 120, 120));
    final mid = lerpVPath(a, b, 0.5);
    expect(mid.nodes.length, 64); expect(mid.closed, isTrue);
    final bounds = mid.toPath().getBounds();
    expect(bounds.left, inInclusiveRange(0, 20)); expect(bounds.right, inInclusiveRange(100, 140));
    expect(bounds.top, inInclusiveRange(0, 20)); expect(bounds.bottom, inInclusiveRange(99, 140));
    for (final (t, source) in [(0.0, a), (1.0, b)]) {
      final result = lerpVPath(a, b, t);
      final metric = source.toPath().computeMetrics().single;
      // Every endpoint sample lies on the original contour, irrespective of cyclic alignment.
      final dense = List.generate(4096, (i) => metric.getTangentForOffset(metric.length * i / 4096)!.position);
      for (final node in result.nodes) {
        expect(dense.map((p) => (p - node.p).distance).reduce((a, b) => a < b ? a : b), lessThan(0.5));
      }
    }
  });
  test('cyclic alignment fixes opposite winding and starting point', () {
    final a = VPath.rect(const Rect.fromLTWH(0, 0, 100, 100));
    final b = VPath.polyline([const Offset(100, 100), const Offset(100, 50), const Offset(100, 0), Offset.zero, const Offset(0, 100)], closed: true);
    final result = lerpVPath(a, b, 0.5);
    final expected = resamplePath(a, 64);
    for (var i = 0; i < 64; i++) { near(result.nodes[i].p, expected[i], 0.001); }
  });
  test('resampling is equidistant on open and closed straight paths', () {
    final line = resamplePath(VPath.line(Offset.zero, const Offset(100, 0)), 11);
    expect(line.length, 11); near(line.first, Offset.zero); near(line.last, const Offset(100, 0));
    for (var i = 1; i < line.length; i++) { expect((line[i] - line[i - 1]).distance, closeTo(10, 0.1)); }
    final square = resamplePath(VPath.rect(const Rect.fromLTWH(0, 0, 100, 100)), 40);
    for (var i = 0; i < square.length; i++) { expect((square[i] - square[(i + 1) % 40]).distance, closeTo(10, 0.1)); }
  });
  test('resampling handles empty, degenerate and single-sample paths', () {
    expect(resamplePath(const VPath([]), 3), List.filled(3, Offset.zero));
    expect(resamplePath(const VPath([VNode(Offset(2, 3))]), 2), List.filled(2, const Offset(2, 3)));
    expect(resamplePath(VPath.line(Offset.zero, const Offset(2, 0)), 1), [Offset.zero]);
    expect(resamplePath(const VPath([]), 0), isEmpty);
    expect(() => resamplePath(const VPath([]), -1), throwsArgumentError);
  });
  test('shape styles blend fill, stroke, opacity and preserve identity', () {
    final a = shape('a').copyWith(fill: const VFill.solid(Color(0xffff0000)), stroke: const VStroke(color: Color(0xff000000), width: 2));
    final b = shape('b', opacity: 0.5).copyWith(fill: const VFill.solid(Color(0xff0000ff)), stroke: const VStroke(color: Color(0xffffffff), width: 10));
    final mid = lerpShape(a, b, 0.5);
    expect(mid.id, 'a'); expect(mid.opacity, 0.75); expect(mid.fill.color.r, closeTo(0.5, 0.01)); expect(mid.fill.color.b, closeTo(0.5, 0.01));
    expect(mid.stroke!.width, 6); expect(mid.stroke!.color.r, closeTo(0.5, 0.01));
    expect(lerpShape(a, b.copyWith(clearStroke: true), 0.25).stroke!.width, 1.5);
    expect(lerpShape(a.copyWith(clearStroke: true), b, 0.25).stroke!.width, 2.5);
    expect(lerpShape(shape('a'), shape('b'), 0.5).stroke, isNull);
    expect(lerpShape(a, shape('b'), 0.49).fill.kind, FillKind.solid);
    expect(lerpShape(a, shape('b'), 0.5).fill.kind, FillKind.none);
  });
  test('compound paths reuse the last available counterpart and allow empties', () {
    final a = shape('a'), b = shape('b').copyWith(paths: [shape('x', x: 20).paths.single, shape('y', x: 40).paths.single]);
    final result = lerpShape(a, b, 0.5);
    expect(result.paths.length, 2); expect(result.paths[1].nodes.first.p.dx, 20);
    expect(lerpShape(a.copyWith(paths: []), b, 0.5).paths.length, 2);
    expect(lerpShape(a, b.copyWith(paths: []), 0.5).paths.length, 1);
  });
  test('art reserves id matches before pairing remaining shapes by order', () {
    final a = VectorArt([shape('fallback', x: 0), shape('match', x: 100)]);
    final b = VectorArt([shape('match', x: 200), shape('new', x: 20), shape('extra', x: 300, opacity: 0.8)]);
    final result = lerpArt(a, b, 0.25);
    expect(result.shapes.map((s) => s.id), ['fallback', 'match', 'extra']);
    expect(result.shapes[0].paths.first.nodes.first.p.dx, 5); expect(result.shapes[1].paths.first.nodes.first.p.dx, 125);
    expect(result.shapes.last.opacity, closeTo(0.2, 1e-6));
  });
  test('unpaired art fades out or in with original opacity', () {
    final a = VectorArt([shape('a', opacity: 0.8)]);
    expect(lerpArt(a, VectorArt.empty, 0.25).shapes.single.opacity, closeTo(0.6, 1e-6));
    expect(lerpArt(VectorArt.empty, a, 0.25).shapes.single.opacity, closeTo(0.2, 1e-6));
    expect(lerpArt(VectorArt.empty, VectorArt.empty, 0.5).isEmpty, isTrue);
  });
  test('inbetweens are strictly interior, monotone and respect ease', () {
    final a = VectorArt([shape('a')]), b = VectorArt([shape('a', x: 100)]);
    final drawings = inbetweens(a, b, 3);
    expect(drawings.length, 3);
    expect(drawings.map((art) => art.shapes.single.paths.first.nodes.first.p.dx), [25, 50, 75]);
    expect(inbetweens(a, b, 3, ease: const Ease(EaseType.easeIn)).first.shapes.single.paths.first.nodes.first.p.dx, 6.25);
    expect(inbetweens(a, b, 0), isEmpty); expect(() => inbetweens(a, b, -1), throwsArgumentError);
  });
}
