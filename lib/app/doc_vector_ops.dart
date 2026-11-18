import '../core/i18n.dart';
import '../engine/morph.dart';
import '../engine/path_ops.dart';
import '../model/anim.dart';
import '../model/layer.dart';
import '../model/vector.dart';
import 'document_controller.dart';

/// Vector-layer operations built on the engine modules (morph, path booleans).
extension DocVectorOps on DocumentController {
  VectorLayer? _vectorLayer(String? layerId) {
    final l = comp.layer(layerId ?? activeLayerId);
    return l is VectorLayer ? l : null;
  }

  /// Fills the gap between the key exposed at the current frame and the next
  /// key with morphed drawings, one per frame (or [count] spread evenly).
  /// Returns how many drawings were inserted (0 when there is no next key or no gap).
  int generateInbetweens({String? layerId, int? count, Ease ease = Ease.linear}) {
    final l = _vectorLayer(layerId);
    if (l == null) return 0;
    final cels = l.cels;
    final from = cels.exposureAt(frame);
    if (from == null) return 0;
    final toFrame = cels.nextKeyFrame(from.frame);
    if (toFrame == null) return 0;
    final gap = toFrame - from.frame - 1;
    if (gap < 1) return 0;
    final a = cels.drawings[from.drawing];
    final b = cels.at(toFrame);
    if (a == null || b == null) return 0;
    final n = (count ?? gap).clamp(1, gap);
    final drawings = inbetweens(a, b, n, ease: ease);
    var next = cels;
    for (var i = 0; i < n; i++) {
      // spread the n drawings over the gap, first one right after the key
      final f = from.frame + 1 + (i * gap / n).floor();
      final id = next.newDrawingId;
      next = next.withDrawing(id, drawings[i]).withKey(f, id);
    }
    final result = next;
    updateLayer(tr('Generar intermedios', 'Generate in-betweens'), l.id, (x) => (x as VectorLayer).withCels(result));
    return n;
  }

  /// Combines the shapes at [indices] (default: all) of the drawing exposed at
  /// the current frame into one shape with [op]; the result takes the place of
  /// the lowest one. Returns false when fewer than two shapes take part or the
  /// result is empty.
  bool combineShapes(BoolOp op, {String? layerId, Set<int>? indices}) {
    final l = _vectorLayer(layerId);
    if (l == null) return false;
    final ex = l.cels.exposureAt(frame);
    final art = ex == null ? null : l.cels.drawings[ex.drawing];
    if (ex == null || art == null) return false;
    final picked = <int>[for (var i = 0; i < art.shapes.length; i++) if (indices == null || indices.contains(i)) i];
    if (picked.length < 2) return false;
    final merged = booleanAll([for (final i in picked) art.shapes[i]], op);
    if (merged == null) return false;
    final shapes = <VShape>[
      for (var i = 0; i < art.shapes.length; i++)
        if (i == picked.first) merged else if (!picked.contains(i)) art.shapes[i],
    ];
    final label = switch (op) {
      BoolOp.union => tr('Unir formas', 'Unite shapes'),
      BoolOp.subtract => tr('Restar formas', 'Subtract shapes'),
      BoolOp.intersect => tr('Intersecar formas', 'Intersect shapes'),
      BoolOp.exclude => tr('Excluir formas', 'Exclude shapes'),
    };
    final cels = l.cels.withDrawing(ex.drawing, VectorArt(shapes));
    updateLayer(label, l.id, (x) => (x as VectorLayer).withCels(cels));
    return true;
  }
}
