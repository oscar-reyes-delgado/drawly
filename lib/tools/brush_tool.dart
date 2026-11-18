import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../app/doc_layers.dart';
import '../app/document_controller.dart';
import '../core/i18n.dart';
import '../core/mat2d.dart';
import '../engine/assist.dart';
import '../engine/brush/preset.dart';
import '../engine/brush/stroke.dart';
import '../engine/compositor.dart';
import '../engine/curve_fit.dart';
import '../engine/tiles.dart';
import '../engine/vector_render.dart';
import '../model/document.dart';
import '../model/layer.dart';
import '../model/vector.dart';
import 'tool.dart';

/// Brush, eraser and smudge: the three tools share one implementation and
/// differ only in the brush slot they read their preset from.
class BrushTool extends Tool {
  BrushTool(this.id);

  @override
  final String id;

  BrushPreset get brush => ts.brushFor(ts.slotOf(id));

  @override
  String get label => switch (id) {
        'eraser' => tr('Borrador', 'Eraser'),
        'smudge' => tr('Difuminar / dedo', 'Smudge'),
        _ => tr('Pincel', 'Brush'),
      };

  @override
  IconData get icon => switch (id) {
        'eraser' => Icons.auto_fix_normal,
        'smudge' => Icons.touch_app,
        _ => Icons.brush,
      };

  @override
  Widget buildIcon(double size, Color color) =>
      id == 'eraser' ? CustomPaint(size: Size.square(size), painter: _EraserIcon(color)) : super.buildIcon(size, color);

  @override
  String get shortcut => switch (id) {
        'eraser' => 'E',
        'smudge' => 'S',
        _ => 'B',
      };

  @override
  String get hint => tr(
        'Arrastra para pintar · Mayús + clic: línea recta desde el último punto · Alt: cuentagotas · [ ]: tamaño',
        'Drag to paint · Shift + click: straight line from the last point · Alt: eyedropper · [ ]: size',
      );

  @override
  double? get brushCursorSize => brush.size;

  @override
  bool get active => _doc != null;

  DocumentController? _doc;
  PaintTarget? _target;
  PaintStroke? _paint;
  SmudgeStroke? _smudge;
  BrushPreset? _brush;
  Mat2D _toLayer = Mat2D.identity;
  AssistSnapper? _snap;
  Offset? _last;
  final Map<String, Offset> _lastEnd = {};
  bool _pumping = false;

  // vector strokes
  ({Project project, VectorLayer layer, int drawing, VectorArt art})? _vt;
  final List<Offset> _pts = [];
  final List<double> _press = [];
  VectorArt? _erased;

  void _reset() {
    _doc = null;
    _target = null;
    _paint = null;
    _smudge = null;
    _brush = null;
    _vt = null;
    _erased = null;
    _snap = null;
    _pts.clear();
    _press.clear();
  }

  @override
  void onDown(ToolEvent e) {
    final d = doc;
    if (d == null || d.isBusy || _doc != null) return;
    final layer = d.activeLayer;
    final b = brush;
    final comp = d.comp;
    _snap = comp.assist.active ? AssistSnapper(comp.assist, e.doc) : null;
    _last = null;
    if (layer is VectorLayer && !(d.editMask && layer.props.mask != null)) {
      _beginVector(d, layer, b, e);
      return;
    }
    final blocker = d.paintBlocker;
    if (blocker != null) {
      toast(blocker);
      return;
    }
    final t = d.resolvePaintTarget();
    if (t == null || layer == null) return;
    if (b.engine != BrushEngine.paint && t.onMask) {
      toast(tr('El difuminado no funciona sobre máscaras', 'Smudge does not work on masks'));
      return;
    }
    final m = d.layerMatrix(layer);
    final ident = m.isIdentity;
    _toLayer = ident ? Mat2D.identity : m.inverse;
    final sym = [for (final s in comp.symmetry.transforms) ident ? s : _toLayer * s * m];
    final clip = (comp.infinite || !ident) ? null : comp.rect;
    final sel = ident ? comp.selection?.mask : null;
    final seed = DateTime.now().microsecondsSinceEpoch & 0x7FFFFFFF;
    final sim = app.settings.simulatePressure;
    if (b.engine == BrushEngine.paint) {
      _paint = PaintStroke(
        brush: b,
        color: t.onMask ? const Color(0xFF000000) : ts.fg,
        symmetry: sym,
        seed: seed,
        clipRect: clip,
        selection: sel,
        lockAlpha: !t.onMask && layer.props.lockAlpha,
        simulatePressure: sim,
      );
    } else {
      _smudge = SmudgeStroke(brush: b, source: t.plane, color: ts.fg, symmetry: sym, seed: seed, clipRect: clip, selection: sel, simulatePressure: sim);
    }
    _doc = d;
    _target = t;
    _brush = b;
    final from = _lastEnd[d.uid];
    if (e.shift && from != null) {
      final n = math.max(2, ((e.doc - from).distance / 4).ceil());
      for (var i = 0; i <= n; i++) {
        _feed(e, at: Offset.lerp(from, e.doc, i / n)!, time: e.timeMs - (n - i) * 6.0);
      }
    } else {
      _feed(e);
    }
    _show();
  }

  void _feed(ToolEvent e, {Offset? at, double? time}) {
    var p = at ?? e.doc;
    if (at == null && _snap != null) p = _snap!.snap(p);
    _last = p;
    final input = StrokeInput(_toLayer.apply(p), pressure: e.pressure, tilt: e.tilt, azimuth: e.azimuth, timeMs: time ?? e.timeMs, hasPressure: e.hasPressure);
    _paint?.add(input);
    _smudge?.add(input);
  }

  void _show() {
    final d = _doc, t = _target;
    if (d == null || t == null) return;
    final p = _paint;
    if (p != null) {
      if (p.flush() || d.live == null) {
        d.setLive(LiveEdit(layerId: t.layerId, replace: t.onMask ? null : t.plane, stroke: p.composite, onMask: t.onMask));
      }
      return;
    }
    final s = _smudge;
    if (s == null) return;
    if (s.flush() || d.live == null) d.setLive(LiveEdit(layerId: t.layerId, replace: s.working));
    if (s.hasPending && !_pumping) {
      // keep draining queued dabs while the pointer rests
      _pumping = true;
      SchedulerBinding.instance.scheduleFrameCallback((_) {
        _pumping = false;
        if (_smudge != null) _show();
      });
    }
  }

  @override
  void onMove(ToolEvent e) {
    if (_doc == null) return;
    if (_vt != null) {
      _vectorMove(e);
      return;
    }
    _feed(e);
    _show();
  }

  @override
  void onUp(ToolEvent e) {
    final d = _doc;
    if (d == null) return;
    if (_vt != null) {
      _endVector(d);
      return;
    }
    final t = _target!, b = _brush!;
    final TilePlane out;
    if (_paint != null) {
      _paint!.finish();
      out = _paint!.commit(t.plane);
    } else {
      _smudge!.finish();
      out = _smudge!.working;
    }
    if (_last != null) _lastEnd[d.uid] = _last!;
    _reset();
    if (identical(out, t.plane) && identical(t.project, d.project)) {
      d.setLive(null);
      return;
    }
    final label = b.erase ? tr('Borrar', 'Erase') : (b.engine == BrushEngine.paint ? tr('Trazo de pincel', 'Brush stroke') : tr('Difuminar', 'Smudge'));
    d.commitPaint(label, t, out);
    if (!t.onMask && !b.erase && b.engine != BrushEngine.smudge) ts.pushColorHistory(ts.fg);
  }

  @override
  void onCancel() {
    final d = _doc;
    _reset();
    d?.setLive(null);
  }

  // ---- vector layers ------------------------------------------------------

  void _beginVector(DocumentController d, VectorLayer layer, BrushPreset b, ToolEvent e) {
    if (b.engine != BrushEngine.paint) {
      toast(tr('Esta herramienta necesita una capa de trama', 'This tool needs a raster layer'));
      return;
    }
    final vt = d.resolveVectorTarget();
    if (vt == null) {
      toast(tr('La capa está bloqueada u oculta', 'The layer is locked or hidden'));
      return;
    }
    final m = d.layerMatrix(layer);
    _toLayer = m.isIdentity ? Mat2D.identity : m.inverse;
    _doc = d;
    _vt = vt;
    _brush = b;
    _erased = b.erase ? vt.art : null;
    _vectorMove(e);
  }

  void _vectorMove(ToolEvent e) {
    final d = _doc!, vt = _vt!, b = _brush!;
    var p = e.doc;
    if (_snap != null) p = _snap!.snap(p);
    final lp = _toLayer.apply(p);
    if (b.erase) {
      final hit = hitTestArt(_erased!, lp, tolerance: math.max(3, b.size / 2));
      if (hit != null) {
        _erased = _erased!.removed({hit.id});
        d.setLive(LiveEdit(layerId: vt.layer.id, replaceArt: _erased));
      }
      return;
    }
    if (_pts.isNotEmpty && (lp - _pts.last).distance < 0.75) return;
    _pts.add(lp);
    _press.add(e.hasPressure ? e.pressure.clamp(0.05, 1.0) : 1.0);
    d.setLive(LiveEdit(layerId: vt.layer.id, replaceArt: vt.art.added(_vectorShape(preview: true))));
  }

  VShape _vectorShape({required bool preview}) {
    final b = _brush!;
    final varWidth = b.pressureSize > 0 && _press.any((p) => p < 0.999);
    VPath path;
    if (_pts.length == 1) {
      path = VPath([VNode(_pts.first), VNode(_pts.first + const Offset(0.01, 0))]);
    } else if (preview || _pts.length < 3) {
      path = VPath([for (var i = 0; i < _pts.length; i++) VNode(_pts[i], width: _press[i])]);
    } else {
      path = CurveFit.fitPath(_pts, tolerance: 1.2, widths: varWidth ? _press : null);
    }
    return VShape(
      paths: [path],
      stroke: VStroke(
        color: ts.fg.withValues(alpha: ts.fg.a * b.opacity),
        width: b.size,
        cap: StrokeCap.round,
        join: StrokeJoin.round,
        profile: varWidth ? WidthProfile.nodes : ts.strokeProfile,
      ),
    );
  }

  void _endVector(DocumentController d) {
    final vt = _vt!, b = _brush!;
    if (b.erase) {
      final art = _erased!;
      _reset();
      if (identical(art, vt.art)) {
        d.setLive(null);
      } else {
        d.commitVector(tr('Borrar trazo', 'Erase stroke'), vt.project, vt.layer.id, vt.drawing, art);
      }
      return;
    }
    if (_pts.isEmpty) {
      _reset();
      d.setLive(null);
      return;
    }
    final shape = _vectorShape(preview: false);
    _reset();
    d.commitVector(tr('Trazo vectorial', 'Vector stroke'), vt.project, vt.layer.id, vt.drawing, vt.art.added(shape));
    ts.pushColorHistory(ts.fg);
  }
}

class _EraserIcon extends CustomPainter {
  _EraserIcon(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.085
      ..strokeJoin = StrokeJoin.round;
    canvas.save();
    canvas.translate(s * 0.5, s * 0.46);
    canvas.rotate(-math.pi / 4);
    final body = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: s * 0.74, height: s * 0.4), Radius.circular(s * 0.07));
    canvas.drawRRect(body, p);
    canvas.drawLine(Offset(-s * 0.08, -s * 0.2), Offset(-s * 0.08, s * 0.2), p);
    canvas.drawRect(Rect.fromLTRB(-s * 0.37, -s * 0.2, -s * 0.08, s * 0.2), Paint()..color = color.withValues(alpha: color.a * 0.45));
    canvas.restore();
    canvas.drawLine(Offset(s * 0.3, s * 0.9), Offset(s * 0.92, s * 0.9), p);
  }

  @override
  bool shouldRepaint(_EraserIcon old) => old.color != color;
}
