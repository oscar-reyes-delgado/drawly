import 'dart:convert';
import 'dart:ui';

import 'package:drawly/engine/tiles.dart';
import 'package:drawly/io/image_export.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Image solidImage(int width, int height, Color color) =>
    renderToImage(width, height, (c) => c.drawRect(Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()), Paint()..color = color));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('StillFormat and AnimFormat metadata', () {
    expect(StillFormat.png.ext, 'png');
    expect(StillFormat.jpg.ext, 'jpg');
    expect(StillFormat.webp.ext, 'webp');
    expect(StillFormat.bmp.ext, 'bmp');
    expect(StillFormat.tiff.ext, 'tiff');
    expect(StillFormat.tga.ext, 'tga');

    expect(StillFormat.png.mime, 'image/png');
    expect(StillFormat.jpg.mime, 'image/jpeg');
    expect(StillFormat.webp.hasAlpha, isTrue);
    expect(StillFormat.jpg.hasAlpha, isFalse);
    expect(StillFormat.bmp.hasAlpha, isFalse);

    expect(AnimFormat.gif.ext, 'gif');
    expect(AnimFormat.apng.ext, 'png');
    expect(AnimFormat.webp.ext, 'webp');
    expect(AnimFormat.gif.mime, 'image/gif');
    expect(AnimFormat.apng.mime, 'image/png');
    expect(AnimFormat.webp.mime, 'image/webp');
  });

  test('every StillFormat encodes and decodes with matching dimensions and pixel values', () async {
    const color = Color(0xFF3399CC);
    final src = solidImage(16, 12, color);
    addTearDown(src.dispose);

    for (final fmt in StillFormat.values) {
      final bytes = await encodeStill(src, fmt);
      final decoded = img.decodeImage(bytes);
      expect(decoded, isNotNull, reason: fmt.name);
      expect(decoded!.width, 16, reason: fmt.name);
      expect(decoded.height, 12, reason: fmt.name);

      final px = decoded.getPixel(8, 6);
      if (fmt == StillFormat.png || fmt == StillFormat.webp) {
        expect(px.r.toInt(), 0x33, reason: fmt.name);
        expect(px.g.toInt(), 0x99, reason: fmt.name);
        expect(px.b.toInt(), 0xCC, reason: fmt.name);
        expect(px.a.toInt(), 0xFF, reason: fmt.name);
      } else if (fmt == StillFormat.jpg) {
        expect((px.r - 0x33).abs(), lessThanOrEqualTo(12));
        expect((px.g - 0x99).abs(), lessThanOrEqualTo(12));
        expect((px.b - 0xCC).abs(), lessThanOrEqualTo(12));
      }
    }
  });

  test('JPG of transparent image composites over white matte', () async {
    final transparent = renderToImage(8, 8, (_) {});
    addTearDown(transparent.dispose);

    final bytes = await encodeStill(transparent, StillFormat.jpg, matte: const Color(0xFFFFFFFF));
    final decoded = img.decodeJpg(bytes)!;
    final px = decoded.getPixel(4, 4);
    expect(px.r, greaterThanOrEqualTo(245));
    expect(px.g, greaterThanOrEqualTo(245));
    expect(px.b, greaterThanOrEqualTo(245));
  });

  test('GIF, APNG and WebP encode 3-frame animations at 10 fps', () async {
    final frames = [
      solidImage(8, 8, const Color(0xFFFF0000)),
      solidImage(8, 8, const Color(0xFF00FF00)),
      solidImage(8, 8, const Color(0xFF0000FF)),
    ];
    addTearDown(() {
      for (final f in frames) {
        f.dispose();
      }
    });

    final gifBytes = await encodeAnimation(frames, AnimFormat.gif, fps: 10);
    final gif = img.decodeGif(gifBytes)!;
    expect(gif.numFrames, 3);
    expect(gif.frames[0].frameDuration, 100);

    final apngBytes = await encodeAnimation(frames, AnimFormat.apng, fps: 10);
    final apng = img.decodePng(apngBytes)!;
    expect(apng.numFrames, 3);

    final webpBytes = await encodeAnimation(frames, AnimFormat.webp, fps: 10);
    final webp = img.decodeWebP(webpBytes)!;
    expect(webp.numFrames, 3);
  });

  test('encodeAnimation throws ArgumentError on empty list or mismatched sizes', () async {
    expect(
      () => encodeAnimation(const [], AnimFormat.gif, fps: 10),
      throwsArgumentError,
    );

    final a = solidImage(8, 8, const Color(0xFFFF0000));
    final b = solidImage(10, 8, const Color(0xFF00FF00));
    addTearDown(() {
      a.dispose();
      b.dispose();
    });
    expect(
      () => encodeAnimation([a, b], AnimFormat.gif, fps: 10),
      throwsArgumentError,
    );
  });

  test('buildSpriteSheet, spriteSheetJson and spriteSheetGodotTres', () async {
    final colors = [
      const Color(0xFFFF0000),
      const Color(0xFF00FF00),
      const Color(0xFF0000FF),
      const Color(0xFFFFFF00),
      const Color(0xFFFF00FF),
    ];
    final frames = [for (final c in colors) solidImage(16, 12, c)];
    addTearDown(() {
      for (final f in frames) {
        f.dispose();
      }
    });

    final sheet = buildSpriteSheet(frames, columns: 3, padding: 2);
    addTearDown(sheet.image.dispose);

    expect(sheet.columns, 3);
    expect(sheet.rows, 2);
    expect(sheet.image.width, 56);
    expect(sheet.image.height, 30);

    final rgba = await imageToRgba(sheet.image, straight: true);
    for (var i = 0; i < colors.length; i++) {
      final r = sheet.frameRect(i);
      final cx = r.center.dx.floor();
      final cy = r.center.dy.floor();
      final off = (cy * sheet.image.width + cx) * 4;
      final actual = Color.fromARGB(rgba[off + 3], rgba[off], rgba[off + 1], rgba[off + 2]);
      expect(actual.toARGB32(), colors[i].toARGB32(), reason: 'frame $i');
    }

    final jsonStr = spriteSheetJson(sheet, imageName: 'hero.png', fps: 10);
    final parsed = jsonDecode(jsonStr) as Map<String, dynamic>;
    final jsonFrames = parsed['frames'] as Map<String, dynamic>;
    expect(jsonFrames.length, 5);
    expect(jsonFrames.containsKey('anim_0000'), isTrue);
    expect(jsonFrames.containsKey('anim_0004'), isTrue);
    expect((jsonFrames['anim_0000'] as Map<String, dynamic>)['duration'], 100);
    final meta = parsed['meta'] as Map<String, dynamic>;
    expect(meta['size'], {'w': 56, 'h': 30});

    final tres = spriteSheetGodotTres(sheet, imagePath: 'res://hero.png', fps: 10);
    expect(tres, contains('[gd_resource type="SpriteFrames"'));
    expect('region = Rect2('.allMatches(tres).length, 5);
  });

  test('sequenceName pads to at least 4 digits and expands for larger totals', () {
    expect(sequenceName('walk', 7, 120, 'png'), 'walk_0007.png');
    expect(sequenceName('walk', 7, 123456, 'png'), 'walk_000007.png');
  });

  test('applyWatermark keeps size and modifies only bottom-right area', () async {
    final src = solidImage(200, 120, const Color(0xFF224466));
    final out = applyWatermark(src, 'Drawly', opacity: 0.6);
    addTearDown(() {
      src.dispose();
      out.dispose();
    });

    expect(out.width, 200);
    expect(out.height, 120);

    final srcBytes = await imageToRgba(src);
    final outBytes = await imageToRgba(out);
    var changedBottomRight = 0;
    var changedElsewhere = 0;
    for (var y = 0; y < 120; y++) {
      for (var x = 0; x < 200; x++) {
        final i = (y * 200 + x) * 4;
        final diff = srcBytes[i] != outBytes[i] ||
            srcBytes[i + 1] != outBytes[i + 1] ||
            srcBytes[i + 2] != outBytes[i + 2] ||
            srcBytes[i + 3] != outBytes[i + 3];
        if (diff) {
          if (x >= 100 && y >= 60) {
            changedBottomRight++;
          } else {
            changedElsewhere++;
          }
        }
      }
    }
    expect(changedBottomRight, greaterThan(0));
    expect(changedElsewhere, 0);
  });
}
