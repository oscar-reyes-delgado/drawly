import 'dart:ui';

import '../core/i18n.dart';
import '../core/ids.dart';
import '../engine/rig.dart';
import '../engine/rig_deform.dart';
import '../model/anim.dart';
import '../model/layer.dart';
import 'document_controller.dart';

/// Bones that deform the pixels of a paint layer ([PaintLayer.rig]).
/// Every point is in the layer's own coordinates (see [layerMatrix]).
extension DocBones on DocumentController {
  PaintLayer? _paint(String layerId) {
    final l = comp.layer(layerId);
    return l is PaintLayer ? l : null;
  }

  void _setRig(String label, String layerId, LayerRig Function(LayerRig r) f, {String? mergeKey}) {
    updateLayer(label, layerId, (l) => l is PaintLayer ? l.withRig(f(l.rig ?? LayerRig.empty)) : l, mergeKey: mergeKey);
  }

  /// Adds a bone from [head] to [tail] to a paint layer; returns its id, or
  /// null when the layer is not a paint layer or the bone has no length.
  String? addBone(String layerId, Offset head, Offset tail, {String? parentId, String name = ''}) {
    final l = _paint(layerId);
    if (l == null || (tail - head).distance < 1) return null;
    final id = newId('B');
    final rig = l.rig ?? LayerRig.empty;
    final parent = parentId != null && rig.skeleton.byId(parentId) != null ? parentId : null;
    _setRig(tr('Añadir hueso', 'Add bone'), layerId, (r) => r.withBone(Bone(id: id, parentId: parent, name: name, head: head, tail: tail)));
    return id;
  }

  /// Removes a bone and its descendants.
  void removeBone(String layerId, String boneId) => _setRig(tr('Eliminar hueso', 'Delete bone'), layerId, (r) => r.withoutBone(boneId));

  /// Removes every bone of the layer.
  void clearBones(String layerId) => updateLayer(tr('Quitar huesos', 'Remove bones'), layerId, (l) => l is PaintLayer ? l.withRig(null) : l);

  /// Rotation of a bone at the current frame (degrees from the rest pose).
  double boneRot(String layerId, String boneId) => _paint(layerId)?.rig?.rotAt(boneId, frame.toDouble()) ?? 0;

  /// Sets bone rotations (degrees from rest) as keys at the current frame.
  /// Calls sharing [mergeKey] form one undo step.
  void setBoneRots(String layerId, Map<String, double> degrees, {String? mergeKey}) {
    if (degrees.isEmpty) return;
    _setRig(tr('Posar huesos', 'Pose bones'), layerId, (r) {
      var out = r;
      degrees.forEach((id, v) {
        final t = out.rot[id] ?? AnimTrack.none;
        final ease = t.keyAt(frame)?.ease ?? Ease.smooth;
        out = out.withRotTrack(id, t.withKey(AnimKey(frame, v, ease)));
      });
      return out;
    }, mergeKey: mergeKey);
  }

  /// Removes the key of a bone at the current frame.
  void removeBoneKey(String layerId, String boneId) =>
      _setRig(tr('Quitar clave de hueso', 'Remove bone key'), layerId, (r) => r.withRotTrack(boneId, (r.rot[boneId] ?? AnimTrack.none).withoutKey(frame)));

  /// Poses the chain ending at [boneId] (at most [chainLength] bones) so its
  /// tail reaches [target]; writes keys. Returns false when nothing changed.
  bool poseBonesIk(String layerId, String boneId, Offset target, {int chainLength = 2, String? mergeKey}) {
    final rig = _paint(layerId)?.rig;
    if (rig == null || rig.skeleton.byId(boneId) == null) return false;
    final pose = rig.poseAt(frame.toDouble());
    final solved = solveIkChain(rig.skeleton, pose, boneId, target, chainLength: chainLength);
    final changed = {
      for (final e in solved.rot.entries)
        if ((e.value - (pose.rot[e.key] ?? 0)).abs() > 1e-6) e.key: e.value,
    };
    setBoneRots(layerId, changed, mergeKey: mergeKey);
    return changed.isNotEmpty;
  }

  /// Bones of a layer posed at the current frame: id → (head, tail).
  Map<String, (Offset, Offset)> posedBonesOf(String layerId) {
    final rig = _paint(layerId)?.rig;
    return rig == null ? const {} : posedBones(rig, frame.toDouble());
  }
}
