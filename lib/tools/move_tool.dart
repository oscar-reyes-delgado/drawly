import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/doc_layers.dart';
import '../app/doc_timeline.dart';
import '../app/document_controller.dart';
import '../core/i18n.dart';
import '../core/mat2d.dart';
import '../engine/compositor.dart';
import '../engine/tiles.dart';
import '../model/anim.dart';
import '../model/document.dart';
import '../model/layer.dart';
import 'tool.dart';

/// Moves the selected layers, or the selected pixels of a raster layer.
class MoveTool extends Tool {
  @override
  String get id => 'move';
  @override
  String get label => tr('Mover', 'Move');
  @override
  IconData get icon => Icons.open_with;
  @override
  String get shortcut => 'V';
  @override
  String get hint => tr(
        'Arrastra para mover la capa (o los píxeles seleccionados) · Mayús: solo horizontal o vertical · Flechas: 1 px (Mayús: 10 px)',
        'Drag to move the layer (or the selected pixels) · Shift: horizontal or vertical only · Arrows: 1 px (Shift: 10 px)',
      );
  @override
  MouseCursor get cursor => SystemMouseCursors.move;
  @override
  bool get active => _doc != null;

  DocumentController? _doc;
  Offset _start = Offset.zero;
  String _key = '';

  // layers
  final Map<String, Offset> _orig = {};
  final Map<String, Mat2D> _parentInv = {};

  // floating pixels
  PaintTarget? _target;
  TilePlane? _base, _float;
  SelectionMask? _sel;
  Offset _delta = Offset.zero;

  static final Paint _dstOut = Paint()..blendMode = BlendMode.dstOut;

  bool _begin(DocumentController d, Offset at) {
    final l = d.activeLayer;
    if (l == null) {
      toast(tr('No hay ninguna capa seleccionada', 'No layer selected'));
      return false;
    }
    if (l.props.locked || l.props.lockPosition) {
      toast(tr('La capa tiene la posición bloqueada', 'The layer position is locked'));
      return false;
    }
    _start = at;
    _delta = Offset.zero;
    _key = DocumentController.gestureKey('move');
    _orig.clear();
    _parentInv.clear();
    final sel = d.comp.selection;
    if (sel != null && l is PaintLayer && !d.editMask && d.layerMatrix(l).isIdentity) {
      final t = d.resolvePaintTarget();
      if (t != null) {
        final keys = sel.mask.keys.where(t.plane.containsKey).toList();
        _target = t;
        _sel = sel;
        _float = t.plane.maskedBy(sel.mask);
        _base = keys.isEmpty ? t.plane : t.plane.drawn((c) => sel.mask.paint(c, paint: _dstOut), keys: keys);
        _doc = d;
        return true;
      }
    }
    final f = d.frame.toDouble();
    final ids = d.selectedLayers.isEmpty ? {l.id} : d.selectedLayers;
    for (final id in ids) {
      final layer = d.comp.layer(id);
      if (layer == null || layer.props.locked || layer.props.lockPosition) continue;
      // a child of a layer that is also being moved follows its parent
      if (ids.contains(layer.props.parentId)) continue;
      _orig[id] = Offset(layer.props.valueAt(Prop.x, f), layer.props.valueAt(Prop.y, f));
      final parent = d.comp.layer(layer.props.parentId);
      _parentInv[id] = parent == null ? Mat2D.identity : d.comp.worldMatrix(parent, f).inverse;
    }
    if (_orig.isEmpty) return false;
    _doc = d;
    return true;
  }

  void _apply(Offset delta) {
    final d = _doc;
    if (d == null) return;
    final t = _target;
    if (t != null) {
      _delta = Offset(delta.dx.roundToDouble(), delta.dy.roundToDouble());
      d.setLive(LiveEdit(layerId: t.layerId, replace: _base!.composited(_float!.translated(_delta.dx, _delta.dy))));
      return;
    }
    d.setLayersProps({
      for (final e in _orig.entries)
        e.key: () {
          final local = _parentInv[e.key]!.applyVector(delta);
          return {Prop.x: e.value.dx + local.dx, Prop.y: e.value.dy + local.dy};
        }(),
    }, mergeKey: _key, label: tr('Mover capa', 'Move layer'));
  }

  void _finish() {
    final d = _doc;
    final t = _target, sel = _sel, base = _base, float = _float, delta = _delta;
    _clear();
    if (d == null || t == null || sel == null) return;
    if (delta == Offset.zero) {
      d.setLive(null);
      return;
    }
    final out = base!.composited(float!.translated(delta.dx, delta.dy));
    final moved = SelectionMask(sel.mask.translated(delta.dx, delta.dy), sel.bounds.shift(delta));
    final c = t.project.comp(d.compId);
    final next = c.updateLayer(t.layerId, (l) => (l as PaintLayer).withCels(l.cels.withDrawing(t.drawing, out))).copyWith(selection: moved);
    d.live = null;
    d.apply(tr('Mover píxeles', 'Move pixels'), t.project.withComp(next));
  }

  void _clear() {
    _doc = null;
    _target = null;
    _base = null;
    _float = null;
    _sel = null;
    _orig.clear();
    _parentInv.clear();
  }

  @override
  void onDown(ToolEvent e) {
    final d = doc;
    if (d == null || d.isBusy || _doc != null) return;
    _begin(d, e.doc);
  }

  @override
  void onMove(ToolEvent e) {
    if (_doc == null) return;
    var delta = e.doc - _start;
    if (e.shift) delta = delta.dx.abs() >= delta.dy.abs() ? Offset(delta.dx, 0) : Offset(0, delta.dy);
    _apply(delta);
  }

  @override
  void onUp(ToolEvent e) => _finish();

  @override
  void onCancel() {
    final d = _doc;
    final floating = _target != null;
    _clear();
    if (floating) d?.setLive(null);
  }

  @override
  bool onKey(KeyEvent e) {
    if (e is KeyUpEvent || _doc != null) return false;
    final step = HardwareKeyboard.instance.isShiftPressed ? 10.0 : 1.0;
    final k = e.logicalKey;
    final Offset delta;
    if (k == LogicalKeyboardKey.arrowLeft) {
      delta = Offset(-step, 0);
    } else if (k == LogicalKeyboardKey.arrowRight) {
      delta = Offset(step, 0);
    } else if (k == LogicalKeyboardKey.arrowUp) {
      delta = Offset(0, -step);
    } else if (k == LogicalKeyboardKey.arrowDown) {
      delta = Offset(0, step);
    } else {
      return false;
    }
    final d = doc;
    if (d == null || d.isBusy) return false;
    if (!_begin(d, Offset.zero)) return true;
    // consecutive nudges of the same layers collapse into one undo step
    _key = 'nudge';
    _apply(delta);
    _finish();
    return true;
  }
}
