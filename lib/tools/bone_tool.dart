import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/doc_bones.dart';
import '../app/doc_layers.dart';
import '../app/document_controller.dart';
import '../app/view_state.dart';
import '../core/i18n.dart';
import '../core/mat2d.dart';
import '../model/layer.dart';
import '../model/layer_rig.dart';
import 'tool.dart';

enum _BoneMode { none, create, rotate, ik }

/// Creates, poses (FK/IK) and deletes deformation bones on the active [PaintLayer].
class BoneTool extends Tool {
  @override
  String get id => 'bones';

  @override
  String get label => tr('Huesos', 'Bones');

  @override
  IconData get icon => Icons.polyline;
  @override
  String get shortcut => 'Shift+B';

  @override
  String get hint => tr(
        'Arrastra en vacío para crear un hueso (desde una punta para emparentar) · Arrastra un hueso para girarlo · Mayús+arrastrar: IK · Alt+clic: eliminar',
        'Drag in empty space to create a bone (from a tip to parent) · Drag a bone to rotate · Shift+drag: IK · Alt+click: delete',
      );

  @override
  bool get active => _mode != _BoneMode.none;

  _BoneMode _mode = _BoneMode.none;
  DocumentController? _doc;
  String _layerId = '';
  String _boneId = '';
  String _mergeKey = '';
  String? _hoveredBoneId;

  Offset _downDoc = Offset.zero;
  Offset _lastDoc = Offset.zero;

  // Create mode state (layer coordinates).
  Offset _createHead = Offset.zero;
  Offset _createTail = Offset.zero;
  String? _createParentId;

  // Rotate mode state (layer coordinates).
  Offset _boneHead = Offset.zero;
  Offset _prevVec = Offset.zero;
  double _startRot = 0;
  double _accumRad = 0;

  void _resetDrag() {
    _mode = _BoneMode.none;
    _doc = null;
    _layerId = '';
    _boneId = '';
    _mergeKey = '';
    _downDoc = Offset.zero;
    _lastDoc = Offset.zero;
    _createHead = Offset.zero;
    _createTail = Offset.zero;
    _createParentId = null;
    _boneHead = Offset.zero;
    _prevVec = Offset.zero;
    _startRot = 0;
    _accumRad = 0;
  }

  /// Bone under [docPoint] on the active layer (posed), within [tolerance]
  /// document px; null if none.
  String? boneAt(Offset docPoint, {double tolerance = 6}) {
    final d = doc;
    if (d == null) return null;
    final l = d.activeLayer;
    if (l is! PaintLayer) return null;
    final posed = d.posedBonesOf(l.id);
    if (posed.isEmpty) return null;
    final m = d.layerMatrix(l);
    String? bestId;
    var bestDist = tolerance;
    for (final entry in posed.entries) {
      final a = m.apply(entry.value.$1);
      final b = m.apply(entry.value.$2);
      final dist = distanceToSegment(docPoint, a, b);
      if (dist <= bestDist) {
        bestDist = dist;
        bestId = entry.key;
      }
    }
    return bestId;
  }

  ({String parentId, Offset headLayer})? _tailSnapAt(
    DocumentController d,
    PaintLayer layer,
    Offset docPoint,
    double maxDocDist,
  ) {
    final posed = d.posedBonesOf(layer.id);
    if (posed.isEmpty) return null;
    final m = d.layerMatrix(layer);
    String? bestId;
    Offset? bestTail;
    var bestDist = maxDocDist;
    for (final entry in posed.entries) {
      final docTail = m.apply(entry.value.$2);
      final dist = (docTail - docPoint).distance;
      if (dist < bestDist) {
        bestDist = dist;
        bestId = entry.key;
        bestTail = entry.value.$2;
      }
    }
    if (bestId == null || bestTail == null) return null;
    return (parentId: bestId, headLayer: bestTail);
  }

  Offset _toLayer(DocumentController d, Layer l, Offset docPoint) =>
      d.layerMatrix(l).inverse.apply(docPoint);

  @override
  void onHover(ToolEvent e) {
    final d = doc;
    final zoom = (d == null || d.view.zoom <= 0) ? 1.0 : d.view.zoom;
    final next = (d == null || d.activeLayer is! PaintLayer)
        ? null
        : boneAt(e.doc, tolerance: 6 / zoom);
    if (next != _hoveredBoneId) {
      _hoveredBoneId = next;
      requestOverlay();
    }
  }

  @override
  void onDown(ToolEvent e) {
    final d = doc;
    if (d == null || d.isBusy || _mode != _BoneMode.none) return;
    final l = d.activeLayer;
    if (l is! PaintLayer || d.editMask) {
      toast(tr('Los huesos solo funcionan en capas de dibujo', 'Bones only work on paint layers'));
      return;
    }
    if (l.props.locked) {
      toast(tr('La capa está bloqueada', 'The layer is locked'));
      return;
    }

    final zoom = d.view.zoom <= 0 ? 1.0 : d.view.zoom;
    final hit = boneAt(e.doc, tolerance: 6 / zoom);

    if (e.alt) {
      if (hit != null) {
        d.removeBone(l.id, hit);
        if (_hoveredBoneId == hit) _hoveredBoneId = null;
        requestOverlay();
      }
      return;
    }

    if (e.shift) {
      if (hit == null) return;
      _mode = _BoneMode.ik;
      _doc = d;
      _layerId = l.id;
      _boneId = hit;
      _mergeKey = DocumentController.gestureKey('bones');
      _downDoc = e.doc;
      _lastDoc = e.doc;
      _hoveredBoneId = hit;
      requestOverlay();
      return;
    }

    final rig = l.rig;
    final isRest = rig == null || rig.isRestAt(d.frame.toDouble());
    final snap = isRest ? _tailSnapAt(d, l, e.doc, 8 / zoom) : null;
    final layerPt = _toLayer(d, l, e.doc);

    if (snap != null) {
      _mode = _BoneMode.create;
      _doc = d;
      _layerId = l.id;
      _downDoc = e.doc;
      _lastDoc = e.doc;
      _createHead = snap.headLayer;
      _createTail = layerPt;
      _createParentId = snap.parentId;
      requestOverlay();
      return;
    }

    if (hit != null) {
      final posed = d.posedBonesOf(l.id)[hit];
      if (posed == null) return;
      _mode = _BoneMode.rotate;
      _doc = d;
      _layerId = l.id;
      _boneId = hit;
      _mergeKey = DocumentController.gestureKey('bones');
      _downDoc = e.doc;
      _lastDoc = e.doc;
      _boneHead = posed.$1;
      _prevVec = layerPt - _boneHead;
      _startRot = d.boneRot(l.id, hit);
      _accumRad = 0;
      _hoveredBoneId = hit;
      requestOverlay();
      return;
    }

    if (!isRest) {
      toast(tr('Para añadir huesos ve a un fotograma sin pose', 'Go to a frame without pose to add bones'));
      return;
    }

    _mode = _BoneMode.create;
    _doc = d;
    _layerId = l.id;
    _downDoc = e.doc;
    _lastDoc = e.doc;
    _createHead = layerPt;
    _createTail = layerPt;
    _createParentId = null;
    requestOverlay();
  }

  void _applyMove(ToolEvent e) {
    final d = _doc;
    if (d == null) return;
    final l = d.comp.layer(_layerId);
    if (l is! PaintLayer) return;
    final layerPt = _toLayer(d, l, e.doc);
    _lastDoc = e.doc;

    switch (_mode) {
      case _BoneMode.none:
        return;
      case _BoneMode.create:
        _createTail = layerPt;
        requestOverlay();
      case _BoneMode.rotate:
        final curVec = layerPt - _boneHead;
        if (curVec.distance < 1e-6) return;
        if (_prevVec.distance < 1e-6) {
          _prevVec = curVec;
          return;
        }
        final cross = _prevVec.dx * curVec.dy - _prevVec.dy * curVec.dx;
        final dot = _prevVec.dx * curVec.dx + _prevVec.dy * curVec.dy;
        _accumRad += math.atan2(cross, dot);
        _prevVec = curVec;
        final nextRot = _startRot + radToDeg(_accumRad);
        d.setBoneRots(_layerId, {_boneId: nextRot}, mergeKey: _mergeKey);
        requestOverlay();
      case _BoneMode.ik:
        d.poseBonesIk(_layerId, _boneId, layerPt, chainLength: 2, mergeKey: _mergeKey);
        requestOverlay();
    }
  }

  @override
  void onMove(ToolEvent e) {
    if (_mode == _BoneMode.none) return;
    _applyMove(e);
  }

  @override
  void onUp(ToolEvent e) {
    if (_mode == _BoneMode.none) return;
    final d = _doc;
    final mode = _mode;
    final layerId = _layerId;
    final downDoc = _downDoc;
    if (e.doc != _lastDoc) _applyMove(e);
    final createHead = _createHead;
    final createTail = _createTail;
    final createParentId = _createParentId;
    _resetDrag();

    if (mode == _BoneMode.create && d != null) {
      final dragDist = (e.doc - downDoc).distance;
      if (dragDist >= 1 && (createTail - createHead).distance >= 1) {
        d.addBone(layerId, createHead, createTail, parentId: createParentId);
      }
    }
    requestOverlay();
  }

  @override
  void onCancel() {
    if (_mode == _BoneMode.none) return;
    _resetDrag();
    requestOverlay();
  }

  @override
  void onDeactivate() {
    _hoveredBoneId = null;
    onCancel();
  }

  void _drawBoneShape(Canvas canvas, Offset head, Offset tail, {required bool highlight}) {
    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = highlight ? const Color(0xCC4F8CFF) : const Color(0xCCFFFFFF);
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeJoin = StrokeJoin.round
      ..color = const Color(0xDD1B1B1F);

    final delta = tail - head;
    final len = delta.distance;
    if (len >= 1) {
      final dir = delta / len;
      final perp = Offset(-dir.dy, dir.dx);
      final width = math.min(7.0, math.max(3.0, len * 0.12));
      final shoulder = head + dir * math.min(len * 0.22, 14.0);
      final path = Path()
        ..moveTo(head.dx, head.dy)
        ..lineTo(shoulder.dx + perp.dx * width, shoulder.dy + perp.dy * width)
        ..lineTo(tail.dx, tail.dy)
        ..lineTo(shoulder.dx - perp.dx * width, shoulder.dy - perp.dy * width)
        ..close();
      canvas.drawPath(path, fill);
      canvas.drawPath(path, border);
    }
    Tool.drawHandle(canvas, head, round: true, selected: highlight, size: 9);
  }

  @override
  void paintOverlay(Canvas canvas, Size size, ViewState view) {
    final d = doc;
    final l = d?.activeLayer;
    if (d == null || l is! PaintLayer) return;
    final toScreen = view.matrix * d.layerMatrix(l);
    final posed = d.posedBonesOf(l.id);
    for (final entry in posed.entries) {
      final head = toScreen.apply(entry.value.$1);
      final tail = toScreen.apply(entry.value.$2);
      final highlight = entry.key == _hoveredBoneId ||
          ((_mode == _BoneMode.rotate || _mode == _BoneMode.ik) && entry.key == _boneId);
      _drawBoneShape(canvas, head, tail, highlight: highlight);
    }
    if (_mode == _BoneMode.create && _layerId == l.id) {
      final head = toScreen.apply(_createHead);
      final tail = toScreen.apply(_createTail);
      if ((tail - head).distance >= 1) {
        _drawBoneShape(canvas, head, tail, highlight: true);
      }
    }
  }
}
