import 'dart:math' as math;

import 'package:drawly/core/mat2d.dart';
import 'package:drawly/engine/tiles.dart';
import 'package:drawly/model/anim.dart';
import 'package:drawly/model/document.dart';
import 'package:drawly/model/layer.dart';
import 'package:flutter_test/flutter_test.dart';

PaintLayer paint(String id, {Xform xf = Xform.identity, String? parentId}) =>
    PaintLayer(id, LayerProps(name: id, xf: xf, parentId: parentId), CelTrack.single(TilePlane.empty));

List<String> ids(List<Layer> layers) => walkLayers(layers).map((l) => l.id).toList();

void expectOffset(Offset actual, Offset expected, [double eps = 1e-9]) {
  expect(actual.dx, closeTo(expected.dx, eps), reason: 'dx of $actual vs $expected');
  expect(actual.dy, closeTo(expected.dy, eps), reason: 'dy of $actual vs $expected');
}

void expectMat(Mat2D actual, Mat2D expected, [double eps = 1e-9]) {
  final a = actual.toJson(), e = expected.toJson();
  for (var i = 0; i < 6; i++) {
    expect(a[i], closeTo(e[i], eps), reason: 'component $i of $actual vs $expected');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // root (bottom -> top): A, G[B, H[C]], D
  final c = paint('C');
  final h = GroupLayer('H', const LayerProps(name: 'H'), [c]);
  final b = paint('B');
  final g = GroupLayer('G', const LayerProps(name: 'G'), [b, h]);
  final a = paint('A'), d = paint('D');
  final root = <Layer>[a, g, d];

  group('tree helpers', () {
    test('walkLayers visits depth first in stored order', () {
      expect(ids(root), ['A', 'G', 'B', 'H', 'C', 'D']);
    });

    test('findLayer and parentGroupOf', () {
      expect(findLayer(root, 'C'), same(c));
      expect(findLayer(root, 'G'), same(g));
      expect(findLayer(root, 'nope'), isNull);
      expect(findLayer(root, null), isNull);
      expect(parentGroupOf(root, 'C'), same(h));
      expect(parentGroupOf(root, 'B'), same(g));
      expect(parentGroupOf(root, 'A'), isNull);
      expect(parentGroupOf(root, 'nope'), isNull);
    });

    test('mapLayer', () {
      expect(identical(mapLayer(root, 'nope', (l) => l), root), isTrue);
      final renamed = mapLayer(root, 'C', (l) => l.withProps(l.props.copyWith(name: 'renamed')));
      expect(findLayer(renamed, 'C')!.name, 'renamed');
      expect(findLayer(root, 'C')!.name, 'C', reason: 'original untouched');
      expect(renamed[0], same(a));
      expect(renamed[2], same(d));
      expect(renamed[1], isNot(same(g)));
    });

    test('removeLayer inside a group', () {
      final out = removeLayer(root, 'B');
      expect(ids(out), ['A', 'G', 'H', 'C', 'D']);
      expect(ids(removeLayer(root, 'C')), ['A', 'G', 'B', 'H', 'D']);
      expect(identical(removeLayer(root, 'nope'), root), isTrue);
    });

    test('insertLayer', () {
      final x = paint('X');
      expect(ids(insertLayer(root, x, aboveId: 'B')), ['A', 'G', 'B', 'X', 'H', 'C', 'D']);
      expect(ids(insertLayer(root, x, aboveId: 'A')), ['A', 'X', 'G', 'B', 'H', 'C', 'D']);
      expect(ids(insertLayer(root, x, intoGroup: 'H')), ['A', 'G', 'B', 'H', 'C', 'X', 'D']);
      expect(ids(insertLayer(root, x, aboveId: 'nope')), ['A', 'G', 'B', 'H', 'C', 'D', 'X']);
      expect(ids(insertLayer(root, x)), ['A', 'G', 'B', 'H', 'C', 'D', 'X']);
    });

    test('cloneLayer gives fresh ids to the group and every descendant', () {
      final clone = cloneLayer(g, name: 'copy');
      expect(clone, isA<GroupLayer>());
      expect(clone.name, 'copy');
      final cloneIds = ids([clone]);
      expect(cloneIds.length, 4);
      expect(cloneIds.toSet().length, 4);
      expect(cloneIds.toSet().intersection({'G', 'B', 'H', 'C'}), isEmpty);
      final names = walkLayers([clone]).skip(1).map((l) => l.name).toList();
      expect(names, ['B', 'H', 'C']);
    });
  });

  group('transforms', () {
    test('Comp.worldMatrix follows the parent chain', () {
      final parent = paint('P', xf: const Xform(x: 10));
      final child = paint('K', xf: const Xform(x: 5, y: 2), parentId: 'P');
      final comp = Comp(id: 'c', name: 'c', width: 100, height: 100, layers: [parent, child]);
      expectOffset(comp.worldMatrix(comp.layer('K')!, 0).apply(Offset.zero), const Offset(15, 2));

      final moved = comp.updateLayer('P', (l) => l.withProps(l.props.copyWith(xf: const Xform(x: 30, y: -4))));
      expectOffset(moved.worldMatrix(moved.layer('K')!, 0).apply(Offset.zero), const Offset(35, -2));
    });

    test('Xform.fromMatrix inverts Xform.matrix for TRS matrices', () {
      const cases = [
        Xform(x: 12, y: -4, sx: 2, sy: 1.5, rot: 30, ax: 5, ay: 7),
        Xform(x: -3, y: 8, sx: 0.5, sy: 0.25, rot: 120, ax: -10, ay: 2),
        Xform(x: 0, y: 0, sx: 1, sy: 3, rot: -75, ax: 0, ay: 0),
      ];
      for (final xf in cases) {
        final m = xf.matrix;
        final back = Xform.fromMatrix(m, ax: xf.ax, ay: xf.ay);
        expectMat(back.matrix, m);
        expect(back.rot, closeTo(xf.rot, 1e-9));
        expect(back.sx, closeTo(xf.sx, 1e-9));
        expect(back.sy, closeTo(xf.sy, 1e-9));
      }
    });

    test('LayerProps.valueAt: the track overrides the static value', () {
      const props = LayerProps(
        opacity: 0.5,
        xf: Xform(x: 5, y: 9),
        tracks: {
          Prop.x: AnimTrack([AnimKey(0, 100)]),
        },
      );
      expect(props.valueAt(Prop.x, 3), 100);
      expect(props.valueAt(Prop.y, 3), 9);
      expect(props.valueAt(Prop.opacity, 0), 0.5);
    });
  });

  group('SymmetrySpec.transforms', () {
    const center = Offset(100, 50);

    test('number of transforms per kind', () {
      const n = 6;
      const expected = {
        SymmetryKind.none: 1,
        SymmetryKind.vertical: 2,
        SymmetryKind.horizontal: 2,
        SymmetryKind.quad: 4,
        SymmetryKind.radial: n,
        SymmetryKind.mandala: 2 * n,
      };
      for (final e in expected.entries) {
        final s = SymmetrySpec(kind: e.key, center: center, count: n);
        expect(s.transforms.length, e.value, reason: e.key.name);
      }
    });

    test('vertical mirror reflects across the centre line', () {
      const s = SymmetrySpec(kind: SymmetryKind.vertical, center: center);
      final mirror = s.transforms[1];
      expectOffset(mirror.apply(Offset(center.dx + 10, 80)), Offset(center.dx - 10, 80));
      expectOffset(mirror.apply(Offset(center.dx + 10, center.dy)), Offset(center.dx - 10, center.dy));
      expect(s.transforms[0].isIdentity, isTrue);
    });

    test('radial rotates around the centre', () {
      const s = SymmetrySpec(kind: SymmetryKind.radial, center: center, count: 4);
      final quarter = s.transforms[1];
      final p = quarter.apply(Offset(center.dx + 10, center.dy));
      expectOffset(p, Offset(center.dx + 10 * math.cos(math.pi / 2), center.dy + 10 * math.sin(math.pi / 2)));
    });
  });
}
