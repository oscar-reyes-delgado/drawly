import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui';

import '../core/color_utils.dart';
import '../core/i18n.dart';

enum GradientKind { linear, radial, angular, diamond, reflected }

extension GradientKindLabel on GradientKind {
  String get label => switch (this) {
        GradientKind.linear => tr('Lineal', 'Linear'),
        GradientKind.radial => tr('Radial', 'Radial'),
        GradientKind.angular => tr('Angular', 'Angular'),
        GradientKind.diamond => tr('Diamante', 'Diamond'),
        GradientKind.reflected => tr('Reflejado', 'Reflected'),
      };
}

class GradStop {
  const GradStop(this.t, this.color);
  final double t;
  final Color color;

  Map<String, dynamic> toJson() => {'t': t, 'c': color.toARGB32()};
  static GradStop fromJson(dynamic j) => GradStop(((j as Map)['t'] as num).toDouble(), Color(j['c'] as int));
}

/// A colour ramp plus its geometry ([from] is the origin / centre, [to]
/// the end point that defines length and direction).
class GradientSpec {
  const GradientSpec({
    this.kind = GradientKind.linear,
    required this.stops,
    this.from = Offset.zero,
    this.to = const Offset(100, 0),
    this.repeat = false,
  });

  final GradientKind kind;
  final List<GradStop> stops;
  final Offset from, to;
  final bool repeat;

  static const GradientSpec blackWhite = GradientSpec(stops: [
    GradStop(0, Color(0xFF000000)),
    GradStop(1, Color(0xFFFFFFFF)),
  ]);

  factory GradientSpec.twoColor(Color a, Color b, {GradientKind kind = GradientKind.linear}) =>
      GradientSpec(kind: kind, stops: [GradStop(0, a), GradStop(1, b)]);

  GradientSpec copyWith({GradientKind? kind, List<GradStop>? stops, Offset? from, Offset? to, bool? repeat}) => GradientSpec(
        kind: kind ?? this.kind,
        stops: stops ?? this.stops,
        from: from ?? this.from,
        to: to ?? this.to,
        repeat: repeat ?? this.repeat,
      );

  List<GradStop> get sorted => [...stops]..sort((a, b) => a.t.compareTo(b.t));

  Color colorAt(double t) {
    final s = sorted;
    if (s.isEmpty) return const Color(0x00000000);
    if (t <= s.first.t) return s.first.color;
    if (t >= s.last.t) return s.last.color;
    for (var i = 0; i < s.length - 1; i++) {
      if (t >= s[i].t && t <= s[i + 1].t) {
        final span = s[i + 1].t - s[i].t;
        return lerpColor(s[i].color, s[i + 1].color, span <= 0 ? 0 : (t - s[i].t) / span);
      }
    }
    return s.last.color;
  }

  /// 256-entry premultiplied RGBA lookup table of the ramp.
  Uint8List lut() {
    final out = Uint8List(256 * 4);
    for (var i = 0; i < 256; i++) {
      final c = colorAt(i / 255.0);
      out[i * 4] = (c.r * c.a * 255).round();
      out[i * 4 + 1] = (c.g * c.a * 255).round();
      out[i * 4 + 2] = (c.b * c.a * 255).round();
      out[i * 4 + 3] = (c.a * 255).round();
    }
    return out;
  }

  ui.Shader _shader(GradientKind k) {
    final s = sorted;
    final colors = s.map((e) => e.color).toList();
    final ts = s.map((e) => e.t.clamp(0.0, 1.0)).toList();
    if (colors.length == 1) {
      colors.add(colors.first);
      ts.add(1);
    }
    final tile = repeat ? TileMode.repeated : TileMode.clamp;
    final d = to - from;
    switch (k) {
      case GradientKind.radial:
        return ui.Gradient.radial(from, math.max(d.distance, 0.001), colors, ts, tile);
      case GradientKind.angular:
        final ang = math.atan2(d.dy, d.dx);
        final m = Float64List(16)
          ..[0] = math.cos(ang)
          ..[1] = math.sin(ang)
          ..[4] = -math.sin(ang)
          ..[5] = math.cos(ang)
          ..[10] = 1
          ..[15] = 1
          ..[12] = from.dx - (math.cos(ang) * from.dx - math.sin(ang) * from.dy)
          ..[13] = from.dy - (math.sin(ang) * from.dx + math.cos(ang) * from.dy);
        return ui.Gradient.sweep(from, colors, ts, TileMode.clamp, 0, math.pi * 2, m);
      case GradientKind.reflected:
        return ui.Gradient.linear(from, to, colors, ts, TileMode.mirror);
      case GradientKind.linear:
      case GradientKind.diamond:
        return ui.Gradient.linear(from, to, colors, ts, tile);
    }
  }

  /// Fills [canvas] (whatever the current clip is) with this gradient.
  void paint(Canvas canvas, Rect area, {Paint? base}) {
    final p = (base ?? Paint())..isAntiAlias = true;
    if (kind != GradientKind.diamond) {
      p.shader = _shader(kind);
      canvas.drawRect(area, p);
      p.shader = null;
      return;
    }
    // Diamond: |x|/r + |y|/r is linear inside each quadrant of the local frame.
    final d = to - from;
    final r = math.max(d.distance, 0.001);
    final ang = math.atan2(d.dy, d.dx);
    final s = sorted;
    final colors = s.map((e) => e.color).toList();
    final ts = s.map((e) => e.t.clamp(0.0, 1.0)).toList();
    if (colors.length == 1) {
      colors.add(colors.first);
      ts.add(1);
    }
    canvas.save();
    canvas.clipRect(area);
    canvas.translate(from.dx, from.dy);
    canvas.rotate(ang);
    const big = 1e5;
    for (final q in const [Offset(1, 1), Offset(-1, 1), Offset(-1, -1), Offset(1, -1)]) {
      // gradient along the quadrant diagonal: t = (x*qx + y*qy) / r
      final end = Offset(q.dx * r / 2, q.dy * r / 2);
      p.shader = ui.Gradient.linear(Offset.zero, end, colors, ts, repeat ? TileMode.repeated : TileMode.clamp);
      final rect = Rect.fromLTRB(q.dx > 0 ? 0 : -big, q.dy > 0 ? 0 : -big, q.dx > 0 ? big : 0, q.dy > 0 ? big : 0);
      canvas.drawRect(rect, p);
    }
    p.shader = null;
    canvas.restore();
  }

  ui.Shader toShader() => _shader(kind == GradientKind.diamond ? GradientKind.linear : kind);

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'stops': stops.map((s) => s.toJson()).toList(),
        'from': [from.dx, from.dy],
        'to': [to.dx, to.dy],
        'repeat': repeat,
      };

  static GradientSpec fromJson(dynamic j) {
    final m = j as Map<String, dynamic>;
    final f = m['from'] as List, t = m['to'] as List;
    return GradientSpec(
      kind: GradientKind.values.firstWhere((k) => k.name == m['kind'], orElse: () => GradientKind.linear),
      stops: (m['stops'] as List).map(GradStop.fromJson).toList(),
      from: Offset((f[0] as num).toDouble(), (f[1] as num).toDouble()),
      to: Offset((t[0] as num).toDouble(), (t[1] as num).toDouble()),
      repeat: m['repeat'] as bool? ?? false,
    );
  }
}

/// Built-in gradient presets.
List<(String, List<GradStop>)> gradientPresets() => [
      (tr('Atardecer', 'Sunset'), const [GradStop(0, Color(0xFF2B1055)), GradStop(0.5, Color(0xFFD53369)), GradStop(1, Color(0xFFFFB56B))]),
      (tr('Océano', 'Ocean'), const [GradStop(0, Color(0xFF0B486B)), GradStop(1, Color(0xFF7EE8FA))]),
      (tr('Bosque', 'Forest'), const [GradStop(0, Color(0xFF134E5E)), GradStop(1, Color(0xFF71B280))]),
      (tr('Fuego', 'Fire'), const [GradStop(0, Color(0xFF200000)), GradStop(0.4, Color(0xFFE62E00)), GradStop(0.8, Color(0xFFFFC400)), GradStop(1, Color(0xFFFFFFE0))]),
      (tr('Arcoíris', 'Rainbow'), const [
        GradStop(0, Color(0xFFFF0000)),
        GradStop(0.17, Color(0xFFFF9900)),
        GradStop(0.33, Color(0xFFFFFF00)),
        GradStop(0.5, Color(0xFF00CC00)),
        GradStop(0.67, Color(0xFF0066FF)),
        GradStop(0.83, Color(0xFF6600CC)),
        GradStop(1, Color(0xFFFF00AA)),
      ]),
      (tr('Metal', 'Metal'), const [GradStop(0, Color(0xFF30363D)), GradStop(0.45, Color(0xFFE6EBF0)), GradStop(0.55, Color(0xFF8E99A5)), GradStop(1, Color(0xFFF6F8FA))]),
      (tr('Piel', 'Skin'), const [GradStop(0, Color(0xFF8D5524)), GradStop(0.5, Color(0xFFE0AC69)), GradStop(1, Color(0xFFFFDBAC))]),
      (tr('Noche', 'Night'), const [GradStop(0, Color(0xFF020111)), GradStop(0.6, Color(0xFF20124D)), GradStop(1, Color(0xFF5C4A9E))]),
    ];
