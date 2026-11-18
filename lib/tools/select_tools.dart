import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/doc_selection.dart';
import '../app/document_controller.dart';
import '../app/view_state.dart';
import '../core/i18n.dart';
import 'tool.dart';

const String _modeHint = 'Mayús: añadir · Alt: restar · Mayús + Alt: intersecar';
const String _modeHintEn = 'Shift: add · Alt: subtract · Shift + Alt: intersect';

mixin _SelectMode on Tool {
  SelectMode modeFor(ToolEvent e) {
    if (e.shift && e.alt) return SelectMode.intersect;
    if (e.shift) return SelectMode.add;
    if (e.alt) return SelectMode.subtract;
    return ts.selectMode;
  }
}

/// Rectangular / elliptical marquee.
class MarqueeTool extends Tool with _SelectMode {
  @override
  String get id => 'marquee';
  @override
  String get label => tr('Marco de selección', 'Marquee');
  @override
  IconData get icon => Icons.highlight_alt;
  @override
  String get shortcut => 'M';
  @override
  String get hint => tr('Arrastra para seleccionar · Ctrl: proporción 1:1 · $_modeHint', 'Drag to select · Ctrl: 1:1 ratio · $_modeHintEn');
  @override
  bool get active => _a != null;

  DocumentController? _doc;
  Offset? _a, _b;
  SelectMode _mode = SelectMode.replace;

  Rect get _rect {
    final r = Rect.fromPoints(_a!, _b!);
    return Rect.fromLTRB(r.left.roundToDouble(), r.top.roundToDouble(), r.right.roundToDouble(), r.bottom.roundToDouble());
  }

  Path _path(Rect r) => ts.marqueeShape == 'ellipse' ? (Path()..addOval(r)) : (Path()..addRect(r));

  @override
  void onDown(ToolEvent e) {
    final d = doc;
    if (d == null || d.isBusy) return;
    _doc = d;
    _mode = modeFor(e);
    _a = _b = snapDoc(e.doc);
  }

  @override
  void onMove(ToolEvent e) {
    final a = _a;
    if (a == null) return;
    var b = snapDoc(e.doc);
    if (e.ctrl) {
      final v = b - a;
      final s = math.max(v.dx.abs(), v.dy.abs());
      b = a + Offset(v.dx < 0 ? -s : s, v.dy < 0 ? -s : s);
    }
    _b = b;
    requestOverlay();
  }

  @override
  void onUp(ToolEvent e) {
    final d = _doc;
    if (d == null || _a == null) return;
    final r = _rect;
    final mode = _mode;
    onCancel();
    if (r.width < 1 || r.height < 1) {
      if (mode == SelectMode.replace) d.deselect();
      return;
    }
    d.selectPath(_path(r), mode: mode, antiAlias: ts.marqueeShape == 'ellipse' && ts.selectAntiAlias, feather: ts.selectFeather);
  }

  @override
  void onCancel() {
    _doc = null;
    _a = null;
    _b = null;
    requestOverlay();
  }

  @override
  void paintOverlay(Canvas canvas, Size size, ViewState view) {
    if (_a == null) return;
    Tool.drawContrastPath(canvas, Tool.viewPath(_path(_rect), view));
  }
}

/// Freehand lasso.
class LassoTool extends Tool with _SelectMode {
  @override
  String get id => 'lasso';
  @override
  String get label => tr('Lazo', 'Lasso');
  @override
  IconData get icon => Icons.gesture;
  @override
  String get shortcut => 'L';
  @override
  String get hint => tr('Dibuja el contorno de la selección · $_modeHint', 'Draw the outline of the selection · $_modeHintEn');
  @override
  bool get active => _doc != null;

  DocumentController? _doc;
  final List<Offset> _pts = [];
  SelectMode _mode = SelectMode.replace;

  Path _path({bool close = true}) {
    final p = Path()..moveTo(_pts.first.dx, _pts.first.dy);
    for (final q in _pts.skip(1)) {
      p.lineTo(q.dx, q.dy);
    }
    if (close) p.close();
    return p;
  }

  @override
  void onDown(ToolEvent e) {
    final d = doc;
    if (d == null || d.isBusy) return;
    _doc = d;
    _mode = modeFor(e);
    _pts
      ..clear()
      ..add(e.doc);
  }

  @override
  void onMove(ToolEvent e) {
    if (_doc == null) return;
    if ((e.doc - _pts.last).distance * _doc!.view.zoom < 1.5) return;
    _pts.add(e.doc);
    requestOverlay();
  }

  @override
  void onUp(ToolEvent e) {
    final d = _doc;
    if (d == null) return;
    final mode = _mode;
    final path = _pts.length >= 3 ? _path() : null;
    onCancel();
    if (path == null) {
      if (mode == SelectMode.replace) d.deselect();
      return;
    }
    d.selectPath(path, mode: mode, antiAlias: ts.selectAntiAlias, feather: ts.selectFeather);
  }

  @override
  void onCancel() {
    _doc = null;
    _pts.clear();
    requestOverlay();
  }

  @override
  void paintOverlay(Canvas canvas, Size size, ViewState view) {
    if (_pts.length < 2) return;
    Tool.drawContrastPath(canvas, Tool.viewPath(_path(close: false), view));
  }
}

/// Polygonal lasso: click to add corners, double click or Enter to close.
class PolyLassoTool extends Tool with _SelectMode {
  @override
  String get id => 'polylasso';
  @override
  String get label => tr('Lazo poligonal', 'Polygonal lasso');
  @override
  IconData get icon => Icons.polyline;
  @override
  String get shortcut => 'Shift+L';
  @override
  String get hint => tr(
        'Clic: añadir vértice · Doble clic o Intro: cerrar · Retroceso: quitar el último · Esc: cancelar',
        'Click: add a corner · Double click or Enter: close · Backspace: remove the last · Esc: cancel',
      );
  @override
  bool get active => _pts.isNotEmpty;

  DocumentController? _doc;
  final List<Offset> _pts = [];
  Offset? _hover;
  SelectMode _mode = SelectMode.replace;

  @override
  void onDown(ToolEvent e) {
    final d = doc;
    if (d == null || d.isBusy) return;
    final p = snapDoc(e.doc);
    if (_pts.isEmpty) {
      _doc = d;
      _mode = modeFor(e);
    } else if (_pts.length >= 3 && (p - _pts.first).distance * d.view.zoom < 10) {
      _close();
      return;
    }
    _pts.add(p);
    _hover = p;
    requestOverlay();
  }

  @override
  void onMove(ToolEvent e) => onHover(e);

  @override
  void onHover(ToolEvent e) {
    if (_pts.isEmpty) return;
    _hover = snapDoc(e.doc);
    requestOverlay();
  }

  @override
  void onDoubleTap(ToolEvent e) => _close();

  void _close() {
    final d = _doc;
    if (d == null || _pts.length < 3) {
      onCancel();
      return;
    }
    final path = Path()..addPolygon(List.of(_pts), true);
    final mode = _mode;
    onCancel();
    d.selectPath(path, mode: mode, antiAlias: ts.selectAntiAlias, feather: ts.selectFeather);
  }

  @override
  bool onKey(KeyEvent e) {
    if (_pts.isEmpty || e is KeyUpEvent) return false;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) {
      _close();
      return true;
    }
    if (k == LogicalKeyboardKey.escape) {
      onCancel();
      return true;
    }
    if (k == LogicalKeyboardKey.backspace) {
      _pts.removeLast();
      if (_pts.isEmpty) onCancel();
      requestOverlay();
      return true;
    }
    return false;
  }

  @override
  void onCancel() {
    _doc = null;
    _pts.clear();
    _hover = null;
    requestOverlay();
  }

  @override
  void onDeactivate() => onCancel();

  @override
  void paintOverlay(Canvas canvas, Size size, ViewState view) {
    if (_pts.isEmpty) return;
    final path = Path()..moveTo(_pts.first.dx, _pts.first.dy);
    for (final q in _pts.skip(1)) {
      path.lineTo(q.dx, q.dy);
    }
    if (_hover != null) path.lineTo(_hover!.dx, _hover!.dy);
    Tool.drawContrastPath(canvas, Tool.viewPath(path, view));
    for (var i = 0; i < _pts.length; i++) {
      Tool.drawHandle(canvas, view.toView(_pts[i]), size: i == 0 ? 9 : 6, selected: i == 0 && _pts.length >= 3);
    }
  }
}

/// Magic wand.
class WandTool extends Tool with _SelectMode {
  @override
  String get id => 'wand';
  @override
  String get label => tr('Varita mágica', 'Magic wand');
  @override
  IconData get icon => Icons.auto_fix_high;
  @override
  String get shortcut => 'W';
  @override
  String get hint => tr('Clic para seleccionar una zona de color parecido · $_modeHint', 'Click to select an area of similar colour · $_modeHintEn');

  @override
  void onDown(ToolEvent e) {
    final d = doc;
    if (d == null || d.isBusy) return;
    d.magicWand(e.doc, tolerance: ts.tolerance, contiguous: ts.contiguous, source: ts.sampleSource, mode: modeFor(e), antiAlias: ts.selectAntiAlias, gap: ts.fillGap);
  }
}
