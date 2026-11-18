import 'dart:ui';

import '../core/i18n.dart';
import 'vector.dart';

// ---------------------------------------------------------------------------
// Text
// ---------------------------------------------------------------------------

enum TextAnimKind { none, typewriter, fadeIn, wave, bounce, scaleIn, slideUp, shake }

extension TextAnimKindLabel on TextAnimKind {
  String get label => switch (this) {
        TextAnimKind.none => tr('Ninguna', 'None'),
        TextAnimKind.typewriter => tr('Máquina de escribir', 'Typewriter'),
        TextAnimKind.fadeIn => tr('Aparecer', 'Fade in'),
        TextAnimKind.wave => tr('Onda', 'Wave'),
        TextAnimKind.bounce => tr('Rebote', 'Bounce'),
        TextAnimKind.scaleIn => tr('Escalar', 'Scale in'),
        TextAnimKind.slideUp => tr('Deslizar', 'Slide up'),
        TextAnimKind.shake => tr('Temblor', 'Shake'),
      };
}

enum TextUnit { letter, word, line }

class TextSpec {
  const TextSpec({
    this.text = '',
    this.font = '',
    this.size = 64,
    this.color = const Color(0xFF000000),
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.align = 0,
    this.letterSpacing = 0,
    this.lineHeight = 1.2,
    this.boxWidth = 0,
    this.pos = Offset.zero,
    this.strokeColor = const Color(0xFFFFFFFF),
    this.strokeWidth = 0,
    this.path,
    this.pathOffset = 0,
    this.anim = TextAnimKind.none,
    this.animUnit = TextUnit.letter,
    this.animStart = 0,
    this.animStagger = 2,
    this.animDuration = 8,
    this.animAmount = 20,
  });

  final String text;

  /// Font family ('' = app default).
  final String font;
  final double size;
  final Color color;
  final bool bold, italic, underline;

  /// 0 left, 1 centre, 2 right.
  final int align;
  final double letterSpacing, lineHeight;

  /// Wrap width (0 = no wrapping).
  final double boxWidth;
  final Offset pos;
  final Color strokeColor;
  final double strokeWidth;

  /// When set the glyphs follow this path.
  final VPath? path;
  final double pathOffset;

  final TextAnimKind anim;
  final TextUnit animUnit;
  final int animStart;

  /// Delay in frames between consecutive units and duration per unit.
  final double animStagger, animDuration, animAmount;

  TextSpec copyWith({
    String? text,
    String? font,
    double? size,
    Color? color,
    bool? bold,
    bool? italic,
    bool? underline,
    int? align,
    double? letterSpacing,
    double? lineHeight,
    double? boxWidth,
    Offset? pos,
    Color? strokeColor,
    double? strokeWidth,
    VPath? path,
    bool clearPath = false,
    double? pathOffset,
    TextAnimKind? anim,
    TextUnit? animUnit,
    int? animStart,
    double? animStagger,
    double? animDuration,
    double? animAmount,
  }) =>
      TextSpec(
        text: text ?? this.text,
        font: font ?? this.font,
        size: size ?? this.size,
        color: color ?? this.color,
        bold: bold ?? this.bold,
        italic: italic ?? this.italic,
        underline: underline ?? this.underline,
        align: align ?? this.align,
        letterSpacing: letterSpacing ?? this.letterSpacing,
        lineHeight: lineHeight ?? this.lineHeight,
        boxWidth: boxWidth ?? this.boxWidth,
        pos: pos ?? this.pos,
        strokeColor: strokeColor ?? this.strokeColor,
        strokeWidth: strokeWidth ?? this.strokeWidth,
        path: clearPath ? null : (path ?? this.path),
        pathOffset: pathOffset ?? this.pathOffset,
        anim: anim ?? this.anim,
        animUnit: animUnit ?? this.animUnit,
        animStart: animStart ?? this.animStart,
        animStagger: animStagger ?? this.animStagger,
        animDuration: animDuration ?? this.animDuration,
        animAmount: animAmount ?? this.animAmount,
      );

  Map<String, dynamic> toJson() => {
        'text': text,
        'font': font,
        'size': size,
        'color': color.toARGB32(),
        'bold': bold,
        'italic': italic,
        'underline': underline,
        'align': align,
        'ls': letterSpacing,
        'lh': lineHeight,
        'box': boxWidth,
        'pos': [pos.dx, pos.dy],
        'sc': strokeColor.toARGB32(),
        'sw': strokeWidth,
        if (path != null) 'path': path!.toJson(),
        'po': pathOffset,
        'anim': anim.name,
        'unit': animUnit.name,
        'as': animStart,
        'ag': animStagger,
        'ad': animDuration,
        'aa': animAmount,
      };

  static TextSpec fromJson(dynamic j) {
    final m = j as Map<String, dynamic>;
    double d(String k, double def) => (m[k] as num?)?.toDouble() ?? def;
    final pos = m['pos'] as List?;
    return TextSpec(
      text: m['text'] as String? ?? '',
      font: m['font'] as String? ?? '',
      size: d('size', 64),
      color: Color(m['color'] as int? ?? 0xFF000000),
      bold: m['bold'] as bool? ?? false,
      italic: m['italic'] as bool? ?? false,
      underline: m['underline'] as bool? ?? false,
      align: m['align'] as int? ?? 0,
      letterSpacing: d('ls', 0),
      lineHeight: d('lh', 1.2),
      boxWidth: d('box', 0),
      pos: pos == null ? Offset.zero : Offset((pos[0] as num).toDouble(), (pos[1] as num).toDouble()),
      strokeColor: Color(m['sc'] as int? ?? 0xFFFFFFFF),
      strokeWidth: d('sw', 0),
      path: m['path'] == null ? null : VPath.fromJson(m['path']),
      pathOffset: d('po', 0),
      anim: TextAnimKind.values.firstWhere((e) => e.name == m['anim'], orElse: () => TextAnimKind.none),
      animUnit: TextUnit.values.firstWhere((e) => e.name == m['unit'], orElse: () => TextUnit.letter),
      animStart: m['as'] as int? ?? 0,
      animStagger: d('ag', 2),
      animDuration: d('ad', 8),
      animAmount: d('aa', 20),
    );
  }
}

// ---------------------------------------------------------------------------
// Particles
// ---------------------------------------------------------------------------

enum ParticleShape { circle, soft, streak, square, star, flake }

enum ParticlePreset { rain, snow, fire, smoke, sparks, confetti, dust, bubbles }

extension ParticlePresetLabel on ParticlePreset {
  String get label => switch (this) {
        ParticlePreset.rain => tr('Lluvia', 'Rain'),
        ParticlePreset.snow => tr('Nieve', 'Snow'),
        ParticlePreset.fire => tr('Fuego', 'Fire'),
        ParticlePreset.smoke => tr('Humo', 'Smoke'),
        ParticlePreset.sparks => tr('Chispas', 'Sparks'),
        ParticlePreset.confetti => tr('Confeti', 'Confetti'),
        ParticlePreset.dust => tr('Polvo', 'Dust'),
        ParticlePreset.bubbles => tr('Burbujas', 'Bubbles'),
      };
}

/// Emitter description. The simulation is a pure function of
/// (spec, frame), so any frame can be evaluated without stepping.
class ParticleSpec {
  const ParticleSpec({
    this.emitter = const Rect.fromLTWH(0, 0, 100, 10),
    this.rate = 6,
    this.life = 48,
    this.lifeVar = 0.3,
    this.speed = 8,
    this.speedVar = 0.3,
    this.angle = 90,
    this.spread = 10,
    this.gravityX = 0,
    this.gravityY = 0.2,
    this.drag = 0,
    this.size = 6,
    this.sizeVar = 0.4,
    this.sizeEnd = 1,
    this.colorStart = const Color(0xFFFFFFFF),
    this.colorEnd = const Color(0xFFFFFFFF),
    this.alphaStart = 1,
    this.alphaEnd = 0,
    this.shape = ParticleShape.circle,
    this.additive = false,
    this.seed = 1,
    this.floorY,
    this.bounce = 0.4,
    this.turbulence = 0,
    this.spin = 0,
    this.colorVar = 0,
  });

  final Rect emitter;

  /// Particles emitted per frame.
  final double rate;

  /// Lifetime in frames.
  final double life, lifeVar;
  final double speed, speedVar;

  /// Direction in degrees (0 = right, 90 = down) and its spread.
  final double angle, spread;
  final double gravityX, gravityY, drag;
  final double size, sizeVar, sizeEnd;
  final Color colorStart, colorEnd;
  final double alphaStart, alphaEnd;
  final ParticleShape shape;
  final bool additive;
  final int seed;

  /// Collision floor (comp y) or null for none.
  final double? floorY;
  final double bounce, turbulence, spin, colorVar;

  ParticleSpec copyWith({
    Rect? emitter,
    double? rate,
    double? life,
    double? lifeVar,
    double? speed,
    double? speedVar,
    double? angle,
    double? spread,
    double? gravityX,
    double? gravityY,
    double? drag,
    double? size,
    double? sizeVar,
    double? sizeEnd,
    Color? colorStart,
    Color? colorEnd,
    double? alphaStart,
    double? alphaEnd,
    ParticleShape? shape,
    bool? additive,
    int? seed,
    double? floorY,
    bool clearFloor = false,
    double? bounce,
    double? turbulence,
    double? spin,
    double? colorVar,
  }) =>
      ParticleSpec(
        emitter: emitter ?? this.emitter,
        rate: rate ?? this.rate,
        life: life ?? this.life,
        lifeVar: lifeVar ?? this.lifeVar,
        speed: speed ?? this.speed,
        speedVar: speedVar ?? this.speedVar,
        angle: angle ?? this.angle,
        spread: spread ?? this.spread,
        gravityX: gravityX ?? this.gravityX,
        gravityY: gravityY ?? this.gravityY,
        drag: drag ?? this.drag,
        size: size ?? this.size,
        sizeVar: sizeVar ?? this.sizeVar,
        sizeEnd: sizeEnd ?? this.sizeEnd,
        colorStart: colorStart ?? this.colorStart,
        colorEnd: colorEnd ?? this.colorEnd,
        alphaStart: alphaStart ?? this.alphaStart,
        alphaEnd: alphaEnd ?? this.alphaEnd,
        shape: shape ?? this.shape,
        additive: additive ?? this.additive,
        seed: seed ?? this.seed,
        floorY: clearFloor ? null : (floorY ?? this.floorY),
        bounce: bounce ?? this.bounce,
        turbulence: turbulence ?? this.turbulence,
        spin: spin ?? this.spin,
        colorVar: colorVar ?? this.colorVar,
      );

  factory ParticleSpec.preset(ParticlePreset p, Size comp) {
    final w = comp.width, h = comp.height;
    switch (p) {
      case ParticlePreset.rain:
        return ParticleSpec(
          emitter: Rect.fromLTWH(-w * 0.1, -20, w * 1.2, 4),
          rate: 14, life: 40, lifeVar: 0.2, speed: h / 28, speedVar: 0.25, angle: 80, spread: 2,
          gravityY: 0.4, size: 2, sizeVar: 0.4, shape: ParticleShape.streak,
          colorStart: const Color(0xFFBFD9FF), colorEnd: const Color(0xFFBFD9FF), alphaStart: 0.7, alphaEnd: 0.5,
          floorY: h, bounce: 0.15,
        );
      case ParticlePreset.snow:
        return ParticleSpec(
          emitter: Rect.fromLTWH(-w * 0.1, -20, w * 1.2, 4),
          rate: 4, life: 220, lifeVar: 0.2, speed: h / 240, speedVar: 0.5, angle: 90, spread: 20,
          gravityY: 0.002, size: 5, sizeVar: 0.7, shape: ParticleShape.soft, turbulence: 1.2,
          alphaStart: 0.95, alphaEnd: 0.6,
        );
      case ParticlePreset.fire:
        return ParticleSpec(
          emitter: Rect.fromLTWH(w * 0.4, h * 0.75, w * 0.2, 10),
          rate: 10, life: 36, lifeVar: 0.4, speed: 4, speedVar: 0.5, angle: -90, spread: 18,
          gravityY: -0.08, size: 36, sizeVar: 0.5, sizeEnd: 0.2, shape: ParticleShape.soft, additive: true,
          colorStart: const Color(0xFFFFD27A), colorEnd: const Color(0xFFE02200), alphaStart: 0.55, alphaEnd: 0, turbulence: 0.8,
        );
      case ParticlePreset.smoke:
        return ParticleSpec(
          emitter: Rect.fromLTWH(w * 0.45, h * 0.7, w * 0.1, 10),
          rate: 3, life: 110, lifeVar: 0.3, speed: 2.2, speedVar: 0.4, angle: -90, spread: 14,
          gravityY: -0.01, size: 40, sizeVar: 0.5, sizeEnd: 3.2, shape: ParticleShape.soft,
          colorStart: const Color(0xFF8A8A8A), colorEnd: const Color(0xFF3A3A3A), alphaStart: 0.35, alphaEnd: 0, turbulence: 0.9,
        );
      case ParticlePreset.sparks:
        return ParticleSpec(
          emitter: Rect.fromCenter(center: Offset(w / 2, h / 2), width: 8, height: 8),
          rate: 12, life: 30, lifeVar: 0.5, speed: 11, speedVar: 0.6, angle: -90, spread: 180,
          gravityY: 0.45, size: 3, sizeVar: 0.5, sizeEnd: 0.3, shape: ParticleShape.streak, additive: true,
          colorStart: const Color(0xFFFFF3B0), colorEnd: const Color(0xFFFF6A00), alphaStart: 1, alphaEnd: 0,
          floorY: h, bounce: 0.5,
        );
      case ParticlePreset.confetti:
        return ParticleSpec(
          emitter: Rect.fromLTWH(0, -20, w, 4),
          rate: 6, life: 150, lifeVar: 0.2, speed: 4, speedVar: 0.5, angle: 90, spread: 40,
          gravityY: 0.05, drag: 0.02, size: 9, sizeVar: 0.5, shape: ParticleShape.square, spin: 0.3,
          colorStart: const Color(0xFFFF3D7F), colorEnd: const Color(0xFF3DC8FF), colorVar: 1, alphaStart: 1, alphaEnd: 1, turbulence: 0.8,
        );
      case ParticlePreset.dust:
        return ParticleSpec(
          emitter: Rect.fromLTWH(0, 0, w, h),
          rate: 1.5, life: 160, lifeVar: 0.4, speed: 0.5, speedVar: 0.8, angle: -60, spread: 180,
          gravityY: 0, size: 3, sizeVar: 0.8, shape: ParticleShape.soft, additive: true,
          colorStart: const Color(0xFFFFF6D6), colorEnd: const Color(0xFFFFF6D6), alphaStart: 0.55, alphaEnd: 0.0, turbulence: 0.6,
        );
      case ParticlePreset.bubbles:
        return ParticleSpec(
          emitter: Rect.fromLTWH(0, h, w, 4),
          rate: 2, life: 180, lifeVar: 0.3, speed: 2.5, speedVar: 0.5, angle: -90, spread: 12,
          gravityY: -0.01, size: 14, sizeVar: 0.7, shape: ParticleShape.circle,
          colorStart: const Color(0xFFBDEBFF), colorEnd: const Color(0xFFFFFFFF), alphaStart: 0.5, alphaEnd: 0.1, turbulence: 0.7,
        );
    }
  }

  Map<String, dynamic> toJson() => {
        'em': [emitter.left, emitter.top, emitter.width, emitter.height],
        'rate': rate, 'life': life, 'lifeVar': lifeVar, 'speed': speed, 'speedVar': speedVar,
        'angle': angle, 'spread': spread, 'gx': gravityX, 'gy': gravityY, 'drag': drag,
        'size': size, 'sizeVar': sizeVar, 'sizeEnd': sizeEnd,
        'c0': colorStart.toARGB32(), 'c1': colorEnd.toARGB32(), 'a0': alphaStart, 'a1': alphaEnd,
        'shape': shape.name, 'add': additive, 'seed': seed,
        if (floorY != null) 'floor': floorY,
        'bounce': bounce, 'turb': turbulence, 'spin': spin, 'cv': colorVar,
      };

  static ParticleSpec fromJson(dynamic j) {
    final m = j as Map<String, dynamic>;
    double d(String k, double def) => (m[k] as num?)?.toDouble() ?? def;
    final em = (m['em'] as List).map((e) => (e as num).toDouble()).toList();
    return ParticleSpec(
      emitter: Rect.fromLTWH(em[0], em[1], em[2], em[3]),
      rate: d('rate', 6), life: d('life', 48), lifeVar: d('lifeVar', 0.3), speed: d('speed', 8), speedVar: d('speedVar', 0.3),
      angle: d('angle', 90), spread: d('spread', 10), gravityX: d('gx', 0), gravityY: d('gy', 0.2), drag: d('drag', 0),
      size: d('size', 6), sizeVar: d('sizeVar', 0.4), sizeEnd: d('sizeEnd', 1),
      colorStart: Color(m['c0'] as int? ?? 0xFFFFFFFF), colorEnd: Color(m['c1'] as int? ?? 0xFFFFFFFF),
      alphaStart: d('a0', 1), alphaEnd: d('a1', 0),
      shape: ParticleShape.values.firstWhere((s) => s.name == m['shape'], orElse: () => ParticleShape.circle),
      additive: m['add'] as bool? ?? false, seed: m['seed'] as int? ?? 1,
      floorY: (m['floor'] as num?)?.toDouble(),
      bounce: d('bounce', 0.4), turbulence: d('turb', 0), spin: d('spin', 0), colorVar: d('cv', 0),
    );
  }
}
