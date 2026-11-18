import 'dart:ui';

import '../core/i18n.dart';
import '../core/mat2d.dart';
import '../engine/rig.dart';
import '../model/anim.dart';
import '../model/layer.dart';
import 'doc_timeline.dart';
import 'document_controller.dart';

/// Cut-out rigging on top of layer parenting: a layer's parent chain is a
/// skeleton whose joints are the layers' anchor points.
extension DocRig on DocumentController {
  /// Layers from the top of the chain down to [tipId], following `parentId`
  /// (at most [length] layers, the tip included).
  List<Layer> parentChain(String tipId, {int length = 3}) {
    final out = <Layer>[];
    var l = comp.layer(tipId);
    while (l != null && out.length < length && !out.contains(l)) {
      out.insert(0, l);
      l = comp.layer(l.props.parentId);
    }
    return out;
  }

  /// Document position of the joint (anchor point) of [l] at the current frame.
  Offset layerPivot(Layer l) {
    final f = frame.toDouble();
    return comp.worldMatrix(l, f).apply(Offset(l.props.valueAt(Prop.anchorX, f), l.props.valueAt(Prop.anchorY, f)));
  }

  /// Rotations (degrees, absolute values at the current frame) for the parent
  /// chain of [tipId] so that the point [grabLocal] (in the tip layer's own
  /// coordinates) reaches [target]. Empty when the chain has a single layer.
  Map<String, double> solveLayerIk(String tipId, Offset grabLocal, Offset target, {int length = 3}) {
    final chain = parentChain(tipId, length: length);
    if (chain.length < 2) return const {};
    final f = frame.toDouble();
    final bones = <Bone>[];
    for (var i = 0; i < chain.length; i++) {
      final l = chain[i];
      final head = layerPivot(l);
      final tail = i + 1 < chain.length ? layerPivot(chain[i + 1]) : comp.worldMatrix(l, f).apply(grabLocal);
      bones.add(Bone(id: l.id, parentId: i == 0 ? null : chain[i - 1].id, head: head, tail: tail));
    }
    final pose = solveIkChain(Skeleton(bones), Pose.rest, tipId, target, chainLength: chain.length);
    final out = <String, double>{};
    for (final l in chain) {
      final delta = pose.rot[l.id] ?? 0;
      if (delta == 0) continue;
      // a mirrored parent turns a world rotation into the opposite local one
      final parent = comp.layer(l.props.parentId);
      final flip = parent != null && comp.worldMatrix(parent, f).determinant < 0;
      out[l.id] = l.props.valueAt(Prop.rotation, f) + (flip ? -delta : delta);
    }
    return out;
  }

  /// Applies [solveLayerIk] as rotation changes (keys when the rotation is
  /// animated or auto-key is on). Calls sharing [mergeKey] form one undo step.
  /// Returns false when nothing could be solved.
  bool dragLayerIk(String tipId, Offset grabLocal, Offset target, {int length = 3, String? mergeKey}) {
    final rots = solveLayerIk(tipId, grabLocal, target, length: length);
    if (rots.isEmpty) return false;
    setLayersProps({for (final e in rots.entries) e.key: {Prop.rotation: e.value}}, mergeKey: mergeKey, label: tr('Cinemática inversa', 'Inverse kinematics'));
    return true;
  }

  /// Parents [layerId] to [parentId] (null = none) in one undo step, keeping
  /// the layer where it is on screen when its transform is not animated.
  /// Refuses cycles.
  void parentKeepingPlace(String layerId, String? parentId) {
    final l = comp.layer(layerId);
    if (l == null || parentId == layerId || l.props.parentId == parentId) return;
    var p = parentId;
    var guard = 0;
    while (p != null && guard++ < 64) {
      if (p == layerId) return;
      p = comp.layer(p)?.props.parentId;
    }
    final f = frame.toDouble();
    final animated = l.props.tracks.entries.any((e) => e.key != Prop.opacity && e.value.isNotEmpty);
    Xform? xf;
    if (!animated) {
      final world = comp.worldMatrix(l, f);
      final parent = comp.layer(parentId);
      final local = parent == null ? world : comp.worldMatrix(parent, f).inverse * world;
      final candidate = Xform.fromMatrix(local, ax: l.props.xf.ax, ay: l.props.xf.ay);
      if (_close(candidate.matrix, local)) xf = candidate;
    }
    updateProps(tr('Emparentar capa', 'Parent layer'), layerId, (props) => props.copyWith(parentId: parentId, xf: xf ?? props.xf));
  }
}

bool _close(Mat2D a, Mat2D b) =>
    (a.a - b.a).abs() < 1e-6 && (a.b - b.b).abs() < 1e-6 && (a.c - b.c).abs() < 1e-6 && (a.d - b.d).abs() < 1e-6 && (a.tx - b.tx).abs() < 1e-3 && (a.ty - b.ty).abs() < 1e-3;
