import 'package:flutter/material.dart';

import '../app/doc_tracking.dart';
import '../app/document_controller.dart';
import '../app/view_state.dart';
import '../core/i18n.dart';
import 'tool.dart';

/// Click a point on the canvas to track its motion across frames and animate the active layer.
class TrackTool extends Tool {
  @override
  String get id => 'track';

  @override
  String get label => tr('Seguimiento', 'Track motion');

  @override
  IconData get icon => Icons.my_location;

  @override
  String get shortcut => '';

  @override
  String get hint => tr(
        'Haz clic en un punto para seguir su movimiento y animar la capa activa',
        'Click a point to track its motion and animate the active layer',
      );

  @override
  bool get active => _downView != null;

  DocumentController? _doc;
  Offset? _downView;
  bool _dragged = false;
  bool _cancelled = false;

  String? _lastDocId;
  String? _lastCompId;
  List<Offset> _lastPath = const [];

  void _resetPress() {
    _doc = null;
    _downView = null;
    _dragged = false;
    _cancelled = false;
  }

  @override
  void onDown(ToolEvent e) {
    final d = doc;
    if (d == null || d.isBusy) return;
    _doc = d;
    _downView = e.view;
    _dragged = false;
    _cancelled = false;
  }

  @override
  void onMove(ToolEvent e) {
    final s = _downView;
    if (s == null) return;
    if ((e.view - s).distance > 4) _dragged = true;
  }

  @override
  void onCancel() {
    final hadPress = _downView != null;
    _resetPress();
    _cancelled = hadPress;
  }

  @override
  void onUp(ToolEvent e) {
    final d = _doc ?? doc;
    final downView = _downView;
    final dragged = _dragged || (downView != null && (e.view - downView).distance > 4);
    final cancelled = _cancelled;
    _resetPress();
    if (cancelled || dragged || d == null || d.isBusy) return;

    final layer = d.activeLayer;
    if (layer == null) {
      toast(tr('No hay ninguna capa seleccionada', 'No layer selected'));
      return;
    }
    if (layer.props.locked || layer.props.lockPosition) {
      toast(tr('La capa tiene la posición bloqueada', 'The layer position is locked'));
      return;
    }

    final layerId = layer.id;
    final compId = d.compId;
    final point = e.doc;
    d.run(label, () async {
      final path = await d.trackFromCurrentFrame(point, excludeLayerId: layerId);
      if (path.isEmpty) {
        toast(tr('No hay fotogramas para seguir', 'No frames to track'));
        return;
      }
      if (d.compId != compId || d.comp.layer(layerId) == null) return;
      final count = d.applyTrackToLayer(layerId, path);
      _lastDocId = d.uid;
      _lastCompId = compId;
      _lastPath = path;
      requestOverlay();
      toast('${tr('Seguimiento aplicado', 'Motion tracked')} ($count ${tr('fotogramas', 'frames')})');
    });
  }

  @override
  void paintOverlay(Canvas canvas, Size size, ViewState view) {
    final d = doc;
    if (d == null || d.uid != _lastDocId || d.compId != _lastCompId || _lastPath.isEmpty) return;
    if (_lastPath.length >= 2) {
      final path = Path()..moveTo(_lastPath.first.dx, _lastPath.first.dy);
      for (final p in _lastPath.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      Tool.drawContrastPath(canvas, Tool.viewPath(path, view));
    }
    for (var i = 0; i < _lastPath.length; i++) {
      Tool.drawHandle(canvas, view.toView(_lastPath[i]), selected: i == 0, size: i == 0 ? 8 : 5, round: true);
    }
  }
}
