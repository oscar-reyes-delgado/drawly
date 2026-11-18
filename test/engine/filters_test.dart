import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:drawly/engine/filters.dart';
import 'package:drawly/engine/tiles.dart';
import 'package:drawly/model/filter_spec.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Uint8List> px(ui.Image img) => imageToRgba(img);

ui.Image testImage() => renderToImage(64, 64, (c) {
      c.drawRect(const ui.Rect.fromLTWH(0, 0, 64, 64), ui.Paint()..color = const ui.Color(0xFF204060));
      c.drawRect(const ui.Rect.fromLTWH(0, 0, 32, 32), ui.Paint()..color = const ui.Color(0xFFE0E0E0));
      c.drawCircle(const ui.Offset(44, 44), 10, ui.Paint()..color = const ui.Color(0xFFFF2000));
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Shaders.instance.ensureLoaded();
  });

  test('all shader programs load', () {
    for (final n in Shaders.names) {
      expect(Shaders.instance.has(n), isTrue, reason: 'shader $n failed to load');
    }
  });

  test('every filter runs and yields an image', () async {
    final src = testImage();
    for (final def in kFilters) {
      final out = applyFilter(src, def.defaults);
      final d = await px(out);
      expect(d.length, 64 * 64 * 4, reason: def.id);
      // nothing should produce a fully transparent result from an opaque source
      var opaque = 0;
      for (var i = 3; i < d.length; i += 4) {
        if (d[i] > 0) opaque++;
      }
      expect(opaque, greaterThan(64 * 64 ~/ 4), reason: '${def.id} produced an (almost) empty image');
    }
  });

  test('invert matrix', () async {
    final out = applyFilter(testImage(), filterDef('invert').defaults);
    final d = await px(out);
    final o = (50 * 64 + 5) * 4; // dark blue area 0x204060
    expect(d[o], closeTo(0xDF, 1));
    expect(d[o + 1], closeTo(0xBF, 1));
    expect(d[o + 2], closeTo(0x9F, 1));
  });

  test('threshold LUT gives pure black / white', () async {
    final out = applyFilter(testImage(), filterDef('threshold').defaults);
    final d = await px(out);
    final dark = (50 * 64 + 5) * 4, light = (5 * 64 + 5) * 4;
    expect(d.sublist(dark, dark + 3), [0, 0, 0]);
    expect(d.sublist(light, light + 3), [255, 255, 255]);
  });

  test('pixelate makes cells uniform', () async {
    final spec = filterDef('pixelate').defaults.withParam('size', 16);
    final out = applyFilter(testImage(), spec);
    final d = await px(out);
    // two pixels inside the same 16px cell must match
    final a = (40 * 64 + 34) * 4, b = (46 * 64 + 45) * 4;
    expect(d.sublist(a, a + 4), d.sublist(b, b + 4));
  });

  test('levels LUT maps mid grey with gamma', () {
    final lut = filterLut(filterDef('levels').defaults.withParam('gamma', 2));
    expect(lut[128 * 4], greaterThan(170));
    expect(lut[0], 0);
    expect(lut[255 * 4], 255);
  });

  test('curve table is monotone through control points', () {
    final t = curveTable(const [ui.Offset(0, 0), ui.Offset(0.5, 0.7), ui.Offset(1, 1)]);
    expect(t[0], closeTo(0, 1e-6));
    expect(t[128], closeTo(0.7, 0.02));
    expect(t[255], closeTo(1, 1e-6));
    for (var i = 1; i < 256; i++) {
      expect(t[i] >= t[i - 1] - 1e-6, isTrue);
    }
  });
}
