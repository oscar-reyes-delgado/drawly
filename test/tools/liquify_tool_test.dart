import 'dart:ui';

import 'package:drawly/app/app_state.dart';
import 'package:drawly/app/doc_layers.dart';
import 'package:drawly/app/document_controller.dart';
import 'package:drawly/app/tool_state.dart';
import 'package:drawly/engine/tiles.dart';
import 'package:drawly/model/document.dart';
import 'package:drawly/model/layer.dart';
import 'package:drawly/tools/liquify_tool.dart';
import 'package:drawly/tools/tool.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter_test/flutter_test.dart';

ToolEvent _ev(Offset pos, {bool alt = false}) => ToolEvent(doc: pos, view: pos, alt: alt);

Future<({double centroidX, double centroidY, double alphaArea})> _measureAlpha(TilePlane plane, int size) async {
  final rgba = await plane.readRgba(Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()));
  var sumA = 0.0, sumX = 0.0, sumY = 0.0;
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final a = rgba[(y * size + x) * 4 + 3].toDouble();
      sumA += a;
      sumX += (x + 0.5) * a;
      sumY += (y + 0.5) * a;
    }
  }
  return (
    centroidX: sumA == 0 ? 0.0 : sumX / sumA,
    centroidY: sumA == 0 ? 0.0 : sumY / sumA,
    alphaArea: sumA / 255.0,
  );
}

DocumentController _makeSquareDoc({int size = 64, double squareSize = 8}) {
  final app = AppState.I;
  final project = Project.blank(width: size, height: size, background: null);
  final doc = app.addDocument(project, title: 'liquify_test');
  final half = squareSize / 2;
  final center = size / 2;
  final rect = Rect.fromLTRB(center - half, center - half, center + half, center + half);
  final plane = TilePlane.empty.drawn(
    (c) => c.drawRect(rect, Paint()..color = const Color(0xFFFFFFFF)),
    area: rect,
  );
  final layer = doc.activeLayer! as PaintLayer;
  doc.updateLayer('init', layer.id, (l) => (l as PaintLayer).withCels(CelTrack.single(plane)));
  doc.history.clear(doc.history.current);
  return doc;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final app = AppState.I;
  late LiquifyTool tool;
  DocumentController? activeDoc;

  setUp(() {
    tool = LiquifyTool();
    app.message.value = null;
    app.ts
      ..liquifyMode = LiquifyMode.push
      ..liquifySize = 40
      ..liquifyStrength = 1.0;
  });

  tearDown(() {
    tool.onCancel();
    if (activeDoc != null) {
      app.closeDocument(activeDoc!);
      activeDoc = null;
    }
    app.message.value = null;
  });

  test('metadata and active state track drag lifecycle', () {
    expect(tool.id, 'liquify');
    expect(tool.label, isNotEmpty);
    expect(tool.icon, Icons.water_drop_outlined);
    expect(tool.shortcut, 'Shift+W');
    expect(tool.hint, isNotEmpty);
    expect(tool.brushCursorSize, 40);
    expect(tool.active, isFalse);

    final doc = activeDoc = _makeSquareDoc();
    tool.onDown(_ev(const Offset(28, 32)));
    expect(tool.active, isTrue);
    expect(doc.live, isNull);

    tool.onMove(_ev(const Offset(34, 32)));
    expect(tool.active, isTrue);
    expect(doc.live, isNotNull);

    tool.onUp(_ev(const Offset(34, 32)));
    expect(tool.active, isFalse);
    expect(doc.live, isNull);
  });

  test('push shifts alpha centroid right and undo restores it', () async {
    final doc = activeDoc = _makeSquareDoc();
    final beforePlane = (doc.activeLayer! as PaintLayer).cels.at(0)!;
    final before = await _measureAlpha(beforePlane, 64);

    app.ts
      ..liquifyMode = LiquifyMode.push
      ..liquifySize = 40
      ..liquifyStrength = 1.0;

    tool.onDown(_ev(const Offset(28, 32)));
    for (var i = 1; i <= 6; i++) {
      final x = 28.0 + (40.0 - 28.0) * (i / 6);
      tool.onMove(_ev(Offset(x, 32)));
    }
    tool.onUp(_ev(const Offset(40, 32)));

    expect(doc.live, isNull);
    expect(doc.history.canUndo, isTrue);

    final afterPlane = (doc.activeLayer! as PaintLayer).cels.at(0)!;
    final after = await _measureAlpha(afterPlane, 64);
    expect(after.centroidX - before.centroidX, inInclusiveRange(2.0, 12.0));

    doc.undo();
    final undonePlane = (doc.activeLayer! as PaintLayer).cels.at(0)!;
    final undone = await _measureAlpha(undonePlane, 64);
    expect((undone.centroidX - before.centroidX).abs(), lessThanOrEqualTo(0.5));
  });

  test('down and up at the same point does not add history step', () {
    final doc = activeDoc = _makeSquareDoc();
    final beforeCount = doc.history.entries.length;

    tool.onDown(_ev(const Offset(32, 32)));
    tool.onMove(_ev(const Offset(32, 32)));
    tool.onUp(_ev(const Offset(32, 32)));

    expect(doc.history.entries.length, beforeCount);
    expect(doc.history.canUndo, isFalse);
    expect(doc.live, isNull);
  });

  test('onCancel mid-drag leaves document untouched and clears live edit', () async {
    final doc = activeDoc = _makeSquareDoc();
    final beforeCount = doc.history.entries.length;
    final beforeProj = doc.project;

    tool.onDown(_ev(const Offset(28, 32)));
    tool.onMove(_ev(const Offset(36, 32)));
    expect(doc.live, isNotNull);

    tool.onCancel();
    expect(tool.active, isFalse);
    expect(doc.live, isNull);
    expect(doc.history.entries.length, beforeCount);
    expect(identical(doc.project, beforeProj), isTrue);
  });

  test('vector layer shows warning and makes no changes', () {
    final doc = activeDoc = _makeSquareDoc();
    doc.addVectorLayer();
    final beforeCount = doc.history.entries.length;
    final beforeProj = doc.project;

    tool.onDown(_ev(const Offset(32, 32)));
    expect(tool.active, isFalse);
    expect(app.message.value, isNotNull);
    expect(doc.history.entries.length, beforeCount);
    expect(identical(doc.project, beforeProj), isTrue);
  });

  test('transformed layer shows warning and makes no changes', () {
    final doc = activeDoc = _makeSquareDoc();
    doc.updateProps('move', doc.activeLayerId!, (p) => p.copyWith(xf: p.xf.copyWith(x: 5)));
    final beforeCount = doc.history.entries.length;
    final beforeProj = doc.project;

    tool.onDown(_ev(const Offset(32, 32)));
    expect(tool.active, isFalse);
    expect(app.message.value, isNotNull);
    expect(doc.history.entries.length, beforeCount);
    expect(identical(doc.project, beforeProj), isTrue);
  });

  test('bloat increases alpha area and pinch decreases alpha area', () async {
    final doc = activeDoc = _makeSquareDoc();
    final basePlane = (doc.activeLayer! as PaintLayer).cels.at(0)!;
    final base = await _measureAlpha(basePlane, 64);

    app.ts
      ..liquifyMode = LiquifyMode.bloat
      ..liquifySize = 40
      ..liquifyStrength = 1.0;
    tool.onDown(_ev(const Offset(32, 32)));
    tool.onMove(_ev(const Offset(32, 32)));
    tool.onUp(_ev(const Offset(32, 32)));

    final bloatedPlane = (doc.activeLayer! as PaintLayer).cels.at(0)!;
    final bloated = await _measureAlpha(bloatedPlane, 64);
    expect(bloated.alphaArea, greaterThan(base.alphaArea));

    doc.undo();
    app.ts.liquifyMode = LiquifyMode.pinch;
    tool.onDown(_ev(const Offset(32, 32)));
    tool.onMove(_ev(const Offset(32, 32)));
    tool.onUp(_ev(const Offset(32, 32)));

    final pinchedPlane = (doc.activeLayer! as PaintLayer).cels.at(0)!;
    final pinched = await _measureAlpha(pinchedPlane, 64);
    expect(pinched.alphaArea, lessThan(base.alphaArea));
  });

  test('twirl with alt reverses direction and restore reduces deformation', () async {
    final doc = activeDoc = _makeSquareDoc();
    final basePlane = (doc.activeLayer! as PaintLayer).cels.at(0)!;
    final base = await _measureAlpha(basePlane, 64);

    app.ts
      ..liquifyMode = LiquifyMode.push
      ..liquifySize = 40
      ..liquifyStrength = 1.0;

    tool.onDown(_ev(const Offset(28, 32)));
    tool.onMove(_ev(const Offset(38, 32)));
    app.ts.liquifyMode = LiquifyMode.restore;
    tool.onMove(_ev(const Offset(38, 32)));
    tool.onUp(_ev(const Offset(38, 32)));

    final restoredPlane = (doc.activeLayer! as PaintLayer).cels.at(0)!;
    final restored = await _measureAlpha(restoredPlane, 64);
    expect((restored.centroidX - base.centroidX).abs(), lessThan(1.0));

    doc.undo();
    app.ts
      ..liquifyMode = LiquifyMode.twirl
      ..liquifyStrength = 1.0;
    tool.onDown(_ev(const Offset(24, 32)));
    tool.onMove(_ev(const Offset(24, 32)));
    tool.onUp(_ev(const Offset(24, 32)));
    final twirledFwd = await _measureAlpha((doc.activeLayer! as PaintLayer).cels.at(0)!, 64);
    expect((twirledFwd.centroidY - base.centroidY).abs(), greaterThan(0.1));

    doc.undo();
    tool.onDown(_ev(const Offset(24, 32), alt: true));
    tool.onMove(_ev(const Offset(24, 32), alt: true));
    tool.onUp(_ev(const Offset(24, 32), alt: true));
    final twirledRev = await _measureAlpha((doc.activeLayer! as PaintLayer).cels.at(0)!, 64);
    expect((twirledRev.centroidY - base.centroidY) * (twirledFwd.centroidY - base.centroidY), lessThan(0));
  });

  test('preview is throttled to 30 ms and refreshes afterwards', () async {
    final doc = activeDoc = _makeSquareDoc();
    tool.onDown(_ev(const Offset(28, 32)));
    tool.onMove(_ev(const Offset(30, 32)));
    final firstLive = doc.live;
    expect(firstLive, isNotNull);

    tool.onMove(_ev(const Offset(32, 32)));
    expect(identical(doc.live, firstLive), isTrue);

    await Future<void>.delayed(const Duration(milliseconds: 40));
    tool.onMove(_ev(const Offset(36, 32)));
    expect(identical(doc.live, firstLive), isFalse);

    tool.onUp(_ev(const Offset(36, 32)));
    expect(doc.live, isNull);
  });

  test('liquifies layer mask when editMask is enabled', () async {
    final doc = activeDoc = _makeSquareDoc();
    const maskRect = Rect.fromLTRB(28, 28, 36, 36);
    final mask = TilePlane.empty.drawn(
      (c) => c.drawRect(maskRect, Paint()..color = const Color(0xFFFFFFFF)),
      area: maskRect,
    );
    final layer = doc.activeLayer! as PaintLayer;
    doc.updateProps('addMask', layer.id, (p) => p.copyWith(mask: mask));
    doc.editMask = true;

    final beforeMask = await _measureAlpha(doc.activeLayer!.props.mask!, 64);
    final beforePaint = (doc.activeLayer! as PaintLayer).cels.at(0)!;

    tool.onDown(_ev(const Offset(28, 32)));
    for (var i = 1; i <= 6; i++) {
      tool.onMove(_ev(Offset(28.0 + 12.0 * (i / 6), 32)));
    }
    tool.onUp(_ev(const Offset(40, 32)));

    final afterMask = await _measureAlpha(doc.activeLayer!.props.mask!, 64);
    final afterPaint = (doc.activeLayer! as PaintLayer).cels.at(0)!;
    expect(afterMask.centroidX - beforeMask.centroidX, inInclusiveRange(2.0, 12.0));
    expect(identical(afterPaint, beforePaint), isTrue);
  });
}
