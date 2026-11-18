import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui';

import '../core/i18n.dart';
import '../core/mat2d.dart';
import '../engine/compositor.dart';
import '../engine/pixel_ops.dart';
import '../engine/tiles.dart';
import '../model/document.dart';
import '../model/layer.dart';
import 'document_controller.dart';

enum SelectMode { replace, add, subtract, intersect }

/// What a wand / bucket samples.
enum SampleSource { layer, allLayers, reference }

extension SampleSourceLabel on SampleSource {
  String get label => switch (this) {
        SampleSource.layer => tr('Capa actual', 'Current layer'),
        SampleSource.allLayers => tr('Todas las capas', 'All layers'),
        SampleSource.reference => tr('Capas de referencia', 'Reference layers'),
      };
}

/// Straight RGBA snapshot of a document region.
class PixelSnapshot {
  PixelSnapshot(this.rgba, this.rect);
  final Uint8List rgba;
  final Rect rect;
  int get width => rect.width.toInt();
  int get height => rect.height.toInt();
}

final Paint _white = Paint()..color = const Color(0xFFFFFFFF);
final Paint _dstOut = Paint()..blendMode = BlendMode.dstOut;

/// Selection operations.
extension DocSelection on DocumentController {
  SelectionMask? get selection => comp.selection;

  /// Region pixel operations work on: the canvas, or everything painted for
  /// an infinite canvas.
  Rect get workRect {
    var r = comp.rect;
    if (comp.infinite) {
      for (final l in walkLayers(comp.layers)) {
        if (l is PaintLayer) {
          final b = l.cels.at(frame)?.bounds;
          if (b != null) r = r.expandToInclude(b);
        }
      }
      r = r.inflate(64);
    }
    return r.roundedOut;
  }

  void setSelection(SelectionMask? s, {String? label}) {
    if (s == null && comp.selection == null) return;
    applyComp(label ?? (s == null ? tr('Deseleccionar', 'Deselect') : tr('Seleccionar', 'Select')), (c) => c.copyWith(selection: s));
  }

  SelectionMask? _combine(SelectionMask? old, TilePlane add, Rect bounds, SelectMode mode) {
    if (old == null || mode == SelectMode.replace) {
      if (mode == SelectMode.subtract || mode == SelectMode.intersect) return old == null ? null : _combineExisting(old, add, bounds, mode);
      return SelectionMask(add, bounds);
    }
    return _combineExisting(old, add, bounds, mode);
  }

  SelectionMask? _combineExisting(SelectionMask old, TilePlane add, Rect bounds, SelectMode mode) {
    switch (mode) {
      case SelectMode.replace:
        return SelectionMask(add, bounds);
      case SelectMode.add:
        return SelectionMask(old.mask.composited(add), old.bounds.expandToInclude(bounds));
      case SelectMode.subtract:
        final keys = add.keys.where(old.mask.containsKey).toList();
        if (keys.isEmpty) return old;
        return SelectionMask(old.mask.drawn((c) => add.paint(c, paint: _dstOut), keys: keys), old.bounds);
      case SelectMode.intersect:
        final b = old.bounds.intersect(bounds);
        if (b.isEmpty || b.width <= 0 || b.height <= 0) return null;
        return SelectionMask(old.mask.maskedBy(add), b);
    }
  }

  /// Selects the area inside [path] (document coordinates).
  void selectPath(Path path, {SelectMode mode = SelectMode.replace, bool antiAlias = true, double feather = 0}) {
    var bounds = path.getBounds().roundedOut;
    if (!comp.infinite) bounds = bounds.intersect(comp.rect);
    if (bounds.isEmpty || bounds.width < 1 || bounds.height < 1) {
      if (mode == SelectMode.replace) setSelection(null);
      return;
    }
    final area = bounds.inflate(feather * 3).roundedOut;
    final plane = TilePlane.empty.drawn((c) {
      if (!comp.infinite) c.clipRect(comp.rect);
      final p = Paint()
        ..color = const Color(0xFFFFFFFF)
        ..isAntiAlias = antiAlias;
      if (feather > 0) p.maskFilter = MaskFilter.blur(BlurStyle.normal, feather);
      c.drawPath(path, p);
    }, area: area);
    setSelection(_combine(comp.selection, plane, area, mode));
  }

  void selectRect(Rect r, {SelectMode mode = SelectMode.replace, double feather = 0}) =>
      selectPath(Path()..addRect(r), mode: mode, antiAlias: false, feather: feather);

  void selectAll() {
    final r = comp.rect;
    setSelection(SelectionMask(TilePlane.empty.drawn((c) => c.drawRect(r, _white), area: r), r), label: tr('Seleccionar todo', 'Select all'));
  }

  void deselect() => setSelection(null);

  void invertSelection() {
    final sel = comp.selection;
    if (sel == null) return selectAll();
    final r = workRect;
    final inv = TilePlane.empty.drawn((c) {
      c.drawRect(r, _white);
      sel.mask.paint(c, paint: _dstOut);
    }, area: r);
    setSelection(SelectionMask(inv, r), label: tr('Invertir selección', 'Invert selection'));
  }

  /// Runs an image filter over the selection mask.
  void _filterSelection(String label, double margin, void Function(Canvas c, void Function(Canvas) drawMask, Rect area) body) {
    final sel = comp.selection;
    if (sel == null) return;
    var area = sel.bounds.inflate(margin).roundedOut;
    if (!comp.infinite) area = area.intersect(comp.rect);
    if (area.isEmpty) return;
    final img = renderToImage(area.width.toInt(), area.height.toInt(), (c) {
      c.translate(-area.left, -area.top);
      body(c, (cc) => sel.mask.paint(cc), area);
    });
    final plane = TilePlane.fromImage(img, origin: area.topLeft);
    img.dispose();
    setSelection(SelectionMask(plane, area), label: label);
  }

  void growSelection(double px) {
    if (px == 0) return;
    _filterSelection(px > 0 ? tr('Expandir selección', 'Expand selection') : tr('Contraer selección', 'Contract selection'), px.abs() + 2, (c, draw, area) {
      c.saveLayer(area, Paint()..imageFilter = px > 0 ? ui.ImageFilter.dilate(radiusX: px, radiusY: px) : ui.ImageFilter.erode(radiusX: -px, radiusY: -px));
      draw(c);
      c.restore();
    });
  }

  void featherSelection(double px) {
    if (px <= 0) return;
    _filterSelection(tr('Calar selección', 'Feather selection'), px * 3, (c, draw, area) {
      c.saveLayer(area, Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: px, sigmaY: px, tileMode: TileMode.decal));
      draw(c);
      c.restore();
    });
  }

  /// Rounds off jagged selection edges (blur + re-threshold).
  void smoothSelection(double px) {
    if (px <= 0) return;
    _filterSelection(tr('Suavizar selección', 'Smooth selection'), px * 3, (c, draw, area) {
      const k = 12.0;
      c.saveLayer(area, Paint()..colorFilter = const ColorFilter.matrix(<double>[1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, k, -(k - 1) * 127.5]));
      c.saveLayer(area, Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: px, sigmaY: px, tileMode: TileMode.decal));
      draw(c);
      c.restore();
      c.restore();
    });
  }

  /// Keeps only a band of [px] around the selection edge.
  void borderSelection(double px) {
    if (px <= 0) return;
    _filterSelection(tr('Borde de selección', 'Border selection'), px + 2, (c, draw, area) {
      c.saveLayer(area, Paint()..imageFilter = ui.ImageFilter.dilate(radiusX: px / 2, radiusY: px / 2));
      draw(c);
      c.restore();
      c.saveLayer(
        area,
        Paint()
          ..imageFilter = ui.ImageFilter.erode(radiusX: px / 2, radiusY: px / 2)
          ..blendMode = BlendMode.dstOut,
      );
      draw(c);
      c.restore();
    });
  }

  void saveSelection(String name) {
    final sel = comp.selection;
    if (sel == null) return;
    applyComp(tr('Guardar selección', 'Save selection'), (c) => c.copyWith(savedSelections: {...c.savedSelections, name: sel}));
  }

  void loadSelection(String name, {SelectMode mode = SelectMode.replace}) {
    final s = comp.savedSelections[name];
    if (s == null) return;
    setSelection(_combine(comp.selection, s.mask, s.bounds, mode), label: tr('Cargar selección', 'Load selection'));
  }

  void deleteSavedSelection(String name) {
    applyComp(tr('Eliminar selección guardada', 'Delete saved selection'), (c) => c.copyWith(savedSelections: {...c.savedSelections}..remove(name)));
  }

  // ---- pixel sampling -----------------------------------------------------

  /// Plane with the pixels a wand / bucket should look at.
  TilePlane? samplePlane(SampleSource source) {
    switch (source) {
      case SampleSource.layer:
        final l = activeLayer;
        if (l == null) return null;
        if (l is PaintLayer && comp.worldMatrix(l, frame.toDouble()).isIdentity && !l.props.hasMask) {
          return l.cels.at(frame) ?? TilePlane.empty;
        }
        return rasterizeLayer(project, comp, l.withProps(l.props.copyWith(opacity: 1, blend: LayerBlend.normal)), frame.toDouble(), area: workRect);
      case SampleSource.allLayers:
        final img = renderCompImage(project, comp, frame.toDouble(), region: workRect, background: false, forExport: false, useCamera: false, docMode: false);
        final p = TilePlane.fromImage(img, origin: workRect.topLeft);
        img.dispose();
        return p;
      case SampleSource.reference:
        final refs = <String>{
          for (final l in walkLayers(comp.layers))
            if (l.props.reference) l.id,
        };
        if (refs.isEmpty) return samplePlane(SampleSource.allLayers);
        final hidden = <String>{
          for (final l in comp.layers)
            if (!refs.contains(l.id) && !(l is GroupLayer && walkLayers(l.children).any((c) => refs.contains(c.id)))) l.id,
        };
        final img = renderCompImage(project, comp, frame.toDouble(),
            region: workRect, background: false, forExport: false, useCamera: false, docMode: false, hidden: hidden);
        final p = TilePlane.fromImage(img, origin: workRect.topLeft);
        img.dispose();
        return p;
    }
  }

  Future<PixelSnapshot?> snapshot(SampleSource source) async {
    final plane = samplePlane(source);
    if (plane == null) return null;
    final r = workRect;
    return PixelSnapshot(await plane.readRgba(r, straight: true), r);
  }

  /// Colour of the composite (or of the active layer) under [docPoint],
  /// averaged over a square of [radius] pixels.
  Future<Color?> sampleColor(Offset docPoint, {bool allLayers = true, int radius = 0}) async {
    final x = docPoint.dx.floor(), y = docPoint.dy.floor();
    final r = Rect.fromLTWH((x - radius).toDouble(), (y - radius).toDouble(), radius * 2 + 1.0, radius * 2 + 1.0);
    ui.Image img;
    if (allLayers) {
      img = renderCompImage(project, comp, frame.toDouble(), region: r, background: true, forExport: false, useCamera: false, docMode: false);
    } else {
      final l = activeLayer;
      if (l == null) return null;
      final plane = samplePlane(SampleSource.layer);
      if (plane == null) return null;
      img = plane.toImage(r);
    }
    final px = await imageToRgba(img, straight: true);
    img.dispose();
    var rs = 0.0, gs = 0.0, bs = 0.0, as = 0.0;
    for (var o = 0; o < px.length; o += 4) {
      final a = px[o + 3] / 255.0;
      rs += px[o] * a;
      gs += px[o + 1] * a;
      bs += px[o + 2] * a;
      as += a;
    }
    if (as <= 0.001) return null;
    return Color.fromARGB(255, (rs / as).round().clamp(0, 255), (gs / as).round().clamp(0, 255), (bs / as).round().clamp(0, 255));
  }

  Future<SelectionMask?> _maskToSelection(MaskResult m, Rect origin) async {
    final b = m.bounds;
    if (b == null) return null;
    final plane = await TilePlane.fromRgba(m.toRgba(), m.width, m.height, origin: origin.topLeft);
    return SelectionMask(plane, b.shift(origin.topLeft));
  }

  /// Magic wand.
  Future<void> magicWand(
    Offset docPoint, {
    int tolerance = 32,
    bool contiguous = true,
    SampleSource source = SampleSource.layer,
    SelectMode mode = SelectMode.replace,
    bool antiAlias = true,
    int gap = 0,
  }) async {
    await run(tr('Varita mágica', 'Magic wand'), () async {
      final snap = await snapshot(source);
      if (snap == null) return;
      final x = (docPoint.dx - snap.rect.left).floor(), y = (docPoint.dy - snap.rect.top).floor();
      final m = floodSelect(snap.rgba, snap.width, snap.height, x, y,
          tolerance: tolerance, softness: antiAlias ? 24 : 0, contiguous: contiguous, gap: gap);
      final s = await _maskToSelection(m, snap.rect);
      if (s == null) {
        if (mode == SelectMode.replace) setSelection(null);
        return;
      }
      setSelection(_combine(comp.selection, s.mask, s.bounds, mode), label: tr('Varita mágica', 'Magic wand'));
    });
  }

  Future<void> selectByColor(Color color, {int tolerance = 40, SampleSource source = SampleSource.allLayers, SelectMode mode = SelectMode.replace}) async {
    await run(tr('Selección por color', 'Select by colour'), () async {
      final snap = await snapshot(source);
      if (snap == null) return;
      final s = await _maskToSelection(selectColorRange(snap.rgba, snap.width, snap.height, color, tolerance: tolerance), snap.rect);
      if (s == null) return;
      setSelection(_combine(comp.selection, s.mask, s.bounds, mode), label: tr('Selección por color', 'Select by colour'));
    });
  }

  Future<void> selectByLuminosity({int low = 128, int high = 255, SampleSource source = SampleSource.allLayers}) async {
    await run(tr('Selección por luminosidad', 'Select by luminosity'), () async {
      final snap = await snapshot(source);
      if (snap == null) return;
      final s = await _maskToSelection(selectLuminosity(snap.rgba, snap.width, snap.height, low: low, high: high), snap.rect);
      setSelection(s, label: tr('Selección por luminosidad', 'Select by luminosity'));
    });
  }

  /// Selection from the opacity of the active layer.
  Future<void> selectLayerAlpha({SelectMode mode = SelectMode.replace}) async {
    await run(tr('Seleccionar opacidad de capa', 'Select layer opacity'), () async {
      final plane = samplePlane(SampleSource.layer);
      if (plane == null || plane.isEmpty) return;
      final b = await plane.contentBounds();
      if (b == null) return;
      // the layer's own alpha is the mask: tint it white
      final mask = TilePlane.empty.drawn((c) {
        c.saveLayer(b, Paint()..colorFilter = const ColorFilter.mode(Color(0xFFFFFFFF), BlendMode.srcIn));
        plane.paint(c, cull: b);
        c.restore();
      }, area: b);
      setSelection(_combine(comp.selection, mask, b, mode), label: tr('Seleccionar opacidad de capa', 'Select layer opacity'));
    });
  }

  /// "Smart" subject selection: grows a region from the seed using colour
  /// similarity and edge strength, then smooths it. A local, model-free
  /// approximation of AI-assisted selection.
  Future<void> smartSelect(Offset docPoint, {SelectMode mode = SelectMode.add}) async {
    await magicWand(docPoint, tolerance: 48, contiguous: true, source: SampleSource.allLayers, mode: mode, gap: 2);
    smoothSelection(1.5);
  }

  /// Transforms the selection mask itself (not the pixels).
  void transformSelection(Mat2D m) {
    final sel = comp.selection;
    if (sel == null) return;
    final src = sel.mask.toImage(sel.bounds);
    final nb = m.mapRect(sel.bounds).roundedOut;
    final plane = TilePlane.empty.drawn((c) {
      c.transform(m.storage);
      c.drawImage(src, sel.bounds.topLeft, Paint()..filterQuality = FilterQuality.low);
    }, area: nb);
    src.dispose();
    setSelection(SelectionMask(plane, nb), label: tr('Transformar selección', 'Transform selection'));
  }
}
