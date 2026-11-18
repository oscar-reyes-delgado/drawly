import 'dart:math' as math;
import 'dart:ui';

/// HSV colour (h in degrees 0..360, s/v in 0..1).
class Hsv {
  const Hsv(this.h, this.s, this.v, [this.a = 1]);
  final double h, s, v, a;

  factory Hsv.fromColor(Color c) {
    final r = c.r, g = c.g, b = c.b;
    final mx = math.max(r, math.max(g, b)), mn = math.min(r, math.min(g, b));
    final d = mx - mn;
    double h = 0;
    if (d > 1e-9) {
      if (mx == r) {
        h = 60 * (((g - b) / d) % 6);
      } else if (mx == g) {
        h = 60 * ((b - r) / d + 2);
      } else {
        h = 60 * ((r - g) / d + 4);
      }
    }
    if (h < 0) h += 360;
    return Hsv(h, mx <= 0 ? 0 : d / mx, mx, c.a);
  }

  Color toColor() {
    final hh = (h % 360 + 360) % 360;
    final c = v * s;
    final x = c * (1 - ((hh / 60) % 2 - 1).abs());
    final m = v - c;
    double r, g, b;
    if (hh < 60) {
      r = c;
      g = x;
      b = 0;
    } else if (hh < 120) {
      r = x;
      g = c;
      b = 0;
    } else if (hh < 180) {
      r = 0;
      g = c;
      b = x;
    } else if (hh < 240) {
      r = 0;
      g = x;
      b = c;
    } else if (hh < 300) {
      r = x;
      g = 0;
      b = c;
    } else {
      r = c;
      g = 0;
      b = x;
    }
    return Color.from(alpha: a, red: clampUnit(r + m), green: clampUnit(g + m), blue: clampUnit(b + m));
  }

  Hsv copyWith({double? h, double? s, double? v, double? a}) => Hsv(h ?? this.h, s ?? this.s, v ?? this.v, a ?? this.a);
}

double clampUnit(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);

int ch8(double v) => (clampUnit(v) * 255.0).round();

extension ColorX on Color {
  int get r8 => ch8(r);
  int get g8 => ch8(g);
  int get b8 => ch8(b);
  int get a8 => ch8(a);
  int get argb => toARGB32();

  Color withA(double alpha) => withValues(alpha: clampUnit(alpha));

  /// Relative luminance (Rec. 709, gamma space approximation).
  double get luma => 0.2126 * r + 0.7152 * g + 0.0722 * b;

  String get hex {
    String two(int v) => v.toRadixString(16).padLeft(2, '0');
    return '${two(r8)}${two(g8)}${two(b8)}'.toUpperCase();
  }

  String get hexWithAlpha {
    String two(int v) => v.toRadixString(16).padLeft(2, '0');
    return '${two(r8)}${two(g8)}${two(b8)}${two(a8)}'.toUpperCase();
  }

  /// Readable foreground (black / white) for text drawn over this colour.
  Color get contrastText => luma > 0.55 ? const Color(0xFF000000) : const Color(0xFFFFFFFF);
}

Color? parseHex(String input) {
  var s = input.trim().replaceAll('#', '');
  if (s.length == 3) s = s.split('').map((c) => '$c$c').join();
  if (s.length == 6) s = '${s}FF';
  if (s.length != 8) return null;
  final v = int.tryParse(s, radix: 16);
  if (v == null) return null;
  return Color.fromARGB(v & 0xFF, (v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF);
}

/// Naive (profile-less) CMYK, all channels 0..1.
class Cmyk {
  const Cmyk(this.c, this.m, this.y, this.k);
  final double c, m, y, k;

  factory Cmyk.fromColor(Color col) {
    final double k = 1.0 - math.max(col.r, math.max(col.g, col.b));
    if (k >= 1 - 1e-9) return const Cmyk(0, 0, 0, 1);
    return Cmyk((1 - col.r - k) / (1 - k), (1 - col.g - k) / (1 - k), (1 - col.b - k) / (1 - k), k);
  }

  Color toColor([double alpha = 1]) => Color.from(
        alpha: alpha,
        red: clampUnit((1 - c) * (1 - k)),
        green: clampUnit((1 - m) * (1 - k)),
        blue: clampUnit((1 - y) * (1 - k)),
      );
}

/// HSL (h degrees, s/l 0..1).
class Hsl {
  const Hsl(this.h, this.s, this.l);
  final double h, s, l;

  factory Hsl.fromColor(Color c) {
    final r = c.r, g = c.g, b = c.b;
    final mx = math.max(r, math.max(g, b)), mn = math.min(r, math.min(g, b));
    final l = (mx + mn) / 2;
    final d = mx - mn;
    if (d < 1e-9) return Hsl(0, 0, l);
    final s = d / (1 - (2 * l - 1).abs());
    double h;
    if (mx == r) {
      h = 60 * (((g - b) / d) % 6);
    } else if (mx == g) {
      h = 60 * ((b - r) / d + 2);
    } else {
      h = 60 * ((r - g) / d + 4);
    }
    if (h < 0) h += 360;
    return Hsl(h, clampUnit(s), l);
  }

  Color toColor([double alpha = 1]) {
    final c = (1 - (2 * l - 1).abs()) * s;
    final hh = (h % 360 + 360) % 360;
    final x = c * (1 - ((hh / 60) % 2 - 1).abs());
    final m = l - c / 2;
    double r, g, b;
    if (hh < 60) {
      r = c;
      g = x;
      b = 0;
    } else if (hh < 120) {
      r = x;
      g = c;
      b = 0;
    } else if (hh < 180) {
      r = 0;
      g = c;
      b = x;
    } else if (hh < 240) {
      r = 0;
      g = x;
      b = c;
    } else if (hh < 300) {
      r = x;
      g = 0;
      b = c;
    } else {
      r = c;
      g = 0;
      b = x;
    }
    return Color.from(alpha: alpha, red: clampUnit(r + m), green: clampUnit(g + m), blue: clampUnit(b + m));
  }
}

Color lerpColor(Color a, Color b, double t) => Color.from(
      alpha: a.a + (b.a - a.a) * t,
      red: a.r + (b.r - a.r) * t,
      green: a.g + (b.g - a.g) * t,
      blue: a.b + (b.b - a.b) * t,
    );

double _srgbToLinear(double c) => c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

double _linearToSrgb(double c) => c <= 0.0031308 ? c * 12.92 : 1.055 * math.pow(c, 1 / 2.4) - 0.055;

/// Subtractive, pigment-like mix. Blends in a Kubelka-Munk style absorbance
/// space so that e.g. cyan + yellow drifts to green instead of grey.
Color mixPigment(Color a, Color b, double t) {
  double mixCh(double ca, double cb) {
    const eps = 0.002;
    final la = math.max(_srgbToLinear(ca), eps), lb = math.max(_srgbToLinear(cb), eps);
    // K/S of each colourant
    final ka = (1 - la) * (1 - la) / (2 * la);
    final kb = (1 - lb) * (1 - lb) / (2 * lb);
    final k = ka + (kb - ka) * t;
    final refl = 1 + k - math.sqrt(k * k + 2 * k);
    return clampUnit(_linearToSrgb(refl));
  }

  return Color.from(
    alpha: a.a + (b.a - a.a) * t,
    red: mixCh(a.r, b.r),
    green: mixCh(a.g, b.g),
    blue: mixCh(a.b, b.b),
  );
}

enum Harmony { complementary, analogous, triadic, splitComplementary, tetradic, square, monochromatic }

List<Color> harmonyColors(Color base, Harmony h) {
  final hsv = Hsv.fromColor(base);
  Color rot(double deg) => hsv.copyWith(h: (hsv.h + deg) % 360).toColor();
  switch (h) {
    case Harmony.complementary:
      return [base, rot(180)];
    case Harmony.analogous:
      return [rot(-30), base, rot(30)];
    case Harmony.triadic:
      return [base, rot(120), rot(240)];
    case Harmony.splitComplementary:
      return [base, rot(150), rot(210)];
    case Harmony.tetradic:
      return [base, rot(60), rot(180), rot(240)];
    case Harmony.square:
      return [base, rot(90), rot(180), rot(270)];
    case Harmony.monochromatic:
      return [
        hsv.copyWith(v: clampUnit(hsv.v * 0.4)).toColor(),
        hsv.copyWith(v: clampUnit(hsv.v * 0.7)).toColor(),
        base,
        hsv.copyWith(s: clampUnit(hsv.s * 0.6)).toColor(),
        hsv.copyWith(s: clampUnit(hsv.s * 0.3), v: clampUnit(hsv.v * 1.2)).toColor(),
      ];
  }
}

/// Simulates common colour-vision deficiencies (Machado 2009, severity 1).
enum ColorBlindness { none, protanopia, deuteranopia, tritanopia, achromatopsia }

List<double> colorBlindMatrix(ColorBlindness k) {
  switch (k) {
    case ColorBlindness.none:
      return const [1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0];
    case ColorBlindness.protanopia:
      return const [0.152286, 1.052583, -0.204868, 0, 0, 0.114503, 0.786281, 0.099216, 0, 0, -0.003882, -0.048116, 1.051998, 0, 0, 0, 0, 0, 1, 0];
    case ColorBlindness.deuteranopia:
      return const [0.367322, 0.860646, -0.227968, 0, 0, 0.280085, 0.672501, 0.047413, 0, 0, -0.011820, 0.042940, 0.968881, 0, 0, 0, 0, 0, 1, 0];
    case ColorBlindness.tritanopia:
      return const [1.255528, -0.076749, -0.178779, 0, 0, -0.078411, 0.930809, 0.147602, 0, 0, 0.004733, 0.691367, 0.303900, 0, 0, 0, 0, 0, 1, 0];
    case ColorBlindness.achromatopsia:
      return const [0.2126, 0.7152, 0.0722, 0, 0, 0.2126, 0.7152, 0.0722, 0, 0, 0.2126, 0.7152, 0.0722, 0, 0, 0, 0, 0, 1, 0];
  }
}
