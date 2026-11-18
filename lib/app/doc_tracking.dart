import 'dart:math' as math;
import 'dart:ui';

import '../core/i18n.dart';
import '../engine/compositor.dart';
import '../engine/tiles.dart';
import '../engine/tracking.dart';
import '../model/anim.dart';
import 'document_controller.dart';

/// Motion-tracking helpers that follow a rendered point and bake it into layer keyframes.
extension DocTracking on DocumentController {
  /// Tracks [point] (document coordinates) from the current frame to the end of the
  /// timeline (at most [maxFrames]) on the rendered composition, ignoring [excludeLayerId]
  /// so the layer that will follow does not disturb the tracking.
  /// Returns one position per frame (first = [point]).
  Future<List<Offset>> trackFromCurrentFrame(
    Offset point, {
    String? excludeLayerId,
    int maxFrames = 240,
    double scale = 0.5,
    void Function(double)? onProgress,
  }) async {
    final start = frame;
    final n = math.min(maxFrames, timeline.length - start);
    if (n <= 0 || scale <= 0) return const [];
    final hidden = {?excludeLayerId};
    final frames = <GrayFrame>[];
    for (var i = 0; i < n; i++) {
      final img = renderCompImage(
        project,
        comp,
        (start + i).toDouble(),
        scale: scale,
        background: true,
        forExport: true,
        useCamera: false,
        hidden: hidden,
      );
      try {
        final rgba = await imageToRgba(img, straight: true);
        frames.add(grayFromRgba(rgba, img.width, img.height));
      } finally {
        img.dispose();
      }
      onProgress?.call((i + 1) / n);
    }
    final patch = math.max(5, (14 * scale).round() | 1);
    final search = math.max(4, (24 * scale).round());
    final tracked = trackPoint(frames, point * scale, patch: patch, search: search);
    return [
      point,
      for (var i = 1; i < tracked.length; i++) tracked[i] / scale,
    ];
  }

  /// Writes linear X/Y keys on [layerId] so it moves by (path[i] - path[0]) from its
  /// position at the current frame; replaces X/Y keys in that range. Returns keys written.
  int applyTrackToLayer(String layerId, List<Offset> path) {
    final l = comp.layer(layerId);
    if (l == null || path.isEmpty) return 0;
    final start = frame;
    final origin = path.first;
    final props = l.props;
    final x0 = props.valueAt(Prop.x, start.toDouble());
    final y0 = props.valueAt(Prop.y, start.toDouble());
    // a parented layer moves in its parent's space
    final parent = comp.layer(props.parentId);
    final toLocal = parent == null ? null : comp.worldMatrix(parent, start.toDouble()).inverse;
    Offset local(Offset d) => toLocal == null ? d : toLocal.applyVector(d);

    AnimTrack keyed(Prop p, double base, double Function(Offset d) pick) {
      var t = props.tracks[p] ?? AnimTrack.none;
      for (var i = 0; i < path.length; i++) {
        t = t.withoutKey(start + i);
      }
      for (var i = 0; i < path.length; i++) {
        t = t.withKey(AnimKey(start + i, base + pick(local(path[i] - origin)), Ease.linear));
      }
      return t;
    }

    final tracks = {
      ...props.tracks,
      Prop.x: keyed(Prop.x, x0, (d) => d.dx),
      Prop.y: keyed(Prop.y, y0, (d) => d.dy),
    };
    updateProps(tr('Seguimiento de movimiento', 'Track motion'), l.id, (p) => p.copyWith(tracks: tracks));
    return path.length;
  }
}
