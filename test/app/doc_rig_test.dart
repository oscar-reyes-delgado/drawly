import 'package:drawly/app/doc_rig.dart';
import 'package:drawly/app/doc_timeline.dart';
import 'package:drawly/app/document_controller.dart';
import 'package:drawly/core/ids.dart';
import 'package:drawly/engine/tiles.dart';
import 'package:drawly/model/anim.dart';
import 'package:drawly/model/document.dart';
import 'package:drawly/model/layer.dart';
import 'package:flutter_test/flutter_test.dart';

PaintLayer _layer(String id, {String? parent, double ax = 0, double ay = 0, double x = 0, double rot = 0}) =>
    PaintLayer(id, LayerProps(name: id, parentId: parent, xf: Xform(x: x, ax: ax, ay: ay, rot: rot)), CelTrack.single(TilePlane.empty));

/// Arm of three links along y = 100: joints at x = 50, 100 and 150.
DocumentController _arm() {
  final p = Project.blank(width: 300, height: 300);
  final comp = p.main.copyWith(layers: [
    _layer('A', ax: 50, ay: 100),
    _layer('B', parent: 'A', ax: 100, ay: 100),
    _layer('C', parent: 'B', ax: 150, ay: 100),
  ]);
  final d = DocumentController(p.withComp(comp), title: 'rig');
  d.selectLayer('C');
  return d;
}

Offset _tip(DocumentController d, Offset grab) => d.comp.worldMatrix(d.comp.layer('C')!, d.frame.toDouble()).apply(grab);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('parentChain goes from the top ancestor to the tip and honours the length', () {
    final d = _arm();
    expect([for (final l in d.parentChain('C')) l.id], ['A', 'B', 'C']);
    expect([for (final l in d.parentChain('C', length: 2)) l.id], ['B', 'C']);
    expect([for (final l in d.parentChain('A')) l.id], ['A']);
    expect(d.layerPivot(d.comp.layer('B')!), const Offset(100, 100));
  });

  test('dragLayerIk brings the grabbed point to a reachable target in one undo step', () {
    final d = _arm();
    const grab = Offset(200, 100);
    final key = DocumentController.gestureKey('ik');
    for (final t in const [Offset(190, 120), Offset(160, 150), Offset(120, 180)]) {
      expect(d.dragLayerIk('C', grab, t, mergeKey: key), isTrue);
    }
    expect((_tip(d, grab) - const Offset(120, 180)).distance, lessThan(1));
    // the root joint does not move
    expect(d.layerPivot(d.comp.layer('A')!), const Offset(50, 100));
    d.undo();
    for (final id in ['A', 'B', 'C']) {
      expect(d.comp.layer(id)!.props.xf.rot, 0);
    }
  });

  test('an unreachable target stretches the chain towards it', () {
    final d = _arm();
    d.dragLayerIk('C', const Offset(200, 100), const Offset(50, -400));
    final tip = _tip(d, const Offset(200, 100));
    expect(tip.dx, closeTo(50, 1));
    expect(tip.dy, closeTo(-50, 1));
  });

  test('a layer without parent cannot be posed', () {
    final d = _arm();
    expect(d.solveLayerIk('A', Offset.zero, const Offset(10, 10)), isEmpty);
    expect(d.dragLayerIk('A', Offset.zero, const Offset(10, 10)), isFalse);
  });

  test('IK writes keys when the rotation is animated', () {
    final d = _arm();
    d.frame = 4;
    d.setLayerProp('B', Prop.rotation, 0, forceKey: true);
    d.dragLayerIk('C', const Offset(200, 100), const Offset(150, 160));
    final track = d.comp.layer('B')!.props.tracks[Prop.rotation]!;
    expect(track.keyAt(4), isNotNull);
    expect(track.keyAt(4)!.value, isNot(0));
  });

  test('parentKeepingPlace keeps the layer on screen and can be undone', () {
    final p = Project.blank(width: 100, height: 100);
    final comp = p.main.copyWith(layers: [_layer('P', x: 30, ax: 10, ay: 10, rot: 30), _layer(newId('L'), x: 10, ax: 5, ay: 5)]);
    final d = DocumentController(p.withComp(comp), title: 'k');
    final child = d.comp.layers[1];
    final before = d.comp.worldMatrix(child, 0);
    d.parentKeepingPlace(child.id, 'P');
    final now = d.comp.layer(child.id)!;
    expect(now.props.parentId, 'P');
    final after = d.comp.worldMatrix(now, 0);
    for (final pt in const [Offset(0, 0), Offset(20, 7)]) {
      expect((after.apply(pt) - before.apply(pt)).distance, lessThan(1e-6));
    }
    // cycles are refused
    d.parentKeepingPlace('P', child.id);
    expect(d.comp.layer('P')!.props.parentId, isNull);
    d.undo();
    expect(d.comp.layer(child.id)!.props.parentId, isNull);
    expect(d.comp.layer(child.id)!.props.xf.x, 10);
  });
}
