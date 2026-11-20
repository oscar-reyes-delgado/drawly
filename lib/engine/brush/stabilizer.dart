import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui';

import '../../core/i18n.dart';

/// How pointer samples are steadied before they reach the brush.
enum StabilizerMode {
  /// Each brush uses its own smoothing setting.
  brush,

  /// Exponential smoothing: the line follows the pointer with a soft delay.
  smooth,

  /// Average of the last samples: removes hand tremor.
  average,

  /// «Lazy mouse»: the line only moves when the pointer pulls a string longer
  /// than a radius, giving very clean curves.
  rope,

  /// Strongest: string + average + smoothing in a row. Very clean lines even
  /// with a shaky hand, at the cost of more delay.
  superStable,

  /// Smooths a lot when moving slowly (details) and little when moving fast
  /// (long strokes stay responsive).
  dynamic,

  /// Heavy, slow ink: the line chases the pointer at a limited speed and keeps
  /// moving on its own while the pointer rests.
  slow,
}

/// Stabilizer strength shown to people as a level from 0 to 10.
int stabilizerLevel(double strength) => (strength.clamp(0.0, 1.0) * 10).round();
double stabilizerStrengthOf(int level) => level.clamp(0, 10) / 10;

extension StabilizerModeX on StabilizerMode {
  String get label => switch (this) {
        StabilizerMode.brush => tr('Del pincel', 'Per brush'),
        StabilizerMode.smooth => tr('Suavizado', 'Smoothing'),
        StabilizerMode.average => tr('Promedio', 'Average'),
        StabilizerMode.rope => tr('Cuerda', 'Rope'),
        StabilizerMode.superStable => tr('Súper estable', 'Super stable'),
        StabilizerMode.dynamic => tr('Dinámico', 'Dynamic'),
        StabilizerMode.slow => tr('Lento', 'Slow'),
      };

  /// Whether the mode pulls a visible string.
  bool get usesRope => this == StabilizerMode.rope || this == StabilizerMode.superStable;

  /// Whether the line keeps catching up over time (needs [Stabilizer.pump]).
  bool get trails => this == StabilizerMode.slow;

  /// Whether a guide from the line to the pointer is drawn.
  bool get showsGuide => usesRope || trails;

  String get help => switch (this) {
        StabilizerMode.brush => tr('Cada pincel usa su propio suavizado.', 'Each brush uses its own smoothing.'),
        StabilizerMode.smooth => tr('La línea sigue al puntero con un retraso suave.', 'The line follows the pointer with a soft delay.'),
        StabilizerMode.average => tr('Promedia los últimos puntos y quita el temblor del pulso.', 'Averages the last points and removes hand tremor.'),
        StabilizerMode.rope => tr('La línea solo avanza cuando tiras de una cuerda: curvas muy limpias.', 'The line only moves when you pull a string: very clean curves.'),
        StabilizerMode.superStable =>
          tr('Cuerda, promedio y suavizado juntos: líneas limpísimas aunque tiemble la mano.', 'String, average and smoothing together: very clean lines even with a shaky hand.'),
        StabilizerMode.dynamic =>
          tr('Suaviza mucho al ir despacio y poco al ir rápido.', 'Smooths a lot when slow and little when fast.'),
        StabilizerMode.slow =>
          tr('La línea te sigue despacio, como tinta pesada, y sigue avanzando aunque pares.', 'The line follows you slowly, like heavy ink, and keeps going when you stop.'),
      };
}

/// Steadies a stroke. Feed every raw pointer position with [add]; it returns
/// the steadied points to draw (none, one or several). [finish] returns the
/// points that close the gap to the last raw position when [catchUp] is on.
class Stabilizer {
  Stabilizer({required this.mode, double strength = 0.5, this.ropeRadius = 24, this.catchUp = true, this.pixel = 1, double Function()? clock})
      : strength = strength.clamp(0.0, 1.0),
        _clock = clock ?? _stopwatchClock();

  static double Function() _stopwatchClock() {
    final w = Stopwatch()..start();
    return () => w.elapsedMicroseconds / 1000;
  }

  final StabilizerMode mode;

  /// 0 (none) .. 1 (strongest).
  final double strength;

  /// String length for [StabilizerMode.rope], in the same units as the points.
  final double ropeRadius;

  /// Draw the remaining distance to the pointer when the stroke ends.
  final bool catchUp;

  /// Size of one screen pixel in point units (speeds of the slow mode are in
  /// screen pixels so the feel does not change with zoom).
  final double pixel;

  final double Function() _clock;
  double? _lastMs;

  Offset? _pen;
  Offset? _raw;
  Offset? _anchor; // string end of the super-stable mode
  final Queue<Offset> _window = Queue();

  /// Where the line currently is (null before the first sample).
  Offset? get pen => _pen;

  /// Last raw pointer position.
  Offset? get raw => _raw;

  /// Samples averaged by [StabilizerMode.average] (and the super-stable mode).
  int get windowSize => 1 + (strength * (mode == StabilizerMode.superStable ? 16 : 24)).round();

  /// String length of the rope modes.
  double get ropeLength => ropeRadius * strength * (mode == StabilizerMode.superStable ? 0.8 : 1);

  /// Where the string is tied (the point the line is pulled towards), or the
  /// line's tip for the slow mode; null when the mode draws no guide.
  Offset? get ropeAnchor => switch (mode) {
        StabilizerMode.rope => _pen,
        StabilizerMode.superStable => _anchor,
        StabilizerMode.slow => _pen,
        _ => null,
      };

  Offset _averageOf(Offset p) {
    _window.add(p);
    while (_window.length > windowSize) {
      _window.removeFirst();
    }
    var sx = 0.0, sy = 0.0;
    for (final q in _window) {
      sx += q.dx;
      sy += q.dy;
    }
    return Offset(sx / _window.length, sy / _window.length);
  }

  /// Fastest speed of the slow mode, in point units per second.
  double get maxSpeed => (3000 - 2880 * strength) * pixel;

  /// How quickly the slow mode closes the gap (per second, exponential).
  double get followRate => 30 - 26 * strength;

  /// Whether the slow mode still lags behind the pointer.
  bool get lagging {
    final pen = _pen, raw = _raw;
    return active && mode.trails && pen != null && raw != null && (raw - pen).distance > 0.25 * pixel;
  }

  /// Advances the slow mode while the pointer rests; returns the new points.
  List<Offset> pump() => lagging ? _chase() : const [];

  List<Offset> _chase() {
    final now = _clock();
    final dtMs = ((now - (_lastMs ?? now - 16)).clamp(0.0, 50.0)).toDouble();
    _lastMs = now;
    final pen = _pen!, raw = _raw!;
    final gap = raw - pen;
    final dist = gap.distance;
    if (dist <= 0 || dtMs <= 0) return const [];
    final dt = dtMs / 1000;
    final move = math.min(dist * (1 - math.exp(-followRate * dt)), maxSpeed * dt);
    final next = pen + gap / dist * move;
    // dense points so the slow line stays smooth
    final n = math.max(1, (move / (2 * pixel)).ceil());
    final out = [for (var i = 1; i <= n; i++) Offset.lerp(pen, next, i / n)!];
    _pen = next;
    return out;
  }

  /// Whether this stabilizer changes the input at all.
  bool get active => mode != StabilizerMode.brush && strength > 0;

  List<Offset> add(Offset p) {
    final prevRaw = _raw;
    _raw = p;
    final pen = _pen;
    if (pen == null || !active) {
      _lastMs = _clock();
      _pen = p;
      _anchor = p;
      _window
        ..clear()
        ..add(p);
      return [p];
    }
    switch (mode) {
      case StabilizerMode.brush:
        _pen = p;
        return [p];
      case StabilizerMode.smooth:
        final k = 1.0 - strength * 0.95;
        final next = pen + (p - pen) * k;
        _pen = next;
        return [next];
      case StabilizerMode.average:
        final next = _averageOf(p);
        _pen = next;
        return [next];
      case StabilizerMode.rope:
        final r = ropeLength;
        final d = p - pen;
        final dist = d.distance;
        if (dist <= r) return const [];
        final next = p - d / dist * r;
        _pen = next;
        return [next];
      case StabilizerMode.superStable:
        // 1) string: the anchor only moves when pulled beyond the radius
        final a = _anchor ?? pen;
        final d = p - a;
        final dist = d.distance;
        final r = ropeLength;
        if (dist <= r) return const [];
        final anchor = p - d / dist * r;
        _anchor = anchor;
        // 2) average of the last anchor positions, 3) exponential smoothing
        final avg = _averageOf(anchor);
        final next = pen + (avg - pen) * (1.0 - strength * 0.85);
        _pen = next;
        return [next];
      case StabilizerMode.dynamic:
        final speed = prevRaw == null ? 0.0 : (p - prevRaw).distance;
        final slowest = 1.0 - strength * 0.97;
        final t = (speed / 25).clamp(0.0, 1.0);
        final next = pen + (p - pen) * (slowest + (1 - slowest) * t * t);
        _pen = next;
        return [next];
      case StabilizerMode.slow:
        return _chase();
    }
  }

  /// Points from the steadied line to the last raw position (empty when
  /// [catchUp] is off or nothing lags behind). Steps of at most [step].
  List<Offset> finish({double step = 2}) {
    final pen = _pen, raw = _raw;
    if (!catchUp || pen == null || raw == null || !active) return const [];
    final dist = (raw - pen).distance;
    if (dist < 0.5) return const [];
    final n = math.max(1, (dist / step).ceil());
    final out = [for (var i = 1; i <= n; i++) Offset.lerp(pen, raw, i / n)!];
    _pen = raw;
    _anchor = raw;
    return out;
  }
}
