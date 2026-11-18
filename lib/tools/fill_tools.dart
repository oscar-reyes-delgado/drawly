import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../app/doc_edit.dart';
import '../app/doc_layers.dart';
import '../app/doc_selection.dart';
import '../app/document_controller.dart';
import '../app/view_state.dart';
import '../core/i18n.dart';
import '../core/mat2d.dart';
import '../engine/compositor.dart';
import '../engine/vector_render.dart';
import '../model/gradient.dart';
import '../model/layer.dart';
import '../model/vector.dart';
import 'tool.dart';

/// Paint bucket. On vector layers it recolours the shape under the pointer.
class BucketTool extends Tool {
  @override
  String get id => 'bucket';
  @override
  String get label => tr('Cubo de relleno', 'Paint bucket');
  @override
  IconData get icon => Icons.format_color_fill;
  @override
  String get shortcut => 'G';
  @override
  String get hint => tr('Clic para rellenar una zona con el color frontal · Alt: cuentagotas', 'Click to fill an area with the foreground colour · Alt: eyedropper');

  @override
  void onDown(ToolEvent e) {
    final d = doc;
    if (d == null || d.isBusy) return;
    final l = d.activeLayer;
    if (l is VectorLayer && !d.editMask) {
      final vt = d.resolveVectorTarget();
      if (vt == null) return toast(tr('La capa está bloqueada u oculta', 'The layer is locked or hidden'));
      final hit = hitTestArt(vt.art, d.layerMatrix(l).inverse.apply(e.doc), tolerance: 4 / d.view.zoom);
      if (hit == null) return toast(tr('Haz clic sobre una forma para rellenarla', 'Click a shape to fill it'));
      d.commitVector(tr('Rellenar forma', 'Fill shape'), vt.project, vt.layer.id, vt.drawing, vt.art.replaced(hit.copyWith(fill: VFill.solid(ts.fg))));
      ts.pushColorHistory(ts.fg);
      return;
    }
    final blocker = d.paintBlocker;
    if (blocker != null) return toast(blocker);
    final color = ts.fg;
    d
        .bucketFill(e.doc, color,
            tolerance: ts.tolerance, contiguous: ts.contiguous, source: ts.sampleSource, expand: ts.fillExpand, gap: ts.fillGap, opacity: ts.fillOpacity)
        .then((_) => ts.pushColorHistory(color));
  }
}

/// Drag to lay down a gradient over the selection or the canvas.
class GradientTool extends Tool {
  @override
  String get id => 'gradient';
  @override
  String get label => tr('Degradado', 'Gradient');
  @override
  IconData get icon => Icons.gradient;
  @override
  String get shortcut => 'Shift+G';
  @override
  String get hint => tr('Arrastra para definir el inicio y el fin del degradado · Mayús: ángulos de 45°', 'Drag from the start to the end of the gradient · Shift: 45° angles');
  @override
  bool get active => _from != null;

  DocumentController? _doc;
  Offset? _from, _to;
  Mat2D _toLayer = Mat2D.identity;

  @override
  void onDown(ToolEvent e) {
    final d = doc;
    if (d == null || d.isBusy) return;
    final blocker = d.paintBlocker;
    if (blocker != null) return toast(blocker);
    final m = d.layerMatrix(d.activeLayer!);
    _toLayer = m.isIdentity ? Mat2D.identity : m.inverse;
    _doc = d;
    _from = _to = snapDoc(e.doc);
  }

  @override
  void onMove(ToolEvent e) {
    final d = _doc, from = _from;
    if (d == null || from == null) return;
    var to = snapDoc(e.doc);
    if (e.shift) {
      final v = to - from;
      const step = math.pi / 4;
      final a = (math.atan2(v.dy, v.dx) / step).roundToDouble() * step;
      to = from + Offset(math.cos(a), math.sin(a)) * v.distance;
    }
    _to = to;
    final g = _spec();
    final sel = d.comp.selection;
    final area = sel?.bounds ?? d.workRect;
    final opacity = ts.gradientOpacity.clamp(0.0, 1.0);
    d.setLive(LiveEdit(
      layerId: d.activeLayerId!,
      overlay: (c) {
        c.save();
        c.clipRect(area);
        c.saveLayer(area, Paint()..color = Color.fromRGBO(0, 0, 0, opacity));
        g.paint(c, area);
        if (sel != null) {
          c.saveLayer(area, Paint()..blendMode = BlendMode.dstIn);
          sel.mask.paint(c, cull: area);
          c.restore();
        }
        c.restore();
        c.restore();
      },
    ));
    requestOverlay();
  }

  GradientSpec _spec() => ts.gradientFor(_toLayer.apply(_from!), _toLayer.apply(_to!));

  @override
  void onUp(ToolEvent e) {
    final d = _doc, from = _from, to = _to;
    if (d == null || from == null || to == null) return;
    final g = _spec();
    _clear();
    if ((to - from).distance < 2) {
      d.setLive(null);
    } else {
      d.fillGradient(g, opacity: ts.gradientOpacity);
    }
    requestOverlay();
  }

  void _clear() {
    _doc = null;
    _from = null;
    _to = null;
  }

  @override
  void onCancel() {
    final d = _doc;
    _clear();
    d?.setLive(null);
    requestOverlay();
  }

  @override
  void paintOverlay(Canvas canvas, Size size, ViewState view) {
    final from = _from, to = _to;
    if (from == null || to == null) return;
    final a = view.toView(from), b = view.toView(to);
    Tool.drawContrastPath(
        canvas,
        Path()
          ..moveTo(a.dx, a.dy)
          ..lineTo(b.dx, b.dy));
    Tool.drawHandle(canvas, a, round: true);
    Tool.drawHandle(canvas, b, round: true, selected: true);
  }
}

/// Samples a colour from the canvas.
class EyedropperTool extends Tool {
  @override
  String get id => 'eyedropper';
  @override
  String get label => tr('Cuentagotas', 'Eyedropper');
  @override
  IconData get icon => Icons.colorize;
  @override
  String get shortcut => 'I';
  @override
  String get hint => tr('Clic o arrastra para tomar un color · Ctrl o botón derecho: color de fondo', 'Click or drag to pick a colour · Ctrl or right button: background colour');
  @override
  bool get active => _pos != null;

  Offset? _pos;
  Color? _picked;
  Color _before = const Color(0xFF000000);
  bool _busy = false;

  @override
  void onDown(ToolEvent e) {
    _before = ts.fg;
    _pick(e);
  }

  @override
  void onMove(ToolEvent e) => _pick(e);

  Future<void> _pick(ToolEvent e) async {
    final d = doc;
    if (d == null) return;
    _pos = e.view;
    requestOverlay();
    if (_busy) return;
    _busy = true;
    try {
      final c = await d.sampleColor(e.doc, allLayers: ts.pickAllLayers, radius: ts.pickRadius);
      if (c == null || _pos == null) return;
      _picked = c;
      if (e.ctrl || (e.buttons & kSecondaryButton) != 0) {
        ts.bg = c;
      } else {
        ts.fg = c;
      }
    } finally {
      _busy = false;
    }
    requestOverlay();
  }

  @override
  void onUp(ToolEvent e) => onCancel();

  @override
  void onCancel() {
    _pos = null;
    _picked = null;
    requestOverlay();
  }

  @override
  void paintOverlay(Canvas canvas, Size size, ViewState view) {
    final p = _pos, c = _picked;
    if (p == null || c == null) return;
    final center = p - const Offset(0, 46);
    final rect = Rect.fromCircle(center: center, radius: 26);
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12;
    canvas.drawArc(rect, math.pi, math.pi, false, ring..color = c);
    canvas.drawArc(rect, 0, math.pi, false, ring..color = _before);
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, 32.5, edge..color = const Color(0xE6FFFFFF));
    canvas.drawCircle(center, 19.5, edge..color = const Color(0xB0000000));
  }
}
