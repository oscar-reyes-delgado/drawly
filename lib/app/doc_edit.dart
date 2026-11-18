import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:ui';

import '../core/i18n.dart';
import '../core/ids.dart';
import '../core/mat2d.dart';
import '../engine/filters.dart';
import '../engine/pixel_ops.dart';
import '../engine/tiles.dart';
import '../model/filter_spec.dart';
import '../model/gradient.dart';
import '../model/layer.dart';
import '../model/vector.dart';
import 'doc_layers.dart';
import 'doc_selection.dart';
import 'document_controller.dart';

/// In-app clipboard (pixels, layers and vector shapes).
class DrawlyClipboard {
  static TilePlane? pixels;
  static Rect? bounds;
  static List<Layer> layers = const [];
  static List<VShape> shapes = const [];

  static bool get hasContent => pixels != null || layers.isNotEmpty || shapes.isNotEmpty;
}

final Paint _dstOutPaint = Paint()..blendMode = BlendMode.dstOut;
final Paint _dstInPaint = Paint()..blendMode = BlendMode.dstIn;
final Paint _plusPaint = Paint()..blendMode = BlendMode.plus;

/// Pixel editing: clear / fill / gradient / clipboard / filters.
extension DocEdit on DocumentController {
  /// Replaces the selected part of [target] by what [painter] draws
  /// (`old * (1 - sel) + new * sel`); without a selection the painter result
  /// replaces [area] entirely.
  TilePlane replaceInSelection(TilePlane target, Rect area, void Function(Canvas c) painter) {
    final sel = comp.selection;
    var a = area.roundedOut;
    if (!comp.infinite) a = a.intersect(comp.rect);
    if (a.isEmpty || a.width <= 0 || a.height <= 0) return target;
    if (sel == null) {
      return target.cleared(a).drawn((c) {
        c.clipRect(a);
        painter(c);
      }, area: a);
    }
    final b = a.intersect(sel.bounds.roundedOut);
    if (b.isEmpty || b.width <= 0 || b.height <= 0) return target;
    return target.drawn((c) {
      c.clipRect(b);
      c.saveLayer(b, _dstOutPaint);
      sel.mask.paint(c, cull: b);
      c.restore();
      c.saveLayer(b, _plusPaint);
      painter(c);
      c.saveLayer(b, _dstInPaint);
      sel.mask.paint(c, cull: b);
      c.restore();
      c.restore();
    }, area: b);
  }

  /// Draws [painter] on top of [target], limited to the selection and the
  /// canvas, honouring alpha lock.
  TilePlane paintOver(TilePlane target, Rect area, void Function(Canvas c) painter, {bool lockAlpha = false, BlendMode blend = BlendMode.srcOver, double opacity = 1}) {
    final sel = comp.selection;
    var a = area.roundedOut;
    if (!comp.infinite) a = a.intersect(comp.rect);
    if (sel != null) a = a.intersect(sel.bounds.roundedOut);
    if (a.isEmpty || a.width <= 0 || a.height <= 0) return target;
    return target.drawn((c) {
      c.clipRect(a);
      final lp = Paint()..blendMode = lockAlpha && blend == BlendMode.srcOver ? BlendMode.srcATop : blend;
      if (opacity < 1) lp.color = Color.fromRGBO(0, 0, 0, opacity.clamp(0.0, 1.0));
      c.saveLayer(a, lp);
      painter(c);
      if (sel != null) {
        c.saveLayer(a, _dstInPaint);
        sel.mask.paint(c, cull: a);
        c.restore();
      }
      c.restore();
    }, area: a);
  }

  /// Deletes the selected pixels (or everything on the drawing).
  void clearPixels() {
    final l = activeLayer;
    if (l is VectorLayer) {
      final t = resolveVectorTarget();
      if (t == null) return;
      commitVector(tr('Borrar', 'Clear'), t.project, t.layer.id, t.drawing, VectorArt.empty);
      return;
    }
    final t = resolvePaintTarget();
    if (t == null) return;
    final sel = comp.selection;
    TilePlane out;
    if (sel == null) {
      out = TilePlane.empty;
    } else {
      final keys = sel.mask.keys.where(t.plane.containsKey).toList();
      out = keys.isEmpty ? t.plane : t.plane.drawn((c) => sel.mask.paint(c, paint: _dstOutPaint), keys: keys);
    }
    commitPaint(tr('Borrar', 'Clear'), t, out);
  }

  /// Fills the selection (or the canvas) with a flat colour.
  void fillColor(Color color, {double opacity = 1, BlendMode blend = BlendMode.srcOver}) {
    final t = resolvePaintTarget();
    if (t == null) return;
    final area = comp.selection?.bounds ?? workRect;
    final lock = !t.onMask && (t.layer?.props.lockAlpha ?? false);
    final out = paintOver(t.plane, area, (c) => c.drawRect(area, Paint()..color = color), lockAlpha: lock, blend: blend, opacity: opacity);
    commitPaint(tr('Rellenar', 'Fill'), t, out);
  }

  /// Draws a gradient into the selection (or the canvas).
  void fillGradient(GradientSpec g, {double opacity = 1, BlendMode blend = BlendMode.srcOver}) {
    final t = resolvePaintTarget();
    if (t == null) return;
    final area = comp.selection?.bounds ?? workRect;
    final lock = !t.onMask && (t.layer?.props.lockAlpha ?? false);
    final out = paintOver(t.plane, area, (c) => g.paint(c, area), lockAlpha: lock, blend: blend, opacity: opacity);
    commitPaint(tr('Degradado', 'Gradient'), t, out);
  }

  /// Paint bucket.
  Future<void> bucketFill(
    Offset docPoint,
    Color color, {
    int tolerance = 32,
    bool contiguous = true,
    SampleSource source = SampleSource.layer,
    double expand = 0,
    int gap = 0,
    bool antiAlias = true,
    double opacity = 1,
    BlendMode blend = BlendMode.srcOver,
  }) async {
    await run(tr('Cubo de relleno', 'Paint bucket'), () async {
      final t = resolvePaintTarget();
      if (t == null) return;
      final snap = await snapshot(source);
      if (snap == null) return;
      final x = (docPoint.dx - snap.rect.left).floor(), y = (docPoint.dy - snap.rect.top).floor();
      final m = floodSelect(snap.rgba, snap.width, snap.height, x, y,
          tolerance: tolerance, softness: antiAlias ? 28 : 0, contiguous: contiguous, gap: gap);
      final b = m.bounds;
      if (b == null) return;
      final maskImg = await imageFromRgba(m.toRgba(), m.width, m.height);
      final area = b.shift(snap.rect.topLeft).inflate(expand.abs() + 2);
      final lock = !t.onMask && (t.layer?.props.lockAlpha ?? false);
      final out = paintOver(t.plane, area, (c) {
        final p = Paint()..colorFilter = ColorFilter.mode(color.withValues(alpha: 1), BlendMode.srcIn);
        if (expand > 0) {
          p.imageFilter = ui.ImageFilter.dilate(radiusX: expand, radiusY: expand);
        } else if (expand < 0) {
          p.imageFilter = ui.ImageFilter.erode(radiusX: -expand, radiusY: -expand);
        }
        c.saveLayer(area, p);
        c.drawImage(maskImg, snap.rect.topLeft, Paint());
        c.restore();
      }, lockAlpha: lock, blend: blend, opacity: opacity * color.a);
      maskImg.dispose();
      commitPaint(tr('Cubo de relleno', 'Paint bucket'), t, out);
    });
  }

  /// Strokes the outline of the selection.
  void strokeSelection(Color color, double width) {
    final sel = comp.selection;
    final t = resolvePaintTarget();
    if (sel == null || t == null) return;
    final area = sel.bounds.inflate(width + 2).roundedOut;
    final out = t.plane.drawn((c) {
      if (!comp.infinite) c.clipRect(comp.rect);
      c.saveLayer(area, Paint()..colorFilter = ColorFilter.mode(color, BlendMode.srcIn));
      c.saveLayer(area, Paint()..imageFilter = ui.ImageFilter.dilate(radiusX: width / 2, radiusY: width / 2));
      sel.mask.paint(c);
      c.restore();
      c.saveLayer(
        area,
        Paint()
          ..imageFilter = ui.ImageFilter.erode(radiusX: width / 2, radiusY: width / 2)
          ..blendMode = BlendMode.dstOut,
      );
      sel.mask.paint(c);
      c.restore();
      c.restore();
    }, area: area);
    commitPaint(tr('Contornear selección', 'Stroke selection'), t, out);
  }

  // ---- clipboard ----------------------------------------------------------

  bool copyPixels({bool merged = false}) {
    final sel = comp.selection;
    TilePlane? plane;
    if (merged) {
      plane = samplePlane(SampleSource.allLayers);
    } else {
      final l = activeLayer;
      if (l is PaintLayer || merged) {
        plane = samplePlane(SampleSource.layer);
      } else if (l != null) {
        DrawlyClipboard.layers = [l];
        DrawlyClipboard.pixels = null;
        DrawlyClipboard.shapes = const [];
        return true;
      }
    }
    if (plane == null) return false;
    DrawlyClipboard.pixels = sel == null ? plane : plane.maskedBy(sel.mask);
    DrawlyClipboard.bounds = sel?.bounds ?? plane.bounds ?? comp.rect;
    DrawlyClipboard.layers = const [];
    DrawlyClipboard.shapes = const [];
    return true;
  }

  void cutPixels() {
    if (activeLayer is! PaintLayer) return;
    if (copyPixels()) clearPixels();
  }

  /// Pastes the clipboard as a new layer.
  void paste() {
    if (DrawlyClipboard.layers.isNotEmpty) {
      for (final l in DrawlyClipboard.layers) {
        addLayer(cloneLayer(l, name: '${l.name} ${tr('copia', 'copy')}'), label: tr('Pegar capa', 'Paste layer'));
      }
      return;
    }
    if (DrawlyClipboard.shapes.isNotEmpty) {
      final t = resolveVectorTarget();
      if (t != null) {
        var art = t.art;
        for (final s in DrawlyClipboard.shapes) {
          art = art.added(s.copyWith(id: newId('s')).transformed(Mat2D.translation(12, 12)));
        }
        commitVector(tr('Pegar', 'Paste'), t.project, t.layer.id, t.drawing, art);
        return;
      }
    }
    final px = DrawlyClipboard.pixels;
    if (px == null) return;
    addPaintLayer(name: uniqueLayerName(tr('Pegado', 'Pasted')), pixels: px);
  }

  /// Adds an already decoded image as a new layer centred on the canvas.
  void addImageLayer(ui.Image image, String name, {bool fit = true}) {
    var w = image.width.toDouble(), h = image.height.toDouble();
    var scale = 1.0;
    if (fit && (w > comp.width || h > comp.height)) {
      scale = math.min(comp.width / w, comp.height / h);
      w *= scale;
      h *= scale;
    }
    final origin = Offset(((comp.width - w) / 2).roundToDouble(), ((comp.height - h) / 2).roundToDouble());
    final dst = Rect.fromLTWH(origin.dx, origin.dy, w, h);
    final plane = TilePlane.empty.drawn((c) {
      c.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        dst,
        Paint()..filterQuality = scale == 1 ? FilterQuality.none : FilterQuality.medium,
      );
    }, area: dst.roundedOut);
    addPaintLayer(name: name, pixels: plane);
  }

  // ---- filters ------------------------------------------------------------

  /// Image of [region] of [src] after applying [spec], already limited to
  /// the selection.
  ui.Image filteredRegion(TilePlane src, FilterSpec spec, Rect region) {
    final source = src.toImage(region);
    final out = renderToImage(region.width.toInt(), region.height.toInt(), (c) {
      final sel = comp.selection;
      if (sel == null) {
        paintFiltered(c, source, spec, origin: region.topLeft, extent: comp.rect);
        return;
      }
      final local = Rect.fromLTWH(0, 0, region.width, region.height);
      c.drawImage(source, Offset.zero, Paint());
      c.save();
      c.translate(-region.left, -region.top);
      c.saveLayer(region, _dstOutPaint);
      sel.mask.paint(c, cull: region);
      c.restore();
      c.restore();
      c.saveLayer(local, _plusPaint);
      paintFiltered(c, source, spec, origin: region.topLeft, extent: comp.rect);
      c.translate(-region.left, -region.top);
      c.saveLayer(region, _dstInPaint);
      sel.mask.paint(c, cull: region);
      c.restore();
      c.restore();
    });
    source.dispose();
    return out;
  }

  /// Region a destructive filter must process for the given plane.
  Rect filterRegion(TilePlane plane, FilterSpec spec) {
    final sel = comp.selection;
    final margin = filterMargin(spec);
    var r = sel?.bounds ?? (plane.bounds == null ? comp.rect : plane.bounds!.expandToInclude(comp.rect));
    r = r.inflate(sel == null ? margin : 0).roundedOut;
    if (!comp.infinite) r = r.intersect(comp.rect.inflate(margin));
    return r;
  }

  /// Applies [spec] to the active raster layer (current drawing).
  void applyFilterToActive(FilterSpec spec) {
    final t = resolvePaintTarget();
    if (t == null) return;
    final region = filterRegion(t.plane, spec);
    if (region.isEmpty || region.width < 1 || region.height < 1) return;
    final img = filteredRegion(t.plane, spec, region);
    final out = t.plane.cleared(region).withImage(img, region.topLeft, blend: BlendMode.src);
    img.dispose();
    commitPaint(spec.def.label, t, out);
  }
}
