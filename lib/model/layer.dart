import 'dart:math' as math;
import 'dart:ui' as ui;

import '../core/i18n.dart';
import '../core/ids.dart';
import '../core/mat2d.dart';
import '../engine/tiles.dart';
import 'anim.dart';
import 'filter_spec.dart';
import 'layer_rig.dart';
import 'layer_fx.dart';
import 'specs.dart';
import 'vector.dart';

export 'layer_rig.dart' show LayerRig;

enum LayerBlend {
  normal,
  multiply,
  screen,
  overlay,
  darken,
  lighten,
  colorDodge,
  colorBurn,
  hardLight,
  softLight,
  difference,
  exclusion,
  add,
  hue,
  saturation,
  color,
  luminosity,
}

extension LayerBlendX on LayerBlend {
  ui.BlendMode get mode => switch (this) {
        LayerBlend.normal => ui.BlendMode.srcOver,
        LayerBlend.multiply => ui.BlendMode.multiply,
        LayerBlend.screen => ui.BlendMode.screen,
        LayerBlend.overlay => ui.BlendMode.overlay,
        LayerBlend.darken => ui.BlendMode.darken,
        LayerBlend.lighten => ui.BlendMode.lighten,
        LayerBlend.colorDodge => ui.BlendMode.colorDodge,
        LayerBlend.colorBurn => ui.BlendMode.colorBurn,
        LayerBlend.hardLight => ui.BlendMode.hardLight,
        LayerBlend.softLight => ui.BlendMode.softLight,
        LayerBlend.difference => ui.BlendMode.difference,
        LayerBlend.exclusion => ui.BlendMode.exclusion,
        LayerBlend.add => ui.BlendMode.plus,
        LayerBlend.hue => ui.BlendMode.hue,
        LayerBlend.saturation => ui.BlendMode.saturation,
        LayerBlend.color => ui.BlendMode.color,
        LayerBlend.luminosity => ui.BlendMode.luminosity,
      };

  String get label => switch (this) {
        LayerBlend.normal => tr('Normal', 'Normal'),
        LayerBlend.multiply => tr('Multiplicar', 'Multiply'),
        LayerBlend.screen => tr('Pantalla', 'Screen'),
        LayerBlend.overlay => tr('Superponer', 'Overlay'),
        LayerBlend.darken => tr('Oscurecer', 'Darken'),
        LayerBlend.lighten => tr('Aclarar', 'Lighten'),
        LayerBlend.colorDodge => tr('Sobreexponer color', 'Colour dodge'),
        LayerBlend.colorBurn => tr('Subexponer color', 'Colour burn'),
        LayerBlend.hardLight => tr('Luz fuerte', 'Hard light'),
        LayerBlend.softLight => tr('Luz suave', 'Soft light'),
        LayerBlend.difference => tr('Diferencia', 'Difference'),
        LayerBlend.exclusion => tr('Exclusión', 'Exclusion'),
        LayerBlend.add => tr('Añadir (aditivo)', 'Add'),
        LayerBlend.hue => tr('Tono', 'Hue'),
        LayerBlend.saturation => tr('Saturación', 'Saturation'),
        LayerBlend.color => tr('Color', 'Colour'),
        LayerBlend.luminosity => tr('Luminosidad', 'Luminosity'),
      };
}

/// Static (un-keyed) layer transform. Rotation in degrees around the anchor.
class Xform {
  const Xform({this.x = 0, this.y = 0, this.sx = 1, this.sy = 1, this.rot = 0, this.ax = 0, this.ay = 0});
  final double x, y, sx, sy, rot, ax, ay;

  static const Xform identity = Xform();

  bool get isIdentity => x == 0 && y == 0 && sx == 1 && sy == 1 && rot == 0;

  Mat2D get matrix => Mat2D.trs(x: x, y: y, rotation: degToRad(rot), sx: sx, sy: sy, ax: ax, ay: ay);

  Xform copyWith({double? x, double? y, double? sx, double? sy, double? rot, double? ax, double? ay}) => Xform(
        x: x ?? this.x,
        y: y ?? this.y,
        sx: sx ?? this.sx,
        sy: sy ?? this.sy,
        rot: rot ?? this.rot,
        ax: ax ?? this.ax,
        ay: ay ?? this.ay,
      );

  double get(Prop p) => switch (p) {
        Prop.x => x,
        Prop.y => y,
        Prop.scaleX => sx,
        Prop.scaleY => sy,
        Prop.rotation => rot,
        Prop.anchorX => ax,
        Prop.anchorY => ay,
        Prop.opacity => 1,
        Prop.zoom => 1,
      };

  Xform set(Prop p, double v) => switch (p) {
        Prop.x => copyWith(x: v),
        Prop.y => copyWith(y: v),
        Prop.scaleX => copyWith(sx: v),
        Prop.scaleY => copyWith(sy: v),
        Prop.rotation => copyWith(rot: v),
        Prop.anchorX => copyWith(ax: v),
        Prop.anchorY => copyWith(ay: v),
        _ => this,
      };

  /// Decomposes a (skew-free) matrix into a transform around the given anchor.
  static Xform fromMatrix(Mat2D m, {double ax = 0, double ay = 0}) {
    final sx = math.sqrt(m.a * m.a + m.b * m.b);
    final sy = sx == 0 ? 0.0 : m.determinant / sx;
    return Xform(
      x: m.tx - ax + (m.a * ax + m.c * ay),
      y: m.ty - ay + (m.b * ax + m.d * ay),
      sx: sx,
      sy: sy,
      rot: radToDeg(math.atan2(m.b, m.a)),
      ax: ax,
      ay: ay,
    );
  }

  List<double> toJson() => [x, y, sx, sy, rot, ax, ay];

  static Xform fromJson(dynamic j) {
    if (j == null) return Xform.identity;
    final l = (j as List).map((e) => (e as num).toDouble()).toList();
    return Xform(x: l[0], y: l[1], sx: l[2], sy: l[3], rot: l[4], ax: l[5], ay: l[6]);
  }
}

const Object _unset = Object();

/// Properties shared by every layer type.
class LayerProps {
  const LayerProps({
    this.name = '',
    this.visible = true,
    this.opacity = 1,
    this.blend = LayerBlend.normal,
    this.locked = false,
    this.lockAlpha = false,
    this.lockPosition = false,
    this.clip = false,
    this.reference = false,
    this.draft = false,
    this.mask,
    this.maskEnabled = true,
    this.fx = LayerFx.none,
    this.xf = Xform.identity,
    this.tracks = const {},
    this.parentId,
    this.colorTag = 0,
    this.collapsed = false,
    this.depth = 0,
  });

  final String name;
  final bool visible;
  final double opacity;
  final LayerBlend blend;

  /// Lock everything / lock transparent pixels / lock position.
  final bool locked, lockAlpha, lockPosition;

  /// Clipping mask: only shows where the layer below has content.
  final bool clip;

  /// Reference layer: source for fills on other layers.
  final bool reference;

  /// Draft / sketch layer: visible while editing but never exported.
  final bool draft;

  /// Layer mask stored as a "hide" plane (alpha = hidden amount).
  final TilePlane? mask;
  final bool maskEnabled;
  final LayerFx fx;
  final Xform xf;
  final Map<Prop, AnimTrack> tracks;

  /// Transform parent (layer id) for hierarchical animation.
  final String? parentId;
  final int colorTag;
  final bool collapsed;

  /// Distance from the camera plane for 2.5D parallax (0 = on the plane,
  /// positive = further away).
  final double depth;

  bool get hasMask => mask != null && maskEnabled;
  bool get isAnimated => tracks.values.any((t) => t.isNotEmpty);

  LayerProps copyWith({
    String? name,
    bool? visible,
    double? opacity,
    LayerBlend? blend,
    bool? locked,
    bool? lockAlpha,
    bool? lockPosition,
    bool? clip,
    bool? reference,
    bool? draft,
    Object? mask = _unset,
    bool? maskEnabled,
    LayerFx? fx,
    Xform? xf,
    Map<Prop, AnimTrack>? tracks,
    Object? parentId = _unset,
    int? colorTag,
    bool? collapsed,
    double? depth,
  }) =>
      LayerProps(
        name: name ?? this.name,
        visible: visible ?? this.visible,
        opacity: opacity ?? this.opacity,
        blend: blend ?? this.blend,
        locked: locked ?? this.locked,
        lockAlpha: lockAlpha ?? this.lockAlpha,
        lockPosition: lockPosition ?? this.lockPosition,
        clip: clip ?? this.clip,
        reference: reference ?? this.reference,
        draft: draft ?? this.draft,
        mask: identical(mask, _unset) ? this.mask : mask as TilePlane?,
        maskEnabled: maskEnabled ?? this.maskEnabled,
        fx: fx ?? this.fx,
        xf: xf ?? this.xf,
        tracks: tracks ?? this.tracks,
        parentId: identical(parentId, _unset) ? this.parentId : parentId as String?,
        colorTag: colorTag ?? this.colorTag,
        collapsed: collapsed ?? this.collapsed,
        depth: depth ?? this.depth,
      );

  /// Value of an animatable property at [frame] (track overrides static value).
  double valueAt(Prop p, double frame) {
    final t = tracks[p];
    if (t != null && t.isNotEmpty) return t.valueAt(frame)!;
    return p == Prop.opacity ? opacity : xf.get(p);
  }

  Mat2D matrixAt(double frame) {
    if (tracks.isEmpty) return xf.matrix;
    return Mat2D.trs(
      x: valueAt(Prop.x, frame),
      y: valueAt(Prop.y, frame),
      rotation: degToRad(valueAt(Prop.rotation, frame)),
      sx: valueAt(Prop.scaleX, frame),
      sy: valueAt(Prop.scaleY, frame),
      ax: valueAt(Prop.anchorX, frame),
      ay: valueAt(Prop.anchorY, frame),
    );
  }

  double opacityAt(double frame) {
    final t = tracks[Prop.opacity];
    if (t != null && t.isNotEmpty) return t.valueAt(frame)!.clamp(0.0, 1.0);
    return opacity;
  }
}

/// One timeline key of a cel track: from [frame] on, show [drawing]
/// (0 = blank) until the next key.
class Exposure {
  const Exposure(this.frame, this.drawing);
  final int frame;
  final int drawing;
}

/// Frame-by-frame content of a layer: a pool of drawings plus the exposure
/// sheet that says which drawing is shown at which frame. The same drawing
/// may be exposed many times (cycles, lip-sync mouth swaps…).
class CelTrack<T> {
  const CelTrack({required this.drawings, required this.xs});

  final Map<int, T> drawings;

  /// Sorted by frame.
  final List<Exposure> xs;

  factory CelTrack.single(T content) => CelTrack(drawings: {1: content}, xs: const [Exposure(0, 1)]);

  int _idx(int frame) {
    var lo = 0, hi = xs.length - 1, res = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (xs[mid].frame <= frame) {
        res = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return res;
  }

  /// The key that is being held at [frame], if any.
  Exposure? exposureAt(int frame) {
    final i = _idx(frame);
    return i < 0 ? null : xs[i];
  }

  /// Drawing id shown at [frame] (null when nothing / blank).
  int? drawingIdAt(int frame) {
    final e = exposureAt(frame);
    if (e == null || e.drawing == 0 || !drawings.containsKey(e.drawing)) return null;
    return e.drawing;
  }

  T? at(int frame) {
    final id = drawingIdAt(frame);
    return id == null ? null : drawings[id];
  }

  bool hasKeyAt(int frame) {
    final i = _idx(frame);
    return i >= 0 && xs[i].frame == frame;
  }

  int? prevKeyFrame(int frame) {
    final i = _idx(frame - 1);
    return i < 0 ? null : xs[i].frame;
  }

  int? nextKeyFrame(int frame) {
    final i = _idx(frame) + 1;
    return i < xs.length ? xs[i].frame : null;
  }

  int get lastKeyFrame => xs.isEmpty ? 0 : xs.last.frame;

  int get newDrawingId {
    var m = 0;
    for (final k in drawings.keys) {
      if (k > m) m = k;
    }
    return m + 1;
  }

  /// Whether more than one key shows the same drawing.
  bool isShared(int drawing) => xs.where((e) => e.drawing == drawing).length > 1;

  CelTrack<T> withDrawing(int id, T content) => CelTrack(drawings: {...drawings, id: content}, xs: xs);

  CelTrack<T> withKey(int frame, int drawing) {
    final out = <Exposure>[];
    var placed = false;
    for (final e in xs) {
      if (e.frame == frame) {
        out.add(Exposure(frame, drawing));
        placed = true;
      } else {
        if (!placed && e.frame > frame) {
          out.add(Exposure(frame, drawing));
          placed = true;
        }
        out.add(e);
      }
    }
    if (!placed) out.add(Exposure(frame, drawing));
    return CelTrack(drawings: drawings, xs: out);
  }

  CelTrack<T> withoutKey(int frame) => CelTrack(drawings: drawings, xs: xs.where((e) => e.frame != frame).toList()).pruned();

  CelTrack<T> movedKey(int from, int to) {
    if (from == to || !hasKeyAt(from)) return this;
    final d = exposureAt(from)!.drawing;
    final rest = xs.where((e) => e.frame != from && e.frame != to).toList();
    return CelTrack(drawings: drawings, xs: rest).withKey(to, d).pruned();
  }

  /// Inserts ([delta] > 0) or removes ([delta] < 0) frames at [from].
  CelTrack<T> shifted(int from, int delta) {
    final out = <Exposure>[];
    for (final e in xs) {
      if (e.frame < from) {
        out.add(e);
      } else if (delta < 0 && e.frame < from - delta) {
        // removed
      } else {
        out.add(Exposure(e.frame + delta, e.drawing));
      }
    }
    return CelTrack(drawings: drawings, xs: out).pruned();
  }

  /// Drops drawings no key refers to any more.
  CelTrack<T> pruned() {
    final used = {for (final e in xs) e.drawing};
    if (drawings.keys.every(used.contains)) return this;
    return CelTrack(drawings: {
      for (final e in drawings.entries)
        if (used.contains(e.key)) e.key: e.value,
    }, xs: xs);
  }

  CelTrack<R> mapDrawings<R>(R Function(T) f) => CelTrack<R>(drawings: drawings.map((k, v) => MapEntry(k, f(v))), xs: xs);
}

sealed class Layer {
  const Layer(this.id, this.props);
  final String id;
  final LayerProps props;

  Layer withProps(LayerProps p);
  Layer withId(String newId);

  String get name => props.name;
  bool get visible => props.visible;
  double get opacity => props.opacity;
  LayerBlend get blend => props.blend;
  bool get locked => props.locked;

  /// Human readable type name.
  String get typeLabel;
}

/// Bitmap (raster) layer.
class PaintLayer extends Layer {
  const PaintLayer(super.id, super.props, this.cels, {this.rig});
  final CelTrack<TilePlane> cels;

  /// Bones that deform the pixels (null = none).
  final LayerRig? rig;

  factory PaintLayer.create(String name, {TilePlane? pixels}) =>
      PaintLayer(newId('L'), LayerProps(name: name), CelTrack.single(pixels ?? TilePlane.empty));

  PaintLayer withCels(CelTrack<TilePlane> c) => PaintLayer(id, props, c, rig: rig);

  /// Same layer with another rig (null removes the bones).
  PaintLayer withRig(LayerRig? r) => PaintLayer(id, props, cels, rig: r == null || r.isEmpty ? null : r);

  @override
  PaintLayer withProps(LayerProps p) => PaintLayer(id, p, cels, rig: rig);
  @override
  PaintLayer withId(String newId) => PaintLayer(newId, props, cels, rig: rig);
  @override
  String get typeLabel => tr('Capa de trama', 'Raster layer');
}

/// Vector layer (frame-by-frame capable).
class VectorLayer extends Layer {
  const VectorLayer(super.id, super.props, this.cels);
  final CelTrack<VectorArt> cels;

  factory VectorLayer.create(String name) => VectorLayer(newId('L'), LayerProps(name: name), CelTrack.single(VectorArt.empty));

  VectorLayer withCels(CelTrack<VectorArt> c) => VectorLayer(id, props, c);

  @override
  VectorLayer withProps(LayerProps p) => VectorLayer(id, p, cels);
  @override
  VectorLayer withId(String newId) => VectorLayer(newId, props, cels);
  @override
  String get typeLabel => tr('Capa vectorial', 'Vector layer');
}

class TextLayer extends Layer {
  const TextLayer(super.id, super.props, this.text);
  final TextSpec text;

  TextLayer withText(TextSpec t) => TextLayer(id, props, t);

  @override
  TextLayer withProps(LayerProps p) => TextLayer(id, p, text);
  @override
  TextLayer withId(String newId) => TextLayer(newId, props, text);
  @override
  String get typeLabel => tr('Capa de texto', 'Text layer');
}

class GroupLayer extends Layer {
  const GroupLayer(super.id, super.props, this.children, {this.passThrough = true});

  /// Bottom to top.
  final List<Layer> children;

  /// Pass-through groups composite their children straight onto the
  /// backdrop; isolated groups are flattened first.
  final bool passThrough;

  GroupLayer withChildren(List<Layer> c) => GroupLayer(id, props, c, passThrough: passThrough);
  GroupLayer withPassThrough(bool v) => GroupLayer(id, props, children, passThrough: v);

  @override
  GroupLayer withProps(LayerProps p) => GroupLayer(id, p, children, passThrough: passThrough);
  @override
  GroupLayer withId(String newId) => GroupLayer(newId, props, children, passThrough: passThrough);
  @override
  String get typeLabel => tr('Grupo', 'Group');
}

/// Non-destructive adjustment / filter layer acting on everything below it.
class AdjustLayer extends Layer {
  const AdjustLayer(super.id, super.props, this.filter);
  final FilterSpec filter;

  AdjustLayer withFilter(FilterSpec f) => AdjustLayer(id, props, f);

  @override
  AdjustLayer withProps(LayerProps p) => AdjustLayer(id, p, filter);
  @override
  AdjustLayer withId(String newId) => AdjustLayer(newId, props, filter);
  @override
  String get typeLabel => tr('Capa de ajuste', 'Adjustment layer');
}

/// Instance of another composition: symbol, nested comp (precomp) or smart
/// object. Renders [compId] starting at [start], optionally looping.
class InstanceLayer extends Layer {
  const InstanceLayer(super.id, super.props, this.compId, {this.start = 0, this.loop = true, this.speed = 1, this.fixedFrame});
  final String compId;
  final int start;
  final bool loop;
  final double speed;

  /// When set the instance always shows this frame (drawing substitution).
  final int? fixedFrame;

  InstanceLayer copyWith({String? compId, int? start, bool? loop, double? speed, Object? fixedFrame = _unset}) => InstanceLayer(
        id,
        props,
        compId ?? this.compId,
        start: start ?? this.start,
        loop: loop ?? this.loop,
        speed: speed ?? this.speed,
        fixedFrame: identical(fixedFrame, _unset) ? this.fixedFrame : fixedFrame as int?,
      );

  @override
  InstanceLayer withProps(LayerProps p) => InstanceLayer(id, p, compId, start: start, loop: loop, speed: speed, fixedFrame: fixedFrame);
  @override
  InstanceLayer withId(String newId) => InstanceLayer(newId, props, compId, start: start, loop: loop, speed: speed, fixedFrame: fixedFrame);
  @override
  String get typeLabel => tr('Símbolo / composición', 'Symbol / comp');
}

class ParticleLayer extends Layer {
  const ParticleLayer(super.id, super.props, this.spec);
  final ParticleSpec spec;

  ParticleLayer withSpec(ParticleSpec s) => ParticleLayer(id, props, s);

  @override
  ParticleLayer withProps(LayerProps p) => ParticleLayer(id, p, spec);
  @override
  ParticleLayer withId(String newId) => ParticleLayer(newId, props, spec);
  @override
  String get typeLabel => tr('Partículas', 'Particles');
}

// ---------------------------------------------------------------------------
// Tree helpers (layers are stored bottom -> top; groups nest)
// ---------------------------------------------------------------------------

Iterable<Layer> walkLayers(List<Layer> layers) sync* {
  for (final l in layers) {
    yield l;
    if (l is GroupLayer) yield* walkLayers(l.children);
  }
}

Layer? findLayer(List<Layer> layers, String? id) {
  if (id == null) return null;
  for (final l in walkLayers(layers)) {
    if (l.id == id) return l;
  }
  return null;
}

/// Group containing [id], or null when it is at the root (or missing).
GroupLayer? parentGroupOf(List<Layer> layers, String id) {
  for (final l in walkLayers(layers)) {
    if (l is GroupLayer && l.children.any((c) => c.id == id)) return l;
  }
  return null;
}

/// Structural update of one layer anywhere in the tree.
List<Layer> mapLayer(List<Layer> layers, String id, Layer Function(Layer) f) {
  var changed = false;
  final out = <Layer>[];
  for (final l in layers) {
    if (l.id == id) {
      out.add(f(l));
      changed = true;
    } else if (l is GroupLayer) {
      final c = mapLayer(l.children, id, f);
      if (!identical(c, l.children)) {
        out.add(l.withChildren(c));
        changed = true;
      } else {
        out.add(l);
      }
    } else {
      out.add(l);
    }
  }
  return changed ? out : layers;
}

/// Applies [f] to every layer in the tree (children first).
List<Layer> mapAllLayers(List<Layer> layers, Layer Function(Layer) f) => [
      for (final l in layers) f(l is GroupLayer ? l.withChildren(mapAllLayers(l.children, f)) : l),
    ];

List<Layer> removeLayer(List<Layer> layers, String id) {
  var changed = false;
  final out = <Layer>[];
  for (final l in layers) {
    if (l.id == id) {
      changed = true;
      continue;
    }
    if (l is GroupLayer) {
      final c = removeLayer(l.children, id);
      if (!identical(c, l.children)) {
        out.add(l.withChildren(c));
        changed = true;
        continue;
      }
    }
    out.add(l);
  }
  return changed ? out : layers;
}

/// Inserts [layer] directly above [aboveId] (same parent). With a null or
/// unknown id the layer goes on top of the root list. When [intoGroup] is
/// set the layer becomes the top child of that group.
List<Layer> insertLayer(List<Layer> layers, Layer layer, {String? aboveId, String? intoGroup}) {
  if (intoGroup != null && findLayer(layers, intoGroup) is GroupLayer) {
    return mapLayer(layers, intoGroup, (g) => (g as GroupLayer).withChildren([...g.children, layer]));
  }
  if (aboveId == null || findLayer(layers, aboveId) == null) return [...layers, layer];
  List<Layer> rec(List<Layer> list) {
    final i = list.indexWhere((l) => l.id == aboveId);
    if (i >= 0) return [...list.sublist(0, i + 1), layer, ...list.sublist(i + 1)];
    return [
      for (final l in list)
        if (l is GroupLayer) l.withChildren(rec(l.children)) else l,
    ];
  }

  return rec(layers);
}

/// Deep copy with fresh ids (drawings / tiles stay shared).
Layer cloneLayer(Layer l, {String? name}) {
  final p = name == null ? l.props : l.props.copyWith(name: name);
  final id = newId('L');
  return switch (l) {
    GroupLayer g => GroupLayer(id, p, g.children.map((c) => cloneLayer(c)).toList(), passThrough: g.passThrough),
    _ => l.withProps(p).withId(id),
  };
}
