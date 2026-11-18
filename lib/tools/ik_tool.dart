import 'package:flutter/material.dart';

import '../app/doc_rig.dart';
import '../app/document_controller.dart';
import '../app/view_state.dart';
import '../core/i18n.dart';
import '../model/layer.dart';
import 'tool.dart';

/// Poses a chain of parented layers (cut-out rig) by dragging the active one:
/// its parents rotate around their anchor points so the grabbed point follows
/// the pointer. Ctrl limits the chain to two layers.
class IkTool extends Tool {
  @override
  String get id => 'ik';
  @override
  String get label => tr('Cinemática inversa', 'Inverse kinematics');
  @override
  IconData get icon => Icons.accessibility_new;
  @override
  String get shortcut => 'Shift+K';
  @override
  String get hint => tr(
        'Arrastra la capa activa: sus capas padre giran sobre sus anclas para seguir el puntero (Ctrl: solo dos eslabones). Emparenta capas en Propiedades > Capa.',
        'Drag the active layer: its parent layers rotate around their anchors to follow the pointer (Ctrl: two links only). Parent layers in Properties > Layer.',
      );
  @override
  MouseCursor get cursor => SystemMouseCursors.grab;
  @override
  bool get active => _doc != null;

  DocumentController? _doc;
  String _tip = '', _key = '';
  Offset _grab = Offset.zero;
  int _length = 3;

  @override
  void onDown(ToolEvent e) {
    final d = doc;
    if (d == null || d.isBusy || _doc != null) return;
    final l = d.activeLayer;
    if (l == null) {
      toast(tr('No hay ninguna capa seleccionada', 'No layer selected'));
      return;
    }
    _length = e.ctrl ? 2 : 3;
    final chain = d.parentChain(l.id, length: _length);
    if (chain.length < 2) {
      toast(tr('La capa activa no tiene capa padre: emparéntala en Propiedades', 'The active layer has no parent layer: parent it in Properties'));
      return;
    }
    if (chain.any((c) => c.props.locked || c.props.lockPosition)) {
      toast(tr('Una capa de la cadena está bloqueada', 'A layer of the chain is locked'));
      return;
    }
    _doc = d;
    _tip = l.id;
    _grab = d.comp.worldMatrix(l, d.frame.toDouble()).inverse.apply(e.doc);
    _key = DocumentController.gestureKey('ik');
    requestOverlay();
  }

  @override
  void onMove(ToolEvent e) {
    final d = _doc;
    if (d == null) return;
    d.dragLayerIk(_tip, _grab, e.doc, length: _length, mergeKey: _key);
    requestOverlay();
  }

  @override
  void onUp(ToolEvent e) => _end();

  @override
  void onCancel() => _end();

  void _end() {
    _doc = null;
    requestOverlay();
  }

  @override
  void paintOverlay(Canvas canvas, Size size, ViewState view) {
    final d = doc;
    final l = d?.activeLayer;
    if (d == null || l == null) return;
    final chain = d.parentChain(l.id, length: 8);
    if (chain.length < 2) return;
    final pts = [for (final c in chain) view.toView(d.layerPivot(c))];
    final bone = Paint()
      ..color = const Color(0xFF4F8CFF)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i + 1 < pts.length; i++) {
      canvas.drawLine(pts[i], pts[i + 1], Paint()
        ..color = const Color(0xB0000000)
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round);
      canvas.drawLine(pts[i], pts[i + 1], bone);
    }
    final inChain = chain.length - _length;
    for (var i = 0; i < pts.length; i++) {
      Tool.drawHandle(canvas, pts[i], round: true, selected: i >= inChain, size: chain[i] is GroupLayer ? 11 : 9);
    }
  }
}
