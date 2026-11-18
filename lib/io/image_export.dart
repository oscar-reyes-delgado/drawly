import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../engine/tiles.dart';

enum StillFormat { png, jpg, webp, bmp, tiff, tga }

enum AnimFormat { gif, apng, webp }

extension StillFormatX on StillFormat {
  String get ext => switch (this) {
        StillFormat.png => 'png',
        StillFormat.jpg => 'jpg',
        StillFormat.webp => 'webp',
        StillFormat.bmp => 'bmp',
        StillFormat.tiff => 'tiff',
        StillFormat.tga => 'tga',
      };

  String get mime => switch (this) {
        StillFormat.png => 'image/png',
        StillFormat.jpg => 'image/jpeg',
        StillFormat.webp => 'image/webp',
        StillFormat.bmp => 'image/bmp',
        StillFormat.tiff => 'image/tiff',
        StillFormat.tga => 'image/x-tga',
      };

  bool get hasAlpha => this != StillFormat.jpg && this != StillFormat.bmp;
}

extension AnimFormatX on AnimFormat {
  String get ext => switch (this) {
        AnimFormat.gif => 'gif',
        AnimFormat.apng => 'png',
        AnimFormat.webp => 'webp',
      };

  String get mime => switch (this) {
        AnimFormat.gif => 'image/gif',
        AnimFormat.apng => 'image/png',
        AnimFormat.webp => 'image/webp',
      };
}

/// Encodes one image. Formats without alpha are composited over [matte].
Future<Uint8List> encodeStill(
  ui.Image image,
  StillFormat format, {
  int quality = 90,
  Color matte = const Color(0xFFFFFFFF),
}) async {
  if (format == StillFormat.png) {
    final bd = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bd == null) {
      throw StateError('Failed to encode image as PNG.');
    }
    return bd.buffer.asUint8List(bd.offsetInBytes, bd.lengthInBytes);
  }

  final rgba = await imageToRgba(image, straight: true);
  return compute(_encodeStillIsolate, <String, Object>{
    'rgba': rgba,
    'width': image.width,
    'height': image.height,
    'format': format.index,
    'quality': quality.clamp(1, 100),
    'matte': matte.toARGB32(),
  });
}

Uint8List _encodeStillIsolate(Map<String, Object> args) {
  final src = args['rgba'] as Uint8List;
  final width = args['width'] as int;
  final height = args['height'] as int;
  final format = StillFormat.values[args['format'] as int];
  final quality = args['quality'] as int;
  final matteArgb = args['matte'] as int;

  final bytes = Uint8List.fromList(src);
  if (!format.hasAlpha) {
    final mr = (matteArgb >> 16) & 0xFF;
    final mg = (matteArgb >> 8) & 0xFF;
    final mb = matteArgb & 0xFF;
    for (var i = 0; i < bytes.length; i += 4) {
      final a = bytes[i + 3];
      if (a < 255) {
        final alpha = a / 255.0;
        final inv = 1.0 - alpha;
        bytes[i] = (bytes[i] * alpha + mr * inv).round().clamp(0, 255);
        bytes[i + 1] = (bytes[i + 1] * alpha + mg * inv).round().clamp(0, 255);
        bytes[i + 2] = (bytes[i + 2] * alpha + mb * inv).round().clamp(0, 255);
        bytes[i + 3] = 255;
      }
    }
  }

  final im = img.Image.fromBytes(
    width: width,
    height: height,
    bytes: bytes.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );

  return switch (format) {
    StillFormat.png => Uint8List.fromList(img.encodePng(im)),
    StillFormat.jpg => Uint8List.fromList(img.encodeJpg(im, quality: quality)),
    StillFormat.webp => Uint8List.fromList(img.encodeWebP(im)),
    StillFormat.bmp => Uint8List.fromList(img.encodeBmp(im)),
    StillFormat.tiff => Uint8List.fromList(img.encodeTiff(im)),
    StillFormat.tga => Uint8List.fromList(img.encodeTga(im)),
  };
}

/// Encodes same-sized frames as an animation. [loops] 0 = forever.
/// [frameDurationsMs] overrides the per-frame duration derived from [fps].
Future<Uint8List> encodeAnimation(
  List<ui.Image> frames,
  AnimFormat format, {
  required int fps,
  int loops = 0,
  List<int>? frameDurationsMs,
}) async {
  if (frames.isEmpty) {
    throw ArgumentError.value(frames, 'frames', 'Frame list must not be empty.');
  }
  if (fps <= 0) {
    throw ArgumentError.value(fps, 'fps', 'fps must be greater than zero.');
  }
  if (frameDurationsMs != null && frameDurationsMs.length != frames.length) {
    throw ArgumentError.value(
      frameDurationsMs,
      'frameDurationsMs',
      'Must match the number of frames (${frames.length}).',
    );
  }

  final width = frames.first.width;
  final height = frames.first.height;
  for (var i = 1; i < frames.length; i++) {
    if (frames[i].width != width || frames[i].height != height) {
      throw ArgumentError(
        'All frames must have the same dimensions ($width x $height); '
        'frame $i is ${frames[i].width} x ${frames[i].height}.',
      );
    }
  }

  final defaultDur = math.max(1, (1000 / fps).round());
  final durations = frameDurationsMs ?? List<int>.filled(frames.length, defaultDur);
  final rawFrames = await Future.wait([
    for (final f in frames) imageToRgba(f, straight: true),
  ]);

  return compute(_encodeAnimIsolate, <String, Object>{
    'frames': rawFrames,
    'width': width,
    'height': height,
    'format': format.index,
    'loops': loops,
    'durations': durations,
  });
}

Uint8List _encodeAnimIsolate(Map<String, Object> args) {
  final rawFrames = args['frames'] as List<Uint8List>;
  final width = args['width'] as int;
  final height = args['height'] as int;
  final format = AnimFormat.values[args['format'] as int];
  final loops = args['loops'] as int;
  final durations = args['durations'] as List<int>;

  img.Image buildFrame(int index) {
    final copy = Uint8List.fromList(rawFrames[index]);
    return img.Image.fromBytes(
      width: width,
      height: height,
      bytes: copy.buffer,
      numChannels: 4,
      order: img.ChannelOrder.rgba,
      frameDuration: durations[index],
    );
  }

  final anim = buildFrame(0)..loopCount = loops;
  for (var i = 1; i < rawFrames.length; i++) {
    anim.addFrame(buildFrame(i));
  }

  return switch (format) {
    AnimFormat.gif => Uint8List.fromList(img.encodeGif(anim, repeat: loops)),
    AnimFormat.apng => Uint8List.fromList(img.encodePng(anim)),
    AnimFormat.webp => Uint8List.fromList(img.encodeWebP(anim)),
  };
}

class SpriteSheet {
  const SpriteSheet({
    required this.image,
    required this.columns,
    required this.rows,
    required this.frameWidth,
    required this.frameHeight,
    required this.frameCount,
    this.padding = 0,
  });

  final ui.Image image;
  final int columns, rows, frameWidth, frameHeight, frameCount, padding;

  Rect frameRect(int index) {
    if (index < 0 || index >= frameCount) {
      throw RangeError.index(index, this, 'index', null, frameCount);
    }
    final col = index % columns;
    final row = index ~/ columns;
    return Rect.fromLTWH(
      (padding + col * (frameWidth + padding)).toDouble(),
      (padding + row * (frameHeight + padding)).toDouble(),
      frameWidth.toDouble(),
      frameHeight.toDouble(),
    );
  }
}

/// Packs frames on a grid, row by row. [columns] defaults to ceil(sqrt(n)).
SpriteSheet buildSpriteSheet(List<ui.Image> frames, {int? columns, int padding = 0}) {
  if (frames.isEmpty) {
    throw ArgumentError.value(frames, 'frames', 'Frame list must not be empty.');
  }
  if (padding < 0) {
    throw ArgumentError.value(padding, 'padding', 'padding must be >= 0.');
  }
  final fw = frames.first.width;
  final fh = frames.first.height;
  for (var i = 1; i < frames.length; i++) {
    if (frames[i].width != fw || frames[i].height != fh) {
      throw ArgumentError(
        'All frames must have the same dimensions ($fw x $fh); '
        'frame $i is ${frames[i].width} x ${frames[i].height}.',
      );
    }
  }

  final cols = columns ?? math.sqrt(frames.length).ceil();
  if (cols < 1) {
    throw ArgumentError.value(columns, 'columns', 'columns must be >= 1.');
  }
  final rows = (frames.length / cols).ceil();
  final width = cols * fw + (cols + 1) * padding;
  final height = rows * fh + (rows + 1) * padding;

  final copyPaint = Paint()
    ..filterQuality = FilterQuality.none
    ..isAntiAlias = false;

  final image = renderToImage(width, height, (canvas) {
    for (var i = 0; i < frames.length; i++) {
      final col = i % cols;
      final row = i ~/ cols;
      final dx = (padding + col * (fw + padding)).toDouble();
      final dy = (padding + row * (fh + padding)).toDouble();
      canvas.drawImage(frames[i], Offset(dx, dy), copyPaint);
    }
  });

  return SpriteSheet(
    image: image,
    columns: cols,
    rows: rows,
    frameWidth: fw,
    frameHeight: fh,
    frameCount: frames.length,
    padding: padding,
  );
}

/// TexturePacker "JSON (Hash)" metadata (read by Unity, Godot and Phaser importers).
String spriteSheetJson(
  SpriteSheet sheet, {
  required String imageName,
  required int fps,
  String animName = 'anim',
}) {
  final durationMs = math.max(1, (1000 / math.max(1, fps)).round());
  final digits = math.max(4, sheet.frameCount.toString().length);
  final frames = <String, Object>{};
  for (var i = 0; i < sheet.frameCount; i++) {
    final r = sheet.frameRect(i);
    final key = '${animName}_${i.toString().padLeft(digits, '0')}';
    frames[key] = <String, Object>{
      'frame': <String, int>{
        'x': r.left.round(),
        'y': r.top.round(),
        'w': sheet.frameWidth,
        'h': sheet.frameHeight,
      },
      'rotated': false,
      'trimmed': false,
      'spriteSourceSize': <String, int>{
        'x': 0,
        'y': 0,
        'w': sheet.frameWidth,
        'h': sheet.frameHeight,
      },
      'sourceSize': <String, int>{
        'w': sheet.frameWidth,
        'h': sheet.frameHeight,
      },
      'duration': durationMs,
    };
  }

  return jsonEncode(<String, Object>{
    'frames': frames,
    'meta': <String, Object>{
      'app': 'Drawly',
      'image': imageName,
      'format': 'RGBA8888',
      'size': <String, int>{
        'w': sheet.image.width,
        'h': sheet.image.height,
      },
      'scale': '1',
      'frameTags': <Object>[
        <String, Object>{
          'name': animName,
          'from': 0,
          'to': sheet.frameCount - 1,
          'direction': 'forward',
        },
      ],
    },
  });
}

/// Godot 4 SpriteFrames resource (.tres) pointing at [imagePath] (res://…).
String spriteSheetGodotTres(
  SpriteSheet sheet, {
  required String imagePath,
  required int fps,
  String animName = 'default',
}) {
  final loadSteps = sheet.frameCount + 2;
  final sb = StringBuffer()
    ..writeln('[gd_resource type="SpriteFrames" load_steps=$loadSteps format=3]')
    ..writeln()
    ..writeln('[ext_resource type="Texture2D" path="$imagePath" id="1_tex"]')
    ..writeln();

  for (var i = 0; i < sheet.frameCount; i++) {
    final r = sheet.frameRect(i);
    sb
      ..writeln('[sub_resource type="AtlasTexture" id="AtlasTexture_$i"]')
      ..writeln('atlas = ExtResource("1_tex")')
      ..writeln('region = Rect2(${r.left.round()}, ${r.top.round()}, ${sheet.frameWidth}, ${sheet.frameHeight})')
      ..writeln();
  }

  sb
    ..writeln('[resource]')
    ..writeln('animations = [{')
    ..writeln('"frames": [');
  for (var i = 0; i < sheet.frameCount; i++) {
    final comma = i < sheet.frameCount - 1 ? ',' : '';
    sb
      ..writeln('{')
      ..writeln('"duration": 1.0,')
      ..writeln('"texture": SubResource("AtlasTexture_$i")')
      ..writeln('}$comma');
  }
  sb
    ..writeln('],')
    ..writeln('"loop": true,')
    ..writeln('"name": &"$animName",')
    ..writeln('"speed": ${fps.toDouble()}')
    ..writeln('}]');

  return sb.toString();
}

/// `walk_0007.png`: zero padded to at least 4 digits (more when [total] needs it).
String sequenceName(String base, int index, int total, String ext) {
  final digits = math.max(4, total.toString().length);
  final padded = index.toString().padLeft(digits, '0');
  final cleanExt = ext.startsWith('.') ? ext.substring(1) : ext;
  return '${base}_$padded.$cleanExt';
}

/// Returns a copy of [source] with [text] drawn in the bottom-right corner.
ui.Image applyWatermark(ui.Image source, String text, {double opacity = 0.35}) {
  final w = source.width;
  final h = source.height;
  final copyPaint = Paint()
    ..filterQuality = FilterQuality.none
    ..isAntiAlias = false;

  return renderToImage(w, h, (canvas) {
    canvas.drawImage(source, Offset.zero, copyPaint);
    if (text.isEmpty) return;

    final minSide = math.min(w, h).toDouble();
    final fontSize = math.max(8.0, minSide * 0.03);
    final margin = fontSize;
    final alpha = opacity.clamp(0.0, 1.0);
    final maxWidth = math.max(1.0, w - margin * 2);

    ui.Paragraph buildPara(ui.TextStyle style) {
      final pb = ui.ParagraphBuilder(
        ui.ParagraphStyle(
          textAlign: TextAlign.right,
          maxLines: 1,
        ),
      )
        ..pushStyle(style)
        ..addText(text);
      return pb.build()..layout(ui.ParagraphConstraints(width: maxWidth));
    }

    final strokePara = buildPara(
      ui.TextStyle(
        fontSize: fontSize,
        foreground: Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.0, fontSize * 0.16)
          ..color = const Color(0xFF000000).withValues(alpha: alpha),
      ),
    );
    final fillPara = buildPara(
      ui.TextStyle(
        fontSize: fontSize,
        color: const Color(0xFFFFFFFF).withValues(alpha: alpha),
      ),
    );

    final textW = math.min(maxWidth, fillPara.maxIntrinsicWidth);
    final dx = math.max(0.0, w - margin - textW);
    final dy = math.max(0.0, h - margin - fillPara.height);
    // Paragraph is right-aligned inside [maxWidth], so anchor its right edge at w - margin.
    final paraX = w - margin - maxWidth;
    final offset = Offset(dx < paraX ? dx : paraX, dy);
    canvas.drawParagraph(strokePara, offset);
    canvas.drawParagraph(fillPara, offset);
    strokePara.dispose();
    fillPara.dispose();
  });
}
