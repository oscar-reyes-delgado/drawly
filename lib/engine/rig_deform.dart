import 'dart:ui' as ui;
import 'dart:ui';

import '../model/layer_rig.dart';
import 'rig.dart';
import 'tiles.dart';
import 'warp.dart';

/// Skin weights of the rest grid vertices, cached per skeleton and region.
final Expando<Map<String, ({List<Offset> rest, SkinWeights weights})>> _weightCache = Expando('rigWeights');

/// Deformation mesh of [rig] over [region] (layer coordinates) at [frame], or
/// null when the bones are at rest.
WarpGrid? rigGrid(LayerRig rig, Rect region, double frame) {
  if (rig.isEmpty || rig.isRestAt(frame) || region.isEmpty) return null;
  final grid = WarpGrid.forSize(region, cell: rig.cell);
  final cacheKey = '${region.left},${region.top},${region.width},${region.height},${rig.cell},${rig.falloff}';
  final byRegion = _weightCache[rig.skeleton] ??= {};
  final cached = byRegion[cacheKey] ??= () {
    final rest = [for (var r = 0; r <= grid.rows; r++) for (var c = 0; c <= grid.cols; c++) grid.rest(c, r)];
    if (byRegion.length > 8) byRegion.clear();
    return (rest: rest, weights: autoWeights(rest, rig.skeleton, falloff: rig.falloff));
  }();
  final posed = skinPoints(cached.rest, cached.weights, solveFk(rig.skeleton, rig.poseAt(frame)));
  for (var i = 0; i < posed.length; i++) {
    grid.dx[i] = posed[i].dx - cached.rest[i].dx;
    grid.dy[i] = posed[i].dy - cached.rest[i].dy;
  }
  return grid;
}

/// Region deformed for [plane]: its tile bounds, or null when empty.
Rect? rigRegion(TilePlane plane) => plane.bounds;

/// Paints [plane] deformed by [rig] at [frame]. Returns false (nothing drawn)
/// when the bones are at rest or the plane is empty, so the caller paints it
/// normally.
bool paintRigged(Canvas canvas, TilePlane plane, LayerRig rig, double frame, {FilterQuality quality = FilterQuality.medium}) {
  final region = rigRegion(plane);
  if (region == null) return false;
  final grid = rigGrid(rig, region, frame);
  if (grid == null) return false;
  final ui.Image img = plane.toImage(region);
  paintWarped(canvas, img, grid, quality: quality);
  img.dispose();
  return true;
}

/// Posed position of every bone joint (head, tail) at [frame], in layer coordinates.
Map<String, (Offset, Offset)> posedBones(LayerRig rig, double frame) {
  final fk = solveFk(rig.skeleton, rig.poseAt(frame));
  return {for (final b in rig.skeleton.bones) b.id: (posedHead(rig.skeleton, fk, b.id), posedTail(rig.skeleton, fk, b.id))};
}
