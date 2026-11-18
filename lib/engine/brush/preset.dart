import '../../core/i18n.dart';
import '../../core/ids.dart';
import '../../model/layer.dart';

/// How the dab is oriented.
enum BrushRotation { fixed, direction, random, tilt }

/// What a dab does to the canvas.
enum BrushEngine {
  /// Deposits colour (the regular brush).
  paint,

  /// Drags existing paint (finger / smudge).
  smudge,

  /// Deposits colour while dragging and mixing with what is on the canvas.
  mixer,
}

/// A complete, serialisable brush definition.
class BrushPreset {
  const BrushPreset({
    required this.id,
    required this.name,
    this.category = 'custom',
    this.tip = 'round',
    this.size = 20,
    this.minSize = 0.1,
    this.opacity = 1,
    this.flow = 1,
    this.hardness = 0.8,
    this.spacing = 0.1,
    this.angle = 0,
    this.roundness = 1,
    this.rotation = BrushRotation.fixed,
    this.pressureSize = 1,
    this.pressureFlow = 0,
    this.velocitySize = 0,
    this.tiltSize = 0,
    this.tiltFlow = 0,
    this.jitterSize = 0,
    this.jitterAngle = 0,
    this.jitterFlow = 0,
    this.scatter = 0,
    this.jitterHue = 0,
    this.jitterSat = 0,
    this.jitterVal = 0,
    this.count = 1,
    this.grain = '',
    this.grainScale = 1,
    this.grainStrength = 0.6,
    this.smoothing = 0.3,
    this.blend = LayerBlend.normal,
    this.erase = false,
    this.engine = BrushEngine.paint,
    this.smudge = 0.6,
    this.wet = 0.5,
    this.pigment = true,
    this.antialias = true,
    this.taper = 0,
    this.builtin = false,
  });

  final String id, name, category;

  /// Tip shape id (see `BrushTips`).
  final String tip;

  /// Diameter in pixels and its fraction at zero pressure.
  final double size, minSize;

  /// Stroke opacity cap and per-dab flow.
  final double opacity, flow;

  /// Edge hardness of the round tip (0 soft … 1 hard).
  final double hardness;

  /// Distance between dabs as a fraction of the diameter.
  final double spacing;

  /// Tip angle in degrees and roundness (1 = circle, <1 = flattened).
  final double angle, roundness;
  final BrushRotation rotation;

  /// How much pen pressure / speed / tilt drive size and flow (0..1; speed
  /// may be negative to thicken when fast).
  final double pressureSize, pressureFlow, velocitySize, tiltSize, tiltFlow;

  /// Random per-dab variation (0..1).
  final double jitterSize, jitterAngle, jitterFlow, scatter, jitterHue, jitterSat, jitterVal;

  /// Dabs stamped per spacing step (with scatter).
  final int count;

  /// Paper grain texture id ('' = none), its scale and depth.
  final String grain;
  final double grainScale, grainStrength;

  /// Stabiliser amount 0..1.
  final double smoothing;
  final LayerBlend blend;
  final bool erase;
  final BrushEngine engine;

  /// Smudge strength and how much paint is picked up from the canvas.
  final double smudge, wet;

  /// Subtractive (pigment-like) mixing in the mixer engine.
  final bool pigment;
  final bool antialias;

  /// Automatic start taper length in diameters (for devices without pressure).
  final double taper;
  final bool builtin;

  bool get isPixel => !antialias;

  BrushPreset copyWith({
    String? id,
    String? name,
    String? category,
    String? tip,
    double? size,
    double? minSize,
    double? opacity,
    double? flow,
    double? hardness,
    double? spacing,
    double? angle,
    double? roundness,
    BrushRotation? rotation,
    double? pressureSize,
    double? pressureFlow,
    double? velocitySize,
    double? tiltSize,
    double? tiltFlow,
    double? jitterSize,
    double? jitterAngle,
    double? jitterFlow,
    double? scatter,
    double? jitterHue,
    double? jitterSat,
    double? jitterVal,
    int? count,
    String? grain,
    double? grainScale,
    double? grainStrength,
    double? smoothing,
    LayerBlend? blend,
    bool? erase,
    BrushEngine? engine,
    double? smudge,
    double? wet,
    bool? pigment,
    bool? antialias,
    double? taper,
    bool? builtin,
  }) =>
      BrushPreset(
        id: id ?? this.id,
        name: name ?? this.name,
        category: category ?? this.category,
        tip: tip ?? this.tip,
        size: size ?? this.size,
        minSize: minSize ?? this.minSize,
        opacity: opacity ?? this.opacity,
        flow: flow ?? this.flow,
        hardness: hardness ?? this.hardness,
        spacing: spacing ?? this.spacing,
        angle: angle ?? this.angle,
        roundness: roundness ?? this.roundness,
        rotation: rotation ?? this.rotation,
        pressureSize: pressureSize ?? this.pressureSize,
        pressureFlow: pressureFlow ?? this.pressureFlow,
        velocitySize: velocitySize ?? this.velocitySize,
        tiltSize: tiltSize ?? this.tiltSize,
        tiltFlow: tiltFlow ?? this.tiltFlow,
        jitterSize: jitterSize ?? this.jitterSize,
        jitterAngle: jitterAngle ?? this.jitterAngle,
        jitterFlow: jitterFlow ?? this.jitterFlow,
        scatter: scatter ?? this.scatter,
        jitterHue: jitterHue ?? this.jitterHue,
        jitterSat: jitterSat ?? this.jitterSat,
        jitterVal: jitterVal ?? this.jitterVal,
        count: count ?? this.count,
        grain: grain ?? this.grain,
        grainScale: grainScale ?? this.grainScale,
        grainStrength: grainStrength ?? this.grainStrength,
        smoothing: smoothing ?? this.smoothing,
        blend: blend ?? this.blend,
        erase: erase ?? this.erase,
        engine: engine ?? this.engine,
        smudge: smudge ?? this.smudge,
        wet: wet ?? this.wet,
        pigment: pigment ?? this.pigment,
        antialias: antialias ?? this.antialias,
        taper: taper ?? this.taper,
        builtin: builtin ?? this.builtin,
      );

  Map<String, dynamic> toJson() => {
        'id': id, 'name': name, 'category': category, 'tip': tip,
        'size': size, 'minSize': minSize, 'opacity': opacity, 'flow': flow, 'hardness': hardness,
        'spacing': spacing, 'angle': angle, 'roundness': roundness, 'rotation': rotation.name,
        'pressureSize': pressureSize, 'pressureFlow': pressureFlow, 'velocitySize': velocitySize,
        'tiltSize': tiltSize, 'tiltFlow': tiltFlow,
        'jitterSize': jitterSize, 'jitterAngle': jitterAngle, 'jitterFlow': jitterFlow, 'scatter': scatter,
        'jitterHue': jitterHue, 'jitterSat': jitterSat, 'jitterVal': jitterVal, 'count': count,
        'grain': grain, 'grainScale': grainScale, 'grainStrength': grainStrength,
        'smoothing': smoothing, 'blend': blend.name, 'erase': erase, 'engine': engine.name,
        'smudge': smudge, 'wet': wet, 'pigment': pigment, 'antialias': antialias, 'taper': taper,
      };

  static BrushPreset fromJson(dynamic j) {
    final m = j as Map<String, dynamic>;
    double d(String k, double def) => (m[k] as num?)?.toDouble() ?? def;
    return BrushPreset(
      id: m['id'] as String? ?? newId('b'),
      name: m['name'] as String? ?? 'Brush',
      category: m['category'] as String? ?? 'custom',
      tip: m['tip'] as String? ?? 'round',
      size: d('size', 20), minSize: d('minSize', 0.1), opacity: d('opacity', 1), flow: d('flow', 1),
      hardness: d('hardness', 0.8), spacing: d('spacing', 0.1), angle: d('angle', 0), roundness: d('roundness', 1),
      rotation: BrushRotation.values.firstWhere((r) => r.name == m['rotation'], orElse: () => BrushRotation.fixed),
      pressureSize: d('pressureSize', 1), pressureFlow: d('pressureFlow', 0), velocitySize: d('velocitySize', 0),
      tiltSize: d('tiltSize', 0), tiltFlow: d('tiltFlow', 0),
      jitterSize: d('jitterSize', 0), jitterAngle: d('jitterAngle', 0), jitterFlow: d('jitterFlow', 0), scatter: d('scatter', 0),
      jitterHue: d('jitterHue', 0), jitterSat: d('jitterSat', 0), jitterVal: d('jitterVal', 0),
      count: (m['count'] as num?)?.toInt() ?? 1,
      grain: m['grain'] as String? ?? '', grainScale: d('grainScale', 1), grainStrength: d('grainStrength', 0.6),
      smoothing: d('smoothing', 0.3),
      blend: LayerBlend.values.firstWhere((b) => b.name == m['blend'], orElse: () => LayerBlend.normal),
      erase: m['erase'] as bool? ?? false,
      engine: BrushEngine.values.firstWhere((e) => e.name == m['engine'], orElse: () => BrushEngine.paint),
      smudge: d('smudge', 0.6), wet: d('wet', 0.5), pigment: m['pigment'] as bool? ?? true,
      antialias: m['antialias'] as bool? ?? true, taper: d('taper', 0),
    );
  }
}

String brushCategoryLabel(String c) => switch (c) {
      'sketch' => tr('Boceto', 'Sketch'),
      'ink' => tr('Tinta', 'Ink'),
      'paint' => tr('Pintura', 'Paint'),
      'airbrush' => tr('Aerógrafo', 'Airbrush'),
      'dry' => tr('Medios secos', 'Dry media'),
      'marker' => tr('Rotuladores', 'Markers'),
      'pixel' => tr('Pixel art', 'Pixel art'),
      'fx' => tr('Efectos', 'Effects'),
      'blend' => tr('Mezcla y difuminado', 'Blend & smudge'),
      'erase' => tr('Borradores', 'Erasers'),
      _ => tr('Personalizados', 'Custom'),
    };

const List<String> kBrushCategories = ['sketch', 'ink', 'paint', 'airbrush', 'dry', 'marker', 'pixel', 'fx', 'blend', 'erase', 'custom'];

/// Factory brushes shipped with the app.
List<BrushPreset> builtinBrushes() => [
      // ---- sketch ----
      BrushPreset(id: 'pencil_hb', name: tr('Lápiz HB', 'HB pencil'), category: 'sketch', tip: 'pencil', size: 6, minSize: 0.45, opacity: 0.9, flow: 0.55, spacing: 0.12, pressureSize: 0.6, pressureFlow: 0.8, grain: 'paper', grainStrength: 0.7, jitterAngle: 1, rotation: BrushRotation.random, smoothing: 0.25, builtin: true),
      BrushPreset(id: 'pencil_6b', name: tr('Lápiz 6B', '6B pencil'), category: 'sketch', tip: 'pencil', size: 14, minSize: 0.5, opacity: 1, flow: 0.7, spacing: 0.1, pressureSize: 0.5, pressureFlow: 0.9, tiltSize: 0.6, grain: 'rough', grainStrength: 0.8, jitterAngle: 1, rotation: BrushRotation.random, smoothing: 0.25, builtin: true),
      BrushPreset(id: 'mechanical', name: tr('Portaminas', 'Mechanical pencil'), category: 'sketch', tip: 'round', size: 3, minSize: 0.7, hardness: 0.7, opacity: 0.9, flow: 0.8, spacing: 0.15, pressureSize: 0.3, pressureFlow: 0.6, smoothing: 0.3, builtin: true),
      BrushPreset(id: 'sketch_blue', name: tr('Lápiz de boceto', 'Sketch pencil'), category: 'sketch', tip: 'pencil', size: 10, minSize: 0.4, opacity: 0.7, flow: 0.5, spacing: 0.12, pressureSize: 0.7, pressureFlow: 0.7, grain: 'paper', grainStrength: 0.5, rotation: BrushRotation.random, jitterAngle: 1, builtin: true),
      // ---- ink ----
      BrushPreset(id: 'ink_pen', name: tr('Pluma de tinta', 'Ink pen'), category: 'ink', tip: 'round', size: 8, minSize: 0.08, hardness: 1, spacing: 0.06, pressureSize: 1, velocitySize: 0.25, smoothing: 0.5, taper: 3, builtin: true),
      BrushPreset(id: 'g_pen', name: tr('Plumilla G', 'G-pen'), category: 'ink', tip: 'round', size: 12, minSize: 0.03, hardness: 1, spacing: 0.05, pressureSize: 1, velocitySize: 0.4, smoothing: 0.55, taper: 4, builtin: true),
      BrushPreset(id: 'fineliner', name: tr('Estilógrafo', 'Fineliner'), category: 'ink', tip: 'round', size: 4, minSize: 1, hardness: 1, spacing: 0.08, pressureSize: 0, smoothing: 0.45, builtin: true),
      BrushPreset(id: 'brush_pen', name: tr('Pincel de tinta', 'Brush pen'), category: 'ink', tip: 'round', size: 28, minSize: 0.02, hardness: 0.95, spacing: 0.04, pressureSize: 1, velocitySize: 0.5, smoothing: 0.5, taper: 3, builtin: true),
      BrushPreset(id: 'calligraphy', name: tr('Caligrafía', 'Calligraphy'), category: 'ink', tip: 'round', size: 24, minSize: 0.6, hardness: 1, spacing: 0.03, angle: -40, roundness: 0.18, pressureSize: 0.3, smoothing: 0.5, builtin: true),
      BrushPreset(id: 'dry_ink', name: tr('Tinta seca', 'Dry ink'), category: 'ink', tip: 'bristle', size: 26, minSize: 0.3, spacing: 0.05, pressureSize: 0.8, pressureFlow: 0.4, rotation: BrushRotation.direction, grain: 'rough', grainStrength: 0.5, smoothing: 0.4, builtin: true),
      // ---- paint ----
      BrushPreset(id: 'round_brush', name: tr('Pincel redondo', 'Round brush'), category: 'paint', tip: 'round', size: 30, minSize: 0.3, hardness: 0.75, opacity: 1, flow: 0.9, spacing: 0.08, pressureSize: 0.6, pressureFlow: 0.3, smoothing: 0.3, builtin: true),
      BrushPreset(id: 'soft_brush', name: tr('Pincel suave', 'Soft brush'), category: 'paint', tip: 'round', size: 60, minSize: 0.5, hardness: 0.1, opacity: 1, flow: 0.5, spacing: 0.08, pressureSize: 0.3, pressureFlow: 0.8, smoothing: 0.2, builtin: true),
      BrushPreset(id: 'oil', name: tr('Óleo', 'Oil paint'), category: 'paint', tip: 'flat', size: 46, minSize: 0.6, flow: 0.95, spacing: 0.05, rotation: BrushRotation.direction, pressureSize: 0.4, engine: BrushEngine.mixer, wet: 0.55, smudge: 0.5, jitterVal: 0.05, grain: 'canvas', grainStrength: 0.25, smoothing: 0.3, builtin: true),
      BrushPreset(id: 'gouache', name: tr('Gouache', 'Gouache'), category: 'paint', tip: 'bristle', size: 40, minSize: 0.5, opacity: 1, flow: 0.85, spacing: 0.06, rotation: BrushRotation.direction, pressureSize: 0.5, pressureFlow: 0.4, engine: BrushEngine.mixer, wet: 0.25, smudge: 0.25, smoothing: 0.3, builtin: true),
      BrushPreset(id: 'watercolor', name: tr('Acuarela', 'Watercolour'), category: 'paint', tip: 'watercolor', size: 70, minSize: 0.5, opacity: 0.55, flow: 0.25, spacing: 0.1, pressureSize: 0.5, pressureFlow: 0.6, jitterAngle: 1, rotation: BrushRotation.random, grain: 'paper', grainStrength: 0.35, blend: LayerBlend.multiply, smoothing: 0.3, builtin: true),
      BrushPreset(id: 'wet_watercolor', name: tr('Acuarela húmeda', 'Wet watercolour'), category: 'paint', tip: 'cloud', size: 90, minSize: 0.6, opacity: 0.8, flow: 0.3, spacing: 0.12, engine: BrushEngine.mixer, wet: 0.8, smudge: 0.75, jitterAngle: 1, rotation: BrushRotation.random, grain: 'paper', grainStrength: 0.3, smoothing: 0.3, builtin: true),
      BrushPreset(id: 'acrylic', name: tr('Acrílico', 'Acrylic'), category: 'paint', tip: 'flat', size: 50, minSize: 0.7, opacity: 1, flow: 1, spacing: 0.05, rotation: BrushRotation.direction, pressureSize: 0.3, jitterVal: 0.04, jitterHue: 0.01, grain: 'canvas', grainStrength: 0.2, smoothing: 0.3, builtin: true),
      // ---- airbrush ----
      BrushPreset(id: 'airbrush', name: tr('Aerógrafo', 'Airbrush'), category: 'airbrush', tip: 'round', size: 120, minSize: 0.8, hardness: 0, opacity: 1, flow: 0.08, spacing: 0.06, pressureSize: 0.1, pressureFlow: 1, smoothing: 0.2, builtin: true),
      BrushPreset(id: 'spray', name: tr('Spray', 'Spray'), category: 'airbrush', tip: 'splatter', size: 110, minSize: 0.8, opacity: 1, flow: 0.35, spacing: 0.12, jitterAngle: 1, rotation: BrushRotation.random, scatter: 0.25, pressureFlow: 0.8, smoothing: 0.2, builtin: true),
      // ---- dry media ----
      BrushPreset(id: 'charcoal', name: tr('Carboncillo', 'Charcoal'), category: 'dry', tip: 'charcoal', size: 34, minSize: 0.5, opacity: 0.95, flow: 0.6, spacing: 0.08, pressureSize: 0.4, pressureFlow: 0.9, tiltSize: 0.7, jitterAngle: 1, rotation: BrushRotation.random, grain: 'rough', grainStrength: 0.85, smoothing: 0.25, builtin: true),
      BrushPreset(id: 'chalk', name: tr('Tiza', 'Chalk'), category: 'dry', tip: 'chalk', size: 30, minSize: 0.6, opacity: 1, flow: 0.75, spacing: 0.08, pressureSize: 0.3, pressureFlow: 0.7, jitterAngle: 1, rotation: BrushRotation.random, grain: 'rough', grainStrength: 0.75, smoothing: 0.25, builtin: true),
      BrushPreset(id: 'pastel', name: tr('Pastel', 'Pastel'), category: 'dry', tip: 'chalk', size: 44, minSize: 0.7, opacity: 0.9, flow: 0.5, spacing: 0.07, pressureFlow: 0.8, jitterAngle: 1, rotation: BrushRotation.random, grain: 'paper', grainStrength: 0.6, smoothing: 0.25, builtin: true),
      BrushPreset(id: 'crayon', name: tr('Crayón', 'Crayon'), category: 'dry', tip: 'pencil', size: 18, minSize: 0.7, opacity: 1, flow: 0.8, spacing: 0.1, pressureFlow: 0.6, jitterAngle: 1, rotation: BrushRotation.random, grain: 'rough', grainStrength: 0.9, smoothing: 0.3, builtin: true),
      // ---- markers ----
      BrushPreset(id: 'marker', name: tr('Rotulador', 'Marker'), category: 'marker', tip: 'round', size: 26, minSize: 0.85, hardness: 0.9, opacity: 0.6, flow: 1, spacing: 0.05, pressureSize: 0.15, blend: LayerBlend.multiply, smoothing: 0.35, builtin: true),
      BrushPreset(id: 'chisel_marker', name: tr('Rotulador biselado', 'Chisel marker'), category: 'marker', tip: 'square', size: 30, minSize: 0.9, opacity: 0.6, flow: 1, spacing: 0.04, angle: 45, roundness: 0.35, pressureSize: 0.1, blend: LayerBlend.multiply, smoothing: 0.35, builtin: true),
      BrushPreset(id: 'highlighter', name: tr('Resaltador', 'Highlighter'), category: 'marker', tip: 'square', size: 36, minSize: 1, opacity: 0.4, flow: 1, spacing: 0.04, angle: 0, roundness: 0.5, pressureSize: 0, blend: LayerBlend.multiply, smoothing: 0.4, builtin: true),
      // ---- pixel ----
      BrushPreset(id: 'pixel', name: tr('Pixel', 'Pixel'), category: 'pixel', tip: 'square', size: 1, minSize: 1, hardness: 1, spacing: 1, pressureSize: 0, smoothing: 0, antialias: false, builtin: true),
      BrushPreset(id: 'pixel_3', name: tr('Pixel 3×3', 'Pixel 3×3'), category: 'pixel', tip: 'square', size: 3, minSize: 1, hardness: 1, spacing: 0.34, pressureSize: 0, smoothing: 0, antialias: false, builtin: true),
      BrushPreset(id: 'dither', name: tr('Tramado pixel', 'Pixel dither'), category: 'pixel', tip: 'square', size: 1, minSize: 1, spacing: 2, pressureSize: 0, smoothing: 0, antialias: false, scatter: 2, count: 2, builtin: true),
      // ---- fx ----
      BrushPreset(id: 'sparkle', name: tr('Destellos', 'Sparkles'), category: 'fx', tip: 'star', size: 40, minSize: 0.5, spacing: 0.5, jitterSize: 0.8, jitterAngle: 1, rotation: BrushRotation.random, scatter: 1.2, blend: LayerBlend.add, jitterFlow: 0.5, smoothing: 0.2, builtin: true),
      BrushPreset(id: 'clouds', name: tr('Nubes', 'Clouds'), category: 'fx', tip: 'cloud', size: 140, minSize: 0.7, opacity: 1, flow: 0.25, spacing: 0.18, jitterSize: 0.3, jitterAngle: 1, rotation: BrushRotation.random, scatter: 0.2, smoothing: 0.2, builtin: true),
      BrushPreset(id: 'foliage', name: tr('Follaje', 'Foliage'), category: 'fx', tip: 'leaf', size: 44, minSize: 0.6, spacing: 0.35, jitterSize: 0.6, jitterAngle: 1, rotation: BrushRotation.random, scatter: 0.9, jitterHue: 0.06, jitterVal: 0.25, count: 2, smoothing: 0.2, builtin: true),
      BrushPreset(id: 'splatter', name: tr('Salpicadura', 'Splatter'), category: 'fx', tip: 'splatter', size: 90, minSize: 0.6, spacing: 0.4, jitterSize: 0.6, jitterAngle: 1, rotation: BrushRotation.random, scatter: 0.6, smoothing: 0.1, builtin: true),
      BrushPreset(id: 'sponge', name: tr('Esponja', 'Sponge'), category: 'fx', tip: 'sponge', size: 80, minSize: 0.8, flow: 0.6, spacing: 0.25, jitterAngle: 1, rotation: BrushRotation.random, pressureFlow: 0.6, smoothing: 0.2, builtin: true),
      BrushPreset(id: 'rainbow', name: tr('Arcoíris', 'Rainbow'), category: 'fx', tip: 'round', size: 24, minSize: 0.4, hardness: 0.9, spacing: 0.08, jitterHue: 1, pressureSize: 0.8, smoothing: 0.4, builtin: true),
      // ---- blend ----
      BrushPreset(id: 'smudge', name: tr('Dedo', 'Smudge'), category: 'blend', tip: 'round', size: 40, minSize: 0.7, hardness: 0.3, spacing: 0.08, engine: BrushEngine.smudge, smudge: 0.75, pressureSize: 0.2, smoothing: 0.2, builtin: true),
      BrushPreset(id: 'blender', name: tr('Difuminador', 'Blender'), category: 'blend', tip: 'round', size: 70, minSize: 0.8, hardness: 0, spacing: 0.1, engine: BrushEngine.smudge, smudge: 0.45, smoothing: 0.2, builtin: true),
      BrushPreset(id: 'bristle_smudge', name: tr('Arrastre de cerdas', 'Bristle smear'), category: 'blend', tip: 'bristle', size: 50, minSize: 0.8, spacing: 0.06, engine: BrushEngine.smudge, smudge: 0.85, rotation: BrushRotation.direction, smoothing: 0.2, builtin: true),
      BrushPreset(id: 'mixer', name: tr('Mezclador de pigmento', 'Pigment mixer'), category: 'blend', tip: 'round', size: 46, minSize: 0.6, hardness: 0.5, flow: 0.7, spacing: 0.06, engine: BrushEngine.mixer, wet: 0.7, smudge: 0.6, pressureSize: 0.3, smoothing: 0.25, builtin: true),
      // ---- erasers ----
      BrushPreset(id: 'eraser_hard', name: tr('Borrador duro', 'Hard eraser'), category: 'erase', tip: 'round', size: 30, minSize: 0.5, hardness: 1, spacing: 0.06, pressureSize: 0.5, erase: true, smoothing: 0.2, builtin: true),
      BrushPreset(id: 'eraser_soft', name: tr('Borrador suave', 'Soft eraser'), category: 'erase', tip: 'round', size: 60, minSize: 0.6, hardness: 0.1, flow: 0.5, spacing: 0.08, pressureFlow: 0.8, pressureSize: 0.2, erase: true, smoothing: 0.2, builtin: true),
      BrushPreset(id: 'eraser_pixel', name: tr('Borrador pixel', 'Pixel eraser'), category: 'erase', tip: 'square', size: 1, minSize: 1, spacing: 1, pressureSize: 0, erase: true, antialias: false, smoothing: 0, builtin: true),
      BrushPreset(id: 'eraser_kneaded', name: tr('Goma moldeable', 'Kneaded eraser'), category: 'erase', tip: 'charcoal', size: 50, minSize: 0.7, flow: 0.35, spacing: 0.1, pressureFlow: 0.9, jitterAngle: 1, rotation: BrushRotation.random, erase: true, smoothing: 0.2, builtin: true),
    ];
