import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/doc_edit.dart';
import '../app/doc_layers.dart';
import '../app/document_controller.dart';
import '../app/tool_state.dart';
import '../core/i18n.dart';
import '../core/mat2d.dart';
import '../engine/compositor.dart';
import '../engine/shape_paths.dart';
import '../engine/vector_render.dart';
import '../model/document.dart';
import '../model/layer.dart';
import '../model/vector.dart';
import 'tool.dart';

/// Geometry of every [ShapeKind], built inside the dragged rectangle.
///
/// Arrow, heart and comic balloons come from `lib/engine/shape_paths.dart`.
VPath buildShapePath(ShapeKind kind, Offset a, Offset b, {double radius = 24, int sides = 6, double starRatio = 0.5, double strokeWidth = 4}) {
  final r = Rect.fromPoints(a, b);
  switch (kind) {
    case ShapeKind.line:
      return VPath.line(a, b);
    case ShapeKind.arrow:
      return arrowPath(a, b, shaftWidth: math.max(2, strokeWidth * 1.5));
    case ShapeKind.rect:
      return VPath.rect(r);
    case ShapeKind.roundRect:
      return VPath.rect(r, radius: radius);
    case ShapeKind.ellipse:
      return VPath.ellipse(r);
    case ShapeKind.polygon:
      return _fit(VPath.polygon(Offset.zero, 1, sides), r);
    case ShapeKind.star:
      return _fit(VPath.star(Offset.zero, 1, starRatio.clamp(0.05, 0.95), math.max(3, sides)), r);
    case ShapeKind.heart:
      return heartPath(r);
    case ShapeKind.bubble:
      return speechBubblePath(Rect.fromLTRB(r.left, r.top, r.right, r.top + r.height * 0.8), tailTip: Offset(r.left + r.width * 0.2, r.bottom));
    case ShapeKind.burst:
      return burstPath(r);
    case ShapeKind.cloud:
      return cloudPath(r);
  }
}

/// Stretches [p] so the bounds of its anchors fill [r].
VPath _fit(VPath p, Rect r) {
  var l = double.infinity, t = double.infinity, rt = -double.infinity, bt = -double.infinity;
  for (final n in p.nodes) {
    l = math.min(l, n.p.dx);
    t = math.min(t, n.p.dy);
    rt = math.max(rt, n.p.dx);
    bt = math.max(bt, n.p.dy);
  }
  final w = math.max(1e-6, rt - l), h = math.max(1e-6, bt - t);
  return p.transformed(Mat2D.translation(r.left, r.top) * Mat2D.scale(r.width / w, r.height / h) * Mat2D.translation(-l, -t));
}

/// Lines, rectangles, ellipses, polygons, stars and comic balloons. Draws
/// pixels on raster layers and editable shapes on vector layers.
class ShapeTool extends Tool {
  @override
  String get id => 'shape';
  @override
  String get label => tr('Formas', 'Shapes');
  @override
  IconData get icon => Icons.category;
  @override
  String get shortcut => 'U';
  @override
  String get hint => tr('Arrastra para dibujar la forma · Mayús: proporción 1:1 o ángulos de 45° · Ctrl: desde el centro', 'Drag to draw the shape · Shift: 1:1 ratio or 45° angles · Ctrl: from the centre');
  @override
  bool get active => _doc != null;

  DocumentController? _doc;
  Offset? _a, _b;
  Mat2D _toLayer = Mat2D.identity;
  PaintTarget? _target;
  ({Project project, VectorLayer layer, int drawing, VectorArt art})? _vt;

  bool get _isLine => ts.shapeKind == ShapeKind.line || ts.shapeKind == ShapeKind.arrow;

  @override
  void onDown(ToolEvent e) {
    final d = doc;
    if (d == null || d.isBusy) return;
    final l = d.activeLayer;
    if (l is VectorLayer && !d.editMask) {
      _vt = d.resolveVectorTarget();
      if (_vt == null) return toast(tr('La capa está bloqueada u oculta', 'The layer is locked or hidden'));
    } else {
      final blocker = d.paintBlocker;
      if (blocker != null) return toast(blocker);
      _target = d.resolvePaintTarget();
      if (_target == null) return;
    }
    final m = d.layerMatrix(l!);
    _toLayer = m.isIdentity ? Mat2D.identity : m.inverse;
    _doc = d;
    _a = _b = _toLayer.apply(snapDoc(e.doc));
  }

  VShape _shape(ToolEvent? e) {
    var a = _a!, b = _b!;
    final v = b - a;
    if (e != null && e.shift) {
      if (_isLine) {
        const step = math.pi / 4;
        final ang = (math.atan2(v.dy, v.dx) / step).roundToDouble() * step;
        b = a + Offset(math.cos(ang), math.sin(ang)) * v.distance;
      } else {
        final s = math.max(v.dx.abs(), v.dy.abs());
        b = a + Offset(v.dx < 0 ? -s : s, v.dy < 0 ? -s : s);
      }
    }
    if (e != null && e.ctrl) a = a - (b - a);
    final path = buildShapePath(ts.shapeKind, a, b, radius: ts.shapeRadius, sides: ts.shapeSides, starRatio: ts.starRatio, strokeWidth: ts.shapeStrokeWidth);
    final line = ts.shapeKind == ShapeKind.line;
    final filled = !line && ts.shapeFill;
    final stroked = line || ts.shapeStroke || !ts.shapeFill;
    return VShape(
      paths: [path],
      fill: filled ? VFill.solid(ts.fg) : const VFill.none(),
      stroke: stroked
          ? VStroke(
              color: filled ? ts.bg : ts.fg,
              width: ts.shapeStrokeWidth,
              cap: ts.strokeCap,
              join: ts.strokeJoin,
              dash: ts.strokeDash,
              profile: line ? ts.strokeProfile : WidthProfile.uniform,
            )
          : null,
    );
  }

  void _paint(Canvas c, VShape s) {
    if (ts.shapeAntiAlias) {
      paintShape(c, s);
      return;
    }
    // crisp edges for pixel art
    if (!s.fill.isNone) {
      c.drawPath(
          s.path,
          Paint()
            ..color = s.fill.color
            ..isAntiAlias = false);
    }
    final st = s.stroke;
    if (st != null) {
      c.drawPath(
          s.path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = st.width
            ..strokeCap = st.cap
            ..strokeJoin = st.join
            ..color = st.color
            ..isAntiAlias = false);
    }
  }

  @override
  void onMove(ToolEvent e) {
    final d = _doc;
    if (d == null) return;
    _b = _toLayer.apply(snapDoc(e.doc));
    final s = _shape(e);
    final vt = _vt;
    if (vt != null) {
      d.setLive(LiveEdit(layerId: vt.layer.id, replaceArt: vt.art.added(s)));
    } else {
      d.setLive(LiveEdit(layerId: _target!.layerId, overlay: (c) => _paint(c, s), onMask: false));
    }
  }

  @override
  void onUp(ToolEvent e) {
    final d = _doc;
    if (d == null) return;
    final tiny = (_b! - _a!).distance < 1;
    final s = tiny ? null : _shape(e);
    final vt = _vt, t = _target;
    _clear();
    if (s == null) {
      d.setLive(null);
      return;
    }
    final label = ts.shapeKind.label;
    if (vt != null) {
      d.commitVector(label, vt.project, vt.layer.id, vt.drawing, vt.art.added(s));
    } else if (t != null) {
      final lock = !t.onMask && (t.layer?.props.lockAlpha ?? false);
      d.commitPaint(label, t, d.paintOver(t.plane, s.bounds, (c) => _paint(c, s), lockAlpha: lock));
    }
    ts.pushColorHistory(ts.fg);
  }

  void _clear() {
    _doc = null;
    _a = null;
    _b = null;
    _target = null;
    _vt = null;
  }

  @override
  void onCancel() {
    final d = _doc;
    _clear();
    d?.setLive(null);
  }
}
