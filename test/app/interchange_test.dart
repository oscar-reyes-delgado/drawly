import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:drawly/app/doc_layers.dart';
import 'package:drawly/app/document_controller.dart';
import 'package:drawly/app/interchange.dart';
import 'package:drawly/engine/tiles.dart';
import 'package:drawly/model/document.dart';
import 'package:drawly/model/layer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

TilePlane _rectPlane(Rect rect, Color color) =>
    TilePlane.empty.drawn((c) => c.drawRect(rect, Paint()..color = color), area: rect);

DocumentController _makeTwoLayerDoc() {
  final doc = DocumentController(Project.blank(width: 64, height: 64), title: 'doc');
  final baseId = doc.comp.layers.first.id;
  const redRect = Rect.fromLTWH(8, 8, 16, 16);
  doc.updateLayer(
    'Paint red',
    baseId,
    (l) => (l as PaintLayer)
        .withProps(l.props.copyWith(name: 'Red'))
        .withCels(l.cels.withDrawing(1, _rectPlane(redRect, const Color(0xFFFF0000)))),
  );

  doc.addPaintLayer(
    name: 'Overlay',
    pixels: _rectPlane(const Rect.fromLTWH(20, 20, 8, 8), const Color(0xFF00FF00)),
  );
  final topId = doc.activeLayerId!;
  doc.updateProps(
    'Layer props',
    topId,
    (p) => p.copyWith(visible: false, opacity: 0.5, blend: LayerBlend.multiply),
  );
  return doc;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('flattenForInterchange returns bottom-to-top cropped layers including hidden ones', () async {
    final doc = _makeTwoLayerDoc();
    addTearDown(doc.dispose);

    final layers = await flattenForInterchange(doc);
    expect(layers.length, 2);

    final first = layers[0];
    expect(first.name, 'Red');
    expect(first.visible, isTrue);
    expect(first.left, inInclusiveRange(7, 9));
    expect(first.top, inInclusiveRange(7, 9));
    expect(first.width, inInclusiveRange(15, 17));
    expect(first.height, inInclusiveRange(15, 17));

    final second = layers[1];
    expect(second.name, 'Overlay');
    expect(second.visible, isFalse);
    expect(second.opacity, closeTo(0.5, 1e-6));
    expect(second.blend, LayerBlend.multiply);
    expect(second.width, inInclusiveRange(7, 9));
    expect(second.height, inInclusiveRange(7, 9));
  });

  test('flattenForInterchange flattens groups and handles empty layers as 0x0', () async {
    final doc = DocumentController(Project.blank(width: 64, height: 64), title: 'grp');
    addTearDown(doc.dispose);
    doc.addGroupLayer();
    final groupId = doc.activeLayerId!;
    doc.addPaintLayer(
      name: 'Child A',
      pixels: _rectPlane(const Rect.fromLTWH(4, 6, 10, 12), const Color(0xFF0000FF)),
    );
    doc.updateProps('Hide group', groupId, (p) => p.copyWith(opacity: 0.75, blend: LayerBlend.screen));

    final flat = await flattenForInterchange(doc);
    expect(flat.length, 2);
    expect(flat[0].width, 0);
    expect(flat[0].height, 0);
    expect(flat[1].left, 4);
    expect(flat[1].top, 6);
    expect(flat[1].width, 10);
    expect(flat[1].height, 12);
    expect(flat[1].opacity, closeTo(0.75, 1e-6));
    expect(flat[1].blend, LayerBlend.screen);
  });

  test('mergedRgba returns straight RGBA matching composition dimensions and pixels', () async {
    final doc = _makeTwoLayerDoc();
    addTearDown(doc.dispose);

    final rgba = await mergedRgba(doc);
    expect(rgba.length, 64 * 64 * 4);
    final idx = (10 * 64 + 10) * 4;
    expect(rgba[idx], 255);
    expect(rgba[idx + 1], 0);
    expect(rgba[idx + 2], 0);
    expect(rgba[idx + 3], 255);
  });

  test('documentToOra and projectFromOra round-trip names, order, metadata and pixels', () async {
    final doc = _makeTwoLayerDoc();
    addTearDown(doc.dispose);

    final bytes = await documentToOra(doc);
    final imported = await projectFromOra(bytes, name: 'Imported ORA');

    expect(imported.main.name, 'Imported ORA');
    expect(imported.main.width, 64);
    expect(imported.main.height, 64);
    expect(imported.main.background, isNull);
    expect(imported.main.layers.length, 2);

    final l0 = imported.main.layers[0] as PaintLayer;
    final l1 = imported.main.layers[1] as PaintLayer;
    expect(l0.name, 'Red');
    expect(l0.visible, isTrue);
    expect(l0.opacity, closeTo(1.0, 1e-3));
    expect(l0.blend, LayerBlend.normal);

    expect(l1.name, 'Overlay');
    expect(l1.visible, isFalse);
    expect(l1.opacity, closeTo(0.5, 1e-3));
    expect(l1.blend, LayerBlend.multiply);

    final px = await l0.cels.at(0)!.readRgba(const Rect.fromLTWH(10, 10, 1, 1), straight: true);
    expect(px, [255, 0, 0, 255]);

    final pxSemi = await l1.cels.at(0)!.readRgba(const Rect.fromLTWH(22, 22, 1, 1), straight: true);
    expect(pxSemi, [0, 255, 0, 255]);

    await expectLater(projectFromOra(Uint8List.fromList([1, 2, 3])), throwsFormatException);
  });

  test('projectFromOra premultiplies semi-transparent pixels cleanly', () async {
    final doc = DocumentController(Project.blank(width: 16, height: 16), title: 'semi');
    addTearDown(doc.dispose);
    final id = doc.comp.layers.first.id;
    doc.updateLayer(
      'Paint semi',
      id,
      (l) => (l as PaintLayer).withCels(
        l.cels.withDrawing(1, _rectPlane(const Rect.fromLTWH(2, 2, 4, 4), const Color(0x80FF4020))),
      ),
    );

    final imported = await projectFromOra(await documentToOra(doc));
    final layer = imported.main.layers.first as PaintLayer;
    final px = await layer.cels.at(0)!.readRgba(const Rect.fromLTWH(3, 3, 1, 1), straight: true);
    expect(px[0], closeTo(255, 3));
    expect(px[1], closeTo(64, 3));
    expect(px[2], closeTo(32, 3));
    expect(px[3], closeTo(128, 2));
  });

  test('documentToOra handles empty 0x0 layers without throwing', () async {
    final doc = DocumentController(Project.blank(width: 32, height: 32), title: 'blank');
    addTearDown(doc.dispose);

    final bytes = await documentToOra(doc);
    final imported = await projectFromOra(bytes);
    expect(imported.main.layers.length, 1);
    expect((imported.main.layers.first as PaintLayer).cels.at(0)!.isEmpty, isTrue);
  });

  test('documentToPsd produces a valid PSD with 2 layers and document dimensions', () async {
    final doc = _makeTwoLayerDoc();
    addTearDown(doc.dispose);

    final bytes = await documentToPsd(doc);
    final psd = img.PsdDecoder().decodePsd(bytes);
    expect(psd, isNotNull);
    expect(psd!.width, 64);
    expect(psd.height, 64);
    expect(psd.layers.length, 2);
    expect(psd.layers[0].name, 'Red');
    expect(psd.layers[1].name, 'Overlay');
    expect(psd.layers[1].flags & 2, 2);
  });

  test('importSvgLayer adds active VectorLayer or throws FormatException on empty SVG', () {
    final doc = DocumentController(Project.blank(width: 64, height: 64), title: 'svg');
    addTearDown(doc.dispose);
    final initialCount = doc.comp.layers.length;

    const svg = '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">'
        '<rect x="4" y="6" width="20" height="12" fill="#FF0000"/></svg>';
    final id = importSvgLayer(doc, svg, name: 'My SVG');

    expect(doc.comp.layers.length, initialCount + 1);
    expect(doc.activeLayerId, id);
    final added = doc.activeLayer as VectorLayer;
    expect(added.name, 'My SVG');
    expect(added.cels.at(0)!.shapes.length, 1);

    expect(() => importSvgLayer(doc, '<svg xmlns="http://www.w3.org/2000/svg"></svg>'), throwsFormatException);
    expect(doc.comp.layers.length, initialCount + 1);
  });

  test('readPalette and writePalette decode GPL and round-trip all 5 formats', () {
    const gpl = 'GIMP Palette\nName: Three\n#\n255 0 0\tRed\n0 255 0\tGreen\n0 0 255\tBlue\n';
    final parsed = readPalette(Uint8List.fromList(utf8.encode(gpl)), 'three.gpl');
    expect(parsed, isNotNull);
    expect(parsed!.name, 'Three');
    expect(parsed.colors, [0xFFFF0000, 0xFF00FF00, 0xFF0000FF]);

    final colors = [0xFF112233, 0xFF445566, 0xFFAABBCC];
    for (final format in PaletteFormat.values) {
      final bytes = writePalette('Custom', colors, format);
      final roundTrip = readPalette(bytes, 'custom.${paletteExtension(format)}');
      expect(roundTrip, isNotNull, reason: 'Failed for $format');
      expect(roundTrip!.colors, colors, reason: 'Color mismatch for $format');
    }

    expect(readPalette(Uint8List.fromList([0, 1, 2, 3]), 'unknown.bin'), isNull);
  });
}
