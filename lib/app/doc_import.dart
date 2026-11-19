import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../core/i18n.dart';
import '../core/ids.dart';
import '../core/mat2d.dart';
import '../engine/tiles.dart';
import '../model/layer.dart';
import 'doc_layers.dart';
import 'document_controller.dart';

/// How an imported image is scaled onto the canvas.
enum ImageFit { none, contain, cover }

/// Sorts file names the way people expect: "walk_2" before "walk_10" (ignoring case).
List<String> naturalSort(Iterable<String> names) {
  final re = RegExp(r'\d+|\D+');
  int cmp(String a, String b) {
    final pa = re.allMatches(a.toLowerCase()).map((m) => m[0]!).toList();
    final pb = re.allMatches(b.toLowerCase()).map((m) => m[0]!).toList();
    for (var i = 0; i < math.min(pa.length, pb.length); i++) {
      final x = pa[i], y = pb[i];
      final nx = int.tryParse(x), ny = int.tryParse(y);
      final c = nx != null && ny != null ? (nx != ny ? nx.compareTo(ny) : x.length.compareTo(y.length)) : x.compareTo(y);
      if (c != 0) return c;
    }
    return pa.length.compareTo(pb.length);
  }

  return [...names]..sort(cmp);
}

extension DocImport on DocumentController {
  /// Plane with [image] placed on the canvas: [fit] scales it (`contain` never
  /// scales up an image that already fits) and it is centred. Pure, no history.
  TilePlane placeImage(ui.Image image, {ImageFit fit = ImageFit.contain}) {
    final iw = image.width.toDouble(), ih = image.height.toDouble();
    final cw = comp.width.toDouble(), ch = comp.height.toDouble();
    final scale = switch (fit) {
      ImageFit.none => 1.0,
      ImageFit.contain => math.min(1.0, math.min(cw / iw, ch / ih)),
      ImageFit.cover => math.max(cw / iw, ch / ih),
    };
    final w = iw * scale, h = ih * scale;
    final dst = Rect.fromLTWH(((cw - w) / 2).roundToDouble(), ((ch - h) / 2).roundToDouble(), w, h);
    var area = dst.roundedOut;
    if (!comp.infinite) area = area.intersect(comp.rect);
    if (area.isEmpty) return TilePlane.empty;
    return TilePlane.empty.drawn((c) {
      c.save();
      if (!comp.infinite) c.clipRect(comp.rect);
      c.drawImageRect(image, Rect.fromLTWH(0, 0, iw, ih), dst, Paint()..filterQuality = scale == 1 ? FilterQuality.none : FilterQuality.medium);
      c.restore();
    }, area: area);
  }

  /// New paint layer above the active one whose frame `start + i` shows
  /// images[i] (one drawing per image). The timeline grows if needed.
  /// Returns the new layer id. One undo step.
  String importImageSequence(List<ui.Image> images, String name, {int? start, ImageFit fit = ImageFit.contain}) {
    final first = math.max(0, start ?? 0);
    final drawings = <int, TilePlane>{};
    final xs = <Exposure>[];
    for (var i = 0; i < images.length; i++) {
      drawings[i + 1] = placeImage(images[i], fit: fit);
      xs.add(Exposure(first + i, i + 1));
    }
    if (first > 0) xs.insert(0, const Exposure(0, 0));
    final layer = PaintLayer(
      newId('L'),
      LayerProps(name: name, xf: Xform(ax: comp.width / 2, ay: comp.height / 2)),
      CelTrack<TilePlane>(drawings: drawings, xs: xs),
    );
    final active = activeLayer;
    final layers = active is GroupLayer && !active.props.collapsed
        ? insertLayer(comp.layers, layer, intoGroup: active.id)
        : insertLayer(comp.layers, layer, aboveId: active?.id);
    activeLayerId = layer.id;
    selectedLayers = {layer.id};
    editMask = false;
    final end = first + images.length;
    applyComp(tr('Importar secuencia', 'Import sequence'), (c) => c.copyWith(
          layers: layers,
          timeline: end > c.timeline.length ? c.timeline.copyWith(length: end) : c.timeline,
        ));
    return layer.id;
  }

  /// Puts [image] as a new drawing on the active paint layer at the current
  /// frame (replacing what it shows there). One undo step. False when the
  /// active layer is not a paint layer or is locked.
  bool importImageIntoFrame(ui.Image image, {ImageFit fit = ImageFit.contain}) {
    final l = activeLayer;
    if (l is! PaintLayer || l.props.locked || editMask) return false;
    if (!layerMatrix(l).isIdentity) return false;
    final plane = placeImage(image, fit: fit);
    final f = frame;
    final id = l.cels.newDrawingId;
    var cels = l.cels.withDrawing(id, plane);
    // a held drawing keeps showing on the following frame
    final held = l.cels.drawingIdAt(f + 1);
    if (held != null && !l.cels.hasKeyAt(f + 1) && f + 1 < timeline.length) cels = cels.withKey(f + 1, held);
    final next = l.withCels(cels.withKey(f, id).pruned());
    applyComp(tr('Importar imagen', 'Import image'), (c) {
      final updated = c.updateLayer(l.id, (_) => next);
      return f >= c.timeline.length ? updated.copyWith(timeline: c.timeline.copyWith(length: f + 1)) : updated;
    });
    return true;
  }
}
