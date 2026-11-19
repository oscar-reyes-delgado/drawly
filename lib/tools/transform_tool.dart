import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/doc_layers.dart';
import '../app/document_controller.dart';
import '../app/view_state.dart';
import '../core/i18n.dart';
import '../core/mat2d.dart';
import '../engine/compositor.dart';
import '../engine/tiles.dart';
import '../model/document.dart';
import '../model/layer.dart';
import 'tool.dart';

enum _Drag { none, move, scale, rotate }

/// Free transform of the selected pixels (or the whole drawing of the active
/// paint layer): drag inside to move, handles to scale, outside to rotate.
/// The transform stays open until [confirm] (Enter, or switching tool) or
/// [cancel] (Esc).
class TransformTool extends Tool {
  @override
  String get id => 'transform';
  @override
  String get label => tr('Transformar', 'Transform');
  @override
  IconData get icon => Icons.transform;
  @override
  String get shortcut => 'Ctrl+T';
  @override
  String get hint => tr(
        'Arrastra dentro para mover · esquinas para escalar (Mayús: proporcional) · fuera de la caja para rotar (Mayús: de 15 en 15°) · Intro aplica · Esc cancela',
        'Drag inside to move · corners to scale (Shift: keep proportions) · outside the box to rotate (Shift: 15° steps) · Enter applies · Esc cancels',
      );
  @override
  MouseCursor get cursor => SystemMouseCursors.basic;

  @override
  bool get active => _doc != null;

  DocumentController? _doc;
  PaintTarget? _target;
  SelectionMask? _sel;
  TilePlane? _rest, _float;
  Rect _box = Rect.zero;
  Mat2D _m = Mat2D.identity;
  Future<bool>? _opening;

  _Drag _drag = _Drag.none;
  int _handle = -1;
  Mat2D _startM = Mat2D.identity;
  Offset _startPt = Offset.zero;
  double _startAngle = 0;
  final Stopwatch _sinceLive = Stopwatch();
  Timer? _pendingLive;

  static final Paint _dstOut = Paint()..blendMode = BlendMode.dstOut;
  static final Paint _smooth = Paint()..filterQuality = FilterQuality.medium;

  /// Current transform from the original box to the shown one (null when idle).
  Mat2D? get matrix => _doc == null ? null : _m;

  /// The box being transformed, in its original place (document space).
  Rect? get box => _doc == null ? null : _box;

  /// Opens a transform on the active layer. Resolves to false (with a message)
  /// when there is nothing that can be transformed.
  Future<bool> open() {
    if (_doc != null) return Future.value(true);
    return _opening ??= _open().whenComplete(() => _opening = null);
  }

  Future<bool> _open() async {
    final d = doc;
    if (d == null || d.isBusy) return false;
    final l = d.activeLayer;
    final blocker = d.paintBlocker;
    if (blocker != null) {
      toast(blocker);
      return false;
    }
    if (l is! PaintLayer || d.editMask) {
      toast(tr('Transformar solo funciona en capas de dibujo', 'Transform only works on paint layers'));
      return false;
    }
    if (l.props.lockPosition) {
      toast(tr('La capa tiene la posición bloqueada', 'The layer position is locked'));
      return false;
    }
    if (!d.layerMatrix(l).isIdentity) {
      toast(tr('Restablece la transformación de la capa para usar Transformar', 'Reset the layer transform to use Transform'));
      return false;
    }
    final t = d.resolvePaintTarget();
    if (t == null) return false;
    final sel = d.comp.selection;
    final TilePlane float, rest;
    Rect? box;
    if (sel != null) {
      float = t.plane.maskedBy(sel.mask);
      final keys = sel.mask.keys.where(t.plane.containsKey).toList();
      rest = keys.isEmpty ? t.plane : t.plane.drawn((c) => sel.mask.paint(c, paint: _dstOut), keys: keys);
      box = await float.contentBounds();
    } else {
      float = t.plane;
      rest = TilePlane.empty;
      box = await float.contentBounds();
    }
    if (box == null || box.isEmpty) {
      toast(tr('No hay nada que transformar', 'Nothing to transform'));
      return false;
    }
    // the document may have changed while measuring
    if (doc != d || d.activeLayerId != t.layerId) return false;
    _doc = d;
    _target = t;
    _sel = sel;
    _float = float;
    _rest = rest;
    _box = box;
    _m = Mat2D.identity;
    requestOverlay();
    return true;
  }

  // ---- geometry -------------------------------------------------------------

  /// Handles in original-box coordinates: 0..3 corners (TL, TR, BR, BL), 4..7 edges (T, R, B, L).
  List<Offset> get _localHandles => [
        _box.topLeft, _box.topRight, _box.bottomRight, _box.bottomLeft,
        _box.topCenter, _box.centerRight, _box.bottomCenter, _box.centerLeft,
      ];

  static const List<int> _opposite = [2, 3, 0, 1, 6, 7, 4, 5];

  Offset _rotateHandle(ViewState view) {
    final top = view.toView(_m.apply(_box.topCenter));
    final centre = view.toView(_m.apply(_box.center));
    final dir = top - centre;
    final len = dir.distance;
    return len < 1e-6 ? top - const Offset(0, 28) : top + dir / len * 28;
  }

  bool _insideBox(Offset docPoint) => _box.contains(_m.inverse.apply(docPoint));

  // ---- preview / commit -----------------------------------------------------

  TilePlane _transformedOnto(TilePlane base, TilePlane src, Mat2D m) {
    final area = m.mapRect(_box).inflate(2);
    return base.drawn((c) {
      c.save();
      c.transform(m.storage);
      src.paint(c, paint: _smooth);
      c.restore();
    }, area: area);
  }

  void _showLive({bool force = false}) {
    final d = _doc, t = _target;
    if (d == null || t == null) return;
    if (!force && _sinceLive.isRunning && _sinceLive.elapsedMilliseconds < 30) {
      _pendingLive ??= Timer(const Duration(milliseconds: 30), () {
        _pendingLive = null;
        _showLive(force: true);
      });
      return;
    }
    _pendingLive?.cancel();
    _pendingLive = null;
    _sinceLive
      ..reset()
      ..start();
    d.setLive(LiveEdit(layerId: t.layerId, replace: _transformedOnto(_rest!, _float!, _m)));
  }

  /// Applies the open transform as one undo step. No-op when idle or identity.
  void confirm() {
    final d = _doc, t = _target;
    if (d == null || t == null) return;
    final m = _m, sel = _sel;
    if (m.isIdentity) {
      _close();
      return;
    }
    final out = _transformedOnto(_rest!, _float!, m);
    final c = t.project.comp(d.compId);
    var next = c.updateLayer(t.layerId, (l) => (l as PaintLayer).withCels(l.cels.withDrawing(t.drawing, out)));
    if (sel != null) {
      final mask = _transformMask(sel, m);
      next = next.copyWith(selection: SelectionMask(mask, m.mapRect(sel.bounds)));
    }
    _close();
    d.live = null;
    d.apply(tr('Transformar', 'Transform'), t.project.withComp(next));
  }

  TilePlane _transformMask(SelectionMask sel, Mat2D m) => TilePlane.empty.drawn((c) {
        c.save();
        c.transform(m.storage);
        sel.mask.paint(c, paint: _smooth);
        c.restore();
      }, area: m.mapRect(sel.bounds).inflate(2));

  /// Discards the open transform.
  void cancel() {
    final d = _doc;
    _close();
    d?.setLive(null);
  }

  void _close() {
    _pendingLive?.cancel();
    _pendingLive = null;
    _doc = null;
    _target = null;
    _sel = null;
    _rest = null;
    _float = null;
    _drag = _Drag.none;
    _m = Mat2D.identity;
    requestOverlay();
  }

  void flipHorizontal() => _flip(-1, 1);
  void flipVertical() => _flip(1, -1);

  void _flip(double sx, double sy) {
    if (_doc == null) return;
    final c = _box.center;
    _m = _m * Mat2D.translation(c.dx, c.dy) * Mat2D.scale(sx, sy) * Mat2D.translation(-c.dx, -c.dy);
    _showLive(force: true);
    requestOverlay();
  }

  // ---- events ---------------------------------------------------------------

  @override
  void onActivate() => unawaited(open());

  @override
  void onDeactivate() => confirm();

  @override
  void onDown(ToolEvent e) {
    if (_doc == null) {
      unawaited(open());
      return;
    }
    if (_doc != doc) {
      cancel();
      return;
    }
    final view = _doc!.view;
    _startM = _m;
    _startPt = e.doc;
    _drag = _Drag.none;
    // small boxes on screen get smaller handles so their inside can still be dragged
    final hs = [for (final h in _localHandles) view.toView(_m.apply(h))];
    final side = math.min((hs[1] - hs[0]).distance, (hs[3] - hs[0]).distance);
    final tol = (side / 4).clamp(2.0, 10.0);
    var best = -1;
    var bestDist = double.infinity;
    for (var i = 0; i < hs.length; i++) {
      final dist = (hs[i] - e.view).distance;
      if (dist < tol && dist < bestDist) {
        best = i;
        bestDist = dist;
      }
    }
    if ((_rotateHandle(view) - e.view).distance <= 12) {
      _drag = _Drag.rotate;
    } else if (best >= 0) {
      _drag = _Drag.scale;
      _handle = best;
    } else {
      _drag = _insideBox(e.doc) ? _Drag.move : _Drag.rotate;
    }
    if (_drag == _Drag.rotate) {
      final c = _m.apply(_box.center);
      _startAngle = math.atan2(e.doc.dy - c.dy, e.doc.dx - c.dx);
    }
  }

  @override
  void onMove(ToolEvent e) {
    if (_doc == null || _drag == _Drag.none) return;
    switch (_drag) {
      case _Drag.move:
        var delta = e.doc - _startPt;
        if (e.shift) delta = delta.dx.abs() >= delta.dy.abs() ? Offset(delta.dx, 0) : Offset(0, delta.dy);
        _m = Mat2D.translation(delta.dx.roundToDouble(), delta.dy.roundToDouble()) * _startM;
      case _Drag.rotate:
        final c = _startM.apply(_box.center);
        var a = math.atan2(e.doc.dy - c.dy, e.doc.dx - c.dx) - _startAngle;
        if (e.shift) a = (a / (math.pi / 12)).round() * (math.pi / 12);
        _m = Mat2D.translation(c.dx, c.dy) * Mat2D.rotation(a) * Mat2D.translation(-c.dx, -c.dy) * _startM;
      case _Drag.scale:
        final hs = _localHandles;
        final handle = hs[_handle], anchor = hs[_opposite[_handle]];
        final p = _startM.inverse.apply(e.doc);
        final corner = _handle < 4;
        final horizontal = _handle == 5 || _handle == 7;
        double ratio(double v, double h, double a) => (h - a).abs() < 1e-9 ? 1 : (v - a) / (h - a);
        var sx = corner || horizontal ? ratio(p.dx, handle.dx, anchor.dx) : 1.0;
        var sy = corner || !horizontal ? ratio(p.dy, handle.dy, anchor.dy) : 1.0;
        if (e.shift && corner) {
          final s = math.max(sx.abs(), sy.abs());
          sx = s * (sx < 0 ? -1 : 1);
          sy = s * (sy < 0 ? -1 : 1);
        }
        // never collapse to zero (the inverse would not exist)
        if (sx.abs() < 0.01) sx = sx.isNegative ? -0.01 : 0.01;
        if (sy.abs() < 0.01) sy = sy.isNegative ? -0.01 : 0.01;
        _m = _startM * Mat2D.translation(anchor.dx, anchor.dy) * Mat2D.scale(sx, sy) * Mat2D.translation(-anchor.dx, -anchor.dy);
      case _Drag.none:
        break;
    }
    _showLive();
    requestOverlay();
  }

  @override
  void onUp(ToolEvent e) {
    if (_doc == null) return;
    if (_drag != _Drag.none) _showLive(force: true);
    _drag = _Drag.none;
  }

  @override
  void onDoubleTap(ToolEvent e) => confirm();

  @override
  void onCancel() {
    // a cancelled pointer keeps the transform open; only the drag stops
    if (_drag != _Drag.none) {
      _m = _startM;
      _drag = _Drag.none;
      _showLive(force: true);
    }
  }

  @override
  bool onKey(KeyEvent e) {
    if (_doc == null || e is KeyUpEvent) return false;
    if (e.logicalKey == LogicalKeyboardKey.enter || e.logicalKey == LogicalKeyboardKey.numpadEnter) {
      confirm();
      return true;
    }
    if (e.logicalKey == LogicalKeyboardKey.escape) {
      cancel();
      return true;
    }
    return false;
  }

  @override
  void paintOverlay(Canvas canvas, Size size, ViewState view) {
    if (_doc == null) return;
    final corners = [_box.topLeft, _box.topRight, _box.bottomRight, _box.bottomLeft].map((p) => view.toView(_m.apply(p))).toList();
    final outline = Path()..addPolygon(corners, true);
    Tool.drawContrastPath(canvas, outline);
    final topMid = view.toView(_m.apply(_box.topCenter));
    final rot = _rotateHandle(view);
    Tool.drawContrastPath(canvas, Path()
      ..moveTo(topMid.dx, topMid.dy)
      ..lineTo(rot.dx, rot.dy));
    for (final h in _localHandles) {
      Tool.drawHandle(canvas, view.toView(_m.apply(h)), size: 12);
    }
    Tool.drawHandle(canvas, rot, size: 12, round: true, selected: _drag == _Drag.rotate);
  }
}
