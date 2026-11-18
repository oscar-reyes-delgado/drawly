import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui';

import '../core/color_utils.dart';
import '../model/filter_spec.dart';
import '../model/gradient.dart';
import 'tiles.dart';

/// Loads and hands out the fragment programs used by filters and overlays.
class Shaders {
  Shaders._();
  static final Shaders instance = Shaders._();

  final Map<String, ui.FragmentProgram> _programs = {};
  final Map<String, ui.FragmentShader> _shaders = {};
  Future<void>? _loading;
  bool _loaded = false;

  bool get isLoaded => _loaded;

  static const List<String> names = [
    'lut', 'motion_blur', 'radial_blur', 'sharpen', 'denoise', 'noise', 'pixelate', 'halftone',
    'kuwahara', 'comic', 'edges', 'vignette', 'chromatic', 'lens', 'chroma_key', 'softproof', 'ants',
  ];

  Future<void> ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    await Future.wait(names.map((n) async {
      try {
        _programs[n] = await ui.FragmentProgram.fromAsset('shaders/$n.frag');
      } catch (e) {
        // A missing program only disables the filters that need it.
        // ignore: avoid_print
        print('Drawly: shader "$n" unavailable: $e');
      }
    }));
    _loaded = true;
  }

  bool has(String name) => _programs.containsKey(name);

  /// A reusable shader instance for [name] (uniforms must be set before each use).
  ui.FragmentShader? shader(String name) {
    final p = _programs[name];
    if (p == null) return null;
    return _shaders[name] ??= p.fragmentShader();
  }
}

void _setF(ui.FragmentShader s, String name, double v) {
  try {
    s.getUniformFloat(name).set(v);
  } catch (_) {
    // uniform optimised away by the shader compiler
  }
}

void _set2(ui.FragmentShader s, String name, double x, double y) {
  try {
    s.getUniformVec2(name).set(x, y);
  } catch (_) {}
}

void _set4(ui.FragmentShader s, String name, double x, double y, double z, double w) {
  try {
    s.getUniformVec4(name).set(x, y, z, w);
  } catch (_) {}
}

void _setImg(ui.FragmentShader s, String name, ui.Image img) {
  try {
    s.getImageSampler(name).set(img);
  } catch (_) {}
}

// ---------------------------------------------------------------------------
// Colour matrices (row-major 4x5, offsets in 0..255)
// ---------------------------------------------------------------------------

const List<double> kIdentityMatrix = [1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0];

/// `a ∘ b`: applies [b] first, then [a].
List<double> concatMatrix(List<double> a, List<double> b) {
  final out = List<double>.filled(20, 0);
  for (var r = 0; r < 4; r++) {
    for (var c = 0; c < 4; c++) {
      var v = 0.0;
      for (var k = 0; k < 4; k++) {
        v += a[r * 5 + k] * b[k * 5 + c];
      }
      out[r * 5 + c] = v;
    }
    var off = a[r * 5 + 4];
    for (var k = 0; k < 4; k++) {
      off += a[r * 5 + k] * b[k * 5 + 4];
    }
    out[r * 5 + 4] = off;
  }
  return out;
}

List<double> _lerpMatrix(List<double> a, List<double> b, double t) => [for (var i = 0; i < 20; i++) a[i] + (b[i] - a[i]) * t];

List<double> saturationMatrix(double s) {
  const lr = 0.2126, lg = 0.7152, lb = 0.0722;
  final ir = (1 - s) * lr, ig = (1 - s) * lg, ib = (1 - s) * lb;
  return [ir + s, ig, ib, 0, 0, ir, ig + s, ib, 0, 0, ir, ig, ib + s, 0, 0, 0, 0, 0, 1, 0];
}

List<double> hueMatrix(double degrees) {
  final a = degrees * math.pi / 180;
  final c = math.cos(a), s = math.sin(a);
  const lr = 0.213, lg = 0.715, lb = 0.072;
  return [
    lr + c * (1 - lr) + s * (-lr), lg + c * (-lg) + s * (-lg), lb + c * (-lb) + s * (1 - lb), 0, 0,
    lr + c * (-lr) + s * 0.143, lg + c * (1 - lg) + s * 0.140, lb + c * (-lb) + s * (-0.283), 0, 0,
    lr + c * (-lr) + s * (-(1 - lr)), lg + c * (-lg) + s * lg, lb + c * (1 - lb) + s * lb, 0, 0,
    0, 0, 0, 1, 0,
  ];
}

/// The colour matrix of a [FilterKind.matrix] filter.
List<double> filterMatrix(FilterSpec f) {
  switch (f.type) {
    case 'brightnessContrast':
      final b = f.v('brightness') * 2.55;
      final cv = f.v('contrast') * 2.55;
      final k = (259 * (cv + 255)) / (255 * (259 - cv));
      final o = 128 - k * 128 + b;
      return [k, 0, 0, 0, o, 0, k, 0, 0, o, 0, 0, k, 0, o, 0, 0, 0, 1, 0];
    case 'hueSaturation':
      var m = hueMatrix(f.v('hue'));
      m = concatMatrix(saturationMatrix(1 + f.v('saturation') / 100), m);
      final l = f.v('lightness') / 100;
      final lm = l >= 0
          ? <double>[1 - l, 0, 0, 0, 255 * l, 0, 1 - l, 0, 0, 255 * l, 0, 0, 1 - l, 0, 255 * l, 0, 0, 0, 1, 0]
          : <double>[1 + l, 0, 0, 0, 0, 0, 1 + l, 0, 0, 0, 0, 0, 1 + l, 0, 0, 0, 0, 0, 1, 0];
      return concatMatrix(lm, m);
    case 'colorBalance':
      final r = f.v('cyanRed') * 1.1, g = f.v('magentaGreen') * 1.1, b = f.v('yellowBlue') * 1.1;
      // keep overall luminance roughly constant
      final avg = (r * 0.2126 + g * 0.7152 + b * 0.0722);
      return [1, 0, 0, 0, r - avg, 0, 1, 0, 0, g - avg, 0, 0, 1, 0, b - avg, 0, 0, 0, 1, 0];
    case 'temperature':
      final t = f.v('temperature') / 100, ti = f.v('tint') / 100;
      return [1 + 0.25 * t, 0, 0, 0, 0, 0, 1 - 0.18 * ti, 0, 0, 0, 0, 0, 1 - 0.25 * t, 0, 0, 0, 0, 0, 1, 0];
    case 'invert':
      return const [-1, 0, 0, 0, 255, 0, -1, 0, 0, 255, 0, 0, -1, 0, 255, 0, 0, 0, 1, 0];
    case 'grayscale':
      return saturationMatrix(1 - f.v('amount') / 100);
    case 'sepia':
      const sep = <double>[0.393, 0.769, 0.189, 0, 0, 0.349, 0.686, 0.168, 0, 0, 0.272, 0.534, 0.131, 0, 0, 0, 0, 0, 1, 0];
      return _lerpMatrix(kIdentityMatrix, sep, f.v('amount') / 100);
  }
  return kIdentityMatrix;
}

// ---------------------------------------------------------------------------
// Lookup tables
// ---------------------------------------------------------------------------

/// Monotone cubic interpolation through curve control points (0..1 domain).
Float32List curveTable(List<Offset> points) {
  final out = Float32List(256);
  final pts = [...points]..sort((a, b) => a.dx.compareTo(b.dx));
  if (pts.isEmpty) {
    for (var i = 0; i < 256; i++) {
      out[i] = i / 255.0;
    }
    return out;
  }
  if (pts.length == 1) {
    for (var i = 0; i < 256; i++) {
      out[i] = pts.first.dy.clamp(0.0, 1.0);
    }
    return out;
  }
  final n = pts.length;
  final d = List<double>.filled(n - 1, 0), m = List<double>.filled(n, 0);
  for (var i = 0; i < n - 1; i++) {
    final dx = pts[i + 1].dx - pts[i].dx;
    d[i] = dx.abs() < 1e-9 ? 0 : (pts[i + 1].dy - pts[i].dy) / dx;
  }
  m[0] = d[0];
  m[n - 1] = d[n - 2];
  for (var i = 1; i < n - 1; i++) {
    m[i] = d[i - 1] * d[i] <= 0 ? 0 : (d[i - 1] + d[i]) / 2;
  }
  for (var i = 0; i < n - 1; i++) {
    if (d[i] == 0) {
      m[i] = 0;
      m[i + 1] = 0;
    } else {
      final a = m[i] / d[i], b = m[i + 1] / d[i];
      final s = a * a + b * b;
      if (s > 9) {
        final t = 3 / math.sqrt(s);
        m[i] = t * a * d[i];
        m[i + 1] = t * b * d[i];
      }
    }
  }
  for (var i = 0; i < 256; i++) {
    final x = i / 255.0;
    double y;
    if (x <= pts.first.dx) {
      y = pts.first.dy;
    } else if (x >= pts.last.dx) {
      y = pts.last.dy;
    } else {
      var k = 0;
      while (k < n - 2 && x > pts[k + 1].dx) {
        k++;
      }
      final h = pts[k + 1].dx - pts[k].dx;
      final t = h.abs() < 1e-9 ? 0.0 : (x - pts[k].dx) / h;
      final t2 = t * t, t3 = t2 * t;
      y = (2 * t3 - 3 * t2 + 1) * pts[k].dy + (t3 - 2 * t2 + t) * h * m[k] + (-2 * t3 + 3 * t2) * pts[k + 1].dy + (t3 - t2) * h * m[k + 1];
    }
    out[i] = y.clamp(0.0, 1.0);
  }
  return out;
}

/// 256x1 RGBA table (opaque) for LUT based filters.
Uint8List filterLut(FilterSpec f) {
  final out = Uint8List(256 * 4);
  void put(int i, double r, double g, double b) {
    out[i * 4] = ch8(r);
    out[i * 4 + 1] = ch8(g);
    out[i * 4 + 2] = ch8(b);
    out[i * 4 + 3] = 255;
  }

  switch (f.type) {
    case 'curves':
      final master = curveTable(f.curves['rgb'] ?? const [Offset(0, 0), Offset(1, 1)]);
      final cr = curveTable(f.curves['r'] ?? const [Offset(0, 0), Offset(1, 1)]);
      final cg = curveTable(f.curves['g'] ?? const [Offset(0, 0), Offset(1, 1)]);
      final cb = curveTable(f.curves['b'] ?? const [Offset(0, 0), Offset(1, 1)]);
      double via(Float32List t, double v) => t[(v * 255).round().clamp(0, 255)];
      for (var i = 0; i < 256; i++) {
        final mv = master[i];
        put(i, via(cr, mv), via(cg, mv), via(cb, mv));
      }
    case 'levels':
      final ib = f.v('inBlack') / 255, iw = f.v('inWhite') / 255, g = f.v('gamma');
      final ob = f.v('outBlack') / 255, ow = f.v('outWhite') / 255;
      for (var i = 0; i < 256; i++) {
        var v = ((i / 255.0 - ib) / math.max(0.0001, iw - ib)).clamp(0.0, 1.0);
        v = math.pow(v, 1 / math.max(0.01, g)).toDouble();
        v = ob + v * (ow - ob);
        put(i, v, v, v);
      }
    case 'exposure':
      final gain = math.pow(2, f.v('exposure')).toDouble(), g = f.v('gamma');
      for (var i = 0; i < 256; i++) {
        final v = math.pow((i / 255.0 * gain).clamp(0.0, 1.0), 1 / math.max(0.01, g)).toDouble();
        put(i, v, v, v);
      }
    case 'posterize':
      final n = math.max(2, f.v('levels').round());
      for (var i = 0; i < 256; i++) {
        final v = ((i / 255.0) * n).floor().clamp(0, n - 1) / (n - 1);
        put(i, v, v, v);
      }
    case 'threshold':
      final t = f.v('level');
      for (var i = 0; i < 256; i++) {
        final v = i >= t ? 1.0 : 0.0;
        put(i, v, v, v);
      }
    case 'gradientMap':
      final g = f.gradient ?? GradientSpec.blackWhite;
      for (var i = 0; i < 256; i++) {
        final c = g.colorAt(i / 255.0);
        put(i, c.r, c.g, c.b);
      }
    case 'colorize':
      final c = f.color ?? const Color(0xFFFF8800);
      for (var i = 0; i < 256; i++) {
        final t = i / 255.0;
        final col = t < 0.5 ? lerpColor(const Color(0xFF000000), c, t * 2) : lerpColor(c, const Color(0xFFFFFFFF), (t - 0.5) * 2);
        put(i, col.r, col.g, col.b);
      }
    default:
      for (var i = 0; i < 256; i++) {
        put(i, i / 255.0, i / 255.0, i / 255.0);
      }
  }
  return out;
}

final Expando<ui.Image> _lutCache = Expando<ui.Image>('lut');

/// Builds (and caches per spec) the 256x1 LUT texture synchronously.
ui.Image lutImage(FilterSpec f) {
  final cached = _lutCache[f];
  if (cached != null) return cached;
  final bytes = filterLut(f);
  final img = renderToImage(256, 1, (c) {
    final p = Paint()
      ..isAntiAlias = false
      ..blendMode = BlendMode.src;
    for (var i = 0; i < 256; i++) {
      p.color = Color.fromARGB(255, bytes[i * 4], bytes[i * 4 + 1], bytes[i * 4 + 2]);
      c.drawRect(Rect.fromLTWH(i.toDouble(), 0, 1, 1), p);
    }
  });
  _lutCache[f] = img;
  return img;
}

// ---------------------------------------------------------------------------
// Execution
// ---------------------------------------------------------------------------

/// Extra source pixels (in document px) a filter reads around every pixel.
double filterMargin(FilterSpec f) {
  switch (f.def.kind) {
    case FilterKind.blur:
      return f.v('radius') * 2 + 2;
    case FilterKind.glow:
      return f.v('radius') * 2 + 2;
    case FilterKind.morph:
      return f.v('radius') + 1;
    case FilterKind.shader:
      switch (f.type) {
        case 'motionBlur':
          return f.v('distance') / 2 + 2;
        case 'radialBlur':
          return 64;
        case 'chromaticAberration':
          return f.v('amount') + 2;
        case 'lensDistortion':
          return 64;
        case 'oilPaint':
        case 'watercolor':
          return f.v('radius') + 2;
        default:
          return 4;
      }
    default:
      return 0;
  }
}

/// True when the filter is a plain colour matrix (cheap, nests in saveLayer).
bool isMatrixFilter(FilterSpec f) => f.def.kind == FilterKind.matrix;

/// Draws [source] filtered by [f] at the canvas origin.
///
/// [origin] is the document coordinate of the image's top-left pixel,
/// [scale] the number of image pixels per document pixel and [extent] the
/// document rectangle (used by centre-relative effects such as vignette).
void paintFiltered(
  Canvas canvas,
  ui.Image source,
  FilterSpec f, {
  Offset origin = Offset.zero,
  double scale = 1,
  Rect? extent,
}) {
  final w = source.width.toDouble(), h = source.height.toDouble();
  final rect = Rect.fromLTWH(0, 0, w, h);
  final def = f.def;
  final doc = extent ?? Rect.fromLTWH(origin.dx, origin.dy, w / scale, h / scale);
  final plain = Paint()..filterQuality = FilterQuality.none;

  switch (def.kind) {
    case FilterKind.matrix:
      canvas.drawImage(source, Offset.zero, plain..colorFilter = ColorFilter.matrix(filterMatrix(f)));
      return;
    case FilterKind.blur:
      final sigma = f.v('radius') * 0.6 * scale;
      if (sigma <= 0.01) {
        canvas.drawImage(source, Offset.zero, plain);
      } else {
        canvas.save();
        canvas.clipRect(rect);
        canvas.drawImage(source, Offset.zero, plain..imageFilter = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.decal));
        canvas.restore();
      }
      return;
    case FilterKind.morph:
      final r = f.v('radius') * scale;
      canvas.save();
      canvas.clipRect(rect);
      canvas.drawImage(
        source,
        Offset.zero,
        plain..imageFilter = f.type == 'erode' ? ui.ImageFilter.erode(radiusX: r, radiusY: r) : ui.ImageFilter.dilate(radiusX: r, radiusY: r),
      );
      canvas.restore();
      return;
    case FilterKind.glow:
      final sigma = math.max(0.01, f.v('radius') * 0.6 * scale);
      canvas.save();
      canvas.clipRect(rect);
      canvas.drawImage(source, Offset.zero, plain);
      canvas.drawImage(
        source,
        Offset.zero,
        Paint()
          ..imageFilter = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.decal)
          ..blendMode = BlendMode.screen
          ..color = Color.fromRGBO(0, 0, 0, (f.v('intensity') / 100).clamp(0.0, 1.0)),
      );
      canvas.restore();
      return;
    case FilterKind.lut:
    case FilterKind.lumaLut:
      final s = Shaders.instance.shader('lut');
      if (s == null) {
        canvas.drawImage(source, Offset.zero, plain);
        return;
      }
      _commonUniforms(s, w, h, origin, scale);
      _set4(s, 'uA', def.kind == FilterKind.lumaLut ? 1 : 0, 0, 0, 0);
      _setImg(s, 'uImage', source);
      _setImg(s, 'uLut', lutImage(f));
      canvas.drawRect(rect, Paint()..shader = s);
      return;
    case FilterKind.shader:
      final s = Shaders.instance.shader(def.shader!);
      if (s == null) {
        canvas.drawImage(source, Offset.zero, plain);
        return;
      }
      _commonUniforms(s, w, h, origin, scale);
      final vals = [for (final p in def.params) f.v(p.key)];
      double a(int i) => i < vals.length ? vals[i] : 0;
      _set4(s, 'uA', a(0), a(1), a(2), a(3));
      if (def.hasColor) {
        final c = f.color ?? const Color(0xFF00FF00);
        _set4(s, 'uB', c.r, c.g, c.b, c.a);
      } else {
        _set4(s, 'uB', doc.left, doc.top, doc.width, doc.height);
      }
      _setImg(s, 'uImage', source);
      canvas.drawRect(rect, Paint()..shader = s);
      return;
  }
}

void _commonUniforms(ui.FragmentShader s, double w, double h, Offset origin, double scale) {
  _set2(s, 'uSize', w, h);
  _set2(s, 'uOrigin', origin.dx, origin.dy);
  _setF(s, 'uScale', scale);
}

/// Returns a filtered copy of [source].
ui.Image applyFilter(ui.Image source, FilterSpec f, {Offset origin = Offset.zero, double scale = 1, Rect? extent}) =>
    renderToImage(source.width, source.height, (c) => paintFiltered(c, source, f, origin: origin, scale: scale, extent: extent));

/// Simulated CMYK print preview of [source].
void paintSoftProof(Canvas canvas, ui.Image source) {
  final s = Shaders.instance.shader('softproof');
  final w = source.width.toDouble(), h = source.height.toDouble();
  if (s == null) {
    canvas.drawImage(source, Offset.zero, Paint());
    return;
  }
  _commonUniforms(s, w, h, Offset.zero, 1);
  _setImg(s, 'uImage', source);
  canvas.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..shader = s);
}

/// Draws animated marching ants around the 50% contour of [mask] (an image
/// covering the local rect 0,0..size).
void paintMarchingAnts(Canvas canvas, ui.Image mask, Size size, double phase, {double stripe = 8}) {
  final s = Shaders.instance.shader('ants');
  if (s == null) return;
  _set2(s, 'uSize', size.width, size.height);
  _setF(s, 'uPhase', phase);
  _setF(s, 'uStripe', stripe);
  _setImg(s, 'uMask', mask);
  canvas.drawRect(Offset.zero & size, Paint()..shader = s);
}
