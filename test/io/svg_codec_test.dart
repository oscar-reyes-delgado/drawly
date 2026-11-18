import 'dart:ui';

import 'package:drawly/io/svg_codec.dart';
import 'package:drawly/model/gradient.dart';
import 'package:drawly/model/vector.dart';
import 'package:flutter_test/flutter_test.dart';

void expectOffset(Offset actual, Offset expected, [double eps = 1e-6]) {
  expect(actual.dx, closeTo(expected.dx, eps), reason: 'dx of $actual vs $expected');
  expect(actual.dy, closeTo(expected.dy, eps), reason: 'dy of $actual vs $expected');
}

List<Offset> samplePath(Path path, int count) {
  final metrics = path.computeMetrics().toList();
  final total = metrics.fold<double>(0, (s, m) => s + m.length);
  final out = <Offset>[];
  for (var i = 0; i <= count; i++) {
    final target = total * (i / count);
    var acc = 0.0;
    for (final m in metrics) {
      if (target <= acc + m.length || identical(m, metrics.last)) {
        final local = (target - acc).clamp(0.0, m.length);
        out.add(m.getTangentForOffset(local)!.position);
        break;
      }
      acc += m.length;
    }
  }
  return out;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('pathDataToVPaths parses M L Z and equivalent relative commands', () {
    final abs = pathDataToVPaths('M10 10 L20 10 L20 20 Z');
    expect(abs.length, 1);
    expect(abs.single.closed, isTrue);
    expect(abs.single.nodes.length, 3);

    final rel = pathDataToVPaths('m10 10 l10 0 l0 10 z');
    expect(rel.length, 1);
    expect(rel.single.closed, isTrue);
    expect(rel.single.nodes.length, 3);
    for (var i = 0; i < 3; i++) {
      expectOffset(rel.single.nodes[i].p, abs.single.nodes[i].p);
    }
  });

  test('pathDataToVPaths handles C, H, V and Q elevated to cubic (2/3)', () {
    final cubic = pathDataToVPaths('M0 0 C 10 0 10 10 0 10').single;
    expect(cubic.nodes.length, 2);
    expectOffset(cubic.nodes[0].hOut, const Offset(10, 0));
    expectOffset(cubic.nodes[1].hIn, const Offset(10, 10));
    expectOffset(cubic.nodes[1].p, const Offset(0, 10));

    final hv = pathDataToVPaths('M5 5 H 25 v 15').single;
    expect(hv.nodes.map((n) => n.p).toList(), const [
      Offset(5, 5),
      Offset(25, 5),
      Offset(25, 20),
    ]);

    final quad = pathDataToVPaths('M0 0 Q 30 0 30 30').single;
    expect(quad.nodes.length, 2);
    expectOffset(quad.nodes[0].hOut, const Offset(20, 0));
    expectOffset(quad.nodes[1].hIn, const Offset(30, 10));
    expectOffset(quad.nodes[1].p, const Offset(30, 30));
  });

  test('pathDataToVPaths converts SVG arc A into accurate cubic segments', () {
    final arc = pathDataToVPaths('M0 0 A10 10 0 0 1 20 0').single;
    expectOffset(arc.nodes.last.p, const Offset(20, 0));

    final samples = samplePath(arc.toPath(), 20);
    for (final pt in samples) {
      final dist = (pt - const Offset(10, 0)).distance;
      expect(dist, closeTo(10.0, 0.05));
    }
  });

  test('vpathsToPathData(pathDataToVPaths(d)) preserves geometry', () {
    const d = 'M 10 20 C 30 0 60 40 80 20 S 110 0 130 20 Q 150 40 170 10 Z';
    final paths1 = pathDataToVPaths(d);
    final outD = vpathsToPathData(paths1);
    final paths2 = pathDataToVPaths(outD);

    final s1 = samplePath(paths1.single.toPath(), 25);
    final s2 = samplePath(paths2.single.toPath(), 25);
    for (var i = 0; i < s1.length; i++) {
      expectOffset(s2[i], s1[i], 0.01);
    }
  });

  test('svgToVectorArt imports rect, circle, polygon, group transforms, inherited fill and style', () {
    const svg = '''
<svg xmlns="http://www.w3.org/2000/svg" width="200" height="200">
  <g fill="green" transform="translate(10, 20)">
    <rect id="r1" x="5" y="5" width="30" height="20"/>
    <circle id="c1" cx="50" cy="50" r="10" style="fill:#f00;stroke:none"/>
  </g>
  <polygon id="p1" points="0,0 10,0 10,10" fill="url(#someGrad)" stroke="blue" stroke-width="2"/>
</svg>
''';
    final art = svgToVectorArt(svg);
    expect(art.shapes.length, 3);

    final rectShape = art.shapes[0];
    expect(rectShape.fill.color.toARGB32(), 0xFF008000);
    final rb = rectShape.path.getBounds();
    expect(rb.left, closeTo(15, 1e-5));
    expect(rb.top, closeTo(25, 1e-5));
    expect(rb.width, closeTo(30, 1e-5));
    expect(rb.height, closeTo(20, 1e-5));

    final circleShape = art.shapes[1];
    expect(circleShape.fill.color.toARGB32(), 0xFFFF0000);
    expect(circleShape.stroke, isNull);
    final cb = circleShape.path.getBounds();
    expectOffset(cb.center, const Offset(60, 70), 1e-4);

    final polyShape = art.shapes[2];
    expect(polyShape.fill.color.toARGB32(), 0xFF808080);
    expect(polyShape.stroke!.color.toARGB32(), 0xFF0000FF);
    expect(polyShape.stroke!.width, 2);
    expect(polyShape.paths.single.closed, isTrue);
  });

  test('vectorArtToSvg and svgToVectorArt round-trip shapes, bounds, colours and strokes', () {
    final rectShape = VShape(
      id: 'rect1',
      paths: [VPath.rect(const Rect.fromLTWH(10, 15, 80, 50))],
      fill: const VFill.solid(Color(0xFF336699)),
      stroke: const VStroke(color: Color(0xFF112233), width: 3),
    );
    final ellipseShape = VShape(
      id: 'ell1',
      paths: [VPath.ellipse(const Rect.fromLTWH(100, 20, 60, 40))],
      fill: const VFill.solid(Color(0xFFCC4422)),
    );
    final dashedOpen = VShape(
      id: 'open1',
      paths: [VPath.polyline(const [Offset(10, 100), Offset(60, 130), Offset(120, 110)])],
      fill: const VFill.none(),
      stroke: const VStroke(color: Color(0xFF00AA55), width: 4, dash: [6, 3]),
    );

    final original = VectorArt([rectShape, ellipseShape, dashedOpen]);
    final svg = vectorArtToSvg(original, size: const Size(200, 200));
    final restored = svgToVectorArt(svg);

    expect(restored.shapes.length, 3);
    for (var i = 0; i < 3; i++) {
      final a = original.shapes[i];
      final b = restored.shapes[i];
      final ba = a.path.getBounds();
      final bb = b.path.getBounds();
      expect(bb.left, closeTo(ba.left, 0.01));
      expect(bb.top, closeTo(ba.top, 0.01));
      expect(bb.width, closeTo(ba.width, 0.01));
      expect(bb.height, closeTo(ba.height, 0.01));
      expect(b.fill.kind, a.fill.kind);
      if (!a.fill.isNone) {
        expect(b.fill.color.toARGB32(), a.fill.color.toARGB32());
      }
      if (a.stroke != null) {
        expect(b.stroke!.color.toARGB32(), a.stroke!.color.toARGB32());
        expect(b.stroke!.width, closeTo(a.stroke!.width, 0.01));
        expect(b.stroke!.dash, a.stroke!.dash);
      } else {
        expect(b.stroke, isNull);
      }
    }
  });

  test('vectorArtToSvg emits fill-rule="evenodd" and linearGradient defs', () {
    final shape = VShape(
      id: 'grad_eo',
      paths: [VPath.rect(const Rect.fromLTWH(0, 0, 50, 50))],
      fill: const VFill.gradient(
        GradientSpec(
          kind: GradientKind.linear,
          stops: [
            GradStop(0, Color(0xFFFF0000)),
            GradStop(1, Color(0xFF0000FF)),
          ],
          from: Offset(0, 0),
          to: Offset(50, 50),
        ),
      ),
      evenOdd: true,
    );
    final svg = vectorArtToSvg(VectorArt([shape]), size: const Size(100, 100));
    expect(svg, contains('fill-rule="evenodd"'));
    expect(svg, contains('<linearGradient'));
    expect(svg, contains('gradientUnits="userSpaceOnUse"'));
  });

  test('svgSize extracts size from width/height, viewBox, or returns null', () {
    expect(svgSize('<svg width="320" height="240"></svg>'), const Size(320, 240));
    expect(svgSize('<svg viewBox="0 0 640 480"></svg>'), const Size(640, 480));
    expect(svgSize('<svg xmlns="http://www.w3.org/2000/svg"></svg>'), isNull);
  });
}
