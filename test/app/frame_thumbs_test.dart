import 'dart:ui' as ui;

import 'package:drawly/app/document_controller.dart';
import 'package:drawly/app/frame_thumbs.dart';
import 'package:drawly/engine/tiles.dart';
import 'package:drawly/model/document.dart';
import 'package:drawly/model/layer.dart';
import 'package:flutter_test/flutter_test.dart';

TilePlane _solidPlane(ui.Rect r, ui.Color color) =>
    TilePlane.empty.drawn((c) => c.drawRect(r, ui.Paint()..color = color), area: r);

DocumentController _makeThreeFrameDoc({int width = 128, int height = 64}) {
  final r = ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
  final p0 = _solidPlane(r, const ui.Color(0xFFFF0000));
  final p1 = _solidPlane(r, const ui.Color(0xFF00FF00));
  final p2 = _solidPlane(r, const ui.Color(0xFF0000FF));

  final layer = PaintLayer(
    'L1',
    const LayerProps(name: 'Paint'),
    CelTrack<TilePlane>(
      drawings: {1: p0, 2: p1, 3: p2},
      xs: const [Exposure(0, 1), Exposure(1, 2), Exposure(2, 3)],
    ),
  );

  final comp = Comp(
    id: 'c',
    name: 'Main',
    width: width,
    height: height,
    layers: [layer],
    timeline: const Timeline(length: 3),
  );
  return DocumentController(Project(comps: {'c': comp}, mainId: 'c'), title: 't');
}

Future<void> _drainQueue(FrameThumbnailCache cache) async {
  var prev = -1;
  while (cache.renderCount != prev) {
    prev = cache.renderCount;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('renders 3 distinct frames at height 72 with proportional width', () async {
    final doc = _makeThreeFrameDoc(width: 128, height: 64);
    final cache = FrameThumbnailCache(height: 72);
    addTearDown(cache.dispose);

    var notifications = 0;
    cache.addListener(() => notifications++);

    cache.request(doc, [0, 1, 2]);
    await _drainQueue(cache);

    expect(cache.renderCount, 3);
    expect(notifications, greaterThanOrEqualTo(1));

    for (var f = 0; f < 3; f++) {
      final img = cache.thumbnailFor(doc, f);
      expect(img, isNotNull);
      expect(img!.height, 72);
      expect(img.width, 144); // 128 * (72 / 64)
    }
  });

  test('re-requesting without changes does not increase renderCount', () async {
    final doc = _makeThreeFrameDoc();
    final cache = FrameThumbnailCache(height: 72);
    addTearDown(cache.dispose);

    cache.request(doc, [0, 1, 2]);
    await _drainQueue(cache);
    expect(cache.renderCount, 3);

    cache.request(doc, [0, 1, 2]);
    await _drainQueue(cache);
    expect(cache.renderCount, 3);

    expect(cache.thumbnailFor(doc, 0), isNotNull);
    expect(cache.thumbnailFor(doc, 1), isNotNull);
    expect(cache.thumbnailFor(doc, 2), isNotNull);
    await _drainQueue(cache);
    expect(cache.renderCount, 3);
  });

  test('painting frame 1 via updateLayer only re-renders frame 1', () async {
    final doc = _makeThreeFrameDoc();
    final cache = FrameThumbnailCache(height: 72);
    addTearDown(cache.dispose);

    cache.request(doc, [0, 1, 2]);
    await _drainQueue(cache);
    expect(cache.renderCount, 3);

    final newPlane = _solidPlane(const ui.Rect.fromLTWH(0, 0, 128, 64), const ui.Color(0xFFFFFF00));
    doc.updateLayer('paint', 'L1', (l) {
      final pl = l as PaintLayer;
      return pl.withCels(pl.cels.withDrawing(2, newPlane));
    });

    cache.request(doc, [0, 1, 2]);
    await _drainQueue(cache);
    expect(cache.renderCount, 4);
  });

  test('changing layer opacity invalidates all 3 frames', () async {
    final doc = _makeThreeFrameDoc();
    final cache = FrameThumbnailCache(height: 72);
    addTearDown(cache.dispose);

    cache.request(doc, [0, 1, 2]);
    await _drainQueue(cache);
    expect(cache.renderCount, 3);

    doc.updateProps('opacity', 'L1', (p) => p.copyWith(opacity: 0.5));

    // Stale images are returned while scheduling re-renders
    expect(cache.thumbnailFor(doc, 0), isNotNull);
    expect(cache.thumbnailFor(doc, 1), isNotNull);
    expect(cache.thumbnailFor(doc, 2), isNotNull);

    await _drainQueue(cache);
    expect(cache.renderCount, 6);
  });

  test('paused prevents rendering until unpaused and requested again', () async {
    final doc = _makeThreeFrameDoc();
    final cache = FrameThumbnailCache(height: 72);
    addTearDown(cache.dispose);

    cache.paused = true;
    cache.request(doc, [0, 1, 2]);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(cache.renderCount, 0);

    cache.paused = false;
    cache.request(doc, [0, 1, 2]);
    await _drainQueue(cache);
    expect(cache.renderCount, 3);
  });

  test('LRU budget evicts oldest images and re-schedules evicted frame', () async {
    final doc = _makeThreeFrameDoc(width: 64, height: 64);
    // Each 72x72 thumbnail is 72 * 72 * 4 = 20736 bytes. Budget for 2 thumbnails.
    const twoThumbsBytes = 72 * 72 * 4 * 2;
    final cache = FrameThumbnailCache(height: 72, budgetBytes: twoThumbsBytes, perTick: 1);
    addTearDown(cache.dispose);

    cache.request(doc, [0, 1, 2]);
    await _drainQueue(cache);
    expect(cache.renderCount, 3);

    // Frame 0 was rendered first and should have been evicted when frame 2 was inserted.
    final evicted = cache.thumbnailFor(doc, 0);
    expect(evicted, isNull);

    // Calling thumbnailFor(doc, 0) scheduled a re-render.
    await _drainQueue(cache);
    expect(cache.renderCount, 4);
    expect(cache.thumbnailFor(doc, 0), isNotNull);
  });

  test('thumbnail pixels of frame 0 match drawing color at center', () async {
    final doc = _makeThreeFrameDoc(width: 64, height: 64);
    final cache = FrameThumbnailCache(height: 72);
    addTearDown(cache.dispose);

    cache.request(doc, [0]);
    await _drainQueue(cache);

    final thumb = cache.thumbnailFor(doc, 0)!;
    final rgba = await imageToRgba(thumb);
    final cx = thumb.width ~/ 2;
    final cy = thumb.height ~/ 2;
    final off = (cy * thumb.width + cx) * 4;
    expect(rgba[off], 255); // R
    expect(rgba[off + 1], 0); // G
    expect(rgba[off + 2], 0); // B
    expect(rgba[off + 3], 255); // A
  });

  test('ignores out-of-range frames', () async {
    final doc = _makeThreeFrameDoc();
    final cache = FrameThumbnailCache(height: 72);
    addTearDown(cache.dispose);

    cache.request(doc, [-1, 3, 10]);
    await _drainQueue(cache);
    expect(cache.renderCount, 0);
    expect(cache.thumbnailFor(doc, -1), isNull);
    expect(cache.thumbnailFor(doc, 3), isNull);
  });
}
