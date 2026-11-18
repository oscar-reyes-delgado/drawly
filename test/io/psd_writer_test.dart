import 'dart:math' as math;
import 'dart:typed_data';
import 'package:drawly/io/flat_layer.dart';
import 'package:drawly/io/psd_writer.dart';
import 'package:drawly/model/layer.dart';
import 'package:image/image.dart' as img;
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('PackBits round trips runs, literals, mixed packets and boundary lengths', () {
    final random = math.Random(1);
    for (final row in [<int>[], [42], List.filled(300, 9), List.generate(300, (i) => i % 256), [1, 1, 2, 3, 3, 3, 4, 5], List.generate(2000, (_) => random.nextInt(256))]) {
      expect(unpackBits(packBits(Uint8List.fromList(row)), row.length), row);
    }
    expect(() => unpackBits(Uint8List.fromList([0]), 1), throwsFormatException);
    expect(unpackBits(Uint8List.fromList([128, 0, 4]), 1), [4]);
  });
  test('PSD decoder preserves layer metadata and composite pixels', () {
    final rgba = Uint8List.fromList([255, 0, 0, 255, 0, 255, 0, 255, 20, 40, 80, 128, 0, 0, 255, 255]);
    final layers = [FlatLayer(name: 'Línea', rgba: rgba, left: -3, top: 2, width: 2, height: 2, opacity: 0.5, blend: LayerBlend.multiply, visible: false), FlatLayer(name: 'top', rgba: rgba, left: 0, top: 0, width: 2, height: 2)];
    final bytes = encodePsd(layers, width: 2, height: 2, mergedRgba: rgba), decoded = img.PsdDecoder().decodePsd(bytes)!;
    expect(decoded.width, 2); expect(decoded.height, 2); expect(decoded.layers.length, 2);
    final l = decoded.layers.first;
    expect(l.name, 'Línea'); expect((l.left, l.top, l.width, l.height), (-3, 2, 2, 2)); expect(l.opacity, 128); expect(l.blendMode, 0x6d756c20); expect(l.flags & 2, 2);
    expect(l.additionalData.containsKey('luni'), isTrue);
    expect(decoded.layers.last.name, 'top');
    final merged = decoded.mergedImage!;
    for (final (x, y) in [(0, 0), (1, 0), (1, 1)]) { final p = merged.getPixel(x, y); expect([p.r, p.g, p.b, p.a], rgba.sublist((y * 2 + x) * 4, (y * 2 + x) * 4 + 4)); }
    final translucent = merged.getPixel(0, 1);
    expect(translucent.r, closeTo(20, 2)); expect(translucent.g, closeTo(40, 2)); expect(translucent.b, closeTo(80, 2)); expect(translucent.a, 128);
  });
  test('zero-sized layer and empty layer list are valid', () {
    final rgba = Uint8List.fromList([1, 2, 3, 255]);
    for (final layers in [<FlatLayer>[], [FlatLayer(name: 'empty', rgba: Uint8List(0), left: 0, top: 0, width: 0, height: 0)]]) {
      final decoded = img.PsdDecoder().decodePsd(encodePsd(layers, width: 1, height: 1, mergedRgba: rgba));
      expect(decoded, isNotNull); expect(decoded!.layers.length, layers.length);
    }
  });
}
