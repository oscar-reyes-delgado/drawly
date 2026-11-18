import 'dart:ui' as ui;

import 'package:drawly/app/app_state.dart';
import 'package:drawly/app/doc_bones.dart';
import 'package:drawly/app/doc_layers.dart';
import 'package:drawly/app/document_controller.dart';
import 'package:drawly/app/view_state.dart';
import 'package:drawly/engine/tiles.dart';
import 'package:drawly/model/document.dart';
import 'package:drawly/model/layer.dart';
import 'package:drawly/tools/bone_tool.dart';
import 'package:drawly/tools/tool.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter_test/flutter_test.dart';

ToolEvent _ev(
  ui.Offset pos, {
  ViewState view = const ViewState(),
  bool shift = false,
  bool alt = false,
}) =>
    ToolEvent(doc: pos, view: view.toView(pos), shift: shift, alt: alt);

void _drag(
  BoneTool tool,
  ui.Offset from,
  ui.Offset to, {
  int steps = 1,
  bool shift = false,
}) {
  tool.onDown(_ev(from, shift: shift));
  for (var i = 1; i <= steps; i++) {
    final t = i / steps;
    tool.onMove(_ev(ui.Offset.lerp(from, to, t)!, shift: shift));
  }
  tool.onUp(_ev(to, shift: shift));
}

DocumentController _makeDoc({int width = 200, int height = 200, int frames = 12}) {
  final project = Project.blank(width: width, height: height, background: null, frames: frames);
  final doc = AppState.I.addDocument(project, title: 'bone_tool_test');
  // Put the active layer's anchor at origin so layer coordinates match document coordinates unless moved.
  doc.updateProps('reset_xf', doc.activeLayerId!, (p) => p.copyWith(xf: const Xform()));
  doc.history.clear(doc.history.current);
  return doc;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final app = AppState.I;
  late BoneTool tool;
  DocumentController? activeDoc;

  setUp(() {
    tool = BoneTool();
    app.message.value = null;
  });

  tearDown(() {
    tool.onCancel();
    if (activeDoc != null) {
      app.closeDocument(activeDoc!);
      activeDoc = null;
    }
    app.message.value = null;
  });

  test('metadata and active drag lifecycle', () {
    expect(tool.id, 'bones');
    expect(tool.label, isNotEmpty);
    expect(tool.icon, Icons.polyline);
    expect(tool.hint, isNotEmpty);
    expect(tool.active, isFalse);

    final doc = activeDoc = _makeDoc();
    tool.onDown(_ev(const ui.Offset(10, 50)));
    expect(tool.active, isTrue);
    tool.onMove(_ev(const ui.Offset(50, 50)));
    expect(tool.active, isTrue);
    tool.onUp(_ev(const ui.Offset(50, 50)));
    expect(tool.active, isFalse);
    expect((doc.activeLayer! as PaintLayer).rig!.skeleton.bones, hasLength(1));
  });

  test('dragging in empty space creates a bone and snapping near its tip creates a child bone', () {
    final doc = activeDoc = _makeDoc();
    _drag(tool, const ui.Offset(10, 50), const ui.Offset(50, 50));
    _drag(tool, const ui.Offset(51, 50), const ui.Offset(90, 50));

    final rig = (doc.activeLayer! as PaintLayer).rig!;
    expect(rig.skeleton.bones, hasLength(2));
    final first = rig.skeleton.bones[0];
    final second = rig.skeleton.bones[1];
    expect(first.head, const ui.Offset(10, 50));
    expect(first.tail, const ui.Offset(50, 50));
    expect(second.parentId, first.id);
    expect(second.head, const ui.Offset(50, 50));
    expect(second.tail, const ui.Offset(90, 50));
  });

  test('dragging a bone rotates it in one undo step', () {
    final doc = activeDoc = _makeDoc();
    _drag(tool, const ui.Offset(10, 50), const ui.Offset(50, 50));
    _drag(tool, const ui.Offset(51, 50), const ui.Offset(90, 50));

    final layerId = doc.activeLayerId!;
    final secondId = (doc.activeLayer! as PaintLayer).rig!.skeleton.bones[1].id;
    final historyBefore = doc.history.entries.length;

    _drag(tool, const ui.Offset(80, 50), const ui.Offset(50, 80), steps: 4);

    expect(doc.boneRot(layerId, secondId), closeTo(90, 2));
    expect(doc.history.entries.length, historyBefore + 1);

    doc.undo();
    expect(doc.boneRot(layerId, secondId), closeTo(0, 1e-6));
    expect((doc.activeLayer! as PaintLayer).rig!.rot[secondId], isNull);
  });

  test('shift+drag runs IK towards target on the chain', () {
    final doc = activeDoc = _makeDoc();
    _drag(tool, const ui.Offset(10, 50), const ui.Offset(50, 50));
    _drag(tool, const ui.Offset(51, 50), const ui.Offset(90, 50));

    final layerId = doc.activeLayerId!;
    final secondId = (doc.activeLayer! as PaintLayer).rig!.skeleton.bones[1].id;

    _drag(tool, const ui.Offset(70, 50), const ui.Offset(50, 90), steps: 4, shift: true);

    final (_, posedTail) = doc.posedBonesOf(layerId)[secondId]!;
    expect((posedTail - const ui.Offset(50, 90)).distance, lessThan(1));
  });

  test('alt+click on parent bone removes it and its descendants', () {
    final doc = activeDoc = _makeDoc();
    _drag(tool, const ui.Offset(10, 50), const ui.Offset(50, 50));
    _drag(tool, const ui.Offset(51, 50), const ui.Offset(90, 50));
    expect((doc.activeLayer! as PaintLayer).rig!.skeleton.bones, hasLength(2));

    tool.onDown(_ev(const ui.Offset(30, 50), alt: true));
    tool.onUp(_ev(const ui.Offset(30, 50), alt: true));

    expect((doc.activeLayer! as PaintLayer).rig, isNull);
  });

  test('vector layer shows toast without changes and moved paint layer uses layer coordinates', () {
    final doc = activeDoc = _makeDoc();
    doc.addVectorLayer();
    final beforeCount = doc.history.entries.length;
    final beforeProject = doc.project;

    _drag(tool, const ui.Offset(10, 50), const ui.Offset(50, 50));
    expect(tool.active, isFalse);
    expect(app.message.value, isNotNull);
    expect(doc.history.entries.length, beforeCount);
    expect(identical(doc.project, beforeProject), isTrue);

    app.message.value = null;
    doc.addPaintLayer();
    final paintId = doc.activeLayerId!;
    doc.updateProps('move', paintId, (p) => p.copyWith(xf: const Xform(x: 100)));

    _drag(tool, const ui.Offset(110, 50), const ui.Offset(150, 50));
    final bone = (doc.activeLayer! as PaintLayer).rig!.skeleton.bones.single;
    expect(bone.head, const ui.Offset(10, 50));
    expect(bone.tail, const ui.Offset(50, 50));
  });

  test('boneAt finds posed bone and returns null away from it', () {
    final doc = activeDoc = _makeDoc();
    _drag(tool, const ui.Offset(10, 50), const ui.Offset(50, 50));
    final layerId = doc.activeLayerId!;
    final boneId = (doc.activeLayer! as PaintLayer).rig!.skeleton.bones.single.id;

    expect(tool.boneAt(const ui.Offset(30, 50)), boneId);
    expect(tool.boneAt(const ui.Offset(30, 60)), isNull);

    doc.setBoneRots(layerId, {boneId: 90});
    expect(tool.boneAt(const ui.Offset(10, 70)), boneId);
    expect(tool.boneAt(const ui.Offset(30, 50)), isNull);
  });

  test('paintOverlay draws on PictureRecorder without throwing with or without bones', () {
    final doc = activeDoc = _makeDoc();
    const size = ui.Size(200, 200);
    const view = ViewState();

    void paintOnce() {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      tool.paintOverlay(canvas, size, view);
      recorder.endRecording().dispose();
    }

    expect(paintOnce, returnsNormally);

    _drag(tool, const ui.Offset(10, 50), const ui.Offset(50, 50));
    tool.onHover(_ev(const ui.Offset(30, 50)));
    expect(paintOnce, returnsNormally);

    // Mid-creation preview overlay.
    tool.onDown(_ev(const ui.Offset(51, 50)));
    tool.onMove(_ev(const ui.Offset(80, 70)));
    expect(paintOnce, returnsNormally);
    tool.onCancel();
    expect(tool.active, isFalse);
    expect((doc.activeLayer! as PaintLayer).rig!.skeleton.bones, hasLength(1));
  });

  test('guards: sub-1px drag, posed-frame add, editMask, locked layer, and onCancel during rotate', () {
    final doc = activeDoc = _makeDoc();

    // Sub-1px drag creates nothing.
    _drag(tool, const ui.Offset(20, 20), const ui.Offset(20.4, 20.4));
    expect((doc.activeLayer! as PaintLayer).rig, isNull);

    // Create and pose a bone, then try to add a new bone on the posed frame.
    _drag(tool, const ui.Offset(10, 50), const ui.Offset(50, 50));
    final layerId = doc.activeLayerId!;
    final boneId = (doc.activeLayer! as PaintLayer).rig!.skeleton.bones.single.id;
    doc.setBoneRots(layerId, {boneId: 45});
    app.message.value = null;

    _drag(tool, const ui.Offset(120, 120), const ui.Offset(160, 120));
    expect(app.message.value, isNotNull);
    expect((doc.activeLayer! as PaintLayer).rig!.skeleton.bones, hasLength(1));

    // onCancel mid-rotation ends drag while keeping applied rotation.
    tool.onDown(_ev(const ui.Offset(24, 64)));
    tool.onMove(_ev(const ui.Offset(10, 70)));
    expect(tool.active, isTrue);
    expect(doc.boneRot(layerId, boneId), greaterThan(45));
    tool.onCancel();
    expect(tool.active, isFalse);
    expect(doc.boneRot(layerId, boneId), greaterThan(45));

    // editMask blocks bone tool.
    app.message.value = null;
    doc.updateProps('mask', layerId, (p) => p.copyWith(mask: TilePlane.empty));
    doc.editMask = true;
    tool.onDown(_ev(const ui.Offset(10, 50)));
    expect(app.message.value, isNotNull);
    expect(tool.active, isFalse);
    doc.editMask = false;

    // locked layer blocks bone tool.
    app.message.value = null;
    doc.updateProps('lock', layerId, (p) => p.copyWith(locked: true));
    tool.onDown(_ev(const ui.Offset(10, 50)));
    expect(app.message.value, isNotNull);
    expect(tool.active, isFalse);
  });
}
