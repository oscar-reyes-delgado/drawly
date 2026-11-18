import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';
import '../core/mat2d.dart';

const _unchanged = Object();
Offset _offset(dynamic j) => Offset((j[0] as num).toDouble(), (j[1] as num).toDouble());

/// A bone in absolute rest-space coordinates.
class Bone {
  const Bone({required this.id, this.parentId, this.name = '', required this.head, required this.tail});
  final String id;
  final String? parentId;
  final String name;
  final Offset head, tail;
  double get length => (tail - head).distance;
  Bone copyWith({String? name, Offset? head, Offset? tail, Object? parentId = _unchanged}) => Bone(id: id, name: name ?? this.name, head: head ?? this.head, tail: tail ?? this.tail, parentId: identical(parentId, _unchanged) ? this.parentId : parentId as String?);
  Map<String, dynamic> toJson() => {'id': id, 'parentId': parentId, 'name': name, 'head': [head.dx, head.dy], 'tail': [tail.dx, tail.dy]};
  static Bone fromJson(dynamic j) => Bone(id: j['id'] as String, parentId: j['parentId'] as String?, name: j['name'] as String? ?? '', head: _offset(j['head']), tail: _offset(j['tail']));
}

/// Immutable parent-before-child skeleton.
class Skeleton {
  const Skeleton(this.bones);
  final List<Bone> bones;
  Bone? byId(String id) { for (final b in bones) { if (b.id == id) return b; } return null; }
  List<Bone> childrenOf(String id) => bones.where((b) => b.parentId == id).toList();
  /// Returns at most [length] bones in ancestor-to-tip order.
  List<Bone> chainTo(String tipId, int length) {
    final chain = <Bone>[], seen = <String>{};
    var b = byId(tipId);
    while (b != null && chain.length < length && seen.add(b.id)) { chain.add(b); b = b.parentId == null ? null : byId(b.parentId!); }
    return chain.reversed.toList();
  }
  Skeleton withBone(Bone b) {
    final map = {for (final bone in bones) bone.id: bone, b.id: b}, result = <Bone>[], visiting = <String>{}, done = <String>{};
    void visit(Bone bone) {
      if (done.contains(bone.id)) return;
      if (!visiting.add(bone.id)) throw ArgumentError('Cyclic bone hierarchy');
      final parent = map[bone.parentId]; if (parent != null) visit(parent);
      visiting.remove(bone.id); done.add(bone.id); result.add(bone);
    }
    for (final bone in map.values) { visit(bone); }
    return Skeleton(result);
  }
  Skeleton without(String id) {
    final removed = <String>{id};
    var changed = true;
    while (changed) { changed = false; for (final b in bones) { if (removed.contains(b.parentId) && removed.add(b.id)) changed = true; } }
    return Skeleton(bones.where((b) => !removed.contains(b.id)).toList());
  }
  List<dynamic> toJson() => bones.map((b) => b.toJson()).toList();
  static Skeleton fromJson(dynamic j) => Skeleton((j as List).map(Bone.fromJson).toList());
}

/// Local rotations in degrees and translations for each bone.
class Pose {
  const Pose({this.rot = const {}, this.move = const {}});
  static const Pose rest = Pose();
  final Map<String, double> rot;
  final Map<String, Offset> move;
  Pose withRot(String id, double degrees) => Pose(rot: {...rot, id: degrees}, move: move);
  Pose withMove(String id, Offset delta) => Pose(rot: rot, move: {...move, id: delta});
  static Pose lerp(Pose a, Pose b, double t) => Pose(
    rot: {for (final id in {...a.rot.keys, ...b.rot.keys}) id: ((a.rot[id] ?? 0) + (((b.rot[id] ?? 0) - (a.rot[id] ?? 0) + 180) % 360 - 180) * t) % 360},
    move: {for (final id in {...a.move.keys, ...b.move.keys}) id: Offset.lerp(a.move[id] ?? Offset.zero, b.move[id] ?? Offset.zero, t)!},
  );
  Map<String, dynamic> toJson() => {'rot': rot, 'move': {for (final e in move.entries) e.key: [e.value.dx, e.value.dy]}};
  static Pose fromJson(dynamic j) => Pose(rot: (j['rot'] as Map? ?? {}).map((k, v) => MapEntry(k as String, (v as num).toDouble())), move: (j['move'] as Map? ?? {}).map((k, v) => MapEntry(k as String, _offset(v))));
}

/// Builds rest-to-posed matrices for all bones.
Map<String, Mat2D> solveFk(Skeleton s, Pose p) {
  final result = <String, Mat2D>{};
  for (final b in s.bones) {
    final move = p.move[b.id] ?? Offset.zero;
    result[b.id] = (result[b.parentId] ?? Mat2D.identity) * Mat2D.trs(x: move.dx, y: move.dy, rotation: degToRad(p.rot[b.id] ?? 0), ax: b.head.dx, ay: b.head.dy);
  }
  return result;
}
/// Posed head of a bone.
Offset posedHead(Skeleton s, Map<String, Mat2D> fk, String id) => (fk[id] ?? Mat2D.identity).apply(s.byId(id)!.head);
/// Posed tail of a bone.
Offset posedTail(Skeleton s, Map<String, Mat2D> fk, String id) => (fk[id] ?? Mat2D.identity).apply(s.byId(id)!.tail);
double _angle(Offset p) => math.atan2(p.dy, p.dx);

/// Analytic IK for a connected two-bone chain, clamped to its reachable annulus.
Pose solveIk2(Skeleton s, Pose p, String lowerId, Offset target, {bool bendPositive = true}) {
  final lower = s.byId(lowerId), upper = lower?.parentId == null ? null : s.byId(lower!.parentId!);
  if (lower == null || upper == null || upper.length < 1e-9 || lower.length < 1e-9) return p;
  final fk = solveFk(s, p), root = posedHead(s, fk, upper.id), delta = target - root;
  final l1 = upper.length, l2 = lower.length, d = delta.distance.clamp((l1 - l2).abs(), l1 + l2);
  final phi = delta.distance < 1e-9 ? _angle(posedTail(s, fk, upper.id) - root) : _angle(delta);
  final alpha = d < 1e-9 ? math.pi / 2 : math.acos(((l1 * l1 + d * d - l2 * l2) / (2 * l1 * d)).clamp(-1, 1));
  final theta = phi + (bendPositive ? alpha : -alpha);
  var pose = p.withRot(upper.id, (p.rot[upper.id] ?? 0) + radToDeg(theta - _angle(posedTail(s, fk, upper.id) - root)));
  final updated = solveFk(s, pose), head = posedHead(s, updated, lowerId), goal = root + Offset(math.cos(phi), math.sin(phi)) * d;
  pose = pose.withRot(lowerId, (p.rot[lowerId] ?? 0) + radToDeg(_angle(goal - head) - _angle(posedTail(s, updated, lowerId) - head)));
  return pose;
}

/// Cyclic coordinate descent, modifying only the requested terminal chain.
Pose solveIkChain(Skeleton s, Pose p, String tipId, Offset target, {int chainLength = 3, int iterations = 24, double tolerance = 0.25}) {
  final chain = s.chainTo(tipId, chainLength);
  if (chain.isEmpty) return p;
  var pose = p;
  for (var pass = 0; pass < iterations; pass++) {
    for (final bone in chain.reversed) {
      final fk = solveFk(s, pose), tip = posedTail(s, fk, tipId), head = posedHead(s, fk, bone.id);
      if ((tip - target).distance <= tolerance) return pose;
      if ((tip - head).distance < 1e-9 || (target - head).distance < 1e-9) continue;
      pose = pose.withRot(bone.id, (pose.rot[bone.id] ?? 0) + radToDeg(_angle(target - head) - _angle(tip - head)));
    }
  }
  return pose;
}

/// Row-major point-by-bone influence weights.
class SkinWeights {
  const SkinWeights(this.boneIds, this.weights);
  final List<String> boneIds;
  final Float32List weights;
}
/// Inverse-distance weights to bone segments, normalized per point.
SkinWeights autoWeights(List<Offset> points, Skeleton s, {double falloff = 2}) {
  if (falloff < 0) throw ArgumentError.value(falloff, 'falloff');
  final weights = Float32List(points.length * s.bones.length);
  for (var i = 0; i < points.length; i++) {
    final values = <double>[];
    for (final b in s.bones) {
      final v = b.tail - b.head, d = points[i] - b.head;
      final t = v.distanceSquared == 0 ? 0.0 : ((d.dx * v.dx + d.dy * v.dy) / v.distanceSquared).clamp(0.0, 1.0);
      values.add(1 / math.pow(math.max(1e-6, (points[i] - b.head - v * t).distance), falloff));
    }
    final sum = values.fold<double>(0, (s, v) => s + v);
    for (var j = 0; j < values.length; j++) { weights[i * values.length + j] = values[j] / sum; }
  }
  return SkinWeights(s.bones.map((b) => b.id).toList(), weights);
}
/// Applies linear blend skinning; absent bone matrices use the identity.
List<Offset> skinPoints(List<Offset> points, SkinWeights w, Map<String, Mat2D> fk) {
  if (w.weights.length != points.length * w.boneIds.length) throw ArgumentError('Invalid skin weights');
  return List.generate(points.length, (i) {
    if (w.boneIds.isEmpty) return points[i];
    var p = Offset.zero;
    for (var j = 0; j < w.boneIds.length; j++) { p += (fk[w.boneIds[j]] ?? Mat2D.identity).apply(points[i]) * w.weights[i * w.boneIds.length + j]; }
    return p;
  });
}
