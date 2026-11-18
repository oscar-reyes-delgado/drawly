import 'dart:ui';

import '../core/i18n.dart';
import 'gradient.dart';

/// How a filter is executed.
enum FilterKind {
  /// 4x5 colour matrix (GPU colour filter, free to nest).
  matrix,

  /// 256-entry per-channel lookup table.
  lut,

  /// Luminance indexed lookup table (gradient map, threshold…).
  lumaLut,

  /// Gaussian blur through the engine image filter.
  blur,

  /// Morphology (dilate / erode) image filter.
  morph,

  /// Fragment shader from `shaders/<shader>.frag`.
  shader,

  /// Blur + screen composite.
  glow,
}

class ParamDef {
  const ParamDef(this.key, this.es, this.en, this.min, this.max, this.def, {this.decimals = 0, this.unit = ''});
  final String key, es, en, unit;
  final double min, max, def;
  final int decimals;
  String get label => tr(es, en);
}

class FilterDef {
  const FilterDef({
    required this.id,
    required this.es,
    required this.en,
    required this.category,
    required this.kind,
    this.params = const [],
    this.shader,
    this.hasCurve = false,
    this.hasGradient = false,
    this.hasColor = false,
    this.adjustment = false,
  });

  final String id, es, en, category;
  final FilterKind kind;
  final List<ParamDef> params;
  final String? shader;
  final bool hasCurve, hasGradient, hasColor;

  /// Colour adjustments are offered as adjustment layers first.
  final bool adjustment;

  String get label => tr(es, en);

  FilterSpec get defaults => FilterSpec(
        type: id,
        p: {for (final d in params) d.key: d.def},
        gradient: hasGradient ? GradientSpec.blackWhite : null,
        color: hasColor ? const Color(0xFF00FF00) : null,
      );
}

/// A concrete, serialisable filter invocation.
class FilterSpec {
  const FilterSpec({
    required this.type,
    this.p = const {},
    this.curves = const {},
    this.gradient,
    this.color,
  });

  final String type;
  final Map<String, double> p;

  /// Curve control points (0..1) keyed by channel: 'rgb', 'r', 'g', 'b'.
  final Map<String, List<Offset>> curves;
  final GradientSpec? gradient;
  final Color? color;

  FilterDef get def => filterDef(type);

  double v(String key) => p[key] ?? def.params.firstWhere((d) => d.key == key).def;

  FilterSpec withParam(String key, double value) => FilterSpec(
        type: type,
        p: {...p, key: value},
        curves: curves,
        gradient: gradient,
        color: color,
      );

  FilterSpec copyWith({Map<String, double>? p, Map<String, List<Offset>>? curves, GradientSpec? gradient, Color? color}) => FilterSpec(
        type: type,
        p: p ?? this.p,
        curves: curves ?? this.curves,
        gradient: gradient ?? this.gradient,
        color: color ?? this.color,
      );

  Map<String, dynamic> toJson() => {
        'type': type,
        'p': p,
        if (curves.isNotEmpty)
          'curves': {
            for (final e in curves.entries) e.key: [for (final o in e.value) [o.dx, o.dy]],
          },
        if (gradient != null) 'gradient': gradient!.toJson(),
        if (color != null) 'color': color!.toARGB32(),
      };

  static FilterSpec fromJson(dynamic j) {
    final m = j as Map<String, dynamic>;
    return FilterSpec(
      type: m['type'] as String,
      p: ((m['p'] as Map?) ?? const {}).map((k, v) => MapEntry(k as String, (v as num).toDouble())),
      curves: ((m['curves'] as Map?) ?? const {}).map((k, v) => MapEntry(
            k as String,
            (v as List).map((e) => Offset(((e as List)[0] as num).toDouble(), (e[1] as num).toDouble())).toList(),
          )),
      gradient: m['gradient'] == null ? null : GradientSpec.fromJson(m['gradient']),
      color: m['color'] == null ? null : Color(m['color'] as int),
    );
  }
}

const String kCatAdjust = 'adjust';
const String kCatBlur = 'blur';
const String kCatNoise = 'noise';
const String kCatStylize = 'stylize';
const String kCatArtistic = 'artistic';
const String kCatLens = 'lens';
const String kCatOther = 'other';

String filterCategoryLabel(String c) => switch (c) {
      kCatAdjust => tr('Ajustes', 'Adjustments'),
      kCatBlur => tr('Desenfoque y enfoque', 'Blur & sharpen'),
      kCatNoise => tr('Ruido y textura', 'Noise & texture'),
      kCatStylize => tr('Estilizar', 'Stylize'),
      kCatArtistic => tr('Artísticos', 'Artistic'),
      kCatLens => tr('Lente y luz', 'Lens & light'),
      _ => tr('Otros', 'Other'),
    };

const List<FilterDef> kFilters = [
  // ---- colour adjustments -------------------------------------------------
  FilterDef(id: 'brightnessContrast', es: 'Brillo/Contraste', en: 'Brightness/Contrast', category: kCatAdjust, kind: FilterKind.matrix, adjustment: true, params: [
    ParamDef('brightness', 'Brillo', 'Brightness', -100, 100, 0),
    ParamDef('contrast', 'Contraste', 'Contrast', -100, 100, 0),
  ]),
  FilterDef(id: 'hueSaturation', es: 'Tono/Saturación', en: 'Hue/Saturation', category: kCatAdjust, kind: FilterKind.matrix, adjustment: true, params: [
    ParamDef('hue', 'Tono', 'Hue', -180, 180, 0, unit: '°'),
    ParamDef('saturation', 'Saturación', 'Saturation', -100, 100, 0),
    ParamDef('lightness', 'Luminosidad', 'Lightness', -100, 100, 0),
  ]),
  FilterDef(id: 'colorBalance', es: 'Balance de color', en: 'Colour balance', category: kCatAdjust, kind: FilterKind.matrix, adjustment: true, params: [
    ParamDef('cyanRed', 'Cian – Rojo', 'Cyan – Red', -100, 100, 0),
    ParamDef('magentaGreen', 'Magenta – Verde', 'Magenta – Green', -100, 100, 0),
    ParamDef('yellowBlue', 'Amarillo – Azul', 'Yellow – Blue', -100, 100, 0),
  ]),
  FilterDef(id: 'curves', es: 'Curvas', en: 'Curves', category: kCatAdjust, kind: FilterKind.lut, adjustment: true, hasCurve: true),
  FilterDef(id: 'levels', es: 'Niveles', en: 'Levels', category: kCatAdjust, kind: FilterKind.lut, adjustment: true, params: [
    ParamDef('inBlack', 'Entrada negro', 'Input black', 0, 255, 0),
    ParamDef('inWhite', 'Entrada blanco', 'Input white', 0, 255, 255),
    ParamDef('gamma', 'Gamma', 'Gamma', 0.1, 5, 1, decimals: 2),
    ParamDef('outBlack', 'Salida negro', 'Output black', 0, 255, 0),
    ParamDef('outWhite', 'Salida blanco', 'Output white', 0, 255, 255),
  ]),
  FilterDef(id: 'exposure', es: 'Exposición', en: 'Exposure', category: kCatAdjust, kind: FilterKind.lut, adjustment: true, params: [
    ParamDef('exposure', 'Exposición', 'Exposure', -4, 4, 0, decimals: 2),
    ParamDef('gamma', 'Gamma', 'Gamma', 0.2, 4, 1, decimals: 2),
  ]),
  FilterDef(id: 'temperature', es: 'Temperatura', en: 'Temperature', category: kCatAdjust, kind: FilterKind.matrix, adjustment: true, params: [
    ParamDef('temperature', 'Temperatura', 'Temperature', -100, 100, 0),
    ParamDef('tint', 'Matiz', 'Tint', -100, 100, 0),
  ]),
  FilterDef(id: 'invert', es: 'Invertir', en: 'Invert', category: kCatAdjust, kind: FilterKind.matrix, adjustment: true),
  FilterDef(id: 'grayscale', es: 'Escala de grises', en: 'Grayscale', category: kCatAdjust, kind: FilterKind.matrix, adjustment: true, params: [
    ParamDef('amount', 'Cantidad', 'Amount', 0, 100, 100),
  ]),
  FilterDef(id: 'sepia', es: 'Sepia', en: 'Sepia', category: kCatAdjust, kind: FilterKind.matrix, adjustment: true, params: [
    ParamDef('amount', 'Cantidad', 'Amount', 0, 100, 100),
  ]),
  FilterDef(id: 'posterize', es: 'Posterizar', en: 'Posterize', category: kCatAdjust, kind: FilterKind.lut, adjustment: true, params: [
    ParamDef('levels', 'Niveles', 'Levels', 2, 32, 4),
  ]),
  FilterDef(id: 'threshold', es: 'Umbral', en: 'Threshold', category: kCatAdjust, kind: FilterKind.lumaLut, adjustment: true, params: [
    ParamDef('level', 'Nivel', 'Level', 0, 255, 128),
  ]),
  FilterDef(id: 'gradientMap', es: 'Mapa de degradado', en: 'Gradient map', category: kCatAdjust, kind: FilterKind.lumaLut, adjustment: true, hasGradient: true),
  FilterDef(id: 'colorize', es: 'Colorear', en: 'Colorize', category: kCatAdjust, kind: FilterKind.lumaLut, adjustment: true, hasColor: true),

  // ---- blur & sharpen -----------------------------------------------------
  FilterDef(id: 'gaussianBlur', es: 'Desenfoque gaussiano', en: 'Gaussian blur', category: kCatBlur, kind: FilterKind.blur, params: [
    ParamDef('radius', 'Radio', 'Radius', 0, 150, 8, decimals: 1, unit: 'px'),
  ]),
  FilterDef(id: 'motionBlur', es: 'Desenfoque de movimiento', en: 'Motion blur', category: kCatBlur, kind: FilterKind.shader, shader: 'motion_blur', params: [
    ParamDef('angle', 'Ángulo', 'Angle', -180, 180, 0, unit: '°'),
    ParamDef('distance', 'Distancia', 'Distance', 0, 200, 30, unit: 'px'),
  ]),
  FilterDef(id: 'radialBlur', es: 'Desenfoque radial', en: 'Radial blur', category: kCatBlur, kind: FilterKind.shader, shader: 'radial_blur', params: [
    ParamDef('amount', 'Cantidad', 'Amount', 0, 100, 25),
    ParamDef('cx', 'Centro X', 'Centre X', 0, 100, 50, unit: '%'),
    ParamDef('cy', 'Centro Y', 'Centre Y', 0, 100, 50, unit: '%'),
    ParamDef('spin', 'Giro (0 = zoom)', 'Spin (0 = zoom)', 0, 1, 0),
  ]),
  FilterDef(id: 'sharpen', es: 'Enfocar', en: 'Sharpen', category: kCatBlur, kind: FilterKind.shader, shader: 'sharpen', params: [
    ParamDef('amount', 'Cantidad', 'Amount', 0, 300, 80, unit: '%'),
    ParamDef('radius', 'Radio', 'Radius', 0.5, 8, 1, decimals: 1, unit: 'px'),
  ]),
  FilterDef(id: 'denoise', es: 'Reducir ruido', en: 'Denoise', category: kCatBlur, kind: FilterKind.shader, shader: 'denoise', params: [
    ParamDef('strength', 'Fuerza', 'Strength', 0, 100, 50),
    ParamDef('radius', 'Radio', 'Radius', 1, 4, 2, decimals: 1, unit: 'px'),
  ]),

  // ---- noise / texture ----------------------------------------------------
  FilterDef(id: 'noise', es: 'Ruido', en: 'Noise', category: kCatNoise, kind: FilterKind.shader, shader: 'noise', params: [
    ParamDef('amount', 'Cantidad', 'Amount', 0, 100, 20),
    ParamDef('mono', 'Monocromo', 'Monochrome', 0, 1, 1),
    ParamDef('size', 'Tamaño', 'Size', 1, 8, 1, decimals: 1),
    ParamDef('seed', 'Semilla', 'Seed', 0, 100, 1),
  ]),
  FilterDef(id: 'grain', es: 'Grano de película', en: 'Film grain', category: kCatNoise, kind: FilterKind.shader, shader: 'noise', params: [
    ParamDef('amount', 'Cantidad', 'Amount', 0, 100, 12),
    ParamDef('mono', 'Monocromo', 'Monochrome', 0, 1, 1),
    ParamDef('size', 'Tamaño', 'Size', 1, 8, 2.5, decimals: 1),
    ParamDef('seed', 'Semilla', 'Seed', 0, 100, 7),
  ]),
  FilterDef(id: 'pixelate', es: 'Pixelar', en: 'Pixelate', category: kCatNoise, kind: FilterKind.shader, shader: 'pixelate', params: [
    ParamDef('size', 'Tamaño', 'Size', 1, 128, 8, unit: 'px'),
  ]),
  FilterDef(id: 'halftone', es: 'Semitonos', en: 'Halftone', category: kCatNoise, kind: FilterKind.shader, shader: 'halftone', params: [
    ParamDef('size', 'Tamaño', 'Size', 2, 64, 8, unit: 'px'),
    ParamDef('angle', 'Ángulo', 'Angle', 0, 90, 45, unit: '°'),
    ParamDef('color', 'Color (CMYK)', 'Colour (CMYK)', 0, 1, 0),
  ]),

  // ---- artistic -----------------------------------------------------------
  FilterDef(id: 'oilPaint', es: 'Óleo', en: 'Oil paint', category: kCatArtistic, kind: FilterKind.shader, shader: 'kuwahara', params: [
    ParamDef('radius', 'Radio', 'Radius', 1, 6, 4, unit: 'px'),
    ParamDef('paper', 'Papel', 'Paper', 0, 0, 0),
  ]),
  FilterDef(id: 'watercolor', es: 'Acuarela', en: 'Watercolour', category: kCatArtistic, kind: FilterKind.shader, shader: 'kuwahara', params: [
    ParamDef('radius', 'Radio', 'Radius', 1, 6, 3, unit: 'px'),
    ParamDef('paper', 'Papel', 'Paper', 0, 100, 60),
  ]),
  FilterDef(id: 'comic', es: 'Cómic', en: 'Comic', category: kCatArtistic, kind: FilterKind.shader, shader: 'comic', params: [
    ParamDef('levels', 'Niveles de color', 'Colour levels', 2, 12, 5),
    ParamDef('edge', 'Contorno', 'Outline', 0, 100, 60),
    ParamDef('dots', 'Trama de puntos', 'Dot screen', 0, 100, 0),
  ]),
  FilterDef(id: 'sketch', es: 'Boceto a lápiz', en: 'Pencil sketch', category: kCatArtistic, kind: FilterKind.shader, shader: 'edges', params: [
    ParamDef('strength', 'Fuerza', 'Strength', 0, 400, 150, unit: '%'),
    ParamDef('mode', 'Modo', 'Mode', 1, 1, 1),
  ]),

  // ---- stylize ------------------------------------------------------------
  FilterDef(id: 'edgeDetect', es: 'Detectar bordes', en: 'Find edges', category: kCatStylize, kind: FilterKind.shader, shader: 'edges', params: [
    ParamDef('strength', 'Fuerza', 'Strength', 0, 400, 150, unit: '%'),
    ParamDef('mode', 'Modo', 'Mode', 0, 0, 0),
  ]),
  FilterDef(id: 'emboss', es: 'Relieve', en: 'Emboss', category: kCatStylize, kind: FilterKind.shader, shader: 'edges', params: [
    ParamDef('strength', 'Fuerza', 'Strength', 0, 400, 150, unit: '%'),
    ParamDef('mode', 'Modo', 'Mode', 2, 2, 2),
    ParamDef('angle', 'Ángulo', 'Angle', -180, 180, 135, unit: '°'),
  ]),
  FilterDef(id: 'glow', es: 'Resplandor', en: 'Glow', category: kCatLens, kind: FilterKind.glow, params: [
    ParamDef('radius', 'Radio', 'Radius', 0, 100, 16, unit: 'px'),
    ParamDef('intensity', 'Intensidad', 'Intensity', 0, 100, 60),
  ]),
  FilterDef(id: 'vignette', es: 'Viñeta', en: 'Vignette', category: kCatLens, kind: FilterKind.shader, shader: 'vignette', params: [
    ParamDef('amount', 'Cantidad', 'Amount', -100, 100, 50),
    ParamDef('size', 'Tamaño', 'Size', 0, 100, 50),
    ParamDef('softness', 'Suavidad', 'Softness', 1, 100, 50),
  ]),
  FilterDef(id: 'chromaticAberration', es: 'Aberración cromática', en: 'Chromatic aberration', category: kCatLens, kind: FilterKind.shader, shader: 'chromatic', params: [
    ParamDef('amount', 'Cantidad', 'Amount', 0, 50, 6, decimals: 1, unit: 'px'),
    ParamDef('radial', 'Radial', 'Radial', 0, 1, 1),
  ]),
  FilterDef(id: 'lensDistortion', es: 'Corrección de lente', en: 'Lens correction', category: kCatLens, kind: FilterKind.shader, shader: 'lens', params: [
    ParamDef('amount', 'Distorsión', 'Distortion', -100, 100, 30),
    ParamDef('zoom', 'Zoom', 'Zoom', 50, 200, 100, unit: '%'),
  ]),
  FilterDef(id: 'chromaKey', es: 'Pantalla verde (chroma key)', en: 'Chroma key', category: kCatOther, kind: FilterKind.shader, shader: 'chroma_key', hasColor: true, params: [
    ParamDef('tolerance', 'Tolerancia', 'Tolerance', 0, 100, 30),
    ParamDef('softness', 'Suavidad', 'Softness', 0, 100, 15),
    ParamDef('spill', 'Quitar derrame', 'Despill', 0, 100, 50),
  ]),
  FilterDef(id: 'dilate', es: 'Expandir (máximo)', en: 'Dilate (maximum)', category: kCatOther, kind: FilterKind.morph, params: [
    ParamDef('radius', 'Radio', 'Radius', 0, 40, 2, unit: 'px'),
  ]),
  FilterDef(id: 'erode', es: 'Contraer (mínimo)', en: 'Erode (minimum)', category: kCatOther, kind: FilterKind.morph, params: [
    ParamDef('radius', 'Radio', 'Radius', 0, 40, 2, unit: 'px'),
  ]),
];

final Map<String, FilterDef> _filterIndex = {for (final f in kFilters) f.id: f};

FilterDef filterDef(String id) => _filterIndex[id] ?? kFilters.first;

/// Names of every shader asset the filter list needs.
Set<String> get filterShaderNames => {
      for (final f in kFilters)
        if (f.shader != null) f.shader!,
    };
