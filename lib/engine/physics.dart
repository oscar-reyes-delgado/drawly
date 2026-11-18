import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

/// A Verlet particle; zero mass makes it immovable.
class PhysBody {
  PhysBody(this.pos, {this.radius = 8, this.mass = 1, this.bounce = 0.4, this.friction = 0.02}) : prev = pos;
  Offset pos, prev;
  double radius, mass, bounce, friction;

  /// Displacement during the preceding step, in pixels per step.
  Offset get velocity => pos - prev;
}

/// Distance constraint between two body indices.
class PhysLink {
  PhysLink(this.a, this.b, this.length, {this.stiffness = 1});
  final int a, b;
  final double length, stiffness;
}
double _inverse(PhysBody b) => b.mass == 0 ? 0 : 1 / b.mass;
double _dot(Offset a, Offset b) => a.dx * b.dx + a.dy * b.dy;

/// Deterministic Verlet world with iterative distance and collision constraints.
class PhysWorld {
  PhysWorld({this.gravity = const Offset(0, 0.5), this.bounds, List<PhysBody>? bodies, List<PhysLink>? links}) : bodies = List.of(bodies ?? []), links = List.of(links ?? []);

  /// Acceleration in pixels per step squared, independent of body mass.
  Offset gravity;

  /// Walls for dynamic bodies; null leaves the world unbounded.
  Rect? bounds;
  final List<PhysBody> bodies;
  final List<PhysLink> links;

  /// Whether circle collisions are resolved in addition to links and walls.
  bool collide = true;

  /// Advances one Verlet step, then performs [iterations] constraint passes.
  /// Bodies with zero mass keep both their position and previous position.
  void step({int iterations = 8}) {
    if (iterations < 1) throw ArgumentError.value(iterations, 'iterations');
    for (final b in bodies) {
      if (b.mass < 0 || b.radius < 0) throw ArgumentError('Negative mass or radius');
      if (b.mass == 0) continue;
      final next = b.pos + b.velocity * (1 - b.friction.clamp(0, 1)) + gravity;
      b.prev = b.pos; b.pos = next;
    }
    for (var pass = 0; pass < iterations; pass++) {
      for (final link in links) {
        final a = bodies[link.a], b = bodies[link.b], ia = _inverse(a), ib = _inverse(b), sum = ia + ib;
        if (sum == 0) continue;
        final delta = b.pos - a.pos, distance = delta.distance, normal = distance < 1e-12 ? const Offset(1, 0) : delta / distance;
        final correction = normal * ((distance - link.length) * link.stiffness.clamp(0, 1) / sum);
        if (ia > 0) a.pos += correction * ia;
        if (ib > 0) b.pos -= correction * ib;
      }
      if (collide) {
        for (var i = 0; i < bodies.length; i++) {
          for (var j = i + 1; j < bodies.length; j++) { _collision(bodies[i], bodies[j]); }
        }
      }
      final rect = bounds;
      if (rect != null) { for (final b in bodies) { if (b.mass > 0) _walls(b, rect); } }
    }
  }
  void _collision(PhysBody a, PhysBody b) {
    final ia = _inverse(a), ib = _inverse(b), sum = ia + ib;
    if (sum == 0) return;
    final delta = b.pos - a.pos, distance = delta.distance, overlap = a.radius + b.radius - distance;
    if (overlap <= 0) return;
    final normal = distance < 1e-12 ? const Offset(1, 0) : delta / distance;
    var va = a.mass == 0 ? Offset.zero : a.velocity, vb = b.mass == 0 ? Offset.zero : b.velocity;
    if (ia > 0) a.pos -= normal * (overlap * ia / sum);
    if (ib > 0) b.pos += normal * (overlap * ib / sum);
    final closing = _dot(vb - va, normal);
    if (closing < 0) {
      final impulse = -(1 + math.min(a.bounce, b.bounce).clamp(0, 1)) * closing / sum;
      va -= normal * (impulse * ia); vb += normal * (impulse * ib);
    }
    if (ia > 0) a.prev = a.pos - va;
    if (ib > 0) b.prev = b.pos - vb;
  }
  void _walls(PhysBody b, Rect rect) {
    var x = b.pos.dx, y = b.pos.dy, vx = b.velocity.dx, vy = b.velocity.dy;
    final left = rect.left + b.radius, right = rect.right - b.radius, top = rect.top + b.radius, bottom = rect.bottom - b.radius;
    final bounce = b.bounce.clamp(0, 1);
    if (left > right) { x = rect.center.dx; vx = 0; }
    else if (x < left) { x = left; if (vx < 0) vx = -vx * bounce; }
    else if (x > right) { x = right; if (vx > 0) vx = -vx * bounce; }
    if (top > bottom) { y = rect.center.dy; vy = 0; }
    else if (y < top) { y = top; if (vy < 0) vy = -vy * bounce; }
    else if (y > bottom) { y = bottom; if (vy > 0) vy = -vy * bounce; }
    b.pos = Offset(x, y); b.prev = b.pos - Offset(vx, vy);
  }
}

/// Builds a grid joined horizontally, vertically and across both cell diagonals.
PhysWorld softBody(Rect r, {int columns = 4, int rows = 4, double stiffness = 0.6, double radius = 4}) {
  if (columns < 1 || rows < 1) throw ArgumentError('Invalid soft body dimensions');
  final bodies = [for (var y = 0; y < rows; y++) for (var x = 0; x < columns; x++) PhysBody(Offset(columns == 1 ? r.center.dx : r.left + x * r.width / (columns - 1), rows == 1 ? r.center.dy : r.top + y * r.height / (rows - 1)), radius: radius)];
  final links = <PhysLink>[];
  void link(int a, int b) => links.add(PhysLink(a, b, (bodies[a].pos - bodies[b].pos).distance, stiffness: stiffness));
  for (var y = 0; y < rows; y++) {
    for (var x = 0; x < columns; x++) {
      final i = y * columns + x;
      if (x + 1 < columns) link(i, i + 1);
      if (y + 1 < rows) link(i, i + columns);
      if (x + 1 < columns && y + 1 < rows) { link(i, i + columns + 1); link(i + 1, i + columns); }
    }
  }
  return PhysWorld(bodies: bodies, links: links);
}

/// Bakes [frames] independent position lists, with the initial state at frame 0.
/// Advances [world] by [substeps] steps between frames, leaving it at the last
/// frame. Zero frames returns an empty list without advancing the world.
List<List<Offset>> simulate(PhysWorld world, int frames, {int substeps = 2}) {
  if (frames < 0 || substeps < 1) throw ArgumentError('Invalid simulation duration');
  final result = <List<Offset>>[];
  for (var f = 0; f < frames; f++) {
    if (f > 0) { for (var i = 0; i < substeps; i++) { world.step(); } }
    result.add(world.bodies.map((b) => b.pos).toList());
  }
  return result;
}
