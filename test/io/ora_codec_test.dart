import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:drawly/io/flat_layer.dart';
import 'package:drawly/io/ora_codec.dart';
import 'package:drawly/model/layer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final pixels = Uint8List.fromList([255, 0, 0, 255, 20, 30, 40, 128, 0, 0, 255, 255, 3, 8, 9, 0]);
  final layers = [FlatLayer(name: 'Fondo & <base>', rgba: pixels, left: -2, top: 3, width: 2, height: 2), FlatLayer(name: 'Línea "arriba"', rgba: pixels, left: 4, top: -5, width: 2, height: 2, opacity: 0.5, blend: LayerBlend.multiply, visible: false)];
  test('round trip retains pixels, layer ordering and properties', () async {
    final bytes = await encodeOra(layers, width: 2, height: 2, mergedRgba: pixels), result = await decodeOra(bytes);
    expect(result.width, 2); expect(result.height, 2); expect(result.layers.length, 2);
    for (var i = 0; i < 2; i++) { final a = layers[i], b = result.layers[i]; expect(b.name, a.name); expect(b.rgba, a.rgba); expect((b.left, b.top, b.width, b.height), (a.left, a.top, a.width, a.height)); expect(b.opacity, a.opacity); expect(b.blend, a.blend); expect(b.visible, a.visible); }
    final zip = ZipDecoder().decodeBytes(bytes); expect(zip.files.first.name, 'mimetype'); expect(utf8.decode(zip.files.first.content), 'image/openraster');
    expect(ByteData.sublistView(bytes).getUint16(8, Endian.little), 0);
    final xml = utf8.decode(zip.findFile('stack.xml')!.content); expect(xml.indexOf('layer1.png'), lessThan(xml.indexOf('layer0.png')));
    expect(zip.findFile('Thumbnails/thumbnail.png'), isNotNull);
  });
  test('nested stacks flatten while inheriting offsets and visibility', () async {
    final zip = ZipDecoder().decodeBytes(await encodeOra(layers, width: 2, height: 2, mergedRgba: pixels));
    zip.addFile(ArchiveFile.string('stack.xml', '<image w="2" h="2"><stack><layer name="top" src="data/layer1.png"/><stack x="5" y="2" opacity="0.5" visibility="hidden"><layer name="bottom" src="data/layer0.png" x="3"/></stack></stack></image>'));
    final result = await decodeOra(Uint8List.fromList(ZipEncoder().encodeBytes(zip)));
    expect(result.layers.map((l) => l.name), ['bottom', 'top']); expect(result.layers.first.left, 8); expect(result.layers.first.top, 2); expect(result.layers.first.opacity, 0.5); expect(result.layers.first.visible, isFalse);
  });
  test('invalid bytes and missing PNG fail with FormatException', () async {
    await expectLater(decodeOra(Uint8List.fromList([1, 2, 3])), throwsFormatException);
    final zip = Archive()..addFile(ArchiveFile.string('mimetype', 'image/openraster'))..addFile(ArchiveFile.string('stack.xml', '<image w="1" h="1"><stack><layer src="missing.png"/></stack></image>'));
    await expectLater(decodeOra(Uint8List.fromList(ZipEncoder().encodeBytes(zip))), throwsFormatException);
  });
}
