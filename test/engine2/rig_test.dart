import 'package:drawly/engine/rig.dart';
import 'package:flutter_test/flutter_test.dart';

const skeleton = Skeleton([Bone(id: 'a', head: Offset.zero, tail: Offset(100, 0)), Bone(id: 'b', parentId: 'a', head: Offset(100, 0), tail: Offset(200, 0))]);
void near(Offset a, Offset b, [double e = 1e-6]) => expect((a - b).distance, lessThanOrEqualTo(e));
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('FK rest, root rotation, child rotation and translation', () {
    expect(solveFk(skeleton, Pose.rest).values.every((m) => m.isIdentity), isTrue);
    near(posedTail(skeleton, solveFk(skeleton, Pose.rest.withRot('a', 90)), 'b'), const Offset(0, 200));
    near(posedTail(skeleton, solveFk(skeleton, Pose.rest.withRot('b', 90)), 'b'), const Offset(100, 100));
    near(posedTail(skeleton, solveFk(skeleton, Pose.rest.withMove('a', const Offset(10, 5))), 'b'), const Offset(210, 5));
  });
  test('analytic IK reachable, unreachable, folded and opposite bends', () {
    for (final target in [const Offset(120, 80), const Offset(500, 0), Offset.zero]) {
      final p = solveIk2(skeleton, Pose.rest, 'b', target);
      near(posedTail(skeleton, solveFk(skeleton, p), 'b'), target.dx == 500 ? const Offset(200, 0) : target, 0.01);
    }
    final a = solveFk(skeleton, solveIk2(skeleton, Pose.rest, 'b', const Offset(120, 0))), b = solveFk(skeleton, solveIk2(skeleton, Pose.rest, 'b', const Offset(120, 0), bendPositive: false));
    expect(posedTail(skeleton, a, 'a').dy * posedTail(skeleton, b, 'a').dy, lessThan(0));
  });
  test('CCD reaches target without rotating bones outside chain', () {
    final s = skeleton.withBone(const Bone(id: 'c', parentId: 'b', head: Offset(200, 0), tail: Offset(300, 0))).withBone(const Bone(id: 'd', parentId: 'c', head: Offset(300, 0), tail: Offset(400, 0)));
    final pose = Pose.rest.withRot('a', 10), solved = solveIkChain(s, pose, 'd', const Offset(200, 120));
    expect(solved.rot['a'], 10); near(posedTail(s, solveFk(s, solved), 'd'), const Offset(200, 120), 0.25);
  });
  test('shortest arc and JSON round trips', () {
    expect(Pose.lerp(Pose.rest.withRot('a', 350), Pose.rest.withRot('a', 10), 0.5).rot['a'], 0);
    final pose = Pose.rest.withRot('b', 42).withMove('a', const Offset(5, 3));
    expect(Pose.fromJson(pose.toJson()).toJson(), pose.toJson()); expect(Skeleton.fromJson(skeleton.toJson()).toJson(), skeleton.toJson());
    expect(skeleton.bones.last.copyWith(parentId: null).parentId, isNull);
  });
  test('hierarchy ordering, removal and chain', () {
    expect(skeleton.chainTo('b', 2).map((b) => b.id), ['a', 'b']); expect(skeleton.without('a').bones, isEmpty);
    final s = Skeleton([skeleton.bones.last]).withBone(skeleton.bones.first); expect(s.bones.map((b) => b.id), ['a', 'b']);
    expect(() => skeleton.withBone(skeleton.bones.first.copyWith(parentId: 'b')), throwsArgumentError);
  });
  test('weights normalize and skinning follows root rotation', () {
    const points = [Offset(50, 0), Offset(150, 0), Offset(100, 30)];
    final weights = autoWeights(points, skeleton); expect(weights.weights[0], greaterThan(0.9)); expect(weights.weights[3], greaterThan(0.9));
    for (var i = 0; i < 3; i++) { expect(weights.weights[i * 2] + weights.weights[i * 2 + 1], closeTo(1, 1e-5)); }
    final rest = skinPoints(points, weights, solveFk(skeleton, Pose.rest)), turned = skinPoints(points, weights, solveFk(skeleton, Pose.rest.withRot('a', 90)));
    for (var i = 0; i < 3; i++) { near(rest[i], points[i], 1e-5); near(turned[i], Offset(-points[i].dy, points[i].dx), 1e-5); }
  });
}
