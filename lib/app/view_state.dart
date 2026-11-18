import 'dart:math' as math;
import 'dart:ui';

import '../core/mat2d.dart';

/// Canvas viewport: pan, zoom, rotation and horizontal flip.
class ViewState {
  const ViewState({this.pan = Offset.zero, this.zoom = 1, this.rotation = 0, this.flip = false});

  /// Position of the document origin in viewport pixels.
  final Offset pan;
  final double zoom;

  /// Radians.
  final double rotation;

  /// Mirrored view (flip horizontally to spot drawing errors).
  final bool flip;

  static const double minZoom = 0.01, maxZoom = 256;

  /// Document -> viewport (logical pixels of the canvas widget).
  Mat2D get matrix => Mat2D.translation(pan.dx, pan.dy) * Mat2D.rotation(rotation) * Mat2D.scale(flip ? -zoom : zoom, zoom);

  Mat2D get inverse => matrix.inverse;

  Offset toDoc(Offset viewport) => inverse.apply(viewport);
  Offset toView(Offset doc) => matrix.apply(doc);

  ViewState copyWith({Offset? pan, double? zoom, double? rotation, bool? flip}) =>
      ViewState(pan: pan ?? this.pan, zoom: zoom ?? this.zoom, rotation: rotation ?? this.rotation, flip: flip ?? this.flip);

  ViewState panned(Offset delta) => copyWith(pan: pan + delta);

  /// Zooms by [factor] keeping the document point under [focal] fixed.
  ViewState zoomedAt(Offset focal, double factor) {
    final nz = (zoom * factor).clamp(minZoom, maxZoom);
    final doc = toDoc(focal);
    final next = copyWith(zoom: nz);
    return next.copyWith(pan: next.pan + (focal - next.toView(doc)));
  }

  ViewState withZoomAt(Offset focal, double newZoom) => zoomedAt(focal, newZoom / zoom);

  ViewState rotatedAt(Offset focal, double deltaRadians) {
    final doc = toDoc(focal);
    final next = copyWith(rotation: rotation + deltaRadians);
    return next.copyWith(pan: next.pan + (focal - next.toView(doc)));
  }

  ViewState withRotationAt(Offset focal, double radians) => rotatedAt(focal, radians - rotation);

  ViewState flippedAt(Offset focal) {
    final doc = toDoc(focal);
    final next = copyWith(flip: !flip, rotation: -rotation);
    return next.copyWith(pan: next.pan + (focal - next.toView(doc)));
  }

  /// Fits [doc] inside [viewport] with a margin.
  static ViewState fit(Size viewport, Rect doc, {double margin = 40, double rotation = 0, bool flip = false}) {
    if (viewport.isEmpty || doc.isEmpty) return const ViewState();
    final z = math.min((viewport.width - margin * 2) / doc.width, (viewport.height - margin * 2) / doc.height).clamp(minZoom, maxZoom);
    final base = ViewState(zoom: z, rotation: rotation, flip: flip);
    final c = base.toView(doc.center);
    return base.copyWith(pan: Offset(viewport.width / 2, viewport.height / 2) - c);
  }

  /// Document rectangle visible in a viewport of [size] (bounding box).
  Rect visibleDoc(Size size) => inverse.mapRect(Offset.zero & size);
}
