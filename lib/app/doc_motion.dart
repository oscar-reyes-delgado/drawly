import 'dart:math' as math;
import 'dart:ui';

import '../core/i18n.dart';
import '../engine/compositor.dart';
import '../engine/physics.dart';
import '../model/anim.dart';
import 'document_controller.dart';

/// Procedural motion baked into ordinary keyframes.
extension DocMotion on DocumentController {
  /// Drops the active layer from where it is at the current frame: it falls
  /// under [gravity] (px per frame²), bounces on the bottom of the canvas
  /// losing energy ([bounce] 0..1) and its path is written as one linear X/Y
  /// key per frame, from the current frame to the end of the timeline (at
  /// most [frames]). Existing X/Y keys in that range are replaced.
  /// Returns the number of frames written (0 when the layer is empty).
  Future<int> bakeBounce({int frames = 48, double gravity = 0.8, double bounce = 0.6, Offset velocity = Offset.zero}) async {
    final l = activeLayer;
    if (l == null) return 0;
    final start = frame;
    final n = math.min(frames, timeline.length - start);
    if (n < 2) return 0;
    final box = await rasterizeLayer(project, comp, l, start.toDouble()).contentBounds();
    if (box == null || box.isEmpty) return 0;

    // the content is a circle of its half height; only the floor matters
    final r = box.height / 2;
    final body = PhysBody(box.center, radius: r, bounce: bounce.clamp(0.0, 1.0), friction: 0.01);
    body.prev = box.center - velocity;
    final world = PhysWorld(gravity: Offset(0, gravity), bounds: Rect.fromLTRB(-1e9, -1e9, 1e9, comp.height.toDouble()), bodies: [body])..collide = false;
    final path = simulate(world, n, substeps: 1);

    final props = l.props;
    final x0 = props.valueAt(Prop.x, start.toDouble()), y0 = props.valueAt(Prop.y, start.toDouble());
    AnimTrack keyed(Prop p, double base, double Function(Offset d) pick) {
      var t = props.tracks[p] ?? AnimTrack.none;
      for (var i = 0; i < n; i++) {
        t = t.withoutKey(start + i);
      }
      for (var i = 0; i < n; i++) {
        t = t.withKey(AnimKey(start + i, base + pick(path[i][0] - box.center), Ease.linear));
      }
      return t;
    }

    final tracks = {...props.tracks, Prop.x: keyed(Prop.x, x0, (d) => d.dx), Prop.y: keyed(Prop.y, y0, (d) => d.dy)};
    updateProps(tr('Animar caída con rebote', 'Animate bouncing drop'), l.id, (p) => p.copyWith(tracks: tracks));
    return n;
  }
}
