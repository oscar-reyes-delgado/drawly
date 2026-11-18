import 'dart:ui' show Rect;
import 'package:drawly/engine/physics.dart';
import 'package:flutter_test/flutter_test.dart';

void _expectOffset(Offset actual, Offset expected) {
  expect(actual.dx, closeTo(expected.dx, 1e-9));
  expect(actual.dy, closeTo(expected.dy, 1e-9));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('free fall follows discrete acceleration', () {
    final b = PhysBody(Offset.zero, friction: 0), world = PhysWorld(bodies: [b]);
    for (var n = 1; n <= 100; n++) { world.step(); expect(b.pos.dy, closeTo(0.5 * n * (n + 1) / 2, 1e-8)); }
  });
  test('friction damps initial velocity before gravity is applied', () {
    final b = PhysBody(const Offset(10, 20), friction: 0.25)..prev = const Offset(6, 22);
    final world = PhysWorld(gravity: const Offset(1, 2), bodies: [b]);
    world.step();
    _expectOffset(b.pos, const Offset(14, 20.5));
    _expectOffset(b.prev, const Offset(10, 20));
    _expectOffset(b.velocity, const Offset(4, 0.5));
  });
  test('floor contains ball and successive bounce heights decrease', () {
    final b = PhysBody(const Offset(50, 10), radius: 5, bounce: 0.7, friction: 0), world = PhysWorld(bounds: const Rect.fromLTWH(0, 0, 100, 100), bodies: [b]);
    final peaks = <double>[];
    var previousVelocity = 0.0;
    for (var i = 0; i < 180; i++) {
      world.step(); expect(b.pos.dy, lessThanOrEqualTo(95.01));
      if (previousVelocity < 0 && b.velocity.dy >= 0 && 95 - b.pos.dy > 1) peaks.add(95 - b.pos.dy);
      previousVelocity = b.velocity.dy;
    }
    expect(peaks.length, greaterThanOrEqualTo(3)); for (var i = 1; i < peaks.length; i++) { expect(peaks[i], lessThan(peaks[i - 1])); }
  });
  test('static body stays fixed and blocks a falling body', () {
    final fixed = PhysBody(const Offset(0, 50), mass: 0, radius: 10), falling = PhysBody(Offset.zero, radius: 5), world = PhysWorld(bodies: [fixed, falling]);
    for (var i = 0; i < 100; i++) { world.step(); expect(fixed.pos, const Offset(0, 50)); expect(falling.pos.dy, lessThanOrEqualTo(35.001)); }
  });
  test('static bodies ignore velocity, links, overlaps and wall constraints', () {
    final a = PhysBody(const Offset(0, 50), mass: 0, radius: 10)..prev = const Offset(-20, 20);
    final b = PhysBody(const Offset(0, 50), mass: 0, radius: 5);
    final moving = PhysBody(const Offset(30, 50), radius: 1);
    final world = PhysWorld(
      bounds: const Rect.fromLTWH(0, 0, 100, 100),
      bodies: [a, b, moving],
      links: [PhysLink(0, 1, 20), PhysLink(0, 2, 30)],
    );
    for (var i = 0; i < 100; i++) {
      world.step();
      expect(a.pos, const Offset(0, 50));
      expect(a.prev, const Offset(-20, 20));
      expect(b.pos, const Offset(0, 50));
      expect(b.prev, const Offset(0, 50));
    }
  });
  test('each wall reflects only the normal velocity with restitution', () {
    void check(Offset position, Offset velocity, Offset expectedPosition, Offset expectedVelocity) {
      final b = PhysBody(position, radius: 5, bounce: 0.5, friction: 0)..prev = position - velocity;
      final world = PhysWorld(gravity: Offset.zero, bounds: const Rect.fromLTWH(0, 0, 100, 100), bodies: [b]);
      world.step();
      _expectOffset(b.pos, expectedPosition);
      _expectOffset(b.velocity, expectedVelocity);
    }

    check(const Offset(6, 50), const Offset(-4, 2), const Offset(5, 52), const Offset(2, 2));
    check(const Offset(94, 50), const Offset(4, 2), const Offset(95, 52), const Offset(-2, 2));
    check(const Offset(50, 6), const Offset(2, -4), const Offset(52, 5), const Offset(2, 2));
    check(const Offset(50, 94), const Offset(2, 4), const Offset(52, 95), const Offset(2, -2));
    check(const Offset(6, 6), const Offset(-4, -6), const Offset(5, 5), const Offset(2, 3));
  });
  test('rigid link keeps its length under gravity', () {
    final a = PhysBody(Offset.zero, mass: 0, radius: 1), b = PhysBody(const Offset(30, 0), radius: 1), world = PhysWorld(bodies: [a, b], links: [PhysLink(0, 1, 30)]);
    for (var i = 0; i < 60; i++) { world.step(); expect((b.pos - a.pos).distance, closeTo(30, 0.3)); }
  });
  test('link correction respects stiffness and inverse mass', () {
    final a = PhysBody(Offset.zero, mass: 1), b = PhysBody(const Offset(40, 0), mass: 3);
    final world = PhysWorld(gravity: Offset.zero, bodies: [a, b], links: [PhysLink(0, 1, 20, stiffness: 0.5)])..collide = false;
    world.step(iterations: 1);
    expect((b.pos - a.pos).distance, closeTo(30, 1e-9));
    _expectOffset(a.pos, const Offset(7.5, 0));
    _expectOffset(b.pos, const Offset(37.5, 0));
    _expectOffset((a.pos * a.mass + b.pos * b.mass) / (a.mass + b.mass), const Offset(30, 0));
  });
  test('zero-stiffness link leaves freely falling bodies unconstrained', () {
    final a = PhysBody(Offset.zero, friction: 0), b = PhysBody(const Offset(40, 0), friction: 0);
    final world = PhysWorld(bodies: [a, b], links: [PhysLink(0, 1, 20, stiffness: 0)]);
    for (var i = 0; i < 60; i++) { world.step(); }
    _expectOffset(b.pos - a.pos, const Offset(40, 0));
    expect(a.pos.dy, greaterThan(0));
  });
  test('soft body has the full grid and all structural and diagonal links', () {
    final world = softBody(const Rect.fromLTWH(10, 20, 60, 40), columns: 4, rows: 3, stiffness: 0.35, radius: 2.5);
    expect(world.bodies.length, 12);
    expect(world.links.length, 29);
    expect(world.bodies.map((b) => b.pos).toList(), const [
      Offset(10, 20), Offset(30, 20), Offset(50, 20), Offset(70, 20),
      Offset(10, 40), Offset(30, 40), Offset(50, 40), Offset(70, 40),
      Offset(10, 60), Offset(30, 60), Offset(50, 60), Offset(70, 60),
    ]);
    expect(world.bodies.every((b) => b.radius == 2.5), isTrue);
    final pairs = <(int, int)>{};
    final directions = <Offset, int>{};
    for (final link in world.links) {
      expect(link.a, inInclusiveRange(0, 11));
      expect(link.b, inInclusiveRange(0, 11));
      expect(link.a, isNot(link.b));
      pairs.add(link.a < link.b ? (link.a, link.b) : (link.b, link.a));
      var delta = world.bodies[link.b].pos - world.bodies[link.a].pos;
      expect(link.length, closeTo(delta.distance, 1e-9));
      expect(link.stiffness, 0.35);
      if (delta.dy < 0 || (delta.dy == 0 && delta.dx < 0)) delta = -delta;
      directions.update(delta, (count) => count + 1, ifAbsent: () => 1);
    }
    expect(pairs.length, 29);
    expect(directions, {const Offset(20, 0): 9, const Offset(0, 20): 8, const Offset(20, 20): 6, const Offset(-20, 20): 6});
  });
  test('simulate preserves every initial position and bakes deterministically', () {
    PhysWorld make() {
      final world = softBody(const Rect.fromLTWH(10, 20, 60, 40), columns: 4, rows: 3);
      world.bounds = const Rect.fromLTWH(0, 0, 100, 100);
      world.bodies.first.mass = 0;
      world.bodies[1].prev -= const Offset(1, -1);
      return world;
    }

    final world = make(), initial = world.bodies.map((b) => b.pos).toList();
    final a = simulate(world, 12), b = simulate(make(), 12);
    expect(a, b);
    expect(a.length, 12);
    expect(a.every((p) => p.length == 12), isTrue);
    expect(a.first, initial);
    final last = List<Offset>.of(a.last);
    world.step();
    expect(a.first, initial);
    expect(a.last, last);
  });
  test('simulate advances the requested number of substeps between frames', () {
    final b = PhysBody(const Offset(3, 7), friction: 0)..prev = const Offset(2, 9);
    final world = PhysWorld(gravity: const Offset(0, 2), bodies: [b]);
    expect(simulate(world, 3, substeps: 3), const [
      [Offset(3, 7)], [Offset(6, 13)], [Offset(9, 37)],
    ]);
    expect(b.pos, const Offset(9, 37));

    final defaults = PhysWorld(bodies: [PhysBody(Offset.zero, friction: 0)]);
    expect(simulate(defaults, 3), const [
      [Offset.zero], [Offset(0, 1.5)], [Offset(0, 5)],
    ]);
  });
  test('zero or one frame does not advance and empty worlds keep frame count', () {
    final b = PhysBody(const Offset(3, 7))..prev = const Offset(2, 9);
    final world = PhysWorld(bodies: [b]);
    expect(simulate(world, 0), isEmpty);
    expect(simulate(world, 1), const [[Offset(3, 7)]]);
    expect(b.pos, const Offset(3, 7));
    expect(b.prev, const Offset(2, 9));
    expect(simulate(PhysWorld(), 3), [isEmpty, isEmpty, isEmpty]);
  });
  test('coincident bodies separate and collision toggle is honored', () {
    final a = PhysBody(Offset.zero), b = PhysBody(Offset.zero), world = PhysWorld(gravity: Offset.zero, bodies: [a, b]);
    world.step(); expect((a.pos - b.pos).distance, greaterThanOrEqualTo(15.5));
    final off = PhysWorld(gravity: Offset.zero, bodies: [PhysBody(Offset.zero), PhysBody(Offset.zero)])..collide = false;
    off.step(); expect(off.bodies.first.pos, off.bodies.last.pos);
  });
  test('overlap correction preserves the center of mass for unequal bodies', () {
    final a = PhysBody(Offset.zero, mass: 1, radius: 10), b = PhysBody(const Offset(12, 0), mass: 3, radius: 6);
    final world = PhysWorld(gravity: Offset.zero, bodies: [a, b]);
    world.step();
    expect((b.pos - a.pos).distance, closeTo(a.radius + b.radius, 1e-9));
    _expectOffset(a.pos, const Offset(-3, 0));
    _expectOffset(b.pos, const Offset(13, 0));
    _expectOffset((a.pos * a.mass + b.pos * b.mass) / (a.mass + b.mass), const Offset(9, 0));
    _expectOffset(a.velocity, Offset.zero);
    _expectOffset(b.velocity, Offset.zero);
  });
}
