import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:ui';

import '../core/ids.dart';
import '../core/mat2d.dart';
import 'gradient.dart';

enum NodeKind { corner, smooth, symmetric }

/// A Bézier anchor with absolute handle positions.
class VNode {
  const VNode(this.p, {Offset? hIn, Offset? hOut, this.kind = NodeKind.corner, this.width = 1})
      : hIn = hIn ?? p,
        hOut = hOut ?? p;

  final Offset p, hIn, hOut;
  final NodeKind kind;

  /// Relative stroke width at this node (variable-width strokes).
  final double width;

  bool get hasIn => hIn != p;
  bool get hasOut => hOut != p;

  VNode copyWith({Offset? p, Offset? hIn, Offset? hOut, NodeKind? kind, double? width}) =>
      VNode(p ?? this.p, hIn: hIn ?? this.hIn, hOut: hOut ?? this.hOut, kind: kind ?? this.kind, width: width ?? this.width);

  VNode moved(Offset d) => VNode(p + d, hIn: hIn + d, hOut: hOut + d, kind: kind, width: width);

  VNode transformed(Mat2D m) => VNode(m.apply(p), hIn: m.apply(hIn), hOut: m.apply(hOut), kind: kind, width: width);

  VNode get asCorner => VNode(p, kind: NodeKind.corner, width: width);

  List<double> toJson() => [p.dx, p.dy, hIn.dx, hIn.dy, hOut.dx, hOut.dy, kind.index.toDouble(), width];

  static VNode fromJson(dynamic j) {
    final l = (j as List).map((e) => (e as num).toDouble()).toList();
    return VNode(
      Offset(l[0], l[1]),
      hIn: Offset(l[2], l[3]),
      hOut: Offset(l[4], l[5]),
      kind: NodeKind.values[l[6].toInt().clamp(0, 2)],
      width: l.length > 7 ? l[7] : 1,
    );
  }
}

class VPath {
  const VPath(this.nodes, {this.closed = false});
  final List<VNode> nodes;
  final bool closed;

  VPath copyWith({List<VNode>? nodes, bool? closed}) => VPath(nodes ?? this.nodes, closed: closed ?? this.closed);

  VPath transformed(Mat2D m) => VPath(nodes.map((n) => n.transformed(m)).toList(), closed: closed);

  void addTo(ui.Path path) {
    if (nodes.isEmpty) return;
    path.moveTo(nodes.first.p.dx, nodes.first.p.dy);
    for (var i = 1; i < nodes.length; i++) {
      _seg(path, nodes[i - 1], nodes[i]);
    }
    if (closed && nodes.length > 1) {
      _seg(path, nodes.last, nodes.first);
      path.close();
    }
  }

  static void _seg(ui.Path path, VNode a, VNode b) {
    if (!a.hasOut && !b.hasIn) {
      path.lineTo(b.p.dx, b.p.dy);
    } else {
      path.cubicTo(a.hOut.dx, a.hOut.dy, b.hIn.dx, b.hIn.dy, b.p.dx, b.p.dy);
    }
  }

  ui.Path toPath() {
    final p = ui.Path();
    addTo(p);
    return p;
  }

  Map<String, dynamic> toJson() => {'n': nodes.map((n) => n.toJson()).toList(), 'c': closed};

  static VPath fromJson(dynamic j) =>
      VPath(((j as Map)['n'] as List).map(VNode.fromJson).toList(), closed: j['c'] as bool? ?? false);

  // ---- primitive builders -------------------------------------------------

  static VPath rect(Rect r, {double radius = 0}) {
    if (radius <= 0) {
      return VPath([VNode(r.topLeft), VNode(r.topRight), VNode(r.bottomRight), VNode(r.bottomLeft)], closed: true);
    }
    final rad = math.min(radius, math.min(r.width, r.height) / 2);
    const k = 0.5522847498;
    final c = rad * k;
    final l = r.left, t = r.top, rt = r.right, b = r.bottom;
    return VPath([
      VNode(Offset(l + rad, t), hIn: Offset(l + rad - c, t)),
      VNode(Offset(rt - rad, t), hOut: Offset(rt - rad + c, t)),
      VNode(Offset(rt, t + rad), hIn: Offset(rt, t + rad - c)),
      VNode(Offset(rt, b - rad), hOut: Offset(rt, b - rad + c)),
      VNode(Offset(rt - rad, b), hIn: Offset(rt - rad + c, b)),
      VNode(Offset(l + rad, b), hOut: Offset(l + rad - c, b)),
      VNode(Offset(l, b - rad), hIn: Offset(l, b - rad + c)),
      VNode(Offset(l, t + rad), hOut: Offset(l, t + rad - c)),
    ], closed: true);
  }

  static VPath ellipse(Rect r) {
    const k = 0.5522847498;
    final cx = r.center.dx, cy = r.center.dy, rx = r.width / 2, ry = r.height / 2;
    final ox = rx * k, oy = ry * k;
    return VPath([
      VNode(Offset(cx, cy - ry), hIn: Offset(cx - ox, cy - ry), hOut: Offset(cx + ox, cy - ry), kind: NodeKind.symmetric),
      VNode(Offset(cx + rx, cy), hIn: Offset(cx + rx, cy - oy), hOut: Offset(cx + rx, cy + oy), kind: NodeKind.symmetric),
      VNode(Offset(cx, cy + ry), hIn: Offset(cx + ox, cy + ry), hOut: Offset(cx - ox, cy + ry), kind: NodeKind.symmetric),
      VNode(Offset(cx - rx, cy), hIn: Offset(cx - rx, cy + oy), hOut: Offset(cx - rx, cy - oy), kind: NodeKind.symmetric),
    ], closed: true);
  }

  static VPath polygon(Offset center, double radius, int sides, {double rotation = -math.pi / 2}) {
    final n = math.max(3, sides);
    return VPath([
      for (var i = 0; i < n; i++)
        VNode(center + Offset(math.cos(rotation + i * 2 * math.pi / n), math.sin(rotation + i * 2 * math.pi / n)) * radius),
    ], closed: true);
  }

  static VPath star(Offset center, double outer, double inner, int points, {double rotation = -math.pi / 2}) {
    final n = math.max(3, points);
    return VPath([
      for (var i = 0; i < n * 2; i++)
        VNode(center +
            Offset(math.cos(rotation + i * math.pi / n), math.sin(rotation + i * math.pi / n)) * (i.isEven ? outer : inner)),
    ], closed: true);
  }

  static VPath line(Offset a, Offset b) => VPath([VNode(a), VNode(b)]);

  static VPath polyline(List<Offset> pts, {bool closed = false}) => VPath(pts.map((p) => VNode(p)).toList(), closed: closed);
}

enum FillKind { none, solid, gradient, pattern }

enum PatternKind { stripes, dots, checker, crosshatch, grid, waves }

class VFill {
  const VFill.none()
      : kind = FillKind.none,
        color = const Color(0x00000000),
        gradient = null,
        pattern = PatternKind.stripes,
        patternScale = 1;
  const VFill.solid(this.color)
      : kind = FillKind.solid,
        gradient = null,
        pattern = PatternKind.stripes,
        patternScale = 1;
  const VFill.gradient(GradientSpec this.gradient)
      : kind = FillKind.gradient,
        color = const Color(0xFF000000),
        pattern = PatternKind.stripes,
        patternScale = 1;
  const VFill.pattern(this.pattern, this.color, {this.patternScale = 1})
      : kind = FillKind.pattern,
        gradient = null;

  final FillKind kind;
  final Color color;
  final GradientSpec? gradient;
  final PatternKind pattern;
  final double patternScale;

  bool get isNone => kind == FillKind.none;

  Map<String, dynamic> toJson() => {
        'k': kind.name,
        'c': color.toARGB32(),
        if (gradient != null) 'g': gradient!.toJson(),
        if (kind == FillKind.pattern) 'p': pattern.name,
        if (kind == FillKind.pattern) 'ps': patternScale,
      };

  static VFill fromJson(dynamic j) {
    if (j == null) return const VFill.none();
    final m = j as Map<String, dynamic>;
    final color = Color(m['c'] as int? ?? 0xFF000000);
    switch (m['k']) {
      case 'solid':
        return VFill.solid(color);
      case 'gradient':
        return VFill.gradient(GradientSpec.fromJson(m['g']));
      case 'pattern':
        return VFill.pattern(
          PatternKind.values.firstWhere((p) => p.name == m['p'], orElse: () => PatternKind.stripes),
          color,
          patternScale: (m['ps'] as num?)?.toDouble() ?? 1,
        );
    }
    return const VFill.none();
  }
}

/// Stroke width distribution along the path.
enum WidthProfile { uniform, taperEnd, taperStart, taperBoth, bulge, nodes }

class VStroke {
  const VStroke({
    this.color = const Color(0xFF000000),
    this.width = 2,
    this.cap = StrokeCap.round,
    this.join = StrokeJoin.round,
    this.miterLimit = 4,
    this.dash = const [],
    this.profile = WidthProfile.uniform,
  });

  final Color color;
  final double width;
  final StrokeCap cap;
  final StrokeJoin join;
  final double miterLimit;

  /// Alternating on/off lengths (empty = solid).
  final List<double> dash;
  final WidthProfile profile;

  VStroke copyWith({
    Color? color,
    double? width,
    StrokeCap? cap,
    StrokeJoin? join,
    double? miterLimit,
    List<double>? dash,
    WidthProfile? profile,
  }) =>
      VStroke(
        color: color ?? this.color,
        width: width ?? this.width,
        cap: cap ?? this.cap,
        join: join ?? this.join,
        miterLimit: miterLimit ?? this.miterLimit,
        dash: dash ?? this.dash,
        profile: profile ?? this.profile,
      );

  Map<String, dynamic> toJson() => {
        'c': color.toARGB32(),
        'w': width,
        'cap': cap.index,
        'join': join.index,
        'ml': miterLimit,
        if (dash.isNotEmpty) 'dash': dash,
        'pr': profile.name,
      };

  static VStroke? fromJson(dynamic j) {
    if (j == null) return null;
    final m = j as Map<String, dynamic>;
    return VStroke(
      color: Color(m['c'] as int),
      width: (m['w'] as num).toDouble(),
      cap: StrokeCap.values[(m['cap'] as int? ?? 1).clamp(0, 2)],
      join: StrokeJoin.values[(m['join'] as int? ?? 1).clamp(0, 2)],
      miterLimit: (m['ml'] as num?)?.toDouble() ?? 4,
      dash: ((m['dash'] as List?) ?? const []).map((e) => (e as num).toDouble()).toList(),
      profile: WidthProfile.values.firstWhere((p) => p.name == m['pr'], orElse: () => WidthProfile.uniform),
    );
  }
}

/// One vector object: a compound path with fill and stroke.
class VShape {
  VShape({
    String? id,
    this.name = '',
    required this.paths,
    this.fill = const VFill.none(),
    this.stroke,
    this.opacity = 1,
    this.evenOdd = false,
  }) : id = id ?? newId('s');

  final String id;
  final String name;
  final List<VPath> paths;
  final VFill fill;
  final VStroke? stroke;
  final double opacity;
  final bool evenOdd;

  /// Geometry as a ui.Path (cached; shapes are immutable).
  late final ui.Path path = _build();

  ui.Path _build() {
    final p = ui.Path()..fillType = evenOdd ? PathFillType.evenOdd : PathFillType.nonZero;
    for (final vp in paths) {
      vp.addTo(p);
    }
    return p;
  }

  Rect get bounds {
    final b = path.getBounds();
    final w = (stroke?.width ?? 0) / 2;
    return b.inflate(w + 1);
  }

  VShape copyWith({
    String? id,
    String? name,
    List<VPath>? paths,
    VFill? fill,
    VStroke? stroke,
    bool clearStroke = false,
    double? opacity,
    bool? evenOdd,
  }) =>
      VShape(
        id: id ?? this.id,
        name: name ?? this.name,
        paths: paths ?? this.paths,
        fill: fill ?? this.fill,
        stroke: clearStroke ? null : (stroke ?? this.stroke),
        opacity: opacity ?? this.opacity,
        evenOdd: evenOdd ?? this.evenOdd,
      );

  VShape transformed(Mat2D m) {
    final s = m.scaleFactor;
    var f = fill;
    if (f.gradient != null) {
      f = VFill.gradient(f.gradient!.copyWith(from: m.apply(f.gradient!.from), to: m.apply(f.gradient!.to)));
    }
    return copyWith(
      paths: paths.map((p) => p.transformed(m)).toList(),
      fill: f,
      stroke: stroke?.copyWith(width: stroke!.width * s),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        if (name.isNotEmpty) 'name': name,
        'paths': paths.map((p) => p.toJson()).toList(),
        'fill': fill.toJson(),
        if (stroke != null) 'stroke': stroke!.toJson(),
        'op': opacity,
        'eo': evenOdd,
      };

  static VShape fromJson(dynamic j) {
    final m = j as Map<String, dynamic>;
    return VShape(
      id: m['id'] as String?,
      name: m['name'] as String? ?? '',
      paths: (m['paths'] as List).map(VPath.fromJson).toList(),
      fill: VFill.fromJson(m['fill']),
      stroke: VStroke.fromJson(m['stroke']),
      opacity: (m['op'] as num?)?.toDouble() ?? 1,
      evenOdd: m['eo'] as bool? ?? false,
    );
  }
}

/// The content of one vector drawing (cel): an ordered list of shapes.
class VectorArt {
  const VectorArt(this.shapes);
  static const VectorArt empty = VectorArt(<VShape>[]);

  final List<VShape> shapes;

  bool get isEmpty => shapes.isEmpty;

  Rect? get bounds {
    Rect? b;
    for (final s in shapes) {
      b = b == null ? s.bounds : b.expandToInclude(s.bounds);
    }
    return b;
  }

  VShape? byId(String id) {
    for (final s in shapes) {
      if (s.id == id) return s;
    }
    return null;
  }

  VectorArt added(VShape s) => VectorArt([...shapes, s]);

  VectorArt replaced(VShape s) => VectorArt([for (final e in shapes) e.id == s.id ? s : e]);

  VectorArt removed(Set<String> ids) => VectorArt(shapes.where((s) => !ids.contains(s.id)).toList());

  VectorArt mapped(VShape Function(VShape) f) => VectorArt(shapes.map(f).toList());

  List<dynamic> toJson() => shapes.map((s) => s.toJson()).toList();

  static VectorArt fromJson(dynamic j) => j == null ? VectorArt.empty : VectorArt((j as List).map(VShape.fromJson).toList());
}
