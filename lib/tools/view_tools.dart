import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/document_controller.dart';
import '../app/view_state.dart';
import '../core/i18n.dart';
import 'tool.dart';

/// Pans the view.
class HandTool extends Tool {
  @override
  String get id => 'hand';
  @override
  String get label => tr('Mano', 'Hand');
  @override
  IconData get icon => Icons.pan_tool_outlined;
  @override
  String get shortcut => 'H';
  @override
  String get hint => tr('Arrastra para desplazar la vista · También: mantén Espacio con cualquier herramienta', 'Drag to pan · Also: hold Space with any tool');
  @override
  MouseCursor get cursor => _last == null ? SystemMouseCursors.grab : SystemMouseCursors.grabbing;
  @override
  bool get active => _last != null;

  Offset? _last;
  DocumentController? _doc;

  @override
  void onDown(ToolEvent e) {
    _doc = doc;
    _last = e.view;
  }

  @override
  void onMove(ToolEvent e) {
    final d = _doc, last = _last;
    if (d == null || last == null) return;
    d.setView(d.view.panned(e.view - last));
    _last = e.view;
  }

  @override
  void onUp(ToolEvent e) => onCancel();

  @override
  void onCancel() {
    _last = null;
    _doc = null;
  }
}

/// Click to zoom in (Alt: out); drag sideways for a continuous zoom.
class ZoomTool extends Tool {
  @override
  String get id => 'zoom';
  @override
  String get label => tr('Zoom', 'Zoom');
  @override
  IconData get icon => Icons.zoom_in;
  @override
  String get shortcut => 'Z';
  @override
  String get hint => tr('Clic: acercar · Alt + clic: alejar · Arrastra a los lados: zoom continuo', 'Click: zoom in · Alt + click: zoom out · Drag sideways: scrubby zoom');
  @override
  MouseCursor get cursor => SystemMouseCursors.zoomIn;
  @override
  bool get active => _start != null;

  Offset? _start;
  ViewState? _view;
  DocumentController? _doc;
  bool _dragged = false;

  @override
  void onDown(ToolEvent e) {
    _doc = doc;
    _start = e.view;
    _view = _doc?.view;
    _dragged = false;
  }

  @override
  void onMove(ToolEvent e) {
    final d = _doc, s = _start, v = _view;
    if (d == null || s == null || v == null) return;
    final dx = e.view.dx - s.dx;
    if (dx.abs() > 3) _dragged = true;
    if (_dragged) d.setView(v.zoomedAt(s, math.exp(dx / 120)));
  }

  @override
  void onUp(ToolEvent e) {
    final d = _doc, s = _start;
    if (d != null && s != null && !_dragged) d.setView(d.view.zoomedAt(s, e.alt ? 0.5 : 2));
    onCancel();
  }

  @override
  void onCancel() {
    _start = null;
    _view = null;
    _doc = null;
  }
}

/// Rotates the view around the middle of the viewport.
class RotateViewTool extends Tool {
  @override
  String get id => 'rotateView';
  @override
  String get label => tr('Rotar vista', 'Rotate view');
  @override
  IconData get icon => Icons.screen_rotation_alt;
  @override
  String get shortcut => 'R';
  @override
  String get hint => tr('Arrastra para girar el lienzo · Mayús: pasos de 15° · Doble clic: restablecer', 'Drag to rotate the canvas · Shift: 15° steps · Double click: reset');
  @override
  MouseCursor get cursor => SystemMouseCursors.grab;
  @override
  bool get active => _startAngle != null;

  double? _startAngle;
  ViewState? _view;
  DocumentController? _doc;

  Offset get _center => Offset((_doc?.viewportSize.width ?? 0) / 2, (_doc?.viewportSize.height ?? 0) / 2);

  @override
  void onDown(ToolEvent e) {
    _doc = doc;
    _view = _doc?.view;
    final v = e.view - _center;
    _startAngle = math.atan2(v.dy, v.dx);
  }

  @override
  void onMove(ToolEvent e) {
    final d = _doc, v0 = _view, a0 = _startAngle;
    if (d == null || v0 == null || a0 == null) return;
    final v = e.view - _center;
    var target = v0.rotation + math.atan2(v.dy, v.dx) - a0;
    if (e.shift) {
      const step = math.pi / 12;
      target = (target / step).roundToDouble() * step;
    }
    d.setView(v0.withRotationAt(_center, target));
  }

  @override
  void onUp(ToolEvent e) => onCancel();

  @override
  void onDoubleTap(ToolEvent e) {
    final d = doc;
    if (d == null) return;
    d.setView(d.view.withRotationAt(Offset(d.viewportSize.width / 2, d.viewportSize.height / 2), 0));
  }

  @override
  void onCancel() {
    _startAngle = null;
    _view = null;
    _doc = null;
  }
}
