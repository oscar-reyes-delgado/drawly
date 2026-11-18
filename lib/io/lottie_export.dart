import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import '../core/i18n.dart';
import '../model/anim.dart';
import '../model/document.dart';
import '../model/layer.dart';
import '../model/vector.dart';

/// Exported JSON and one warning per omitted layer or unsupported feature.
class LottieResult {
  const LottieResult(this.json, this.warnings);
  final String json;
  final List<String> warnings;
}

Map<String, dynamic> _static(dynamic value) => {'a': 0, 'k': value};
Map<String, dynamic> _ease(Ease ease) {
  if (ease.type == EaseType.hold) return {'h': 1};
  final (x1, y1, x2, y2) = switch (ease.type) {
    EaseType.easeIn => (0.42, 0.0, 1.0, 1.0), EaseType.easeOut => (0.0, 0.0, 0.58, 1.0),
    EaseType.easeInOut => (0.42, 0.0, 0.58, 1.0), EaseType.bezier => (ease.x1, ease.y1, ease.x2, ease.y2),
    _ => (0.167, 0.167, 0.833, 0.833),
  };
  return {'o': {'x': [x1], 'y': [y1]}, 'i': {'x': [x2], 'y': [y2]}};
}
bool _native(Ease ease) => const {EaseType.linear, EaseType.hold, EaseType.easeIn, EaseType.easeOut, EaseType.easeInOut, EaseType.bezier}.contains(ease.type);

Map<String, dynamic> _scalar(AnimTrack? track, double value, {double factor = 1, double add = 0}) {
  if (track == null || track.isEmpty) return _static(value * factor + add);
  final keys = <Map<String, dynamic>>[];
  for (var i = 0; i < track.keys.length; i++) {
    final key = track.keys[i];
    if (i == track.keys.length - 1) { keys.add({'t': key.frame, 's': [key.value * factor + add]}); }
    else if (_native(key.ease)) { keys.add({'t': key.frame, 's': [key.value * factor + add], ..._ease(key.ease)}); }
    else {
      for (var f = key.frame; f < track.keys[i + 1].frame; f++) { keys.add({'t': f, 's': [track.valueAt(f.toDouble())! * factor + add], ..._ease(Ease.linear)}); }
    }
  }
  return {'a': 1, 'k': keys};
}

Map<String, dynamic> _sampled(LayerProps p, List<Prop> properties, dynamic Function(double) value) {
  final frames = [for (final prop in properties) for (final k in p.tracks[prop]?.keys ?? <AnimKey>[]) k.frame];
  if (frames.isEmpty) return _static(value(0));
  final first = frames.reduce(math.min), last = frames.reduce(math.max);
  return {'a': 1, 'k': [for (var f = first; f <= last; f++) {'t': f, 's': value(f.toDouble()) is List ? value(f.toDouble()) : [value(f.toDouble())], if (f < last) ..._ease(Ease.linear)}]};
}

Map<String, dynamic> _transform(LayerProps p, {ui.Offset origin = ui.Offset.zero}) {
  double at(Prop prop, double frame) => p.valueAt(prop, frame);
  Map<String, dynamic> position(Prop coordinate, Prop anchor) {
    if (p.tracks[anchor]?.isNotEmpty ?? false) return _sampled(p, [coordinate, anchor], (f) => at(coordinate, f) + at(anchor, f));
    return _scalar(p.tracks[coordinate], p.xf.get(coordinate), add: p.xf.get(anchor));
  }
  final animatedPosition = [Prop.x, Prop.y, Prop.anchorX, Prop.anchorY].any((prop) => p.tracks[prop]?.isNotEmpty ?? false);
  return {
    'a': _sampled(p, [Prop.anchorX, Prop.anchorY], (f) => [at(Prop.anchorX, f) - origin.dx, at(Prop.anchorY, f) - origin.dy, 0]),
    'p': animatedPosition ? {'s': true, 'x': position(Prop.x, Prop.anchorX), 'y': position(Prop.y, Prop.anchorY)} : _static([p.xf.x + p.xf.ax, p.xf.y + p.xf.ay, 0]),
    's': _sampled(p, [Prop.scaleX, Prop.scaleY], (f) => [at(Prop.scaleX, f) * 100, at(Prop.scaleY, f) * 100, 100]),
    'r': _scalar(p.tracks[Prop.rotation], p.xf.rot), 'o': _scalar(p.tracks[Prop.opacity], p.opacity, factor: 100),
  };
}
List<double> _point(ui.Offset p) => [p.dx, p.dy];
List<double> _color(ui.Color c) => [c.r, c.g, c.b, 1];

Map<String, dynamic> _shape(VShape shape, void Function(String) warn) {
  final items = <Map<String, dynamic>>[
    for (final path in shape.paths) {'ty': 'sh', 'ks': _static({'v': path.nodes.map((n) => _point(n.p)).toList(), 'i': path.nodes.map((n) => _point(n.hIn - n.p)).toList(), 'o': path.nodes.map((n) => _point(n.hOut - n.p)).toList(), 'c': path.closed})},
  ];
  if (shape.fill.kind == FillKind.solid) {
    items.add({'ty': 'fl', 'c': _static(_color(shape.fill.color)), 'o': _static(shape.opacity * shape.fill.color.a * 100), 'r': shape.evenOdd ? 2 : 1});
  } else if (!shape.fill.isNone) { warn(tr('Relleno no compatible', 'Unsupported fill')); }
  final stroke = shape.stroke;
  if (stroke != null) {
    items.add({'ty': 'st', 'c': _static(_color(stroke.color)), 'o': _static(shape.opacity * stroke.color.a * 100), 'w': _static(stroke.width), 'lc': stroke.cap.index + 1, 'lj': stroke.join.index + 1, 'ml': stroke.miterLimit,
      if (stroke.dash.isNotEmpty) 'd': [for (var i = 0; i < stroke.dash.length; i++) {'n': i.isEven ? 'd' : 'g', 'v': _static(stroke.dash[i])}]});
    if (stroke.profile != WidthProfile.uniform) warn(tr('Ancho variable omitido', 'Variable width omitted'));
  }
  items.add({'ty': 'tr', 'a': _static([0, 0]), 'p': _static([0, 0]), 's': _static([100, 100]), 'r': _static(0), 'o': _static(100), 'sk': _static(0), 'sa': _static(0)});
  return {'ty': 'gr', 'nm': shape.name, 'it': items};
}

/// Exports the selected composition to Lottie, reporting unsupported features.
Future<LottieResult> exportLottie(Project project, {String? compId, bool embedRaster = true}) async {
  final comp = compId == null ? project.main : project.comps[compId];
  if (comp == null) throw ArgumentError.value(compId, 'compId');
  final layers = <Map<String, dynamic>>[], assets = <Map<String, dynamic>>[], warnings = <String>[];
  Future<void> visit(Layer layer) async {
    final p = layer.props;
    if (!p.visible || p.draft) return;
    void warn(String message) => warnings.add('$message: ${p.name.isEmpty ? layer.id : p.name}');
    if (p.hasMask || p.clip) warn(tr('Máscara omitida', 'Mask omitted'));
    if (p.fx.any) warn(tr('Efectos omitidos', 'Effects omitted'));
    if (p.blend != LayerBlend.normal) warn(tr('Modo de fusión omitido', 'Blend mode omitted'));
    if (p.parentId != null) warn(tr('Transformación del padre omitida', 'Parent transform omitted'));
    if (layer is GroupLayer) {
      if (!p.xf.isIdentity || p.opacity != 1 || p.isAnimated) warn(tr('Transformación u opacidad del grupo omitida', 'Group transform or opacity omitted'));
      for (final child in layer.children.reversed) { await visit(child); }
      return;
    }
    if (layer is! VectorLayer && layer is! PaintLayer) { warn(tr('Tipo de capa no compatible', 'Unsupported layer type')); return; }
    if (layer is PaintLayer && !embedRaster) { warn(tr('Capa de trama omitida', 'Raster layer omitted')); return; }
    final exposures = layer is VectorLayer ? layer.cels.xs : (layer as PaintLayer).cels.xs;
    for (var i = 0; i < exposures.length; i++) {
      final x = exposures[i], start = math.max(0, x.frame), end = math.min(comp.timeline.length, i + 1 < exposures.length ? exposures[i + 1].frame : comp.timeline.length);
      if (x.drawing == 0 || end <= start) continue;
      final entry = <String, dynamic>{'ind': layers.length + 1, 'nm': p.name, 'ip': start, 'op': end, 'st': 0, 'sr': 1, 'ddd': 0, 'ks': _transform(p)};
      if (layer is VectorLayer) {
        final art = layer.cels.drawings[x.drawing]; if (art == null || art.isEmpty) continue;
        entry['ty'] = 4;
        entry['shapes'] = art.shapes.reversed.map((shape) => _shape(shape, warn)).toList();
      } else if (layer is PaintLayer) {
        final plane = layer.cels.drawings[x.drawing], bounds = await plane?.contentBounds();
        if (plane == null || bounds == null || bounds.isEmpty) continue;
        final image = plane.toImage(bounds);
        try {
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          final id = 'image_${assets.length}';
          assets.add({'id': id, 'w': image.width, 'h': image.height, 'u': '', 'p': 'data:image/png;base64,${base64Encode(png!.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes))}', 'e': 1});
          entry['ty'] = 2; entry['refId'] = id; entry['ks'] = _transform(p, origin: bounds.topLeft);
        } finally { image.dispose(); }
      }
      layers.add(entry);
    }
  }
  for (final layer in comp.layers.reversed) { await visit(layer); }
  return LottieResult(jsonEncode({'v': '5.7.4', 'fr': comp.timeline.fps, 'ip': 0, 'op': comp.timeline.length, 'w': comp.width, 'h': comp.height, 'nm': comp.name, 'ddd': 0, 'assets': assets, 'layers': layers}), warnings);
}
