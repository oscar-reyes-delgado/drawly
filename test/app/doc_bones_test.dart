import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:drawly/app/doc_bones.dart';
import 'package:drawly/app/document_controller.dart';
import 'package:drawly/engine/compositor.dart';
import 'package:drawly/engine/tiles.dart';
import 'package:drawly/io/project_codec.dart';
import 'package:drawly/model/document.dart';
import 'package:drawly/model/layer.dart';
import 'package:flutter_test/flutter_test.dart';

const _bar = ui.Rect.fromLTRB(10, 45, 90, 55);

/// 100x100 document with a horizontal bar on a paint layer and two bones along it.
(DocumentController, String, String, String) _doc() {
  final p = Project.blank(width: 100, height: 100, background: null, frames: 12);
  final plane = TilePlane.empty.drawn((c) => c.drawRect(_bar, ui.Paint()..color = const ui.Color(0xFF000000)), area: _bar);
  final layer = PaintLayer('L', const LayerProps(name: 'arm'), CelTrack.single(plane));
  final d = DocumentController(p.withComp(p.main.copyWith(layers: [layer])), title: 'b');
  final a = d.addBone('L', const ui.Offset(10, 50), const ui.Offset(50, 50))!;
  final b = d.addBone('L', const ui.Offset(50, 50), const ui.Offset(90, 50), parentId: a)!;
  return (d, 'L', a, b);
}

Future<Uint8List> _render(DocumentController d) async {
  final img = renderCompImage(d.project, d.comp, d.frame.toDouble(), background: false, useCamera: false);
  final px = await imageToRgba(img, straight: true);
  img.dispose();
  return px;
}

int _alpha(Uint8List px, int x, int y) => px[(y * 100 + x) * 4 + 3];

int _maxAlpha(Uint8List px, ui.Rect r) {
  var m = 0;
  for (var y = r.top.toInt(); y < r.bottom; y++) {
    for (var x = r.left.toInt(); x < r.right; x++) {
      if (_alpha(px, x, y) > m) m = _alpha(px, x, y);
    }
  }
  return m;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bones are added to a paint layer, parented, and undone one by one', () {
    final (d, l, a, b) = _doc();
    final rig = (d.comp.layer(l)! as PaintLayer).rig!;
    expect(rig.skeleton.bones.map((x) => x.id), [a, b]);
    expect(rig.skeleton.byId(b)!.parentId, a);
    expect(d.addBone(l, const ui.Offset(1, 1), const ui.Offset(1.2, 1)), isNull, reason: 'too short');
    d.undo();
    expect((d.comp.layer(l)! as PaintLayer).rig!.skeleton.bones, hasLength(1));
    d.undo();
    expect((d.comp.layer(l)! as PaintLayer).rig, isNull);
  });

  test('a bone rotation is a key at the current frame and interpolates', () {
    final (d, l, _, b) = _doc();
    d.setBoneRots(l, {b: 0});
    d.frame = 10;
    d.setBoneRots(l, {b: 90});
    d.frame = 5;
    expect(d.boneRot(l, b), inInclusiveRange(1, 89));
    final (head, tail) = d.posedBonesOf(l)[b]!;
    expect(head, const ui.Offset(50, 50));
    expect(tail.dy, greaterThan(50));
  });

  test('the rest pose renders unchanged and a posed bone moves the pixels', () async {
    final (d, l, _, b) = _doc();
    var px = await _render(d);
    expect(_alpha(px, 80, 50), 255);
    expect(_maxAlpha(px, const ui.Rect.fromLTWH(45, 70, 10, 10)), 0);

    d.setBoneRots(l, {b: 90});
    px = await _render(d);
    expect(_alpha(px, 30, 50), greaterThan(200), reason: 'the first bone does not move');
    expect(_maxAlpha(px, const ui.Rect.fromLTWH(78, 47, 10, 6)), lessThan(60), reason: 'the end of the bar left its place');
    expect(_maxAlpha(px, const ui.Rect.fromLTWH(45, 70, 10, 10)), greaterThan(200), reason: 'and is now below the elbow');
  });

  test('IK poses a two-bone chain towards a target', () {
    final (d, l, _, b) = _doc();
    expect(d.poseBonesIk(l, b, const ui.Offset(50, 90)), isTrue);
    final (_, tail) = d.posedBonesOf(l)[b]!;
    expect((tail - const ui.Offset(50, 90)).distance, lessThan(1));
  });

  test('the rig survives JSON and the .drawly codec', () async {
    final (d, l, a, b) = _doc();
    d.setBoneRots(l, {b: 45});
    final rig = (d.comp.layer(l)! as PaintLayer).rig!;
    final json = LayerRig.fromJson(rig.toJson())!;
    expect(json.skeleton.bones.map((x) => (x.id, x.parentId, x.head, x.tail)), rig.skeleton.bones.map((x) => (x.id, x.parentId, x.head, x.tail)));
    expect(json.rotAt(b, 0), 45);

    final bytes = await ProjectCodec.encode(d.project, thumbnail: false);
    final back = await ProjectCodec.decode(bytes);
    final layer = back.main.layer(l)! as PaintLayer;
    expect(layer.rig!.skeleton.byId(b)!.parentId, a);
    expect(layer.rig!.rotAt(b, 0), 45);
    // a layer without bones stays without rig
    final plain = await ProjectCodec.decode(await ProjectCodec.encode(Project.blank(), thumbnail: false));
    expect(plain.main.layers.whereType<PaintLayer>().every((x) => x.rig == null), isTrue);
  });

  test('removing a bone removes its children and their keys', () {
    final (d, l, a, b) = _doc();
    d.setBoneRots(l, {b: 30});
    d.removeBone(l, a);
    expect((d.comp.layer(l)! as PaintLayer).rig, isNull);
  });
}
