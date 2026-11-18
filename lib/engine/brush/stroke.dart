import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui';

import '../../core/color_utils.dart';
import '../../core/mat2d.dart';
import '../../model/layer.dart';
import '../tiles.dart';
import 'preset.dart';
import 'tips.dart';

/// One raw pointer sample in document space.
class StrokeInput {
  const StrokeInput(this.pos, {this.pressure = 1, this.tilt = 0, this.azimuth = 0, this.timeMs = 0, this.hasPressure = false});
  final Offset pos;

  /// 0..1
  final double pressure;

  /// 0 (pen upright) .. 1 (pen flat on the tablet)
  final double tilt;

  /// Direction the pen leans towards, radians.
  final double azimuth;
  final double timeMs;

  /// False for mice / fingers, where pressure is synthesised from speed.
  final bool hasPressure;
}

class Dab {
  Dab(this.x, this.y, this.size, this.angle, this.alpha, this.color);
  final double x, y, size, angle, alpha;

  /// ARGB32
  final int color;
}

class _Pt {
  _Pt(this.p, this.pressure, this.tilt, this.azimuth, this.t);
  final Offset p;
  final double pressure, tilt, azimuth, t;
}

/// Turns pointer samples into evenly spaced dabs: stabiliser, Catmull-Rom
/// interpolation, spacing, pressure / tilt / speed dynamics, jitter and
/// symmetry replication.
class DabGenerator {
  DabGenerator(this.brush, this.color, {List<Mat2D>? symmetry, int seed = 1, this.sizeScale = 1, this.simulatePressure = true})
      : symmetry = symmetry ?? const [Mat2D.identity],
        _rng = math.Random(seed),
        _hsv = Hsv.fromColor(color);

  final BrushPreset brush;
  final Color color;
  final List<Mat2D> symmetry;

  /// Extra multiplier on the brush size (e.g. for previews).
  final double sizeScale;

  /// Derive pressure from speed for devices that report none.
  final bool simulatePressure;
  final math.Random _rng;
  final Hsv _hsv;

  final List<_Pt> _pts = [];
  final List<Dab> pending = [];

  Offset? _ema;
  double _emaPressure = 1;
  StrokeInput? _lastRaw;
  double _distToNext = 0;
  double _strokeLen = 0;
  double _speed = 0; // px per ms, smoothed
  Offset _dir = const Offset(1, 0);
  bool _hasPressure = false;
  bool _finished = false;

  double get strokeLength => _strokeLen;

  void add(StrokeInput s) {
    if (_finished) return;
    _hasPressure = s.hasPressure;
    final last = _lastRaw;
    if (last != null) {
      final dt = math.max(1.0, s.timeMs - last.timeMs);
      final v = (s.pos - last.pos).distance / dt;
      _speed = _speed * 0.7 + v * 0.3;
    }
    _lastRaw = s;

    var pressure = s.pressure.clamp(0.0, 1.0);
    if (!s.hasPressure) {
      // synthesise pressure from speed: fast = light
      pressure = (!simulatePressure || brush.velocitySize != 0) ? 1.0 : (1.0 - (_speed / 4.0).clamp(0.0, 0.55));
      if (brush.pressureSize == 0 && brush.pressureFlow == 0) pressure = 1;
    }

    if (_ema == null) {
      _ema = s.pos;
      _emaPressure = pressure;
      _pts.add(_Pt(s.pos, pressure, s.tilt, s.azimuth, s.timeMs));
      _distToNext = 0;
      // a first dab so that single taps leave a mark
      _emitDab(s.pos, pressure, s.tilt, s.azimuth);
      _distToNext = _spacingPx(pressure, s.tilt);
      return;
    }
    final k = 1.0 - brush.smoothing.clamp(0.0, 1.0) * 0.93;
    _ema = _ema! + (s.pos - _ema!) * k;
    _emaPressure += (pressure - _emaPressure) * math.max(k, 0.35);
    _push(_Pt(_ema!, _emaPressure, s.tilt, s.azimuth, s.timeMs));
  }

  void _push(_Pt pt) {
    if ((pt.p - _pts.last.p).distanceSquared < 0.01) return;
    _pts.add(pt);
    final n = _pts.length;
    if (n >= 3) {
      _segment(_pts[math.max(0, n - 4)], _pts[n - 3], _pts[n - 2], _pts[n - 1]);
    }
    if (_pts.length > 8) _pts.removeRange(0, _pts.length - 4);
  }

  /// Flushes the lagging tail of the stroke (delayed stabiliser correction).
  void finish() {
    if (_finished) return;
    final raw = _lastRaw;
    if (raw != null && _ema != null && brush.smoothing > 0) {
      final k = 1.0 - brush.smoothing.clamp(0.0, 1.0) * 0.93;
      for (var i = 0; i < 40 && (raw.pos - _ema!).distance > 0.6; i++) {
        _ema = _ema! + (raw.pos - _ema!) * math.max(k, 0.25);
        _push(_Pt(_ema!, _emaPressure, raw.tilt, raw.azimuth, raw.timeMs));
      }
      if ((raw.pos - _pts.last.p).distance > 0.1) {
        _push(_Pt(raw.pos, _emaPressure, raw.tilt, raw.azimuth, raw.timeMs));
      }
    }
    final n = _pts.length;
    if (n >= 2) {
      _segment(_pts[math.max(0, n - 3)], _pts[n - 2], _pts[n - 1], _pts[n - 1]);
    }
    _finished = true;
  }

  static Offset _cr(Offset p0, Offset p1, Offset p2, Offset p3, double t) {
    final t2 = t * t, t3 = t2 * t;
    return Offset(
      0.5 * ((2 * p1.dx) + (-p0.dx + p2.dx) * t + (2 * p0.dx - 5 * p1.dx + 4 * p2.dx - p3.dx) * t2 + (-p0.dx + 3 * p1.dx - 3 * p2.dx + p3.dx) * t3),
      0.5 * ((2 * p1.dy) + (-p0.dy + p2.dy) * t + (2 * p0.dy - 5 * p1.dy + 4 * p2.dy - p3.dy) * t2 + (-p0.dy + 3 * p1.dy - 3 * p2.dy + p3.dy) * t3),
    );
  }

  void _segment(_Pt a, _Pt b, _Pt c, _Pt d) {
    final len = (c.p - b.p).distance;
    if (len < 1e-6) return;
    final steps = math.max(1, (len / 1.5).ceil());
    var prev = b.p;
    for (var i = 1; i <= steps; i++) {
      final t1 = i / steps;
      final cur = brush.isPixel ? Offset.lerp(b.p, c.p, t1)! : _cr(a.p, b.p, c.p, d.p, t1);
      final seg = cur - prev;
      final segLen = seg.distance;
      if (segLen < 1e-9) continue;
      _dir = seg / segLen;
      var consumed = 0.0;
      while (_distToNext <= segLen - consumed) {
        consumed += _distToNext;
        final f = consumed / segLen;
        final tt = (i - 1 + f) / steps;
        final pressure = b.pressure + (c.pressure - b.pressure) * tt;
        final tilt = b.tilt + (c.tilt - b.tilt) * tt;
        _strokeLen += _distToNext;
        _emitDab(prev + seg * f, pressure, tilt, c.azimuth);
        _distToNext = _spacingPx(pressure, tilt);
      }
      _distToNext -= segLen - consumed;
      prev = cur;
    }
  }

  double _sizeFor(double pressure, double tilt) {
    final b = brush;
    var s = 1.0 - b.pressureSize * (1.0 - (b.minSize + (1.0 - b.minSize) * pressure));
    if (b.velocitySize != 0) {
      final v = (_speed / 3.0).clamp(0.0, 1.0);
      s *= (1.0 - b.velocitySize * v).clamp(0.05, 2.0);
    }
    if (b.tiltSize != 0) s *= 1.0 + b.tiltSize * tilt * 1.5;
    if (b.taper > 0 && !_hasPressure) {
      final ramp = (_strokeLen / math.max(1.0, b.taper * b.size)).clamp(0.0, 1.0);
      s *= 0.12 + 0.88 * ramp;
    }
    return math.max(b.isPixel ? 1.0 : 0.35, b.size * sizeScale * s);
  }

  double _spacingPx(double pressure, double tilt) {
    final size = _sizeFor(pressure, tilt);
    return math.max(brush.isPixel ? 1.0 : 0.45, brush.spacing * size);
  }

  void _emitDab(Offset p, double pressure, double tilt, double azimuth) {
    final b = brush;
    final baseSize = _sizeFor(pressure, tilt);
    for (var n = 0; n < math.max(1, b.count); n++) {
      var size = baseSize;
      if (b.jitterSize > 0) size *= 1.0 - b.jitterSize * _rng.nextDouble();
      size = math.max(b.isPixel ? 1.0 : 0.35, size);

      var flow = b.flow * (1.0 - b.pressureFlow * (1.0 - pressure));
      if (b.tiltFlow != 0) flow *= 1.0 - b.tiltFlow * tilt;
      if (b.jitterFlow > 0) flow *= 1.0 - b.jitterFlow * _rng.nextDouble();

      var angle = degToRad(b.angle);
      switch (b.rotation) {
        case BrushRotation.fixed:
          break;
        case BrushRotation.direction:
          angle += math.atan2(_dir.dy, _dir.dx);
        case BrushRotation.random:
          angle += _rng.nextDouble() * math.pi * 2;
        case BrushRotation.tilt:
          angle += azimuth;
      }
      if (b.jitterAngle > 0 && b.rotation != BrushRotation.random) {
        angle += (_rng.nextDouble() - 0.5) * 2 * math.pi * b.jitterAngle;
      }

      var pos = p;
      if (b.scatter > 0) {
        pos += Offset((_rng.nextDouble() - 0.5) * 2, (_rng.nextDouble() - 0.5) * 2) * (b.scatter * baseSize);
      }

      var col = color;
      if (b.jitterHue > 0 || b.jitterSat > 0 || b.jitterVal > 0) {
        col = Hsv(
          (_hsv.h + (_rng.nextDouble() - 0.5) * 360 * b.jitterHue) % 360,
          (_hsv.s + (_rng.nextDouble() - 0.5) * 2 * b.jitterSat).clamp(0.0, 1.0),
          (_hsv.v + (_rng.nextDouble() - 0.5) * 2 * b.jitterVal).clamp(0.0, 1.0),
          _hsv.a,
        ).toColor();
      }
      final argb = col.toARGB32();

      if (b.isPixel) {
        size = size.roundToDouble();
      }
      for (final m in symmetry) {
        if (m.isIdentity) {
          pending.add(Dab(pos.dx, pos.dy, size, angle, flow.clamp(0.0, 1.0), argb));
        } else {
          final q = m.apply(pos);
          final v = m.applyVector(Offset(math.cos(angle), math.sin(angle)));
          pending.add(Dab(q.dx, q.dy, size, math.atan2(v.dy, v.dx), flow.clamp(0.0, 1.0), argb));
        }
      }
    }
  }
}

/// Draws dabs with the given tip. Shared by the paint and smudge engines.
class DabPainter {
  DabPainter(this.brush) : tip = BrushTips.instance.tip(brush.tip, brush.hardness);

  final BrushPreset brush;
  final BrushTip tip;

  static final Paint _atlasPaint = Paint()
    ..filterQuality = FilterQuality.low
    ..isAntiAlias = true;

  Rect boundsOf(Dab d) {
    final h = d.size * (brush.isPixel ? 0.5 : 0.72) + 1.5;
    return Rect.fromLTRB(d.x - h, d.y - h, d.x + h, d.y + h);
  }

  /// [alphaScale] multiplies every dab's alpha; [colorOverride] replaces the
  /// dab colour (used for masks). [blend] is the canvas blend of each dab.
  void draw(Canvas canvas, List<Dab> dabs, {double alphaScale = 1, int? colorOverride, BlendMode blend = BlendMode.srcOver}) {
    if (dabs.isEmpty) return;
    if (brush.isPixel) {
      _drawPixel(canvas, dabs, alphaScale, colorOverride, blend);
      return;
    }
    final paint = blend == BlendMode.srcOver
        ? _atlasPaint
        : (Paint()
          ..filterQuality = FilterQuality.low
          ..blendMode = blend);
    if (brush.roundness >= 0.999) {
      final n = dabs.length;
      final rst = Float32List(n * 4), rects = Float32List(n * 4);
      final colors = Int32List(n);
      for (var i = 0; i < n; i++) {
        final d = dabs[i];
        final lvl = BrushTip.levelFor(d.size);
        final ls = BrushTip.sizes[lvl].toDouble(), lx = BrushTip.offsets[lvl].toDouble();
        final scale = d.size / ls;
        final scos = math.cos(d.angle) * scale, ssin = math.sin(d.angle) * scale;
        final ax = ls / 2, ay = ls / 2;
        rst[i * 4] = scos;
        rst[i * 4 + 1] = ssin;
        rst[i * 4 + 2] = d.x - scos * ax + ssin * ay;
        rst[i * 4 + 3] = d.y - ssin * ax - scos * ay;
        rects[i * 4] = lx;
        rects[i * 4 + 1] = 0;
        rects[i * 4 + 2] = lx + ls;
        rects[i * 4 + 3] = ls;
        colors[i] = _argb(colorOverride ?? d.color, d.alpha * alphaScale);
      }
      canvas.drawRawAtlas(tip.atlas, rst, rects, colors, BlendMode.modulate, null, paint);
      return;
    }
    // flattened tips need a non-uniform scale: one transform per dab
    final rst = Float32List(4), rect = Float32List(4);
    final colors = Int32List(1);
    for (final d in dabs) {
      final lvl = BrushTip.levelFor(d.size);
      final ls = BrushTip.sizes[lvl].toDouble(), lx = BrushTip.offsets[lvl].toDouble();
      final scale = d.size / ls;
      canvas.save();
      canvas.translate(d.x, d.y);
      canvas.rotate(d.angle);
      canvas.scale(1, brush.roundness.clamp(0.02, 1.0));
      rst[0] = scale;
      rst[1] = 0;
      rst[2] = -scale * ls / 2;
      rst[3] = -scale * ls / 2;
      rect[0] = lx;
      rect[1] = 0;
      rect[2] = lx + ls;
      rect[3] = ls;
      colors[0] = _argb(colorOverride ?? d.color, d.alpha * alphaScale);
      canvas.drawRawAtlas(tip.atlas, rst, rect, colors, BlendMode.modulate, null, paint);
      canvas.restore();
    }
  }

  void _drawPixel(Canvas canvas, List<Dab> dabs, double alphaScale, int? colorOverride, BlendMode blend) {
    final paint = Paint()
      ..isAntiAlias = false
      ..blendMode = blend;
    final round = brush.tip == 'round';
    for (final d in dabs) {
      paint.color = Color(_argb(colorOverride ?? d.color, d.alpha * alphaScale));
      final s = math.max(1.0, d.size.roundToDouble());
      final si = s.toInt();
      final left = si.isOdd ? d.x.floorToDouble() - (si - 1) / 2 : d.x.roundToDouble() - si / 2;
      final top = si.isOdd ? d.y.floorToDouble() - (si - 1) / 2 : d.y.roundToDouble() - si / 2;
      final r = Rect.fromLTWH(left, top, s, s);
      if (round && s >= 3) {
        canvas.drawOval(r, paint);
      } else {
        canvas.drawRect(r, paint);
      }
    }
  }

  static int _argb(int color, double alpha) {
    final a = (((color >> 24) & 0xFF) * alpha.clamp(0.0, 1.0)).round();
    return (a << 24) | (color & 0x00FFFFFF);
  }
}

/// How an accumulated stroke plane is merged into its target plane. Used
/// identically for the live preview and for the final commit, so what you
/// see while drawing is exactly what lands on the layer.
class StrokeComposite {
  StrokeComposite({
    required this.plane,
    required this.bounds,
    this.opacity = 1,
    this.blend = BlendMode.srcOver,
    this.erase = false,
    this.lockAlpha = false,
    this.grain,
    this.grainScale = 1,
    this.grainStrength = 0,
    this.selection,
    this.clipRect,
  });

  final TilePlane plane;
  final Rect bounds;
  final double opacity;
  final BlendMode blend;
  final bool erase, lockAlpha;
  final ui.Image? grain;
  final double grainScale, grainStrength;

  /// Selection mask (alpha = selected) limiting the stroke.
  final TilePlane? selection;

  /// Canvas rect (null for an infinite canvas).
  final Rect? clipRect;

  static final Paint _dstIn = Paint()..blendMode = BlendMode.dstIn;

  void paintOnto(Canvas c, TilePlane target, {Rect? cull, Paint? tilePaint}) {
    if (plane.isEmpty) return;
    var b = bounds;
    if (clipRect != null) b = b.intersect(clipRect!);
    if (cull != null) b = b.intersect(cull);
    if (b.isEmpty || b.width <= 0 || b.height <= 0) return;
    final lp = Paint();
    if (opacity < 1) lp.color = Color.fromRGBO(0, 0, 0, opacity.clamp(0.0, 1.0));
    final maskByTarget = lockAlpha && !erase && blend != BlendMode.srcOver;
    lp.blendMode = erase ? BlendMode.dstOut : (lockAlpha && blend == BlendMode.srcOver ? BlendMode.srcATop : blend);
    c.save();
    c.clipRect(b);
    c.saveLayer(b, lp);
    plane.paint(c, cull: b, paint: tilePaint);
    if (grain != null && grainStrength > 0) {
      final s = grainStrength.clamp(0.0, 1.0);
      final m = Float64List(16)
        ..[0] = grainScale
        ..[5] = grainScale
        ..[10] = 1
        ..[15] = 1;
      final gp = Paint()
        ..shader = ImageShader(grain!, TileMode.repeated, TileMode.repeated, m, filterQuality: FilterQuality.low)
        ..colorFilter = ColorFilter.matrix(<double>[1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, s, (1 - s) * 255])
        ..blendMode = BlendMode.dstIn;
      c.drawRect(b, gp);
    }
    if (selection != null) {
      c.saveLayer(b, _dstIn);
      selection!.paint(c, cull: b);
      c.restore();
    }
    if (maskByTarget) {
      c.saveLayer(b, _dstIn);
      target.paint(c, cull: b);
      c.restore();
    }
    c.restore();
    c.restore();
  }

  /// Bakes the stroke into [target].
  TilePlane commit(TilePlane target) {
    if (plane.isEmpty) return target;
    var keys = plane.keys;
    if (clipRect != null) {
      final allowed = tileKeysIn(clipRect!).toSet();
      keys = keys.where(allowed.contains);
    }
    final list = keys.toList();
    if (list.isEmpty) return target;
    return target.drawn((c) => paintOnto(c, target), keys: list);
  }
}

/// A regular (deposit) brush stroke being drawn.
class PaintStroke {
  PaintStroke({
    required this.brush,
    required Color color,
    List<Mat2D>? symmetry,
    int seed = 1,
    this.clipRect,
    this.selection,
    this.lockAlpha = false,
    double sizeScale = 1,
    bool simulatePressure = true,
  })  : gen = DabGenerator(brush, color, symmetry: symmetry, seed: seed, sizeScale: sizeScale, simulatePressure: simulatePressure),
        _painter = DabPainter(brush);

  final BrushPreset brush;
  final DabGenerator gen;
  final DabPainter _painter;
  final Rect? clipRect;
  final TilePlane? selection;
  final bool lockAlpha;

  TilePlane plane = TilePlane.empty;
  Rect? bounds;

  void add(StrokeInput s) => gen.add(s);

  /// Rasterises queued dabs. Returns true when the stroke changed.
  bool flush() {
    final dabs = gen.pending;
    if (dabs.isEmpty) return false;
    final keys = <int>{};
    Rect? b;
    for (final d in dabs) {
      final r = _painter.boundsOf(d);
      b = b == null ? r : b.expandToInclude(r);
      keys.addAll(tileKeysIn(r));
    }
    if (clipRect != null) {
      final allowed = tileKeysIn(clipRect!).toSet();
      keys.retainAll(allowed);
    }
    final batch = List<Dab>.of(dabs);
    dabs.clear();
    if (keys.isNotEmpty) {
      plane = plane.drawn((c) => _painter.draw(c, batch), keys: keys);
    }
    bounds = bounds == null ? b : bounds!.expandToInclude(b!);
    return true;
  }

  void finish() {
    gen.finish();
    flush();
  }

  StrokeComposite get composite => StrokeComposite(
        plane: plane,
        bounds: bounds ?? Rect.zero,
        opacity: brush.opacity,
        blend: brush.blend.mode,
        erase: brush.erase,
        lockAlpha: lockAlpha,
        grain: BrushTips.instance.grain(brush.grain),
        grainScale: brush.grainScale,
        grainStrength: brush.grain.isEmpty ? 0 : brush.grainStrength,
        selection: selection,
        clipRect: clipRect,
      );

  TilePlane commit(TilePlane target) => composite.commit(target);
}

/// Smudge / wet-mix stroke: works directly on a private copy of the target
/// plane, dragging pixels dab by dab entirely on the GPU.
class SmudgeStroke {
  SmudgeStroke({
    required this.brush,
    required TilePlane source,
    required this.color,
    List<Mat2D>? symmetry,
    int seed = 1,
    this.clipRect,
    this.selection,
    bool simulatePressure = true,
  })  : working = source,
        gen = DabGenerator(brush, color, symmetry: symmetry, seed: seed, simulatePressure: simulatePressure),
        _painter = DabPainter(brush),
        _symCount = (symmetry ?? const [Mat2D.identity]).length;

  final BrushPreset brush;
  final Color color;
  final DabGenerator gen;
  final DabPainter _painter;
  final Rect? clipRect;
  final TilePlane? selection;
  final int _symCount;

  /// Evolving result (replaces the layer pixels while the stroke is live).
  TilePlane working;
  Rect? bounds;

  final List<Dab> _queue = [];
  final List<Offset?> _last = [];
  int _dabIndex = 0;

  /// Dabs processed per frame; the rest stays queued so a fast stroke never
  /// stalls the UI.
  static const int maxPerFlush = 28;

  void add(StrokeInput s) => gen.add(s);

  bool get hasPending => _queue.isNotEmpty || gen.pending.isNotEmpty;

  bool flush({bool all = false}) {
    if (gen.pending.isNotEmpty) {
      _queue.addAll(gen.pending);
      gen.pending.clear();
    }
    if (_queue.isEmpty) return false;
    final n = all ? _queue.length : math.min(maxPerFlush, _queue.length);
    for (var i = 0; i < n; i++) {
      _apply(_queue[i]);
    }
    _queue.removeRange(0, n);
    return true;
  }

  void finish() {
    gen.finish();
    flush(all: true);
  }

  void _apply(Dab d) {
    final slot = _dabIndex % _symCount;
    _dabIndex++;
    while (_last.length <= slot) {
      _last.add(null);
    }
    final prev = _last[slot];
    final p = Offset(d.x, d.y);
    _last[slot] = p;

    final rect = _painter.boundsOf(d).roundedOut;
    if (clipRect != null && !rect.overlaps(clipRect!)) return;
    bounds = bounds == null ? rect : bounds!.expandToInclude(rect);

    final strength = (brush.smudge * (0.35 + 0.65 * d.alpha / math.max(0.001, brush.flow))).clamp(0.0, 0.98);
    final deposit = brush.engine == BrushEngine.mixer ? (d.alpha * (1.0 - brush.wet * 0.75)).clamp(0.0, 1.0) : 0.0;

    ui.Image? src;
    Offset shift = Offset.zero;
    if (prev != null && strength > 0) {
      shift = p - prev;
      if (shift.distanceSquared > 0.0001) {
        src = working.toImage(rect.shift(-shift));
      }
    }
    final base = working;
    final dab = [d];
    final kScale = strength / math.max(0.001, d.alpha);

    void ops(Canvas c) {
      final s = src;
      if (s != null) {
        // result = old * (1 - k*tip) + dragged * (k*tip)
        _painter.draw(c, dab, alphaScale: kScale, colorOverride: 0xFF000000, blend: BlendMode.dstOut);
        c.saveLayer(rect, Paint()..blendMode = BlendMode.plus);
        c.drawImage(s, rect.topLeft, Paint()..filterQuality = FilterQuality.none);
        c.saveLayer(rect, Paint()..blendMode = BlendMode.dstIn);
        _painter.draw(c, dab, alphaScale: kScale, colorOverride: 0xFF000000);
        c.restore();
        c.restore();
      }
      if (deposit > 0) {
        final a = deposit / math.max(0.001, d.alpha);
        if (brush.pigment) {
          // multiply pass = subtractive mixing with the paint underneath
          c.saveLayer(rect, Paint()..blendMode = BlendMode.multiply);
          _painter.draw(c, dab, alphaScale: a * 0.6);
          c.restore();
          _painter.draw(c, dab, alphaScale: a * 0.55);
        } else {
          _painter.draw(c, dab, alphaScale: a);
        }
      }
    }

    working = working.drawn((c) {
      c.save();
      c.clipRect(rect);
      if (clipRect != null) c.clipRect(clipRect!);
      final sel = selection;
      if (sel == null) {
        ops(c);
      } else {
        // old * (1 - selection) + modified * selection
        c.saveLayer(rect, Paint()..blendMode = BlendMode.dstOut);
        sel.paint(c, cull: rect);
        c.restore();
        c.saveLayer(rect, Paint()..blendMode = BlendMode.plus);
        base.paint(c, cull: rect);
        ops(c);
        c.saveLayer(rect, Paint()..blendMode = BlendMode.dstIn);
        sel.paint(c, cull: rect);
        c.restore();
        c.restore();
      }
      c.restore();
    }, area: clipRect == null ? rect : rect.intersect(clipRect!));
    src?.dispose();
  }
}

/// Renders a sample S-curve stroke for brush thumbnails.
ui.Image renderBrushPreview(BrushPreset brush, {int width = 220, int height = 56, Color color = const Color(0xFFFFFFFF)}) {
  final maxSize = height * 0.55;
  final scale = brush.size > maxSize ? maxSize / brush.size : 1.0;
  final b = brush.engine == BrushEngine.paint ? brush : brush.copyWith(engine: BrushEngine.paint);
  final stroke = PaintStroke(brush: b.copyWith(smoothing: 0, erase: false, blend: LayerBlend.normal, taper: 0), color: color, seed: 7, sizeScale: scale);
  const n = 48;
  for (var i = 0; i <= n; i++) {
    final t = i / n;
    final x = 14 + t * (width - 28);
    final y = height / 2 + math.sin(t * math.pi * 2) * height * 0.22;
    final pressure = math.sin(t * math.pi).clamp(0.0, 1.0);
    stroke.add(StrokeInput(Offset(x, y), pressure: 0.15 + 0.85 * pressure, timeMs: i * 8.0, hasPressure: true));
  }
  stroke.finish();
  final comp = stroke.composite;
  return renderToImage(width, height, (c) => comp.paintOnto(c, TilePlane.empty));
}
