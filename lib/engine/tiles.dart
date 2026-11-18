import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui';

/// Edge length of one raster tile in pixels.
const int kTile = 256;
const double kTileF = 256.0;

int tileKey(int tx, int ty) => (tx + 0x8000) * 0x10000 + (ty + 0x8000);
int tileKeyX(int k) => (k ~/ 0x10000) - 0x8000;
int tileKeyY(int k) => (k % 0x10000) - 0x8000;
Rect tileRectOf(int k) => Rect.fromLTWH(tileKeyX(k) * kTileF, tileKeyY(k) * kTileF, kTileF, kTileF);

/// Keys of every tile touched by [r].
Iterable<int> tileKeysIn(Rect r) sync* {
  if (r.isEmpty) return;
  final x0 = (r.left / kTileF).floor(), y0 = (r.top / kTileF).floor();
  final x1 = ((r.right - 1e-6) / kTileF).floor(), y1 = ((r.bottom - 1e-6) / kTileF).floor();
  for (var ty = y0; ty <= y1; ty++) {
    for (var tx = x0; tx <= x1; tx++) {
      yield tileKey(tx, ty);
    }
  }
}

/// Immutable, sparse raster plane made of GPU-resident 256px tiles.
///
/// Every mutating operation returns a new plane that shares all untouched
/// tiles with its source, which makes document snapshots (undo history,
/// animation frames, duplicated layers) nearly free.
class TilePlane {
  const TilePlane._(this._tiles);

  static const TilePlane empty = TilePlane._(<int, ui.Image>{});

  final Map<int, ui.Image> _tiles;

  bool get isEmpty => _tiles.isEmpty;
  bool get isNotEmpty => _tiles.isNotEmpty;
  int get tileCount => _tiles.length;
  Iterable<int> get keys => _tiles.keys;
  ui.Image? operator [](int key) => _tiles[key];
  bool containsKey(int key) => _tiles.containsKey(key);
  int get approxBytes => _tiles.length * kTile * kTile * 4;

  static final Paint _copyPaint = Paint()
    ..blendMode = BlendMode.src
    ..isAntiAlias = false
    ..filterQuality = FilterQuality.none;

  static final Paint _nearest = Paint()
    ..isAntiAlias = false
    ..filterQuality = FilterQuality.none;
  static final Paint _linear = Paint()
    ..isAntiAlias = false
    ..filterQuality = FilterQuality.low;
  static final Paint _mip = Paint()
    ..isAntiAlias = false
    ..filterQuality = FilterQuality.medium;

  static Paint paintFor(FilterQuality q) => switch (q) {
        FilterQuality.none => _nearest,
        FilterQuality.low => _linear,
        _ => _mip,
      };

  /// Tile-aligned bounds of everything stored (coarse, never smaller than the content).
  Rect? get bounds {
    if (_tiles.isEmpty) return null;
    var x0 = 1 << 30, y0 = 1 << 30, x1 = -(1 << 30), y1 = -(1 << 30);
    for (final k in _tiles.keys) {
      final x = tileKeyX(k), y = tileKeyY(k);
      if (x < x0) x0 = x;
      if (y < y0) y0 = y;
      if (x > x1) x1 = x;
      if (y > y1) y1 = y;
    }
    return Rect.fromLTRB(x0 * kTileF, y0 * kTileF, (x1 + 1) * kTileF, (y1 + 1) * kTileF);
  }

  /// Draws the stored tiles in plane coordinates.
  void paint(Canvas canvas, {Rect? cull, Paint? paint}) {
    if (_tiles.isEmpty) return;
    final p = paint ?? _nearest;
    if (cull == null) {
      _tiles.forEach((k, img) {
        canvas.drawImage(img, Offset(tileKeyX(k) * kTileF, tileKeyY(k) * kTileF), p);
      });
      return;
    }
    final x0 = (cull.left / kTileF).floor(), y0 = (cull.top / kTileF).floor();
    final x1 = ((cull.right - 1e-6) / kTileF).floor(), y1 = ((cull.bottom - 1e-6) / kTileF).floor();
    final span = (x1 - x0 + 1) * (y1 - y0 + 1);
    if (span <= _tiles.length * 2 && span > 0) {
      for (var ty = y0; ty <= y1; ty++) {
        for (var tx = x0; tx <= x1; tx++) {
          final img = _tiles[tileKey(tx, ty)];
          if (img != null) canvas.drawImage(img, Offset(tx * kTileF, ty * kTileF), p);
        }
      }
    } else {
      _tiles.forEach((k, img) {
        final tx = tileKeyX(k), ty = tileKeyY(k);
        if (tx >= x0 && tx <= x1 && ty >= y0 && ty <= y1) {
          canvas.drawImage(img, Offset(tx * kTileF, ty * kTileF), p);
        }
      });
    }
  }

  /// Returns a plane with [painter] drawn on top of the existing content.
  ///
  /// The painter works in plane coordinates and is rasterised only into the
  /// tiles given by [keys], or those intersecting [area].
  TilePlane drawn(void Function(Canvas canvas) painter, {Rect? area, Iterable<int>? keys}) {
    assert(area != null || keys != null, 'drawn() needs an area or tile keys');
    final targets = keys ?? tileKeysIn(area!);
    final it = targets.iterator;
    if (!it.moveNext()) return this;

    final rec = ui.PictureRecorder();
    painter(Canvas(rec));
    final pic = rec.endRecording();

    final out = Map<int, ui.Image>.of(_tiles);
    do {
      final key = it.current;
      final r = ui.PictureRecorder();
      final c = Canvas(r, const Rect.fromLTWH(0, 0, kTileF, kTileF));
      final old = _tiles[key];
      if (old != null) c.drawImage(old, Offset.zero, _copyPaint);
      c.translate(-tileKeyX(key) * kTileF, -tileKeyY(key) * kTileF);
      c.drawPicture(pic);
      final p = r.endRecording();
      out[key] = p.toImageSync(kTile, kTile);
      p.dispose();
    } while (it.moveNext());
    pic.dispose();
    return TilePlane._(out);
  }

  /// Like [drawn] but starts every target tile from transparent instead of
  /// the existing content.
  TilePlane redrawn(void Function(Canvas canvas) painter, {Rect? area, Iterable<int>? keys}) {
    final targets = (keys ?? tileKeysIn(area!)).toList();
    if (targets.isEmpty) return this;
    final rec = ui.PictureRecorder();
    painter(Canvas(rec));
    final pic = rec.endRecording();
    final out = Map<int, ui.Image>.of(_tiles);
    for (final key in targets) {
      final r = ui.PictureRecorder();
      final c = Canvas(r, const Rect.fromLTWH(0, 0, kTileF, kTileF));
      c.translate(-tileKeyX(key) * kTileF, -tileKeyY(key) * kTileF);
      c.drawPicture(pic);
      final p = r.endRecording();
      out[key] = p.toImageSync(kTile, kTile);
      p.dispose();
    }
    pic.dispose();
    return TilePlane._(out);
  }

  /// Replaces / removes individual tiles.
  TilePlane withTiles(Map<int, ui.Image?> changes) {
    if (changes.isEmpty) return this;
    final out = Map<int, ui.Image>.of(_tiles);
    changes.forEach((k, v) {
      if (v == null) {
        out.remove(k);
      } else {
        out[k] = v;
      }
    });
    return TilePlane._(out);
  }

  /// Copy restricted to the tiles intersecting [area] (coarse crop).
  TilePlane tilesIn(Rect area) {
    final out = <int, ui.Image>{};
    for (final k in tileKeysIn(area)) {
      final t = _tiles[k];
      if (t != null) out[k] = t;
    }
    return TilePlane._(out);
  }

  /// Draws [image] with its top-left at [at]. With [BlendMode.src] the
  /// covered pixels are replaced.
  TilePlane withImage(ui.Image image, Offset at, {BlendMode blend = BlendMode.srcOver, double opacity = 1}) {
    final rect = Rect.fromLTWH(at.dx, at.dy, image.width.toDouble(), image.height.toDouble());
    final paint = Paint()
      ..blendMode = blend
      ..filterQuality = FilterQuality.none
      ..isAntiAlias = false;
    if (opacity < 1) paint.color = Color.fromRGBO(0, 0, 0, opacity);
    return drawn((c) => c.drawImage(image, at, paint), area: rect);
  }

  /// Composites [top] over this plane (tile by tile) using [paint].
  TilePlane composited(TilePlane top, {Paint? paint}) {
    if (top.isEmpty) return this;
    final p = paint ?? _nearest;
    final out = Map<int, ui.Image>.of(_tiles);
    top._tiles.forEach((key, img) {
      final old = _tiles[key];
      final r = ui.PictureRecorder();
      final c = Canvas(r, const Rect.fromLTWH(0, 0, kTileF, kTileF));
      if (old != null) c.drawImage(old, Offset.zero, _copyPaint);
      c.drawImage(img, Offset.zero, p);
      final pic = r.endRecording();
      out[key] = pic.toImageSync(kTile, kTile);
      pic.dispose();
    });
    return TilePlane._(out);
  }

  /// Makes [area] fully transparent.
  TilePlane cleared(Rect area) {
    if (_tiles.isEmpty) return this;
    final touched = <int>[];
    final removed = <int, ui.Image?>{};
    for (final k in tileKeysIn(area)) {
      if (!_tiles.containsKey(k)) continue;
      final tr = tileRectOf(k);
      if (area.left <= tr.left && area.top <= tr.top && area.right >= tr.right && area.bottom >= tr.bottom) {
        removed[k] = null;
      } else {
        touched.add(k);
      }
    }
    var out = removed.isEmpty ? this : withTiles(removed);
    if (touched.isNotEmpty) {
      final clear = Paint()..blendMode = BlendMode.clear;
      out = out.drawn((c) => c.drawRect(area, clear), keys: touched);
    }
    return out;
  }

  /// Erases wherever [path] covers.
  TilePlane clearedPath(Path path) {
    if (_tiles.isEmpty) return this;
    final keys = tileKeysIn(path.getBounds()).where(_tiles.containsKey).toList();
    if (keys.isEmpty) return this;
    final clear = Paint()..blendMode = BlendMode.dstOut;
    return drawn((c) => c.drawPath(path, clear), keys: keys);
  }

  /// Keeps only what [mask]'s alpha covers (or removes it when [invert]).
  TilePlane maskedBy(TilePlane mask, {bool invert = false}) {
    if (_tiles.isEmpty) return this;
    final out = <int, ui.Image>{};
    _tiles.forEach((key, img) {
      final m = mask._tiles[key];
      if (m == null) {
        if (invert) out[key] = img;
        return;
      }
      final r = ui.PictureRecorder();
      final c = Canvas(r, const Rect.fromLTWH(0, 0, kTileF, kTileF));
      c.drawImage(img, Offset.zero, _copyPaint);
      c.drawImage(m, Offset.zero, Paint()..blendMode = invert ? BlendMode.dstOut : BlendMode.dstIn);
      final pic = r.endRecording();
      out[key] = pic.toImageSync(kTile, kTile);
      pic.dispose();
    });
    return TilePlane._(out);
  }

  /// Moves the content. Whole-tile moves just re-key the tiles.
  TilePlane translated(double dx, double dy) {
    if (_tiles.isEmpty || (dx == 0 && dy == 0)) return this;
    if (dx % kTile == 0 && dy % kTile == 0) {
      final ox = dx ~/ kTile, oy = dy ~/ kTile;
      final out = <int, ui.Image>{};
      _tiles.forEach((k, v) => out[tileKey(tileKeyX(k) + ox, tileKeyY(k) + oy)] = v);
      return TilePlane._(out);
    }
    final b = bounds!.shift(Offset(dx, dy));
    return TilePlane.empty.drawn((c) {
      c.translate(dx, dy);
      paint(c, paint: dx == dx.roundToDouble() && dy == dy.roundToDouble() ? _nearest : _linear);
    }, area: b);
  }

  /// Flattens [rect] into a single image (optionally scaled).
  ui.Image toImage(Rect rect, {double scale = 1.0, Color? background}) {
    final w = math.max(1, (rect.width * scale).ceil()), h = math.max(1, (rect.height * scale).ceil());
    final rec = ui.PictureRecorder();
    final c = Canvas(rec, Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()));
    if (background != null) c.drawColor(background, BlendMode.src);
    if (scale != 1.0) c.scale(scale);
    c.translate(-rect.left, -rect.top);
    paint(c, cull: rect, paint: scale == 1.0 ? _nearest : (scale < 1 ? _mip : _linear));
    final pic = rec.endRecording();
    final img = pic.toImageSync(w, h);
    pic.dispose();
    return img;
  }

  /// Premultiplied RGBA8888 bytes of [rect] (which must be integer aligned).
  Future<Uint8List> readRgba(Rect rect, {bool straight = false}) async {
    final img = toImage(rect);
    try {
      final data = await img.toByteData(
        format: straight ? ui.ImageByteFormat.rawStraightRgba : ui.ImageByteFormat.rawRgba,
      );
      return data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } finally {
      img.dispose();
    }
  }

  /// Exact bounds of non-transparent pixels (async: needs a readback).
  Future<Rect?> contentBounds() async {
    final b = bounds;
    if (b == null) return null;
    final w = b.width.toInt(), h = b.height.toInt();
    final px = await readRgba(b);
    var x0 = w, y0 = h, x1 = -1, y1 = -1;
    for (var y = 0; y < h; y++) {
      var o = y * w * 4 + 3;
      for (var x = 0; x < w; x++, o += 4) {
        if (px[o] != 0) {
          if (x < x0) x0 = x;
          if (x > x1) x1 = x;
          if (y < y0) y0 = y;
          if (y > y1) y1 = y;
        }
      }
    }
    if (x1 < 0) return null;
    return Rect.fromLTRB(b.left + x0, b.top + y0, b.left + x1 + 1, b.top + y1 + 1);
  }

  /// Drops tiles that became fully transparent (after erasing).
  Future<TilePlane> compacted() async {
    if (_tiles.isEmpty) return this;
    final drop = <int, ui.Image?>{};
    final entries = _tiles.entries.toList();
    await Future.wait(entries.map((e) async {
      final data = await e.value.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) return;
      final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      for (var i = 3; i < bytes.length; i += 4) {
        if (bytes[i] != 0) return;
      }
      drop[e.key] = null;
    }));
    return drop.isEmpty ? this : withTiles(drop);
  }

  /// Builds a plane from premultiplied RGBA bytes placed at [origin].
  static Future<TilePlane> fromRgba(Uint8List rgba, int width, int height, {Offset origin = Offset.zero}) async {
    final img = await imageFromRgba(rgba, width, height);
    final plane = TilePlane.empty.withImage(img, origin, blend: BlendMode.src);
    return plane;
  }

  static TilePlane fromImage(ui.Image image, {Offset origin = Offset.zero}) =>
      TilePlane.empty.withImage(image, origin, blend: BlendMode.src);
}

/// Decodes premultiplied RGBA8888 bytes into a GPU image.
Future<ui.Image> imageFromRgba(Uint8List rgba, int width, int height) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(rgba);
  final desc = ui.ImageDescriptor.raw(buffer, width: width, height: height, pixelFormat: ui.PixelFormat.rgba8888);
  final codec = await desc.instantiateCodec();
  final frame = await codec.getNextFrame();
  codec.dispose();
  desc.dispose();
  buffer.dispose();
  return frame.image;
}

/// Decodes an encoded image file (PNG/JPEG/GIF/WebP/BMP…).
Future<ui.Image> decodeImageBytes(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  codec.dispose();
  return frame.image;
}

/// Reads an image back as premultiplied (or straight) RGBA8888.
Future<Uint8List> imageToRgba(ui.Image img, {bool straight = false}) async {
  final data = await img.toByteData(
    format: straight ? ui.ImageByteFormat.rawStraightRgba : ui.ImageByteFormat.rawRgba,
  );
  return data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

/// Rasterises [painter] into a new image of the given size.
ui.Image renderToImage(int width, int height, void Function(Canvas canvas) painter) {
  final rec = ui.PictureRecorder();
  final c = Canvas(rec, Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()));
  painter(c);
  final pic = rec.endRecording();
  final img = pic.toImageSync(math.max(1, width), math.max(1, height));
  pic.dispose();
  return img;
}
