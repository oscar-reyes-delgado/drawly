import 'package:drawly/app/doc_layers.dart';
import 'package:drawly/app/doc_vector_ops.dart';
import 'package:drawly/app/document_controller.dart';
import 'package:drawly/core/ids.dart';
import 'package:drawly/engine/path_ops.dart';
import 'package:drawly/model/document.dart';
import 'package:drawly/model/layer.dart';
import 'package:drawly/model/vector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

VShape _rect(Rect r, {String? id}) => VShape(id: id ?? newId('S'), paths: [VPath.rect(r)], fill: const VFill.solid(Color(0xFF2266FF)));

DocumentController _docWith(CelTrack<VectorArt> cels) {
  final d = DocumentController(Project.blank(width: 200, height: 200), title: 'v');
  d.addLayer(VectorLayer(newId('L'), const LayerProps(name: 'vec'), cels));
  return d;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('generateInbetweens fills every frame between two keys with a morph', () {
    final a = VectorArt([_rect(const Rect.fromLTWH(0, 0, 20, 20), id: 's')]);
    final b = VectorArt([_rect(const Rect.fromLTWH(100, 0, 20, 20), id: 's')]);
    final d = _docWith(CelTrack(drawings: {1: a, 2: b}, xs: const [Exposure(0, 1), Exposure(4, 2)]));
    expect(d.generateInbetweens(), 3);
    final cels = (d.activeLayer! as VectorLayer).cels;
    expect([for (final x in cels.xs) x.frame], [0, 1, 2, 3, 4]);
    final mid = cels.at(2)!.shapes.single.path.getBounds();
    expect(mid.left, closeTo(50, 0.5));
    d.undo();
    expect((d.activeLayer! as VectorLayer).cels.xs, hasLength(2));
  });

  test('generateInbetweens with a count spreads fewer drawings and needs a next key', () {
    final a = VectorArt([_rect(const Rect.fromLTWH(0, 0, 20, 20))]);
    final b = VectorArt([_rect(const Rect.fromLTWH(60, 0, 20, 20))]);
    final d = _docWith(CelTrack(drawings: {1: a, 2: b}, xs: const [Exposure(0, 1), Exposure(6, 2)]));
    expect(d.generateInbetweens(count: 2), 2);
    expect([for (final x in (d.activeLayer! as VectorLayer).cels.xs) x.frame], [0, 1, 3, 6]);
    d.frame = 6;
    expect(d.generateInbetweens(), 0, reason: 'no key after the last one');
  });

  test('combineShapes unites two overlapping squares into one shape', () {
    final art = VectorArt([_rect(const Rect.fromLTWH(0, 0, 100, 100)), _rect(const Rect.fromLTWH(50, 50, 100, 100))]);
    final d = _docWith(CelTrack.single(art));
    expect(d.combineShapes(BoolOp.union), isTrue);
    final shapes = (d.activeLayer! as VectorLayer).cels.at(0)!.shapes;
    expect(shapes, hasLength(1));
    expect(shapes.single.path.contains(const Offset(125, 125)), isTrue);
    expect(shapes.single.path.contains(const Offset(125, 25)), isFalse);
  });

  test('combineShapes subtract and the guards', () {
    final art = VectorArt([_rect(const Rect.fromLTWH(0, 0, 100, 100)), _rect(const Rect.fromLTWH(50, 0, 100, 100)), _rect(const Rect.fromLTWH(300, 300, 10, 10))]);
    final d = _docWith(CelTrack.single(art));
    expect(d.combineShapes(BoolOp.subtract, indices: {0}), isFalse, reason: 'needs two shapes');
    expect(d.combineShapes(BoolOp.subtract, indices: {0, 1}), isTrue);
    final shapes = (d.activeLayer! as VectorLayer).cels.at(0)!.shapes;
    expect(shapes, hasLength(2), reason: 'the third shape stays');
    expect(shapes.first.path.contains(const Offset(25, 50)), isTrue);
    expect(shapes.first.path.contains(const Offset(75, 50)), isFalse);
    expect(d.combineShapes(BoolOp.intersect, indices: {0, 1}), isFalse, reason: 'disjoint shapes give nothing');
  });
}
