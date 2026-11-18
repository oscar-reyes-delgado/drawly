import 'dart:ui';

/// Non-destructive layer styles (drop shadow, glow, outline, bevel, overlay).
class LayerFx {
  const LayerFx({
    this.shadow = false,
    this.shadowColor = const Color(0xFF000000),
    this.shadowDx = 6,
    this.shadowDy = 6,
    this.shadowBlur = 8,
    this.shadowOpacity = 0.6,
    this.glow = false,
    this.glowColor = const Color(0xFFFFE680),
    this.glowBlur = 12,
    this.glowOpacity = 0.85,
    this.innerGlow = false,
    this.stroke = false,
    this.strokeColor = const Color(0xFF000000),
    this.strokeWidth = 3,
    this.strokeOpacity = 1,
    this.bevel = false,
    this.bevelSize = 4,
    this.bevelAngle = 135,
    this.bevelHighlight = 0.7,
    this.bevelShadow = 0.6,
    this.overlay = false,
    this.overlayColor = const Color(0xFFFF0000),
    this.overlayOpacity = 1,
  });

  final bool shadow;
  final Color shadowColor;
  final double shadowDx, shadowDy, shadowBlur, shadowOpacity;

  final bool glow;
  final Color glowColor;
  final double glowBlur, glowOpacity;
  final bool innerGlow;

  final bool stroke;
  final Color strokeColor;
  final double strokeWidth, strokeOpacity;

  final bool bevel;
  final double bevelSize, bevelAngle, bevelHighlight, bevelShadow;

  final bool overlay;
  final Color overlayColor;
  final double overlayOpacity;

  static const LayerFx none = LayerFx();

  bool get any => shadow || glow || stroke || bevel || overlay;

  /// How far the effects reach outside the layer content.
  double get outset {
    var o = 0.0;
    if (shadow) o = shadowBlur * 2 + (shadowDx.abs() > shadowDy.abs() ? shadowDx.abs() : shadowDy.abs());
    if (glow && glowBlur * 2 > o) o = glowBlur * 2;
    if (stroke && strokeWidth > o) o = strokeWidth;
    return o + 2;
  }

  LayerFx copyWith({
    bool? shadow,
    Color? shadowColor,
    double? shadowDx,
    double? shadowDy,
    double? shadowBlur,
    double? shadowOpacity,
    bool? glow,
    Color? glowColor,
    double? glowBlur,
    double? glowOpacity,
    bool? innerGlow,
    bool? stroke,
    Color? strokeColor,
    double? strokeWidth,
    double? strokeOpacity,
    bool? bevel,
    double? bevelSize,
    double? bevelAngle,
    double? bevelHighlight,
    double? bevelShadow,
    bool? overlay,
    Color? overlayColor,
    double? overlayOpacity,
  }) =>
      LayerFx(
        shadow: shadow ?? this.shadow,
        shadowColor: shadowColor ?? this.shadowColor,
        shadowDx: shadowDx ?? this.shadowDx,
        shadowDy: shadowDy ?? this.shadowDy,
        shadowBlur: shadowBlur ?? this.shadowBlur,
        shadowOpacity: shadowOpacity ?? this.shadowOpacity,
        glow: glow ?? this.glow,
        glowColor: glowColor ?? this.glowColor,
        glowBlur: glowBlur ?? this.glowBlur,
        glowOpacity: glowOpacity ?? this.glowOpacity,
        innerGlow: innerGlow ?? this.innerGlow,
        stroke: stroke ?? this.stroke,
        strokeColor: strokeColor ?? this.strokeColor,
        strokeWidth: strokeWidth ?? this.strokeWidth,
        strokeOpacity: strokeOpacity ?? this.strokeOpacity,
        bevel: bevel ?? this.bevel,
        bevelSize: bevelSize ?? this.bevelSize,
        bevelAngle: bevelAngle ?? this.bevelAngle,
        bevelHighlight: bevelHighlight ?? this.bevelHighlight,
        bevelShadow: bevelShadow ?? this.bevelShadow,
        overlay: overlay ?? this.overlay,
        overlayColor: overlayColor ?? this.overlayColor,
        overlayOpacity: overlayOpacity ?? this.overlayOpacity,
      );

  Map<String, dynamic> toJson() => {
        'shadow': shadow,
        'shadowColor': shadowColor.toARGB32(),
        'shadowDx': shadowDx,
        'shadowDy': shadowDy,
        'shadowBlur': shadowBlur,
        'shadowOpacity': shadowOpacity,
        'glow': glow,
        'glowColor': glowColor.toARGB32(),
        'glowBlur': glowBlur,
        'glowOpacity': glowOpacity,
        'innerGlow': innerGlow,
        'stroke': stroke,
        'strokeColor': strokeColor.toARGB32(),
        'strokeWidth': strokeWidth,
        'strokeOpacity': strokeOpacity,
        'bevel': bevel,
        'bevelSize': bevelSize,
        'bevelAngle': bevelAngle,
        'bevelHighlight': bevelHighlight,
        'bevelShadow': bevelShadow,
        'overlay': overlay,
        'overlayColor': overlayColor.toARGB32(),
        'overlayOpacity': overlayOpacity,
      };

  static LayerFx fromJson(dynamic j) {
    if (j == null) return LayerFx.none;
    final m = j as Map<String, dynamic>;
    double d(String k, double def) => (m[k] as num?)?.toDouble() ?? def;
    bool b(String k) => m[k] as bool? ?? false;
    Color c(String k, int def) => Color(m[k] as int? ?? def);
    return LayerFx(
      shadow: b('shadow'),
      shadowColor: c('shadowColor', 0xFF000000),
      shadowDx: d('shadowDx', 6),
      shadowDy: d('shadowDy', 6),
      shadowBlur: d('shadowBlur', 8),
      shadowOpacity: d('shadowOpacity', 0.6),
      glow: b('glow'),
      glowColor: c('glowColor', 0xFFFFE680),
      glowBlur: d('glowBlur', 12),
      glowOpacity: d('glowOpacity', 0.85),
      innerGlow: b('innerGlow'),
      stroke: b('stroke'),
      strokeColor: c('strokeColor', 0xFF000000),
      strokeWidth: d('strokeWidth', 3),
      strokeOpacity: d('strokeOpacity', 1),
      bevel: b('bevel'),
      bevelSize: d('bevelSize', 4),
      bevelAngle: d('bevelAngle', 135),
      bevelHighlight: d('bevelHighlight', 0.7),
      bevelShadow: d('bevelShadow', 0.6),
      overlay: b('overlay'),
      overlayColor: c('overlayColor', 0xFFFF0000),
      overlayOpacity: d('overlayOpacity', 1),
    );
  }
}
