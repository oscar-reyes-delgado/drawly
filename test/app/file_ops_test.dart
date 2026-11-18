import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:drawly/app/doc_layers.dart';
import 'package:drawly/app/doc_timeline.dart';
import 'package:drawly/app/document_controller.dart';
import 'package:drawly/app/file_ops.dart';
import 'package:drawly/engine/tiles.dart';
import 'package:drawly/io/image_export.dart';
import 'package:drawly/model/document.dart';
import 'package:drawly/model/layer.dart';
import 'package:drawly/model/vector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

TilePlane _solidPlane(Rect rect, Color color) =>
    TilePlane.empty.drawn((c) => c.drawRect(rect, Paint()..color = color), area: rect);

DocumentController _makePaintedDoc({
  int width = 64,
  int height = 48,
  Color color = const Color(0xFFE53935),
  Rect? rect,
}) {
  final area = rect ?? Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
  final doc = DocumentController(Project.blank(width: width, height: height), title: 'initial');
  final layer = doc.activeLayer as PaintLayer;
  final plane = _solidPlane(area, color);
  doc.updateLayer(
    'Paint',
    layer.id,
    (l) => (l as PaintLayer).withCels(l.cels.withDrawing(1, plane)),
  );
  return doc;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('drawly_file_ops_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('saveProjectTo and openProjectFrom preserve title, layers, pixels and clean dirty state', () async {
    const area = Rect.fromLTWH(8, 8, 24, 20);
    const paintColor = Color(0xFF1E88E5);
    final doc = _makePaintedDoc(width: 64, height: 48, color: paintColor, rect: area);
    addTearDown(doc.dispose);
    expect(doc.dirty, isTrue);

    final savePath = p.join(tempDir.path, 'nested', 'hero_scene.drawly');
    final progress = <double>[];
    final ok = await saveProjectTo(doc, savePath, onProgress: progress.add);
    expect(ok, isTrue);
    expect(File(savePath).existsSync(), isTrue);
    expect(doc.dirty, isFalse);
    expect(doc.filePath, savePath);
    expect(doc.title, 'hero_scene');
    expect(progress, isNotEmpty);
    expect(progress.last, 1.0);

    final reopened = await openProjectFrom(savePath);
    addTearDown(reopened.dispose);
    expect(reopened.title, doc.title);
    expect(reopened.filePath, savePath);
    expect(reopened.dirty, isFalse);
    expect(reopened.comp.layers.length, doc.comp.layers.length);

    final origPlane = (doc.comp.layers.first as PaintLayer).cels.drawings[1]!;
    final loadedPlane = (reopened.comp.layers.first as PaintLayer).cels.drawings[1]!;
    final origRgba = await origPlane.readRgba(area);
    final loadedRgba = await loadedPlane.readRgba(area);
    expect(loadedRgba.length, origRgba.length);
    for (var i = 0; i < origRgba.length; i++) {
      expect((loadedRgba[i] - origRgba[i]).abs(), lessThanOrEqualTo(1));
    }
  });

  test('saveProjectTo returns false without clearing metadata when write fails', () async {
    final doc = _makePaintedDoc();
    addTearDown(doc.dispose);
    doc.filePath = p.join(tempDir.path, 'previous.drawly');
    doc.title = 'previous';

    // Pointing at an existing directory forces writeFileBytes to fail.
    final blockingDir = Directory(p.join(tempDir.path, 'is_a_dir'))..createSync();
    final ok = await saveProjectTo(doc, blockingDir.path);
    expect(ok, isFalse);
    expect(doc.dirty, isTrue);
    expect(doc.title, 'previous');
    expect(doc.filePath, p.join(tempDir.path, 'previous.drawly'));
  });

  test('openProjectFrom throws Exception on missing file and FormatException on garbage bytes', () async {
    final missingPath = p.join(tempDir.path, 'does_not_exist.drawly');
    await expectLater(openProjectFrom(missingPath), throwsException);

    final badPath = p.join(tempDir.path, 'corrupt.drawly');
    File(badPath).writeAsBytesSync(Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]));
    await expectLater(openProjectFrom(badPath), throwsFormatException);
  });

  test('exportStill writes scaled PNG decoded with package:image and supports frame and watermark', () async {
    final doc = _makePaintedDoc(width: 64, height: 48, color: const Color(0xFF2E7D32));
    addTearDown(doc.dispose);
    doc.addKeyFrame(at: 1);
    final layer = doc.activeLayer as PaintLayer;
    final id2 = layer.cels.drawingIdAt(1)!;
    doc.updateLayer(
      'Frame 1',
      layer.id,
      (l) => (l as PaintLayer).withCels(
        l.cels.withDrawing(id2, _solidPlane(const Rect.fromLTWH(0, 0, 64, 48), const Color(0xFF1565C0))),
      ),
    );
    expect(doc.frame, 0);

    final outPath = p.join(tempDir.path, 'exports', 'still_half.png');
    final ok = await exportStill(doc, outPath, StillFormat.png, scale: 0.5, frame: 1, watermark: 'Drawly');
    expect(ok, isTrue);
    expect(doc.frame, 0);

    final file = File(outPath);
    expect(file.existsSync(), isTrue);
    final decoded = img.decodePng(file.readAsBytesSync());
    expect(decoded, isNotNull);
    expect(decoded!.width, 32);
    expect(decoded.height, 24);
    final topLeft = decoded.getPixel(2, 2);
    expect(topLeft.r.toInt(), 0x15);
    expect(topLeft.g.toInt(), 0x65);
    expect(topLeft.b.toInt(), 0xC0);
  });

  test('exportSequence renders 3-frame playback range into base_0000.png..0002.png', () async {
    final doc = DocumentController(Project.blank(width: 16, height: 16, frames: 3));
    addTearDown(doc.dispose);
    doc.setLength(3);

    final colors = [
      const Color(0xFFFF0000),
      const Color(0xFF00FF00),
      const Color(0xFF0000FF),
    ];
    final layerId = doc.activeLayerId!;
    var track = const CelTrack<TilePlane>(drawings: {}, xs: []);
    for (var i = 0; i < 3; i++) {
      final did = i + 1;
      track = track
          .withDrawing(did, _solidPlane(const Rect.fromLTWH(0, 0, 16, 16), colors[i]))
          .withKey(i, did);
    }
    doc.updateLayer('3 keys', layerId, (l) => (l as PaintLayer).withCels(track));

    final seqDir = p.join(tempDir.path, 'seq');
    final progress = <double>[];
    final paths = await exportSequence(doc, seqDir, 'base', onProgress: progress.add);

    expect(paths.length, 3);
    expect(p.basename(paths[0]), 'base_0000.png');
    expect(p.basename(paths[1]), 'base_0001.png');
    expect(p.basename(paths[2]), 'base_0002.png');
    expect(progress.first, 0.0);
    expect(progress.last, 1.0);

    for (var i = 0; i < 3; i++) {
      final file = File(paths[i]);
      expect(file.existsSync(), isTrue);
      final decoded = img.decodePng(file.readAsBytesSync())!;
      final px = decoded.getPixel(8, 8);
      expect(px.r.toInt(), (colors[i].r * 255).round());
      expect(px.g.toInt(), (colors[i].g * 255).round());
      expect(px.b.toInt(), (colors[i].b * 255).round());
    }
  });

  test('exportAnimationTo writes 3-frame GIF for a 3-frame document', () async {
    final doc = DocumentController(Project.blank(width: 16, height: 16, frames: 3));
    addTearDown(doc.dispose);
    doc.setLength(3);

    final layerId = doc.activeLayerId!;
    final track = const CelTrack<TilePlane>(drawings: {}, xs: [])
        .withDrawing(1, _solidPlane(const Rect.fromLTWH(0, 0, 16, 16), const Color(0xFFFF0000)))
        .withKey(0, 1)
        .withDrawing(2, _solidPlane(const Rect.fromLTWH(0, 0, 16, 16), const Color(0xFF00FF00)))
        .withKey(1, 2)
        .withDrawing(3, _solidPlane(const Rect.fromLTWH(0, 0, 16, 16), const Color(0xFF0000FF)))
        .withKey(2, 3);
    doc.updateLayer('3 keys', layerId, (l) => (l as PaintLayer).withCels(track));

    final gifPath = p.join(tempDir.path, 'anim', 'walk.gif');
    final progress = <double>[];
    final ok = await exportAnimationTo(doc, gifPath, AnimFormat.gif, onProgress: progress.add);

    expect(ok, isTrue);
    expect(progress.first, 0.0);
    expect(progress.last, 1.0);

    final bytes = File(gifPath).readAsBytesSync();
    final gif = img.decodeGif(bytes);
    expect(gif, isNotNull);
    expect(gif!.numFrames, 3);
  });

  test('exportSvgTo exports active vector layer as SVG and returns false for paint layer', () async {
    final doc = DocumentController(Project.blank(width: 100, height: 80));
    addTearDown(doc.dispose);

    final paintSvgPath = p.join(tempDir.path, 'paint_layer.svg');
    expect(await exportSvgTo(doc, paintSvgPath), isFalse);
    expect(File(paintSvgPath).existsSync(), isFalse);

    doc.addVectorLayer();
    final vectorLayer = doc.activeLayer as VectorLayer;
    final art = VectorArt([
      VShape(
        id: 'rect_1',
        paths: [VPath.rect(const Rect.fromLTWH(10, 15, 40, 30))],
        fill: const VFill.solid(Color(0xFFFF5500)),
      ),
    ]);
    doc.updateLayer(
      'Draw rect',
      vectorLayer.id,
      (l) => (l as VectorLayer).withCels(l.cels.withDrawing(1, art)),
    );

    final vectorSvgPath = p.join(tempDir.path, 'svg', 'shape.svg');
    final ok = await exportSvgTo(doc, vectorSvgPath);
    expect(ok, isTrue);
    final content = File(vectorSvgPath).readAsStringSync();
    expect(content, contains('<svg'));
    expect(content, contains('<path'));
  });
}
