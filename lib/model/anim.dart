import 'dart:math' as math;

import '../core/i18n.dart';

/// Interpolation used between a keyframe and the next one.
enum EaseType {
  linear,
  hold,
  easeIn,
  easeOut,
  easeInOut,
  cubicIn,
  cubicOut,
  cubicInOut,
  backIn,
  backOut,
  bounce,
  elastic,
  bezier,
}

extension EaseTypeLabel on EaseType {
  String get label => switch (this) {
        EaseType.linear => tr('Lineal', 'Linear'),
        EaseType.hold => tr('Mantener', 'Hold'),
        EaseType.easeIn => tr('Entrada suave', 'Ease in'),
        EaseType.easeOut => tr('Salida suave', 'Ease out'),
        EaseType.easeInOut => tr('Entrada/salida suave', 'Ease in-out'),
        EaseType.cubicIn => tr('Cúbica entrada', 'Cubic in'),
        EaseType.cubicOut => tr('Cúbica salida', 'Cubic out'),
        EaseType.cubicInOut => tr('Cúbica entrada/salida', 'Cubic in-out'),
        EaseType.backIn => tr('Anticipación', 'Back in'),
        EaseType.backOut => tr('Sobrepaso', 'Back out'),
        EaseType.bounce => tr('Rebote', 'Bounce'),
        EaseType.elastic => tr('Elástico', 'Elastic'),
        EaseType.bezier => tr('Personalizada', 'Custom'),
      };
}

class Ease {
  const Ease(this.type, [this.x1 = 0.42, this.y1 = 0.0, this.x2 = 0.58, this.y2 = 1.0]);

  final EaseType type;

  /// Control points of the cubic-bezier (only for [EaseType.bezier]).
  final double x1, y1, x2, y2;

  static const Ease linear = Ease(EaseType.linear);
  static const Ease hold = Ease(EaseType.hold);
  static const Ease smooth = Ease(EaseType.easeInOut);

  double transform(double t) {
    if (t <= 0) return 0;
    if (t >= 1) return 1;
    switch (type) {
      case EaseType.linear:
        return t;
      case EaseType.hold:
        return 0;
      case EaseType.easeIn:
        return t * t;
      case EaseType.easeOut:
        return 1 - (1 - t) * (1 - t);
      case EaseType.easeInOut:
        return t < 0.5 ? 2 * t * t : 1 - math.pow(-2 * t + 2, 2) / 2;
      case EaseType.cubicIn:
        return t * t * t;
      case EaseType.cubicOut:
        return 1 - math.pow(1 - t, 3).toDouble();
      case EaseType.cubicInOut:
        return t < 0.5 ? 4 * t * t * t : 1 - math.pow(-2 * t + 2, 3) / 2;
      case EaseType.backIn:
        const c1 = 1.70158, c3 = c1 + 1;
        return c3 * t * t * t - c1 * t * t;
      case EaseType.backOut:
        const c1 = 1.70158, c3 = c1 + 1;
        return 1 + c3 * math.pow(t - 1, 3) + c1 * math.pow(t - 1, 2);
      case EaseType.bounce:
        return _bounceOut(t);
      case EaseType.elastic:
        const c4 = (2 * math.pi) / 3;
        return math.pow(2, -10 * t) * math.sin((t * 10 - 0.75) * c4) + 1;
      case EaseType.bezier:
        return _cubicBezier(t);
    }
  }

  static double _bounceOut(double t) {
    const n1 = 7.5625, d1 = 2.75;
    if (t < 1 / d1) return n1 * t * t;
    if (t < 2 / d1) {
      final u = t - 1.5 / d1;
      return n1 * u * u + 0.75;
    }
    if (t < 2.5 / d1) {
      final u = t - 2.25 / d1;
      return n1 * u * u + 0.9375;
    }
    final u = t - 2.625 / d1;
    return n1 * u * u + 0.984375;
  }

  double _cubicBezier(double x) {
    // solve bezierX(s) = x by bisection, then return bezierY(s)
    double bx(double s) => 3 * (1 - s) * (1 - s) * s * x1 + 3 * (1 - s) * s * s * x2 + s * s * s;
    double by(double s) => 3 * (1 - s) * (1 - s) * s * y1 + 3 * (1 - s) * s * s * y2 + s * s * s;
    var lo = 0.0, hi = 1.0;
    for (var i = 0; i < 24; i++) {
      final mid = (lo + hi) / 2;
      if (bx(mid) < x) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return by((lo + hi) / 2);
  }

  Map<String, dynamic> toJson() => {
        't': type.name,
        if (type == EaseType.bezier) 'b': [x1, y1, x2, y2],
      };

  static Ease fromJson(dynamic j) {
    if (j == null) return Ease.linear;
    final m = j as Map<String, dynamic>;
    final type = EaseType.values.firstWhere((e) => e.name == m['t'], orElse: () => EaseType.linear);
    final b = m['b'] as List?;
    if (b != null && b.length == 4) {
      return Ease(type, (b[0] as num).toDouble(), (b[1] as num).toDouble(), (b[2] as num).toDouble(), (b[3] as num).toDouble());
    }
    return Ease(type);
  }

  @override
  bool operator ==(Object other) =>
      other is Ease && other.type == type && other.x1 == x1 && other.y1 == y1 && other.x2 == x2 && other.y2 == y2;

  @override
  int get hashCode => Object.hash(type, x1, y1, x2, y2);
}

class AnimKey {
  const AnimKey(this.frame, this.value, [this.ease = Ease.smooth]);
  final int frame;
  final double value;

  /// Interpolation towards the next key.
  final Ease ease;

  AnimKey copyWith({int? frame, double? value, Ease? ease}) => AnimKey(frame ?? this.frame, value ?? this.value, ease ?? this.ease);

  Map<String, dynamic> toJson() => {'f': frame, 'v': value, 'e': ease.toJson()};

  static AnimKey fromJson(dynamic j) {
    final m = j as Map<String, dynamic>;
    return AnimKey(m['f'] as int, (m['v'] as num).toDouble(), Ease.fromJson(m['e']));
  }
}

/// Immutable keyframe track of a single scalar property.
class AnimTrack {
  const AnimTrack(this.keys);
  static const AnimTrack none = AnimTrack(<AnimKey>[]);

  /// Sorted by frame, one key per frame.
  final List<AnimKey> keys;

  bool get isEmpty => keys.isEmpty;
  bool get isNotEmpty => keys.isNotEmpty;

  int _indexAtOrBefore(double frame) {
    var lo = 0, hi = keys.length - 1, res = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (keys[mid].frame <= frame) {
        res = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return res;
  }

  double? valueAt(double frame) {
    if (keys.isEmpty) return null;
    final i = _indexAtOrBefore(frame);
    if (i < 0) return keys.first.value;
    if (i >= keys.length - 1) return keys.last.value;
    final k0 = keys[i], k1 = keys[i + 1];
    final span = (k1.frame - k0.frame).toDouble();
    if (span <= 0) return k1.value;
    final t = k0.ease.transform((frame - k0.frame) / span);
    return k0.value + (k1.value - k0.value) * t;
  }

  AnimKey? keyAt(int frame) {
    final i = _indexAtOrBefore(frame.toDouble());
    return (i >= 0 && keys[i].frame == frame) ? keys[i] : null;
  }

  AnimTrack withKey(AnimKey k) {
    final out = <AnimKey>[];
    var placed = false;
    for (final e in keys) {
      if (e.frame == k.frame) {
        out.add(k);
        placed = true;
      } else {
        if (!placed && e.frame > k.frame) {
          out.add(k);
          placed = true;
        }
        out.add(e);
      }
    }
    if (!placed) out.add(k);
    return AnimTrack(out);
  }

  AnimTrack withoutKey(int frame) => AnimTrack(keys.where((k) => k.frame != frame).toList());

  AnimTrack movedKey(int from, int to) {
    final k = keyAt(from);
    if (k == null || from == to) return this;
    return withoutKey(from).withoutKey(to).withKey(k.copyWith(frame: to));
  }

  /// Shifts every key at or after [from] by [delta] frames (frame insert/remove).
  AnimTrack shifted(int from, int delta) {
    final out = <AnimKey>[];
    for (final k in keys) {
      if (k.frame < from) {
        out.add(k);
      } else if (delta < 0 && k.frame < from - delta) {
        // key falls inside the removed range
      } else {
        out.add(k.copyWith(frame: k.frame + delta));
      }
    }
    return AnimTrack(out);
  }

  List<dynamic> toJson() => keys.map((k) => k.toJson()).toList();

  static AnimTrack fromJson(dynamic j) => j == null ? AnimTrack.none : AnimTrack((j as List).map(AnimKey.fromJson).toList());
}

/// Animatable layer / camera properties.
enum Prop { x, y, scaleX, scaleY, rotation, opacity, anchorX, anchorY, zoom }

extension PropLabel on Prop {
  String get label => switch (this) {
        Prop.x => tr('Posición X', 'Position X'),
        Prop.y => tr('Posición Y', 'Position Y'),
        Prop.scaleX => tr('Escala X', 'Scale X'),
        Prop.scaleY => tr('Escala Y', 'Scale Y'),
        Prop.rotation => tr('Rotación', 'Rotation'),
        Prop.opacity => tr('Opacidad', 'Opacity'),
        Prop.anchorX => tr('Ancla X', 'Anchor X'),
        Prop.anchorY => tr('Ancla Y', 'Anchor Y'),
        Prop.zoom => tr('Zoom', 'Zoom'),
      };
}

Map<String, dynamic> tracksToJson(Map<Prop, AnimTrack> t) => {
      for (final e in t.entries)
        if (e.value.isNotEmpty) e.key.name: e.value.toJson(),
    };

Map<Prop, AnimTrack> tracksFromJson(dynamic j) {
  if (j == null) return const {};
  final out = <Prop, AnimTrack>{};
  (j as Map<String, dynamic>).forEach((k, v) {
    for (final p in Prop.values) {
      if (p.name == k) out[p] = AnimTrack.fromJson(v);
    }
  });
  return out;
}
