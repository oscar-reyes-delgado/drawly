import 'dart:ui';

import '../core/mat2d.dart';
import '../engine/rig.dart';
import 'anim.dart';

/// Bones that deform the pixels of a paint layer.
///
/// The skeleton is the rest pose in the layer's own coordinates (the space of
/// its drawings). Each bone may have a rotation track (degrees around its head,
/// relative to the rest pose), animated with ordinary keys.
class LayerRig {
  const LayerRig({this.skeleton = const Skeleton([]), this.rot = const {}, this.falloff = 2, this.cell = 16});

  static const LayerRig empty = LayerRig();

  final Skeleton skeleton;
  final Map<String, AnimTrack> rot;

  /// Inverse-distance exponent of the automatic skin weights.
  final double falloff;

  /// Deformation mesh cell size in pixels.
  final double cell;

  bool get isEmpty => skeleton.bones.isEmpty;

  /// Rotation of [boneId] at [frame] (0 when not animated).
  double rotAt(String boneId, double frame) {
    return rot[boneId]?.valueAt(frame) ?? 0;
  }

  Pose poseAt(double frame) => Pose(rot: {for (final b in skeleton.bones) b.id: rotAt(b.id, frame)});

  /// True when every bone is at rest at [frame] (nothing to deform).
  bool isRestAt(double frame) => skeleton.bones.every((b) => rotAt(b.id, frame).abs() < 1e-9);

  LayerRig copyWith({Skeleton? skeleton, Map<String, AnimTrack>? rot, double? falloff, double? cell}) =>
      LayerRig(skeleton: skeleton ?? this.skeleton, rot: rot ?? this.rot, falloff: falloff ?? this.falloff, cell: cell ?? this.cell);

  /// Adds or replaces a bone (parents stay before children).
  LayerRig withBone(Bone b) => copyWith(skeleton: skeleton.withBone(b));

  /// Removes a bone, its descendants and their tracks.
  LayerRig withoutBone(String id) {
    final s = skeleton.without(id);
    final keep = {for (final b in s.bones) b.id};
    return copyWith(skeleton: s, rot: {for (final e in rot.entries) if (keep.contains(e.key)) e.key: e.value});
  }

  /// Rotation track of a bone replaced ([AnimTrack.none] removes it).
  LayerRig withRotTrack(String boneId, AnimTrack t) => copyWith(rot: {...rot, boneId: t}..removeWhere((_, v) => v.isEmpty));

  /// The rest skeleton mapped by [m] (when the layer pixels are transformed).
  LayerRig transformed(Mat2D m) => copyWith(skeleton: Skeleton([for (final b in skeleton.bones) b.copyWith(head: m.apply(b.head), tail: m.apply(b.tail))]));

  /// Keys moved when frames are inserted or removed (see [AnimTrack.shifted]).
  LayerRig shifted(int at, int delta) => copyWith(rot: {for (final e in rot.entries) e.key: e.value.shifted(at, delta)}..removeWhere((_, v) => v.isEmpty));

  Map<String, dynamic> toJson() => {
        'bones': skeleton.toJson(),
        'rot': tracksToJsonByName(rot),
        'falloff': falloff,
        'cell': cell,
      };

  static LayerRig? fromJson(dynamic j) {
    if (j is! Map) return null;
    return LayerRig(
      skeleton: j['bones'] == null ? const Skeleton([]) : Skeleton.fromJson(j['bones']),
      rot: tracksFromJsonByName(j['rot']),
      falloff: (j['falloff'] as num?)?.toDouble() ?? 2,
      cell: (j['cell'] as num?)?.toDouble() ?? 16,
    );
  }
}

Map<String, dynamic> tracksToJsonByName(Map<String, AnimTrack> m) => {for (final e in m.entries) e.key: e.value.toJson()};

Map<String, AnimTrack> tracksFromJsonByName(dynamic j) {
  if (j is! Map) return const {};
  final out = <String, AnimTrack>{};
  j.forEach((k, v) {
    final t = AnimTrack.fromJson(v);
    if (t.isNotEmpty) out[k.toString()] = t;
  });
  return out;
}

/// Point helper used by the bone tool: distance from [p] to segment [a]-[b].
double distanceToSegment(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
  if (len2 == 0) return (p - a).distance;
  final t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len2).clamp(0.0, 1.0);
  return (p - (a + ab * t)).distance;
}
