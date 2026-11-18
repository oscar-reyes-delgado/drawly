import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../app/doc_layers.dart';
import '../app/document_controller.dart';
import '../app/tool_state.dart';
import '../core/i18n.dart';
import '../core/mat2d.dart';
import '../engine/compositor.dart';
import '../engine/tiles.dart';
import '../engine/warp.dart';
import '../model/layer.dart';
import 'tool.dart';

/// Brush tool that deforms the active raster layer (or its mask) using a [WarpGrid].
class LiquifyTool extends Tool {
  @override
  String get id => 'liquify';

  @override
  String get label => tr('Licuar', 'Liquify');

  @override
  IconData get icon => Icons.water_drop_outlined;

  @override
  String get shortcut => 'Shift+W';

  @override
  String get hint => tr(
        'Arrastra para licuar (empujar, remolino, contraer, inflar, restaurar) · Alt en remolino: invertir · [ ]: tamaño',
        'Drag to liquify (push, twirl, pinch, bloat, restore) · Alt while twirling: reverse · [ ]: size',
      );

  @override
  double? get brushCursorSize => ts.liquifySize;

  @override
  bool get active => _doc != null;

  DocumentController? _doc;
  PaintTarget? _target;
  Rect? _region;
  ui.Image? _src;
  WarpGrid? _grid;
  Offset? _last;
  TilePlane? _previewPlane;
  int _lastPreviewMs = 0;

  void _reset() {
    _doc = null;
    _target = null;
    _region = null;
    _src = null;
    _grid = null;
    _last = null;
    _previewPlane = null;
    _lastPreviewMs = 0;
  }

  @override
  void onDown(ToolEvent e) {
    final d = doc;
    if (d == null || d.isBusy || _doc != null) return;
    final blocker = d.paintBlocker;
    if (blocker != null) {
      toast(blocker);
      return;
    }
    final layer = d.activeLayer;
    final t = d.resolvePaintTarget();
    if (t == null || layer == null) return;
    if (layer is! PaintLayer && !t.onMask) {
      toast(tr('Licuar solo funciona en capas de dibujo', 'Liquify only works on paint layers'));
      return;
    }
    if (!d.layerMatrix(layer).isIdentity) {
      toast(tr('Licuar no admite capas transformadas', 'Liquify does not support transformed layers'));
      return;
    }
    final comp = d.comp;
    var region = (t.plane.bounds ?? comp.rect).inflate(ts.liquifySize);
    if (!comp.infinite) region = region.intersect(comp.rect);
    region = region.roundedOut;
    if (region.isEmpty || region.width < 1 || region.height < 1) return;

    _doc = d;
    _target = t;
    _region = region;
    _src = t.plane.toImage(region);
    _grid = WarpGrid.forSize(region, cell: 16);
    _last = e.doc;
    _previewPlane = null;
    _lastPreviewMs = 0;
  }

  @override
  void onMove(ToolEvent e) {
    final d = _doc, t = _target, region = _region, src = _src, grid = _grid;
    if (d == null || t == null || region == null || src == null || grid == null) return;

    final radius = ts.liquifySize / 2;
    final strength = ts.liquifyStrength;
    switch (ts.liquifyMode) {
      case LiquifyMode.push:
        final delta = e.doc - (_last ?? e.doc);
        if (delta != Offset.zero) grid.push(e.doc, delta, radius, strength);
      case LiquifyMode.twirl:
        grid.twirl(e.doc, e.alt ? -0.15 : 0.15, radius, strength);
      case LiquifyMode.pinch:
        grid.pinch(e.doc, radius, strength);
      case LiquifyMode.bloat:
        grid.bloat(e.doc, radius, strength);
      case LiquifyMode.restore:
        grid.restore(e.doc, radius, strength);
    }
    _last = e.doc;

    final now = DateTime.now().millisecondsSinceEpoch;
    if (_lastPreviewMs != 0 && now - _lastPreviewMs < 30) return;
    _lastPreviewMs = now;

    final nextPlane = _buildWarpedPlane(t.plane, region, src, grid);
    final oldPreview = _previewPlane;
    _previewPlane = nextPlane;
    d.setLive(LiveEdit(layerId: t.layerId, replace: nextPlane, onMask: t.onMask));
    _disposePreviewTiles(oldPreview, t.plane);
  }

  @override
  void onUp(ToolEvent e) {
    final d = _doc, t = _target, region = _region, src = _src, grid = _grid;
    final oldPreview = _previewPlane;
    _reset();
    if (d == null || t == null || region == null || src == null || grid == null) {
      d?.setLive(null);
      if (t != null) _disposePreviewTiles(oldPreview, t.plane);
      src?.dispose();
      return;
    }

    if (grid.isIdentity) {
      d.setLive(null);
      _disposePreviewTiles(oldPreview, t.plane);
      src.dispose();
      return;
    }

    final finalPlane = _buildWarpedPlane(t.plane, region, src, grid);
    d.commitPaint(tr('Licuar', 'Liquify'), t, finalPlane);
    _disposePreviewTiles(oldPreview, t.plane);
    src.dispose();
  }

  @override
  void onCancel() {
    final d = _doc, t = _target, src = _src;
    final oldPreview = _previewPlane;
    _reset();
    d?.setLive(null);
    if (t != null) _disposePreviewTiles(oldPreview, t.plane);
    src?.dispose();
  }

  @override
  void onDeactivate() => onCancel();

  TilePlane _buildWarpedPlane(TilePlane base, Rect region, ui.Image src, WarpGrid grid) {
    final warped = renderWarped(src, grid);
    final cleared = base.cleared(region);
    final out = cleared.withImage(warped, region.topLeft);
    warped.dispose();
    for (final k in cleared.keys) {
      final img = cleared[k];
      if (img != null && !identical(img, base[k]) && !identical(img, out[k])) {
        img.dispose();
      }
    }
    return out;
  }

  void _disposePreviewTiles(TilePlane? preview, TilePlane base) {
    if (preview == null) return;
    for (final k in preview.keys) {
      final img = preview[k];
      if (img != null && !identical(img, base[k])) {
        img.dispose();
      }
    }
  }
}
