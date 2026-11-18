import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:drawly/app/app_state.dart';
import 'package:drawly/app/doc_layers.dart';
import 'package:drawly/app/doc_tracking.dart';
import 'package:drawly/app/document_controller.dart';
import 'package:drawly/app/view_state.dart';
import 'package:drawly/engine/compositor.dart';
import 'package:drawly/engine/tiles.dart';
import 'package:drawly/model/anim.dart';
import 'package:drawly/model/document.dart';
import 'package:drawly/model/layer.dart';
import 'package:drawly/tools/tool.dart';
import 'package:drawly/tools/track_tool.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter_test/flutter_test.dart';

Future<TilePlane> _noisePlane(int width, int height, {int seed = 1, int minV = 0, int maxV = 40}) async {
  final rng = math.Random(seed);
  final rgba = Uint8List(width * height * 4);
  final span = maxV - minV + 1;
  for (var i = 0; i < width * height; i++) {
    final g = minV + rng.nextInt(span);
    final o = i * 4;
    rgba[o] = g;
    rgba[o + 1] = g;
    rgba[o + 2] = g;
    rgba[o + 3] = 255;
  }
  return TilePlane.fromRgba(rgba, width, height);
}

Future<TilePlane> _texturedSquarePlane(int x, int y, int size, {int seed = 7}) async {
  final rng = math.Random(seed);
  final rgba = Uint8List(size * size * 4);
  for (var i = 0; i < size * size; i++) {
    final g = 140 + rng.nextInt(116);
    final o = i * 4;
    rgba[o] = g;
    rgba[o + 1] = g;
    rgba[o + 2] = g;
    rgba[o + 3] = 255;
  }
  return TilePlane.fromRgba(rgba, size, size, origin: Offset(x.toDouble(), y.toDouble()));
}

Future<DocumentController> _makeTrackingScene() async {
  final bgPlane = await _noisePlane(128, 96, seed: 1, minV: 0, maxV: 40);
  final sqPlane = await _texturedSquarePlane(20, 20, 16, seed: 7);

  final bgLayer = PaintLayer.create('bg', pixels: bgPlane);
  final tracks = <Prop, AnimTrack>{
    Prop.x: AnimTrack([for (var f = 0; f < 8; f++) AnimKey(f, f * 4.0, Ease.linear)]),
    Prop.y: AnimTrack([for (var f = 0; f < 8; f++) AnimKey(f, f * 2.0, Ease.linear)]),
  };
  final sqLayer = PaintLayer.create('target', pixels: sqPlane).withProps(
    LayerProps(name: 'target', xf: const Xform(ax: 28, ay: 28), tracks: tracks),
  );

  final base = Project.blank(width: 128, height: 96, frames: 8, background: const Color(0xFF000000));
  final comp = base.main.copyWith(layers: [bgLayer, sqLayer]);
  final project = base.withComp(comp);
  return DocumentController(project, title: 'track');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final app = AppState.I;
  DocumentController? activeDoc;

  tearDown(() {
    if (activeDoc != null) {
      app.closeDocument(activeDoc!);
      activeDoc = null;
    }
    app.message.value = null;
  });

  test('trackFromCurrentFrame follows a moving textured 16x16 square over noisy background', () async {
    final d = await _makeTrackingScene();
    final progress = <double>[];
    final path = await d.trackFromCurrentFrame(const Offset(28, 28), onProgress: progress.add);

    expect(path, hasLength(8));
    expect(path.first, const Offset(28, 28));
    expect(progress.last, closeTo(1.0, 1e-9));
    for (var f = 0; f < 8; f++) {
      final expected = Offset(28 + f * 4.0, 28 + f * 2.0);
      expect((path[f] - expected).distance, lessThanOrEqualTo(2.0), reason: 'frame $f');
    }
  });

  test('applyTrackToLayer writes 8 linear X/Y keys and undo reverts in one step', () async {
    final d = await _makeTrackingScene();
    d.addPaintLayer(name: 'follower');
    final followerId = d.activeLayerId!;
    d.updateProps('init pos', followerId, (p) => p.copyWith(xf: const Xform(x: 10, y: 5, ax: 64, ay: 48)));
    d.history.clear(d.history.current);

    final path = [for (var f = 0; f < 8; f++) Offset(28 + f * 4.0, 28 + f * 2.0)];
    final written = d.applyTrackToLayer(followerId, path);
    expect(written, 8);

    final props = d.comp.layer(followerId)!.props;
    expect(props.tracks[Prop.x]!.keys, hasLength(8));
    expect(props.tracks[Prop.y]!.keys, hasLength(8));
    expect(props.valueAt(Prop.x, 5) - 10.0, closeTo(20.0, 2.0));
    expect(props.valueAt(Prop.y, 5) - 5.0, closeTo(10.0, 2.0));

    d.undo();
    final reverted = d.comp.layer(followerId)!.props;
    expect(reverted.tracks[Prop.x], isNull);
    expect(reverted.tracks[Prop.y], isNull);
  });

  test('excludeLayerId omits the excluded layer from rendered frames', () async {
    final bgPlane = await _noisePlane(128, 96, seed: 1, minV: 0, maxV: 40);
    final sqPlane = await _texturedSquarePlane(20, 20, 16, seed: 7);
    final redPlane = TilePlane.empty.drawn(
      (c) => c.drawRect(const Rect.fromLTWH(20, 20, 16, 16), Paint()..color = const Color(0xFFFF0000)),
      area: const Rect.fromLTWH(20, 20, 16, 16),
    );

    final bgLayer = PaintLayer.create('bg', pixels: bgPlane);
    final redMoving = PaintLayer.create('red', pixels: redPlane).withProps(
      LayerProps(
        name: 'red',
        tracks: {
          Prop.x: AnimTrack([for (var f = 0; f < 8; f++) AnimKey(f, f * 4.0, Ease.linear)]),
          Prop.y: AnimTrack([for (var f = 0; f < 8; f++) AnimKey(f, f * 2.0, Ease.linear)]),
        },
      ),
    );
    final base = Project.blank(width: 128, height: 96, frames: 8, background: const Color(0xFF000000));
    final comp = base.main.copyWith(layers: [bgLayer, redMoving]);
    final d = DocumentController(base.withComp(comp), title: 'exclude');

    // Verify rendered image omits red pixel when hidden
    final img = renderCompImage(
      d.project,
      d.comp,
      0,
      scale: 1,
      background: true,
      forExport: true,
      useCamera: false,
      hidden: {redMoving.id},
    );
    try {
      final rgba = await imageToRgba(img, straight: true);
      final idx = (28 * 128 + 28) * 4;
      expect(rgba[idx] == 255 && rgba[idx + 1] == 0 && rgba[idx + 2] == 0, isFalse);
    } finally {
      img.dispose();
    }

    // Verify trackFromCurrentFrame ignores excluded moving layer (stays near start)
    final sqMoving = PaintLayer.create('sq', pixels: sqPlane).withProps(redMoving.props);
    final d2 = DocumentController(base.withComp(base.main.copyWith(layers: [bgLayer, sqMoving])), title: 'exclude2');
    final trackedExcluded = await d2.trackFromCurrentFrame(const Offset(28, 28), excludeLayerId: sqMoving.id);
    expect((trackedExcluded.last - const Offset(28, 28)).distance, lessThanOrEqualTo(1.5));
  });

  test('TrackTool without active layer shows toast and changes nothing', () async {
    final tool = TrackTool();
    expect(tool.id, 'track');
    expect(tool.label, isNotEmpty);
    expect(tool.icon, Icons.my_location);
    expect(tool.shortcut, '');

    final project = Project.blank(width: 64, height: 64);
    final d = activeDoc = app.addDocument(project.withComp(project.main.copyWith(layers: const [])), title: 'empty');
    expect(d.activeLayer, isNull);
    expect(d.history.canUndo, isFalse);

    const ev = ToolEvent(doc: Offset(32, 32), view: Offset(32, 32));
    tool.onDown(ev);
    tool.onUp(ev);

    expect(app.message.value, isNotNull);
    expect(d.history.canUndo, isFalse);
    expect(d.isBusy, isFalse);
  });

  test('TrackTool tracks and animates active layer on click and paints overlay', () async {
    final d0 = await _makeTrackingScene();
    final follower = PaintLayer.create('follower');
    final compWithFollower = d0.comp.copyWith(layers: [...d0.comp.layers, follower]);
    final d = activeDoc = app.addDocument(d0.project.withComp(compWithFollower), title: 'tool_track');
    expect(d.activeLayerId, follower.id);

    final tool = TrackTool();
    const ev = ToolEvent(doc: Offset(28, 28), view: Offset(28, 28));
    tool.onDown(ev);
    expect(tool.active, isTrue);
    tool.onUp(ev);
    expect(tool.active, isFalse);

    while (d.isBusy) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    final props = d.comp.layer(follower.id)!.props;
    expect(props.tracks[Prop.x]?.keys, hasLength(8));
    expect(props.tracks[Prop.y]?.keys, hasLength(8));
    expect(props.valueAt(Prop.x, 5), closeTo(20.0, 2.0));
    expect(props.valueAt(Prop.y, 5), closeTo(10.0, 2.0));
    expect(app.message.value, contains('8'));

    final rec = PictureRecorder();
    final canvas = Canvas(rec, const Rect.fromLTWH(0, 0, 128, 96));
    tool.paintOverlay(canvas, const Size(128, 96), const ViewState(pan: Offset(10, 20), zoom: 2));
    final pic = rec.endRecording();
    pic.dispose();
  });

  test('trackFromCurrentFrame respects current frame and maxFrames', () async {
    final d = await _makeTrackingScene();
    d.frame = 3;
    final from3 = await d.trackFromCurrentFrame(const Offset(40, 34));
    expect(from3, hasLength(5));
    expect(from3.first, const Offset(40, 34));
    for (var i = 0; i < from3.length; i++) {
      final expected = Offset(40 + i * 4.0, 34 + i * 2.0);
      expect((from3[i] - expected).distance, lessThanOrEqualTo(2.0), reason: 'offset $i');
    }

    final capped = await d.trackFromCurrentFrame(const Offset(40, 34), maxFrames: 3);
    expect(capped, hasLength(3));
  });

  test('applyTrackToLayer replaces keys only within tracked range and preserves outside keys', () async {
    final d = await _makeTrackingScene();
    d.addPaintLayer(name: 'follower');
    final id = d.activeLayerId!;
    d.updateProps(
      'seed keys',
      id,
      (p) => p.copyWith(
        tracks: {
          Prop.x: AnimTrack(const [AnimKey(0, 100), AnimKey(2, 50), AnimKey(7, 200)]),
          Prop.y: AnimTrack(const [AnimKey(0, 10, Ease.linear), AnimKey(3, 70, Ease.linear), AnimKey(7, 300, Ease.linear)]),
        },
      ),
    );
    d.frame = 2;
    final written = d.applyTrackToLayer(id, const [Offset(10, 10), Offset(15, 20), Offset(22, 30)]);
    expect(written, 3);

    final props = d.comp.layer(id)!.props;
    final xTrack = props.tracks[Prop.x]!;
    final yTrack = props.tracks[Prop.y]!;
    expect(xTrack.keyAt(0)?.value, 100);
    expect(xTrack.keyAt(2)?.value, 50);
    expect(xTrack.keyAt(3)?.value, 55);
    expect(xTrack.keyAt(4)?.value, 62);
    expect(xTrack.keyAt(7)?.value, 200);
    expect(yTrack.keyAt(0)?.value, 10);
    expect(yTrack.keyAt(2)?.value, closeTo(50, 1e-9));
    expect(yTrack.keyAt(3)?.value, closeTo(60, 1e-9));
    expect(yTrack.keyAt(4)?.value, closeTo(70, 1e-9));
    expect(yTrack.keyAt(7)?.value, 300);
  });

  test('TrackTool ignores drags, cancellation and locked layers', () async {
    final d0 = await _makeTrackingScene();
    final d = activeDoc = app.addDocument(d0.project, title: 'guards');
    final tool = TrackTool();

    // Drag > 4 px does nothing
    tool.onDown(const ToolEvent(doc: Offset(28, 28), view: Offset(28, 28)));
    tool.onMove(const ToolEvent(doc: Offset(40, 28), view: Offset(40, 28)));
    tool.onUp(const ToolEvent(doc: Offset(40, 28), view: Offset(40, 28)));
    expect(d.isBusy, isFalse);
    expect(d.history.canUndo, isFalse);

    // Cancel before up does nothing
    tool.onDown(const ToolEvent(doc: Offset(28, 28), view: Offset(28, 28)));
    tool.onCancel();
    expect(tool.active, isFalse);
    tool.onUp(const ToolEvent(doc: Offset(28, 28), view: Offset(28, 28)));
    expect(d.isBusy, isFalse);
    expect(d.history.canUndo, isFalse);

    // Locked layer shows toast and does not mutate
    d.updateProps('lock', d.activeLayerId!, (p) => p.copyWith(lockPosition: true));
    d.history.clear(d.history.current);
    tool.onDown(const ToolEvent(doc: Offset(28, 28), view: Offset(28, 28)));
    tool.onUp(const ToolEvent(doc: Offset(28, 28), view: Offset(28, 28)));
    expect(app.message.value, isNotNull);
    expect(d.isBusy, isFalse);
    expect(d.history.canUndo, isFalse);
  });
}
