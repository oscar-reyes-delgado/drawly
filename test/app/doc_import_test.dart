import 'dart:ui' as ui;

import 'package:drawly/app/doc_frames.dart';
import 'package:drawly/app/doc_import.dart';
import 'package:drawly/app/doc_layers.dart';
import 'package:drawly/app/document_controller.dart';
import 'package:drawly/engine/tiles.dart';
import 'package:drawly/model/document.dart';
import 'package:drawly/model/layer.dart';
import 'package:flutter_test/flutter_test.dart';

ui.Image _img(int w, int h, ui.Color c) => renderToImage(w, h, (cv) => cv.drawRect(ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), ui.Paint()..color = c));

Future<List<int>> _px(TilePlane p, double x, double y) async => (await p.readRgba(ui.Rect.fromLTWH(x, y, 1, 1), straight: true)).toList();

DocumentController _doc({int w = 100, int h = 100}) => DocumentController(Project.blank(width: w, height: h, background: null, frames: 1), title: 't');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('naturalSort orders numbers by value and ignores case', () {
    expect(naturalSort(['a10.png', 'a2.png', 'a1.png', 'B3.png']), ['a1.png', 'a2.png', 'a10.png', 'B3.png']);
    expect(naturalSort(['walk_10', 'walk_9', 'walk_010']), ['walk_9', 'walk_10', 'walk_010']);
  });

  test('placeImage: contain, none and cover', () async {
    final d = _doc();
    final img = _img(200, 100, const ui.Color(0xFFFF0000));
    expect(await d.placeImage(img).contentBounds(), const ui.Rect.fromLTWH(0, 25, 100, 50));
    expect(await d.placeImage(img, fit: ImageFit.none).contentBounds(), const ui.Rect.fromLTWH(0, 0, 100, 100), reason: 'centred, cropped by the canvas');
    expect(await d.placeImage(img, fit: ImageFit.cover).contentBounds(), const ui.Rect.fromLTWH(0, 0, 100, 100));
    final small = _img(20, 10, const ui.Color(0xFFFF0000));
    expect(await d.placeImage(small).contentBounds(), const ui.Rect.fromLTWH(40, 45, 20, 10), reason: 'contain never scales up');
  });

  test('importImageSequence: one drawing per frame above the active layer, one undo step', () async {
    final d = _doc();
    final base = d.activeLayerId;
    const colors = [ui.Color(0xFFFF0000), ui.Color(0xFF00FF00), ui.Color(0xFF0000FF)];
    final id = d.importImageSequence([for (final c in colors) _img(10, 10, c)], 'walk');
    expect(d.frameCount, 3);
    expect(d.activeLayerId, id);
    expect(d.comp.layers.map((l) => l.id).toList(), [base, id]);
    final layer = d.comp.layer(id)! as PaintLayer;
    for (var f = 0; f < 3; f++) {
      final px = await _px(layer.cels.at(f)!, 50, 50);
      expect(px.sublist(0, 3), [(colors[f].r * 255).round(), (colors[f].g * 255).round(), (colors[f].b * 255).round()]);
    }
    d.undo();
    expect(d.comp.layer(id), isNull);
    expect(d.frameCount, 1);
  });

  test('importImageSequence with start: frames before stay blank and the timeline grows', () {
    final d = _doc();
    d.insertFrames(count: 3);
    final id = d.importImageSequence([for (var i = 0; i < 3; i++) _img(4, 4, const ui.Color(0xFF000000))], 's', start: 2);
    final cels = (d.comp.layer(id)! as PaintLayer).cels;
    expect(d.frameCount, 5);
    expect(cels.at(0), isNull);
    expect(cels.at(1), isNull);
    expect([cels.drawingIdAt(2), cels.drawingIdAt(3), cels.drawingIdAt(4)], [1, 2, 3]);
  });

  test('importImageIntoFrame replaces only that frame; vector layers refuse', () async {
    final d = _doc();
    d.insertFrames(count: 2); // three frames on the active (now animated) layer
    final l = d.activeLayer! as PaintLayer;
    // hold one drawing over frames 0..2
    final hold = TilePlane.empty.drawn((c) => c.drawRect(const ui.Rect.fromLTWH(0, 0, 10, 10), ui.Paint()..color = const ui.Color(0xFF000000)), area: const ui.Rect.fromLTWH(0, 0, 10, 10));
    d.updateLayer('hold', l.id, (x) => (x as PaintLayer).withCels(CelTrack(drawings: {1: hold}, xs: const [Exposure(0, 1)])));
    d.frame = 1;
    expect(d.importImageIntoFrame(_img(10, 10, const ui.Color(0xFFFF0000))), isTrue);
    final cels = (d.activeLayer! as PaintLayer).cels;
    expect(cels.at(0), same(hold));
    expect(cels.at(1), isNot(same(hold)));
    expect(cels.at(2), same(hold), reason: 'the held drawing keeps showing after');
    expect((await _px(cels.at(1)!, 50, 50)).sublist(0, 3), [255, 0, 0]);

    d.updateProps('lock', l.id, (p) => p.copyWith(locked: true));
    final before = d.project;
    expect(d.importImageIntoFrame(_img(10, 10, const ui.Color(0xFFFF0000))), isFalse, reason: 'locked layer');
    expect(d.project, same(before));

    d.addVectorLayer();
    expect(d.importImageIntoFrame(_img(10, 10, const ui.Color(0xFFFF0000))), isFalse);
  });
}
