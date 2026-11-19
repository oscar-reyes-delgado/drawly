import 'dart:ui';

import 'package:drawly/app/app_state.dart';
import 'package:drawly/app/doc_layers.dart';
import 'package:drawly/app/document_controller.dart';
import 'package:drawly/engine/tiles.dart';
import 'package:drawly/model/document.dart';
import 'package:drawly/model/layer.dart';
import 'package:drawly/tools/transform_tool.dart';
import 'package:drawly/tools/tool.dart';
import 'package:flutter_test/flutter_test.dart';

const _white = Color(0xFFFFFFFF);

DocumentController _doc(List<Rect> rects, {int size = 64}) {
  final d = AppState.I.addDocument(Project.blank(width: size, height: size, background: null), title: 'transform_test');
  var plane = TilePlane.empty;
  for (final r in rects) {
    plane = plane.drawn((c) => c.drawRect(r, Paint()..color = _white), area: r);
  }
  final layer = d.activeLayer! as PaintLayer;
  d.updateLayer('init', layer.id, (l) => (l as PaintLayer).withCels(CelTrack.single(plane)));
  d.history.clear(d.history.current);
  return d;
}

TilePlane _plane(DocumentController d) => (d.activeLayer! as PaintLayer).cels.at(d.frame)!;

Future<int> _alpha(DocumentController d, double x, double y) async {
  final px = await _plane(d).readRgba(Rect.fromLTWH(x, y, 1, 1), straight: true);
  return px[3];
}

ToolEvent _ev(DocumentController d, Offset p, {bool shift = false}) => ToolEvent(doc: p, view: d.view.toView(p), shift: shift);

void _drag(TransformTool t, DocumentController d, Offset from, Offset to, {int steps = 4, bool shift = false}) {
  t.onDown(_ev(d, from, shift: shift));
  for (var i = 1; i <= steps; i++) {
    t.onMove(_ev(d, Offset.lerp(from, to, i / steps)!, shift: shift));
  }
  t.onUp(_ev(d, to, shift: shift));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final app = AppState.I;
  late TransformTool tool;

  setUp(() => tool = TransformTool());
  tearDown(() {
    tool.cancel();
    while (app.docs.isNotEmpty) {
      app.closeDocument(app.docs.first);
    }
  });

  test('scaling from the bottom-right corner doubles the square; undo restores it', () async {
    final d = _doc([const Rect.fromLTWH(10, 10, 10, 10)]);
    expect(await tool.open(), isTrue);
    expect(tool.box, const Rect.fromLTWH(10, 10, 10, 10));
    _drag(tool, d, const Offset(20, 20), const Offset(30, 30));
    tool.confirm();
    expect(await _alpha(d, 28, 28), greaterThan(128));
    expect(await _alpha(d, 32, 32), 0);
    expect(await _alpha(d, 11, 11), greaterThan(128));
    expect(d.live, isNull);
    d.undo();
    expect(await _alpha(d, 28, 28), 0);
    expect(await _alpha(d, 15, 15), 255);
  });

  test('dragging inside moves; Shift keeps proportions on a corner', () async {
    final d = _doc([const Rect.fromLTWH(10, 10, 10, 10)]);
    await tool.open();
    _drag(tool, d, const Offset(15, 15), const Offset(35, 15));
    tool.confirm();
    final b = await _plane(d).contentBounds();
    expect(b, const Rect.fromLTWH(30, 10, 10, 10));

    final tool2 = TransformTool();
    await tool2.open();
    _drag(tool2, d, const Offset(40, 20), const Offset(50, 24), shift: true);
    expect(tool2.matrix!.a, closeTo(tool2.matrix!.d, 1e-9), reason: 'uniform scale with Shift');
    tool2.cancel();
  });

  test('rotating 90° turns a 20×4 bar into a 4×20 bar', () async {
    final d = _doc([const Rect.fromLTWH(22, 30, 20, 4)]);
    await tool.open();
    // the centre is (32, 32): drag from the right of the box to below it, outside the box
    _drag(tool, d, const Offset(52, 32), const Offset(32, 52), steps: 8);
    tool.confirm();
    final b = (await _plane(d).contentBounds())!;
    expect(b.width, closeTo(4, 1.01));
    expect(b.height, closeTo(20, 1.01));
    expect(b.center.dx, closeTo(32, 1));
  });

  test('flipHorizontal mirrors an asymmetric shape', () async {
    final d = _doc([const Rect.fromLTWH(10, 10, 4, 12), const Rect.fromLTWH(14, 10, 8, 4)]);
    await tool.open();
    tool.flipHorizontal();
    tool.confirm();
    expect(await _alpha(d, 20, 18), greaterThan(128), reason: 'the tall bar is now on the right');
    expect(await _alpha(d, 11, 18), 0);
  });

  test('with a selection only the selected pixels move', () async {
    final d = _doc([const Rect.fromLTWH(4, 4, 8, 8), const Rect.fromLTWH(40, 4, 8, 8)]);
    final mask = TilePlane.empty.drawn((c) => c.drawRect(const Rect.fromLTWH(0, 0, 32, 64), Paint()..color = _white), area: const Rect.fromLTWH(0, 0, 32, 64));
    d.applyComp('sel', (c) => c.copyWith(selection: SelectionMask(mask, const Rect.fromLTWH(0, 0, 32, 64))));
    await tool.open();
    expect(tool.box, const Rect.fromLTWH(4, 4, 8, 8));
    _drag(tool, d, const Offset(8, 8), const Offset(8, 28));
    tool.confirm();
    expect(await _alpha(d, 8, 8), 0);
    expect(await _alpha(d, 8, 28), 255);
    expect(await _alpha(d, 44, 8), 255, reason: 'outside the selection nothing changes');
    expect(d.comp.selection!.bounds.top, closeTo(20, 1e-6), reason: 'the selection follows the pixels');
  });

  test('cancel leaves the document untouched; confirm without changes adds no step', () async {
    final d = _doc([const Rect.fromLTWH(10, 10, 10, 10)]);
    final before = d.project;
    final steps = d.history.index;
    await tool.open();
    _drag(tool, d, const Offset(15, 15), const Offset(30, 30));
    expect(d.live, isNotNull);
    tool.cancel();
    expect(d.live, isNull);
    expect(d.project, same(before));
    await tool.open();
    tool.confirm();
    expect(d.history.index, steps);
    expect(tool.active, isFalse);
  });

  test('vector or locked layers and empty layers are refused', () async {
    final d = _doc([]);
    expect(await tool.open(), isFalse, reason: 'nothing to transform');
    d.addVectorLayer();
    expect(await tool.open(), isFalse);
    expect(tool.active, isFalse);

    final d2 = _doc([const Rect.fromLTWH(10, 10, 10, 10)]);
    d2.updateProps('lock', d2.activeLayerId!, (p) => p.copyWith(locked: true));
    expect(await tool.open(), isFalse);
    expect(d2.live, isNull);
  });

  test('paintOverlay draws with and without an open transform', () async {
    final d = _doc([const Rect.fromLTWH(10, 10, 10, 10)]);
    final rec = PictureRecorder();
    final canvas = Canvas(rec);
    tool.paintOverlay(canvas, const Size(64, 64), d.view);
    await tool.open();
    tool.paintOverlay(canvas, const Size(64, 64), d.view);
    rec.endRecording().dispose();
  });
}
