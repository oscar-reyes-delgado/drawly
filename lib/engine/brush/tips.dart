import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui';

import '../../core/i18n.dart';
import '../tiles.dart';

/// A brush tip: white alpha mask stored as an atlas holding six
/// pre-filtered sizes (256 … 8 px) so dabs of any size sample a level that
/// is never minified by more than 2x.
class BrushTip {
  BrushTip(this.id, this.atlas);
  final String id;
  final ui.Image atlas;

  static const List<int> sizes = [256, 128, 64, 32, 16, 8];
  static const List<int> offsets = [0, 256, 384, 448, 480, 496];
  static const int atlasWidth = 512, atlasHeight = 256;

  /// Index of the atlas level to use for a dab that is [px] pixels wide.
  static int levelFor(double px) {
    for (var i = sizes.length - 1; i >= 0; i--) {
      if (sizes[i] >= px) return i;
    }
    return 0;
  }
}

/// Procedural tip & paper-grain library. Everything is generated at start-up
/// so the app ships without bitmap assets.
class BrushTips {
  BrushTips._();
  static final BrushTips instance = BrushTips._();

  final Map<String, BrushTip> _tips = {};
  final Map<String, ui.Image> _grains = {};
  final Map<String, Float32List> _alphaCache = {};
  bool _loaded = false;
  Future<void>? _loading;

  bool get isLoaded => _loaded;

  static const int _hardSteps = 10;

  /// Tip ids offered in the brush editor (excluding the round hardness ramp).
  static const List<String> shapeIds = [
    'round', 'pencil', 'charcoal', 'chalk', 'bristle', 'flat', 'splatter', 'sponge', 'square', 'star', 'leaf', 'cloud', 'watercolor',
  ];

  static const List<String> grainIds = ['', 'paper', 'rough', 'canvas', 'halftone', 'hatch', 'noise'];

  List<String> get customTipIds => _tips.keys.where((k) => k.startsWith('custom:')).toList();

  static String tipLabel(String id) => switch (id) {
        'round' => tr('Redonda', 'Round'),
        'pencil' => tr('Lápiz', 'Pencil'),
        'charcoal' => tr('Carboncillo', 'Charcoal'),
        'chalk' => tr('Tiza', 'Chalk'),
        'bristle' => tr('Cerdas', 'Bristles'),
        'flat' => tr('Plana', 'Flat'),
        'splatter' => tr('Salpicadura', 'Splatter'),
        'sponge' => tr('Esponja', 'Sponge'),
        'square' => tr('Cuadrada', 'Square'),
        'star' => tr('Destello', 'Sparkle'),
        'leaf' => tr('Hoja', 'Leaf'),
        'cloud' => tr('Nube', 'Cloud'),
        'watercolor' => tr('Acuarela', 'Watercolour'),
        _ => id.startsWith('custom:') ? id.substring(7) : id,
      };

  static String grainLabel(String id) => switch (id) {
        '' => tr('Sin grano', 'No grain'),
        'paper' => tr('Papel', 'Paper'),
        'rough' => tr('Papel rugoso', 'Rough paper'),
        'canvas' => tr('Lienzo', 'Canvas'),
        'halftone' => tr('Semitono', 'Halftone'),
        'hatch' => tr('Tramado', 'Hatching'),
        'noise' => tr('Ruido', 'Noise'),
        _ => id,
      };

  Future<void> ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    final futures = <Future<void>>[];
    for (var i = 0; i <= _hardSteps; i++) {
      final h = i / _hardSteps;
      futures.add(_register('round#$i', _roundAtlas(h)));
    }
    final fns = <String, _TipFn>{
      'pencil': _pencil,
      'charcoal': _charcoal,
      'chalk': _chalk,
      'bristle': _bristle,
      'flat': _flat,
      'splatter': _splatter,
      'sponge': _sponge,
      'square': _square,
      'star': _star,
      'leaf': _leaf,
      'cloud': _cloud,
      'watercolor': _watercolor,
    };
    fns.forEach((id, fn) => futures.add(_register(id, _atlasFromFn(fn))));
    for (final g in grainIds) {
      if (g.isEmpty) continue;
      futures.add(_registerGrain(g));
    }
    await Future.wait(futures);
    _loaded = true;
  }

  Future<void> _register(String id, Uint8List rgba) async {
    final img = await imageFromRgba(rgba, BrushTip.atlasWidth, BrushTip.atlasHeight);
    _tips[id] = BrushTip(id, img);
  }

  Future<void> _registerGrain(String id) async {
    const n = 256;
    final a = _grainAlpha(id, n);
    final rgba = Uint8List(n * n * 4);
    for (var i = 0; i < n * n; i++) {
      final v = (a[i].clamp(0.0, 1.0) * 255).round();
      rgba[i * 4] = v;
      rgba[i * 4 + 1] = v;
      rgba[i * 4 + 2] = v;
      rgba[i * 4 + 3] = v;
    }
    _grains[id] = await imageFromRgba(rgba, n, n);
  }

  BrushTip tip(String id, double hardness) {
    if (id == 'round' || !_tips.containsKey(id)) {
      final i = (hardness.clamp(0.0, 1.0) * _hardSteps).round();
      return _tips['round#$i']!;
    }
    return _tips[id]!;
  }

  ui.Image? grain(String id) => id.isEmpty ? null : _grains[id];

  /// Registers a user supplied tip from 256x256 alpha values.
  Future<void> registerCustom(String name, Float32List alpha256) async {
    final id = 'custom:$name';
    _alphaCache[id] = alpha256;
    await _register(id, _atlasFromAlpha(alpha256));
  }

  Float32List? customAlpha(String id) => _alphaCache[id];

  /// Builds a custom tip from any image: dark / opaque pixels become ink.
  Future<String> registerCustomFromImage(String name, ui.Image image) async {
    const n = 256;
    final scaled = renderToImage(n, n, (c) {
      final s = math.min(n / image.width, n / image.height);
      final w = image.width * s, h = image.height * s;
      c.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        Rect.fromLTWH((n - w) / 2, (n - h) / 2, w, h),
        Paint()..filterQuality = FilterQuality.medium,
      );
    });
    final px = await imageToRgba(scaled, straight: true);
    scaled.dispose();
    var opaque = true;
    for (var i = 3; i < px.length; i += 4) {
      if (px[i] < 250) {
        opaque = false;
        break;
      }
    }
    final alpha = Float32List(n * n);
    for (var i = 0; i < n * n; i++) {
      final a = px[i * 4 + 3] / 255.0;
      final lum = (0.2126 * px[i * 4] + 0.7152 * px[i * 4 + 1] + 0.0722 * px[i * 4 + 2]) / 255.0;
      // opaque images: darkness is ink; images with transparency: alpha is ink
      alpha[i] = opaque ? (1 - lum) : a * (1 - lum * 0.0);
    }
    // keep a transparent border so atlas levels never bleed
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        if (x < 2 || y < 2 || x >= n - 2 || y >= n - 2) alpha[y * n + x] = 0;
      }
    }
    await registerCustom(name, alpha);
    return 'custom:$name';
  }

  // ---- atlas builders -----------------------------------------------------

  static void _put(Uint8List rgba, int x, int y, double a) {
    final v = (a.clamp(0.0, 1.0) * 255).round();
    final o = (y * BrushTip.atlasWidth + x) * 4;
    rgba[o] = v;
    rgba[o + 1] = v;
    rgba[o + 2] = v;
    rgba[o + 3] = v;
  }

  /// Analytic round tip evaluated per level (crisp edges at every size).
  static Uint8List _roundAtlas(double hardness) {
    final rgba = Uint8List(BrushTip.atlasWidth * BrushTip.atlasHeight * 4);
    for (var l = 0; l < BrushTip.sizes.length; l++) {
      final s = BrushTip.sizes[l], ox = BrushTip.offsets[l];
      final c = s / 2.0, radius = s / 2.0 - 1.0;
      for (var y = 0; y < s; y++) {
        for (var x = 0; x < s; x++) {
          final dx = x + 0.5 - c, dy = y + 0.5 - c;
          final r = math.sqrt(dx * dx + dy * dy);
          final rn = r / radius;
          final edge = (radius - r + 0.5).clamp(0.0, 1.0);
          double a;
          if (hardness >= 0.999) {
            a = edge;
          } else {
            final t = ((rn - hardness) / (1 - hardness)).clamp(0.0, 1.0);
            a = (1 - (t * t * (3 - 2 * t))) * edge;
          }
          _put(rgba, ox + x, y, a);
        }
      }
    }
    return rgba;
  }

  static Uint8List _atlasFromFn(_TipFn fn) {
    const n = 256;
    final top = Float32List(n * n);
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        // 2x2 supersampling
        var acc = 0.0;
        for (var sy = 0; sy < 2; sy++) {
          for (var sx = 0; sx < 2; sx++) {
            final u = ((x + 0.25 + sx * 0.5) / n) * 2 - 1, v = ((y + 0.25 + sy * 0.5) / n) * 2 - 1;
            acc += fn(u, v);
          }
        }
        var a = acc / 4;
        // guarantee a transparent border
        final border = math.min(math.min(x, y), math.min(n - 1 - x, n - 1 - y));
        if (border < 2) a = 0;
        top[y * n + x] = a.clamp(0.0, 1.0);
      }
    }
    return _atlasFromAlpha(top);
  }

  static Uint8List _atlasFromAlpha(Float32List top) {
    final rgba = Uint8List(BrushTip.atlasWidth * BrushTip.atlasHeight * 4);
    var cur = top;
    var s = 256;
    for (var l = 0; l < BrushTip.sizes.length; l++) {
      final ox = BrushTip.offsets[l];
      for (var y = 0; y < s; y++) {
        for (var x = 0; x < s; x++) {
          _put(rgba, ox + x, y, cur[y * s + x]);
        }
      }
      if (l == BrushTip.sizes.length - 1) break;
      final h = s ~/ 2;
      final next = Float32List(h * h);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < h; x++) {
          final o = (y * 2) * s + x * 2;
          next[y * h + x] = (cur[o] + cur[o + 1] + cur[o + s] + cur[o + s + 1]) / 4;
        }
      }
      cur = next;
      s = h;
    }
    return rgba;
  }

  // ---- noise helpers ------------------------------------------------------

  static double _hash(double x, double y, [double seed = 0]) {
    final s = math.sin(x * 127.1 + y * 311.7 + seed * 74.7) * 43758.5453123;
    return s - s.floorToDouble();
  }

  static double _vnoise(double x, double y, [double seed = 0, int period = 0]) {
    var xi = x.floor(), yi = y.floor();
    final xf = x - xi, yf = y - yi;
    int w(int v) => period > 0 ? ((v % period) + period) % period : v;
    final u = xf * xf * (3 - 2 * xf), v = yf * yf * (3 - 2 * yf);
    xi = w(xi);
    yi = w(yi);
    final x1 = w(xi + 1), y1 = w(yi + 1);
    final a = _hash(xi.toDouble(), yi.toDouble(), seed), b = _hash(x1.toDouble(), yi.toDouble(), seed);
    final c = _hash(xi.toDouble(), y1.toDouble(), seed), d = _hash(x1.toDouble(), y1.toDouble(), seed);
    return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v;
  }

  static double _fbm(double x, double y, {int octaves = 4, double seed = 0, int period = 0}) {
    var amp = 0.5, sum = 0.0, norm = 0.0;
    var fx = x, fy = y;
    var per = period;
    for (var i = 0; i < octaves; i++) {
      sum += _vnoise(fx, fy, seed + i * 17, per) * amp;
      norm += amp;
      amp *= 0.5;
      fx *= 2;
      fy *= 2;
      per *= 2;
    }
    return sum / norm;
  }

  static double _smooth(double e0, double e1, double x) {
    final t = ((x - e0) / (e1 - e0)).clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }

  // ---- tip shapes ---------------------------------------------------------

  static double _pencil(double u, double v) {
    final r = math.sqrt(u * u + v * v);
    final body = 1 - _smooth(0.55, 0.95, r);
    final g = _fbm(u * 14 + 5, v * 14 + 9, octaves: 3, seed: 3);
    return body * (0.35 + 0.65 * _smooth(0.3, 0.7, g));
  }

  static double _charcoal(double u, double v) {
    final ang = math.atan2(v, u);
    final wob = 0.82 + 0.14 * _vnoise(ang * 3 + 10, 0.5, 5);
    final r = math.sqrt(u * u + v * v) / wob;
    final body = 1 - _smooth(0.7, 1.0, r);
    final g = _fbm(u * 22 + 3, v * 22 + 7, octaves: 4, seed: 11);
    return body * _smooth(0.38, 0.6, g);
  }

  static double _chalk(double u, double v) {
    final m = math.max(u.abs(), v.abs()), r = math.sqrt(u * u + v * v);
    final shape = 1 - _smooth(0.7, 0.92, m * 0.6 + r * 0.4);
    final g = _fbm(u * 30 + 1, v * 30 + 2, octaves: 3, seed: 23);
    return shape * _smooth(0.42, 0.56, g);
  }

  static final List<List<double>> _bristleDots = () {
    final rng = math.Random(7);
    return List.generate(46, (_) {
      final a = rng.nextDouble() * math.pi * 2, d = math.sqrt(rng.nextDouble()) * 0.84;
      return [math.cos(a) * d, math.sin(a) * d, 0.035 + rng.nextDouble() * 0.06, 0.5 + rng.nextDouble() * 0.5];
    });
  }();

  static double _bristle(double u, double v) {
    var a = 0.0;
    for (final d in _bristleDots) {
      final dx = u - d[0], dy = v - d[1];
      final r = math.sqrt(dx * dx + dy * dy);
      final k = (1 - _smooth(d[2] * 0.6, d[2], r)) * d[3];
      if (k > a) a = k;
    }
    return a;
  }

  static double _flat(double u, double v) {
    // long axis vertical: when the tip follows the stroke the streaks trail behind
    final edge = (1 - _smooth(0.34, 0.5, u.abs())) * (1 - _smooth(0.8, 0.94, v.abs()));
    final streak = 0.55 + 0.45 * _vnoise(v * 26 + 3, 0.5, 31);
    final gap = _smooth(0.18, 0.32, _vnoise(v * 40 + 9, u * 1.5, 37));
    return edge * streak * (0.75 + 0.25 * gap);
  }

  static final List<List<double>> _splats = () {
    final rng = math.Random(19);
    return List.generate(70, (i) {
      final a = rng.nextDouble() * math.pi * 2, d = math.pow(rng.nextDouble(), 0.7) * 0.9;
      final big = i < 6;
      return [math.cos(a) * d, math.sin(a) * d, big ? 0.08 + rng.nextDouble() * 0.1 : 0.012 + rng.nextDouble() * 0.035];
    });
  }();

  static double _splatter(double u, double v) {
    var a = 0.0;
    for (final d in _splats) {
      final dx = u - d[0], dy = v - d[1];
      final r = math.sqrt(dx * dx + dy * dy);
      final k = 1 - _smooth(d[2] * 0.75, d[2], r);
      if (k > a) a = k;
    }
    return a;
  }

  static double _sponge(double u, double v) {
    final r = math.sqrt(u * u + v * v);
    final body = 1 - _smooth(0.75, 0.96, r);
    final g = _fbm(u * 9 + 4, v * 9 + 8, octaves: 4, seed: 41);
    final holes = _smooth(0.4, 0.52, g);
    return body * holes;
  }

  static double _square(double u, double v) {
    final m = math.max(u.abs(), v.abs());
    return 1 - _smooth(0.95, 0.975, m);
  }

  static double _star(double u, double v) {
    final r = math.sqrt(u * u + v * v);
    final fall = (1 - _smooth(0.0, 0.95, r));
    final cross = 0.02 / (u.abs() * v.abs() * 14 + 0.02);
    final core = 1 - _smooth(0.0, 0.22, r);
    return (math.min(1.0, cross) * fall + core).clamp(0.0, 1.0);
  }

  static double _leaf(double u, double v) {
    // two circular arcs
    const k = 0.62;
    final d1 = math.sqrt((u - k) * (u - k) + v * v), d2 = math.sqrt((u + k) * (u + k) + v * v);
    final rr = math.sqrt(k * k + 0.86 * 0.86);
    final inside = math.min(rr - d1, rr - d2);
    final body = _smooth(0.0, 0.03, inside);
    final rib = 1 - 0.35 * (1 - _smooth(0.0, 0.03, u.abs()));
    return body * rib;
  }

  static double _cloud(double u, double v) {
    final r = math.sqrt(u * u + v * v);
    final g = _fbm(u * 3.2 + 6, v * 3.2 + 2, octaves: 5, seed: 53);
    final body = 1 - _smooth(0.25, 0.95, r + (0.5 - g) * 0.5);
    return body * (0.55 + 0.45 * g);
  }

  static double _watercolor(double u, double v) {
    final ang = math.atan2(v, u);
    final wob = 0.8 + 0.16 * _fbm(math.cos(ang) * 1.6 + 4, math.sin(ang) * 1.6 + 4, octaves: 3, seed: 61);
    final r = math.sqrt(u * u + v * v) / wob;
    final body = 1 - _smooth(0.94, 1.0, r);
    final rim = _smooth(0.72, 0.93, r);
    final wash = 0.5 + 0.12 * _fbm(u * 5, v * 5, octaves: 3, seed: 67);
    return body * (wash + rim * 0.42);
  }

  // ---- paper grains -------------------------------------------------------

  static Float32List _grainAlpha(String id, int n) {
    final out = Float32List(n * n);
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        double a;
        switch (id) {
          case 'paper':
            final g = _fbm(x / 2.0, y / 2.0, octaves: 2, seed: 71, period: n ~/ 2);
            a = 0.2 + 0.8 * _smooth(0.28, 0.72, g);
          case 'rough':
            final g = _fbm(x / 4.0, y / 4.0, octaves: 3, seed: 73, period: n ~/ 4);
            a = _smooth(0.34, 0.62, g);
          case 'canvas':
            final wx = math.sin(x * math.pi * 2 / 8), wy = math.sin(y * math.pi * 2 / 8);
            final weave = ((x ~/ 4 + y ~/ 4).isEven ? wx.abs() : wy.abs());
            final g = _vnoise(x / 4.0, y / 4.0, 79, n ~/ 4);
            a = 0.3 + 0.7 * (weave * 0.75 + g * 0.25);
          case 'halftone':
            final dx = (x % 8) - 3.5, dy = (y % 8) - 3.5;
            a = 1 - _smooth(2.2, 3.2, math.sqrt(dx * dx + dy * dy));
          case 'hatch':
            final d = ((x + y) % 8).toDouble();
            a = 1 - _smooth(1.5, 3.0, (d - 4).abs());
          default:
            a = _hash(x.toDouble(), y.toDouble(), 83);
        }
        out[y * n + x] = a;
      }
    }
    return out;
  }
}

typedef _TipFn = double Function(double u, double v);
