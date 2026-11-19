import 'dart:ui';

import 'package:drawly/app/doc_frames.dart';
import 'package:drawly/app/document_controller.dart';
import 'package:drawly/engine/rig.dart';
import 'package:drawly/engine/tiles.dart';
import 'package:drawly/model/anim.dart';
import 'package:drawly/model/document.dart';
import 'package:drawly/model/layer.dart';
import 'package:drawly/model/specs.dart';
import 'package:drawly/model/vector.dart';
import 'package:flutter_test/flutter_test.dart';

TilePlane _solid(int argb) {
  const r = Rect.fromLTWH(8, 8, 16, 16);
  final plane = TilePlane.empty.drawn((c) => c.drawRect(r, Paint()..color = Color(argb)), area: r);
  addTearDown(() {
    for (final key in plane.keys) {
      plane[key]!.dispose();
    }
  });
  return plane;
}

CelTrack<T> _track<T>(List<T> contents, {List<int>? frames}) => CelTrack<T>(
      drawings: {for (var i = 0; i < contents.length; i++) i + 1: contents[i]},
      xs: [for (var i = 0; i < contents.length; i++) Exposure(frames?[i] ?? i, i + 1)],
    );

DocumentController _doc(List<Layer> layers, {int length = 3, Timeline? timeline}) {
  final p = Project.blank(width: 64, height: 64);
  final d = DocumentController(p.withComp(p.main.copyWith(layers: layers, timeline: timeline ?? Timeline(length: length))), title: 't');
  addTearDown(d.dispose);
  return d;
}

DocumentController _abc({int length = 3, List<int>? frames, LayerProps props = const LayerProps(name: 'Dibujo')}) {
  final contents = [for (final color in [0xFFFF0000, 0xFF00FF00, 0xFF0000FF, 0xFFFFFF00]) _solid(color)];
  return _doc([
    PaintLayer('bg', const LayerProps(name: 'Fondo'), CelTrack.single(contents.last)),
    PaintLayer('paint', props, _track(contents.take(frames?.length ?? length).toList(), frames: frames)),
  ], length: length);
}

CelTrack<TilePlane> _paint(DocumentController d, [String id = 'paint']) => (d.comp.layer(id)! as PaintLayer).cels;
List<int?> _ids(CelTrack<Object> t, int length) => List.generate(length, t.drawingIdAt);
List<Object?> _contents(CelTrack<Object> t, int length) => List.generate(length, t.at);

void _sameContents(CelTrack<Object> actual, List<Object?> expected) {
  for (var i = 0; i < expected.length; i++) {
    expect(actual.at(i), same(expected[i]), reason: 'column $i');
  }
}

void _undo(DocumentController d, Project before, int index) {
  expect(d.history.index, index + 1);
  final after = d.project;
  d.undo();
  expect(d.project, same(before));
  d.redo();
  expect(d.project, same(after));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => FrameColumnClipboard.frames = const []);
  tearDown(() => FrameColumnClipboard.frames = const []);

  test('insert blanks on animated layers, keep the static background and undo once', () {
    final d = _abc();
    final before = d.project, bg = _paint(d, 'bg'), original = _paint(d);
    d.insertFrames(after: 0);
    final result = _paint(d);
    expect(d.frameCount, 4);
    expect(d.frame, 1);
    _sameContents(result, [original.at(0), TilePlane.empty, original.at(1), original.at(2)]);
    expect(result.drawingIdAt(1), isNot(isIn(original.drawings.keys)));
    expect(_paint(d, 'bg'), same(bg));
    expect(bg.xs, hasLength(1));
    expect(bg.drawings, hasLength(1));
    _undo(d, before, 0);
  });

  test('duplicate shares immutable content but allocates an independent id', () {
    final d = _abc();
    final before = d.project, original = _paint(d);
    d.duplicateFrame(1);
    final result = _paint(d);
    _sameContents(result, [original.at(0), original.at(1), original.at(1), original.at(2)]);
    expect(result.drawingIdAt(2), isNot(result.drawingIdAt(1)));
    expect(d.frame, 2);
    expect(d.frameCount, 4);
    _undo(d, before, 0);
    final copyId = result.drawingIdAt(2)!;
    d.updateLayer('Draw on copy', 'paint', (l) => (l as PaintLayer).withCels(l.cels.withDrawing(copyId, TilePlane.empty)));
    expect(_paint(d).at(1), same(original.at(1)));
    expect(_paint(d).at(2), same(TilePlane.empty));
  });

  test('delete columns prunes drawings and drops or shifts property keys', () {
    const props = LayerProps(tracks: {Prop.x: AnimTrack([AnimKey(0, 0), AnimKey(2, 20), AnimKey(3, 30)])});
    final d = _abc(length: 4, props: props);
    final before = d.project, original = _paint(d);
    d.frame = 3;
    d.deleteFrames(1, 3);
    expect(d.frameCount, 2);
    expect(d.frame, 1);
    _sameContents(_paint(d), [original.at(0), original.at(3)]);
    expect(_paint(d).drawings.keys, [1, 4]);
    final keys = d.comp.layer('paint')!.props.tracks[Prop.x]!.keys;
    expect(keys.map((k) => k.frame), [0, 1]);
    expect(keys.map((k) => k.value), [0, 30]);
    _undo(d, before, 0);
  });

  test('move uses original insertion boundaries and self moves are history-free', () {
    final d = _abc();
    final before = d.project, original = _paint(d);
    d.moveFrames(0, 1, 3);
    _sameContents(_paint(d), [original.at(1), original.at(2), original.at(0)]);
    expect(d.frameCount, 3);
    _undo(d, before, 0);
    final after = d.project, index = d.history.index;
    d.moveFrames(1, 2, 1);
    d.moveFrames(0, 2, 1);
    d.moveFrames(0, 2, 2);
    expect(d.project, same(after));
    expect(d.history.index, index);
    d.moveFrames(2, 3, 0);
    _sameContents(_paint(d), _contents(original, 3));
  });

  test('inserting in a hold restores its original id after the new blank', () {
    final d = _abc(length: 6, frames: [0, 3]);
    final original = _paint(d);
    d.insertFrames(after: 1);
    final result = _paint(d), blank = _paint(d).drawingIdAt(2);
    expect(d.frameCount, 7);
    expect(_ids(result, 7), [1, 1, blank, 1, 2, 2, 2]);
    expect(blank, isNot(isIn(original.drawings.keys)));
    expect(result.at(2), same(TilePlane.empty));
    expect(result.xs.map((x) => x.frame), [0, 2, 3, 4]);
    expect(result.at(3), same(original.at(0)));
  });

  test('copy and paste insert columns with new ids and one undo step', () {
    final d = _abc();
    final before = d.project, original = _paint(d), bg = _paint(d, 'bg');
    d.copyFrames(0, 2);
    expect(d.project, same(before));
    expect(d.history.index, 0);
    expect(FrameColumnClipboard.frames[0]['paint'], same(original.at(0)));
    d.pasteFrames(after: 2);
    final result = _paint(d);
    expect(d.frameCount, 5);
    expect(d.frame, 3);
    _sameContents(result, [original.at(0), original.at(1), original.at(2), original.at(0), original.at(1)]);
    expect(_ids(result, 5).toSet(), hasLength(5));
    expect(_paint(d, 'bg'), same(bg));
    _undo(d, before, 0);
  });

  test('reverse reorders every column, including partial holds', () {
    final d = _abc();
    final before = d.project, original = _paint(d);
    d.reverseFrameRange(0, 3);
    _sameContents(_paint(d), [original.at(2), original.at(1), original.at(0)]);
    _undo(d, before, 0);
    final held = _abc(length: 6, frames: [0, 3]);
    held.reverseFrameRange(1, 5);
    expect(_ids(_paint(held), 6), [1, 2, 2, 1, 1, 2]);
    expect(_paint(held).xs.map((e) => e.frame), [0, 1, 3, 5]);
  });

  test('insert recurses into nested groups and shifts tracks on non-cel layers', () {
    const props = LayerProps(tracks: {Prop.opacity: AnimTrack([AnimKey(0, 1), AnimKey(2, 0.5)])});
    final a = _solid(0xFFFF0000), b = _solid(0xFF0000FF);
    final d = _doc([
      const TextLayer('text', props, TextSpec()),
      GroupLayer('group', props, [GroupLayer('inner', const LayerProps(), [PaintLayer('paint', const LayerProps(), _track([a, b], frames: [0, 2]))])]),
    ]);
    d.insertFrames(after: 0);
    _sameContents(_paint(d), [a, TilePlane.empty, a, b]);
    for (final id in ['text', 'group']) {
      expect(d.comp.layer(id)!.props.tracks[Prop.opacity]!.keys.map((k) => k.frame), [0, 3]);
    }
  });

  test('animation detection follows exposures rather than properties or contents', () {
    final d = _abc();
    expect(d.isAnimatedLayer(d.comp.layer('paint')!), isTrue);
    expect(d.isAnimatedLayer(d.comp.layer('bg')!), isFalse);
    const props = LayerProps(tracks: {Prop.x: AnimTrack([AnimKey(0, 1), AnimKey(1, 2)])});
    expect(d.isAnimatedLayer(PaintLayer('static', props, CelTrack.single(TilePlane.empty))), isFalse);
    expect(d.isAnimatedLayer(const PaintLayer('empty', props, CelTrack(drawings: {}, xs: []))), isFalse);
    expect(d.isAnimatedLayer(const PaintLayer('delayed', props, CelTrack(drawings: {}, xs: [Exposure(2, 0)]))), isTrue);
    expect(d.isAnimatedLayer(const VectorLayer('v', props, CelTrack(drawings: {}, xs: [Exposure(0, 0), Exposure(1, 0)]))), isTrue);
    expect(d.isAnimatedLayer(const TextLayer('t', props, TextSpec())), isFalse);
    expect(d.isAnimatedLayer(const GroupLayer('g', props, [])), isFalse);
  });

  test('the active static layer gets separate blank drawings for each insertion', () {
    for (final vector in [false, true]) {
      final Layer active = vector
          ? VectorLayer('active', const LayerProps(), CelTrack.single(VectorArt([VShape(paths: [VPath.rect(const Rect.fromLTWH(0, 0, 4, 4))])])))
          : PaintLayer('active', const LayerProps(), CelTrack.single(_solid(0xFFFF0000)));
      final d = _doc([active]);
      d.frame = 0;
      d.insertFrames(count: 2);
      final layer = d.activeLayer!;
      final CelTrack<Object> track = layer is PaintLayer ? layer.cels : (layer as VectorLayer).cels;
      expect(_ids(track, 5), [1, 2, 3, 1, 1]);
      expect(track.at(1), same(vector ? VectorArt.empty : TilePlane.empty));
      expect(track.at(2), same(track.at(1)));
    }
  });

  test('vector columns support duplicate, clipboard, delete, move and reverse', () {
    final a = VectorArt([VShape(paths: [VPath.rect(const Rect.fromLTWH(0, 0, 4, 4))])]);
    final b = VectorArt([VShape(paths: [VPath.rect(const Rect.fromLTWH(8, 0, 4, 4))])]);
    final d = _doc([VectorLayer('v', const LayerProps(), _track([a, b]))], length: 2);
    CelTrack<VectorArt> track() => (d.activeLayer! as VectorLayer).cels;
    d.duplicateFrame(0);
    _sameContents(track(), [a, a, b]);
    expect(_ids(track(), 3), [1, 3, 2]);
    d.copyFrames(0, 2);
    d.pasteFrames(after: 2);
    _sameContents(track(), [a, a, b, a, a]);
    expect(_ids(track(), 5).toSet(), hasLength(5));
    d.deleteFrames(0, 2);
    _sameContents(track(), [b, a, a]);
    d.moveFrames(0, 1, 3);
    _sameContents(track(), [a, a, b]);
    d.reverseFrameRange(0, 3);
    _sameContents(track(), [b, a, a]);
  });

  test('camera, markers, loop endpoints and bone keys follow inserted/deleted columns', () {
    const keys = AnimTrack([AnimKey(0, 0), AnimKey(1, 10), AnimKey(3, 30)]);
    const rig = LayerRig(skeleton: Skeleton([Bone(id: 'b', head: Offset.zero, tail: Offset(10, 0))]), rot: {'b': keys});
    final a = _solid(0xFFFF0000), b = _solid(0xFF0000FF);
    final d = _doc([
      PaintLayer('paint', const LayerProps(tracks: {Prop.x: keys}), _track([a, b], frames: [0, 3]), rig: rig),
    ], timeline: const Timeline(length: 4, loopStart: 1, loopEnd: 4, markers: [Marker(0, 'a'), Marker(1, 'b'), Marker(3, 'c', 0xFF123456)], camera: Camera(tracks: {Prop.x: keys})));
    d.insertFrames(after: 0, count: 2);
    expect(d.timeline.markers.map((m) => m.frame), [0, 3, 5]);
    expect(d.timeline.loopStart, 3);
    expect(d.timeline.loopEnd, 6);
    expect(d.timeline.camera.tracks[Prop.x]!.keys.map((k) => k.frame), [0, 3, 5]);
    expect((d.activeLayer! as PaintLayer).rig!.rot['b']!.keys.map((k) => k.frame), [0, 3, 5]);
    d.deleteFrames(1, 4);
    expect(d.timeline.markers.map((m) => m.frame), [0, 2]);
    expect(d.timeline.markers.last.label, 'c');
    expect(d.timeline.markers.last.color, 0xFF123456);
    expect(d.timeline.loopStart, isNull);
    expect(d.timeline.loopEnd, 3);
    expect(d.timeline.camera.tracks[Prop.x]!.keys.map((k) => k.frame), [0, 2]);
    expect((d.activeLayer! as PaintLayer).rig!.rot['b']!.keys.map((k) => k.frame), [0, 2]);
  });

  test('duplicate and paste shift timing while move/reverse leave it untouched', () {
    const props = LayerProps(tracks: {Prop.x: AnimTrack([AnimKey(0, 0), AnimKey(2, 20)])});
    final d = _abc(props: props);
    d.duplicateFrame(0);
    expect(d.activeLayer!.props.tracks[Prop.x]!.keys.map((k) => k.frame), [0, 3]);
    d.copyFrames(0, 2);
    d.pasteFrames(after: 0);
    expect(d.activeLayer!.props.tracks[Prop.x]!.keys.map((k) => k.frame), [0, 5]);
    final timing = d.timeline, layerProps = d.activeLayer!.props;
    d.moveFrames(0, 2, 6);
    d.reverseFrameRange(0, 6);
    expect(d.timeline, same(timing));
    expect(d.activeLayer!.props, same(layerProps));
  });

  test('blank and unexposed columns survive reordering and get editable copied ids', () {
    final a = _solid(0xFFFF0000);
    final d = _doc([PaintLayer('paint', const LayerProps(), CelTrack(drawings: {7: a}, xs: const [Exposure(1, 7), Exposure(3, 0)]))], length: 5);
    d.copyFrames(0, 5);
    expect(FrameColumnClipboard.frames.map((c) => c['paint']), [null, a, a, null, null]);
    d.reverseFrameRange(0, 5);
    expect(_ids(_paint(d), 5), [null, null, 7, 7, null]);
    d.pasteFrames(after: 4);
    final result = _paint(d);
    _sameContents(result, [null, null, a, a, null, TilePlane.empty, a, a, TilePlane.empty, TilePlane.empty]);
    expect(_ids(result, 10).skip(5).toSet(), hasLength(5));
    d.duplicateFrame(0);
    expect(_paint(d).at(1), same(TilePlane.empty));
    expect(_paint(d).drawingIdAt(1), isNotNull);
  });

  test('pasting ignores removed layers and holds layers missing from the clipboard', () {
    final d = _abc();
    d.copyFrames(0, 2);
    final original = _paint(d);
    d.applyComp('Change layers', (c) => c.copyWith(layers: [(c.layer('paint')! as PaintLayer).withId('other')]));
    d.pasteFrames(after: 0);
    expect(d.comp.layers.map((l) => l.id), ['other']);
    _sameContents(_paint(d, 'other'), [original.at(0), original.at(0), original.at(0), original.at(1), original.at(2)]);
    expect(_paint(d, 'other').drawings, hasLength(3));
  });

  test('empty clipped ranges and nonpositive insert counts do not edit history', () {
    final d = _abc();
    d.copyFrames(0, 1);
    final before = d.project, copied = FrameColumnClipboard.frames;
    for (final range in [(0, 0), (3, 100), (-5, -1), (2, 1)]) {
      d.deleteFrames(range.$1, range.$2);
      d.moveFrames(range.$1, range.$2, 0);
      d.reverseFrameRange(range.$1, range.$2);
      d.copyFrames(range.$1, range.$2);
    }
    d.insertFrames(count: 0);
    d.insertFrames(count: -2);
    expect(FrameColumnClipboard.frames, same(copied));
    FrameColumnClipboard.frames = const [];
    d.pasteFrames();
    expect(d.project, same(before));
    expect(d.history.index, 0);
    expect(d.dirty, isFalse);
  });

  test('clamps ranges, inserts at both ends and always retains a frame', () {
    final d = _abc();
    d.insertFrames(after: -50);
    expect(d.frame, 0);
    expect(_paint(d).at(0), same(TilePlane.empty));
    d.insertFrames(after: 100);
    expect(d.frame, 4);
    d.copyFrames(-100, 100);
    expect(FrameColumnClipboard.frames, hasLength(5));
    d.deleteFrames(-100, 100);
    expect(d.frameCount, 1);
    expect(d.frame, 0);
    expect(_paint(d).at(0), same(TilePlane.empty));
    expect(_paint(d).drawings, hasLength(1));
    expect(_paint(d, 'bg').drawings, hasLength(1));
    expect(d.timeline.rangeStart, 0);
    expect(d.timeline.rangeEnd, 1);
    d.deleteFrames(0, 1);
    expect(d.frameCount, 1);
    expect(d.frame, 0);
  });

  test('null loops stay null and shortened explicit loops remain valid', () {
    final d = _abc();
    d.insertFrames();
    expect(d.timeline.loopStart, isNull);
    expect(d.timeline.loopEnd, isNull);
    d.applyComp('Loop', (c) => c.copyWith(timeline: c.timeline.copyWith(loopStart: 2, loopEnd: 4)));
    d.deleteFrames(0, 4);
    expect(d.timeline.loopStart, isNull);
    expect(d.timeline.loopEnd, 1);
    expect(d.timeline.rangeStart, 0);
    expect(d.timeline.rangeEnd, 1);
  });

  test('static drawings remain unchanged when duplicated, pasted or reordered', () {
    final layer = PaintLayer('paint', const LayerProps(), CelTrack.single(_solid(0xFFFF0000)));
    final d = _doc([layer]);
    d.duplicateFrame();
    d.copyFrames(0, 2);
    d.pasteFrames();
    d.moveFrames(0, 1, 6);
    d.reverseFrameRange(0, 6);
    expect(_paint(d), same(layer.cels));
    expect(d.frameCount, 6);
    d.deleteFrames(0, 6);
    expect(d.frameCount, 1);
    expect(_paint(d), same(layer.cels));
  });
}
