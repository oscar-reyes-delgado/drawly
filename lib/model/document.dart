import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../core/i18n.dart';
import '../core/ids.dart';
import '../core/mat2d.dart';
import '../engine/tiles.dart';
import 'anim.dart';
import 'layer.dart';

// ---------------------------------------------------------------------------
// Timeline
// ---------------------------------------------------------------------------

class Marker {
  const Marker(this.frame, this.label, [this.color = 0xFFFFC107]);
  final int frame;
  final String label;
  final int color;

  Map<String, dynamic> toJson() => {'f': frame, 'l': label, 'c': color};
  static Marker fromJson(dynamic j) => Marker((j as Map)['f'] as int, j['l'] as String? ?? '', j['c'] as int? ?? 0xFFFFC107);
}

/// A named span of the timeline (scene / shot / storyboard panel).
class Scene {
  const Scene({required this.id, required this.name, required this.start, required this.length, this.notes = '', this.transition = 'cut', this.transitionFrames = 0});
  final String id, name, notes;
  final int start, length;

  /// Transition into this scene: cut, fade, dissolve, wipeLeft, wipeRight,
  /// wipeUp, wipeDown, iris.
  final String transition;
  final int transitionFrames;

  int get end => start + length;

  Scene copyWith({String? name, int? start, int? length, String? notes, String? transition, int? transitionFrames}) => Scene(
        id: id,
        name: name ?? this.name,
        start: start ?? this.start,
        length: length ?? this.length,
        notes: notes ?? this.notes,
        transition: transition ?? this.transition,
        transitionFrames: transitionFrames ?? this.transitionFrames,
      );

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 's': start, 'n': length, 'notes': notes, 'tr': transition, 'tf': transitionFrames};
  static Scene fromJson(dynamic j) {
    final m = j as Map<String, dynamic>;
    return Scene(
      id: m['id'] as String? ?? newId('sc'),
      name: m['name'] as String? ?? '',
      start: m['s'] as int? ?? 0,
      length: m['n'] as int? ?? 24,
      notes: m['notes'] as String? ?? '',
      transition: m['tr'] as String? ?? 'cut',
      transitionFrames: m['tf'] as int? ?? 0,
    );
  }
}

class AudioClip {
  const AudioClip({
    required this.id,
    required this.name,
    required this.assetId,
    this.startFrame = 0,
    this.volume = 1,
    this.fadeIn = 0,
    this.fadeOut = 0,
    this.trimStart = 0,
    this.trimEnd = 0,
    this.muted = false,
    this.duration = 0,
    this.kind = 'music',
  });

  final String id, name, assetId;
  final int startFrame;
  final double volume;

  /// Fade lengths and trims in seconds.
  final double fadeIn, fadeOut, trimStart, trimEnd;
  final bool muted;

  /// Source duration in seconds.
  final double duration;

  /// music | voice | sfx
  final String kind;

  double get playLength => math.max(0, duration - trimStart - trimEnd);

  AudioClip copyWith({
    String? name,
    int? startFrame,
    double? volume,
    double? fadeIn,
    double? fadeOut,
    double? trimStart,
    double? trimEnd,
    bool? muted,
    double? duration,
    String? kind,
  }) =>
      AudioClip(
        id: id,
        assetId: assetId,
        name: name ?? this.name,
        startFrame: startFrame ?? this.startFrame,
        volume: volume ?? this.volume,
        fadeIn: fadeIn ?? this.fadeIn,
        fadeOut: fadeOut ?? this.fadeOut,
        trimStart: trimStart ?? this.trimStart,
        trimEnd: trimEnd ?? this.trimEnd,
        muted: muted ?? this.muted,
        duration: duration ?? this.duration,
        kind: kind ?? this.kind,
      );

  Map<String, dynamic> toJson() => {
        'id': id, 'name': name, 'asset': assetId, 'start': startFrame, 'vol': volume,
        'fi': fadeIn, 'fo': fadeOut, 'ts': trimStart, 'te': trimEnd, 'muted': muted, 'dur': duration, 'kind': kind,
      };

  static AudioClip fromJson(dynamic j) {
    final m = j as Map<String, dynamic>;
    double d(String k, double def) => (m[k] as num?)?.toDouble() ?? def;
    return AudioClip(
      id: m['id'] as String, name: m['name'] as String? ?? '', assetId: m['asset'] as String,
      startFrame: m['start'] as int? ?? 0, volume: d('vol', 1), fadeIn: d('fi', 0), fadeOut: d('fo', 0),
      trimStart: d('ts', 0), trimEnd: d('te', 0), muted: m['muted'] as bool? ?? false, duration: d('dur', 0),
      kind: m['kind'] as String? ?? 'music',
    );
  }
}

/// Animated camera: x/y pan (offset of the view centre), zoom and rotation.
class Camera {
  const Camera({
    this.enabled = false,
    this.tracks = const {},
    this.shakeAmp = 0,
    this.shakeFreq = 6,
    this.focalLength = 1000,
    this.focusDepth = 0,
    this.aperture = 0,
  });
  final bool enabled;
  final Map<Prop, AnimTrack> tracks;

  /// Procedural hand-held shake (pixels / cycles per second).
  final double shakeAmp, shakeFreq;

  /// 2.5D: perspective strength, depth in focus and depth-of-field amount.
  final double focalLength, focusDepth, aperture;

  double valueAt(Prop p, double frame) {
    final t = tracks[p];
    if (t != null && t.isNotEmpty) return t.valueAt(frame)!;
    return p == Prop.zoom ? 1 : 0;
  }

  static double _noise(double t, int seed) {
    // smooth value noise
    double h(int i) {
      var n = (i * 374761393 + seed * 668265263) & 0x7FFFFFFF;
      n = ((n ^ (n >> 13)) * 1274126177) & 0x7FFFFFFF;
      return (n & 0xFFFF) / 32767.5 - 1.0;
    }

    final i = t.floor();
    final f = t - i;
    final u = f * f * (3 - 2 * f);
    return h(i) + (h(i + 1) - h(i)) * u;
  }

  /// View transform for a layer at [depth] (0 = camera plane).
  Mat2D matrixAt(double frame, Size comp, {double depth = 0, double fps = 24}) {
    if (!enabled) return Mat2D.identity;
    var x = valueAt(Prop.x, frame), y = valueAt(Prop.y, frame);
    final zoom = math.max(0.01, valueAt(Prop.zoom, frame));
    var rot = valueAt(Prop.rotation, frame);
    if (shakeAmp > 0) {
      final t = frame / fps * shakeFreq;
      x += _noise(t, 11) * shakeAmp;
      y += _noise(t, 23) * shakeAmp;
      rot += _noise(t, 37) * shakeAmp * 0.05;
    }
    // parallax: distant layers move and scale less
    final par = focalLength / math.max(1, focalLength + depth);
    final cx = comp.width / 2, cy = comp.height / 2;
    final z = 1 + (zoom - 1) * par;
    return Mat2D.translation(cx, cy) * Mat2D.scale(z) * Mat2D.rotation(-degToRad(rot)) * Mat2D.translation(-cx - x * par, -cy - y * par);
  }

  /// Blur sigma for depth of field at [depth].
  double blurAt(double depth) => aperture <= 0 ? 0 : (depth - focusDepth).abs() / 100 * aperture;

  Camera copyWith({
    bool? enabled,
    Map<Prop, AnimTrack>? tracks,
    double? shakeAmp,
    double? shakeFreq,
    double? focalLength,
    double? focusDepth,
    double? aperture,
  }) =>
      Camera(
        enabled: enabled ?? this.enabled,
        tracks: tracks ?? this.tracks,
        shakeAmp: shakeAmp ?? this.shakeAmp,
        shakeFreq: shakeFreq ?? this.shakeFreq,
        focalLength: focalLength ?? this.focalLength,
        focusDepth: focusDepth ?? this.focusDepth,
        aperture: aperture ?? this.aperture,
      );

  Map<String, dynamic> toJson() => {
        'on': enabled, 'tracks': tracksToJson(tracks), 'sa': shakeAmp, 'sf': shakeFreq,
        'fl': focalLength, 'fd': focusDepth, 'ap': aperture,
      };

  static Camera fromJson(dynamic j) {
    if (j == null) return const Camera();
    final m = j as Map<String, dynamic>;
    double d(String k, double def) => (m[k] as num?)?.toDouble() ?? def;
    return Camera(
      enabled: m['on'] as bool? ?? false, tracks: tracksFromJson(m['tracks']),
      shakeAmp: d('sa', 0), shakeFreq: d('sf', 6), focalLength: d('fl', 1000), focusDepth: d('fd', 0), aperture: d('ap', 0),
    );
  }
}

class Timeline {
  const Timeline({
    this.fps = 12,
    this.length = 24,
    this.loopStart,
    this.loopEnd,
    this.markers = const [],
    this.scenes = const [],
    this.camera = const Camera(),
    this.audio = const [],
  });

  final int fps;

  /// Number of frames.
  final int length;

  /// Optional playback range (inclusive start, exclusive end).
  final int? loopStart, loopEnd;
  final List<Marker> markers;
  final List<Scene> scenes;
  final Camera camera;
  final List<AudioClip> audio;

  int get rangeStart => (loopStart ?? 0).clamp(0, math.max(0, length - 1));
  int get rangeEnd => (loopEnd ?? length).clamp(rangeStart + 1, math.max(rangeStart + 1, length));
  double get seconds => length / fps;

  Timeline copyWith({
    int? fps,
    int? length,
    Object? loopStart = _unset,
    Object? loopEnd = _unset,
    List<Marker>? markers,
    List<Scene>? scenes,
    Camera? camera,
    List<AudioClip>? audio,
  }) =>
      Timeline(
        fps: fps ?? this.fps,
        length: length ?? this.length,
        loopStart: identical(loopStart, _unset) ? this.loopStart : loopStart as int?,
        loopEnd: identical(loopEnd, _unset) ? this.loopEnd : loopEnd as int?,
        markers: markers ?? this.markers,
        scenes: scenes ?? this.scenes,
        camera: camera ?? this.camera,
        audio: audio ?? this.audio,
      );

  Map<String, dynamic> toJson() => {
        'fps': fps, 'length': length,
        if (loopStart != null) 'ls': loopStart,
        if (loopEnd != null) 'le': loopEnd,
        'markers': markers.map((m) => m.toJson()).toList(),
        'scenes': scenes.map((s) => s.toJson()).toList(),
        'camera': camera.toJson(),
        'audio': audio.map((a) => a.toJson()).toList(),
      };

  static Timeline fromJson(dynamic j) {
    if (j == null) return const Timeline();
    final m = j as Map<String, dynamic>;
    return Timeline(
      fps: m['fps'] as int? ?? 12,
      length: m['length'] as int? ?? 24,
      loopStart: m['ls'] as int?,
      loopEnd: m['le'] as int?,
      markers: ((m['markers'] as List?) ?? const []).map(Marker.fromJson).toList(),
      scenes: ((m['scenes'] as List?) ?? const []).map(Scene.fromJson).toList(),
      camera: Camera.fromJson(m['camera']),
      audio: ((m['audio'] as List?) ?? const []).map(AudioClip.fromJson).toList(),
    );
  }
}

const Object _unset = Object();

// ---------------------------------------------------------------------------
// Canvas helpers: guides, artboards, drawing assists, symmetry, selection
// ---------------------------------------------------------------------------

class Guide {
  const Guide(this.vertical, this.pos);
  final bool vertical;
  final double pos;
  Map<String, dynamic> toJson() => {'v': vertical, 'p': pos};
  static Guide fromJson(dynamic j) => Guide((j as Map)['v'] as bool, (j['p'] as num).toDouble());
}

class Artboard {
  const Artboard(this.id, this.name, this.rect);
  final String id, name;
  final Rect rect;
  Artboard copyWith({String? name, Rect? rect}) => Artboard(id, name ?? this.name, rect ?? this.rect);
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'r': [rect.left, rect.top, rect.width, rect.height]};
  static Artboard fromJson(dynamic j) {
    final m = j as Map<String, dynamic>;
    final r = (m['r'] as List).map((e) => (e as num).toDouble()).toList();
    return Artboard(m['id'] as String, m['name'] as String? ?? '', Rect.fromLTWH(r[0], r[1], r[2], r[3]));
  }
}

enum AssistKind { none, ruler, parallel, perspective1, perspective2, perspective3, isometric, ellipse, concentric, curve }

extension AssistKindLabel on AssistKind {
  String get label => switch (this) {
        AssistKind.none => tr('Sin guía', 'No guide'),
        AssistKind.ruler => tr('Regla', 'Ruler'),
        AssistKind.parallel => tr('Líneas paralelas', 'Parallel lines'),
        AssistKind.perspective1 => tr('Perspectiva 1 punto', '1-point perspective'),
        AssistKind.perspective2 => tr('Perspectiva 2 puntos', '2-point perspective'),
        AssistKind.perspective3 => tr('Perspectiva 3 puntos', '3-point perspective'),
        AssistKind.isometric => tr('Isométrica', 'Isometric'),
        AssistKind.ellipse => tr('Regla de elipse', 'Ellipse ruler'),
        AssistKind.concentric => tr('Círculos concéntricos', 'Concentric circles'),
        AssistKind.curve => tr('Curva francesa', 'French curve'),
      };
}

/// Drawing assistant (ruler / perspective grid) that strokes snap to.
class AssistSpec {
  const AssistSpec({this.kind = AssistKind.none, this.points = const [], this.snap = true, this.visible = true});
  final AssistKind kind;

  /// Control points: ruler end points, vanishing points, ellipse box corners…
  final List<Offset> points;
  final bool snap, visible;

  static const AssistSpec none = AssistSpec();

  bool get active => kind != AssistKind.none;

  AssistSpec copyWith({AssistKind? kind, List<Offset>? points, bool? snap, bool? visible}) =>
      AssistSpec(kind: kind ?? this.kind, points: points ?? this.points, snap: snap ?? this.snap, visible: visible ?? this.visible);

  /// Sensible default control points for a canvas of [size].
  factory AssistSpec.defaults(AssistKind kind, Size size) {
    final w = size.width, h = size.height;
    final c = Offset(w / 2, h / 2);
    final pts = switch (kind) {
      AssistKind.none => const <Offset>[],
      AssistKind.ruler || AssistKind.parallel => [Offset(w * 0.2, h * 0.6), Offset(w * 0.8, h * 0.4)],
      AssistKind.perspective1 => [c],
      AssistKind.perspective2 => [Offset(-w * 0.2, h * 0.45), Offset(w * 1.2, h * 0.45)],
      AssistKind.perspective3 => [Offset(-w * 0.2, h * 0.45), Offset(w * 1.2, h * 0.45), Offset(w / 2, h * 2.2)],
      AssistKind.isometric => [c],
      AssistKind.ellipse => [Offset(w * 0.25, h * 0.3), Offset(w * 0.75, h * 0.7)],
      AssistKind.concentric => [c],
      AssistKind.curve => [Offset(w * 0.2, h * 0.7), Offset(w * 0.35, h * 0.25), Offset(w * 0.7, h * 0.3), Offset(w * 0.8, h * 0.65)],
    };
    return AssistSpec(kind: kind, points: pts);
  }

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'pts': [for (final p in points) [p.dx, p.dy]],
        'snap': snap,
        'vis': visible,
      };

  static AssistSpec fromJson(dynamic j) {
    if (j == null) return AssistSpec.none;
    final m = j as Map<String, dynamic>;
    return AssistSpec(
      kind: AssistKind.values.firstWhere((k) => k.name == m['kind'], orElse: () => AssistKind.none),
      points: ((m['pts'] as List?) ?? const []).map((e) => Offset(((e as List)[0] as num).toDouble(), (e[1] as num).toDouble())).toList(),
      snap: m['snap'] as bool? ?? true,
      visible: m['vis'] as bool? ?? true,
    );
  }
}

enum SymmetryKind { none, vertical, horizontal, quad, radial, mandala }

extension SymmetryKindLabel on SymmetryKind {
  String get label => switch (this) {
        SymmetryKind.none => tr('Sin simetría', 'No symmetry'),
        SymmetryKind.vertical => tr('Espejo vertical', 'Vertical mirror'),
        SymmetryKind.horizontal => tr('Espejo horizontal', 'Horizontal mirror'),
        SymmetryKind.quad => tr('Cuadrante', 'Quadrant'),
        SymmetryKind.radial => tr('Radial', 'Radial'),
        SymmetryKind.mandala => tr('Mandala', 'Mandala'),
      };
}

class SymmetrySpec {
  const SymmetrySpec({this.kind = SymmetryKind.none, this.center = Offset.zero, this.count = 6, this.angle = 0});
  final SymmetryKind kind;
  final Offset center;

  /// Number of segments (radial / mandala).
  final int count;

  /// Rotation of the axes in degrees.
  final double angle;

  static const SymmetrySpec none = SymmetrySpec();

  bool get active => kind != SymmetryKind.none;

  SymmetrySpec copyWith({SymmetryKind? kind, Offset? center, int? count, double? angle}) =>
      SymmetrySpec(kind: kind ?? this.kind, center: center ?? this.center, count: count ?? this.count, angle: angle ?? this.angle);

  /// All transforms a stroke must be replicated through (includes identity).
  List<Mat2D> get transforms {
    if (!active) return const [Mat2D.identity];
    final a = degToRad(angle);
    final toC = Mat2D.translation(center.dx, center.dy) * Mat2D.rotation(a);
    final fromC = Mat2D.rotation(-a) * Mat2D.translation(-center.dx, -center.dy);
    Mat2D local(Mat2D m) => toC * m * fromC;
    const flipX = Mat2D(-1, 0, 0, 1, 0, 0), flipY = Mat2D(1, 0, 0, -1, 0, 0);
    switch (kind) {
      case SymmetryKind.none:
        return const [Mat2D.identity];
      case SymmetryKind.vertical:
        return [Mat2D.identity, local(flipX)];
      case SymmetryKind.horizontal:
        return [Mat2D.identity, local(flipY)];
      case SymmetryKind.quad:
        return [Mat2D.identity, local(flipX), local(flipY), local(const Mat2D(-1, 0, 0, -1, 0, 0))];
      case SymmetryKind.radial:
        final n = math.max(2, count);
        return [for (var i = 0; i < n; i++) local(Mat2D.rotation(i * 2 * math.pi / n))];
      case SymmetryKind.mandala:
        final n = math.max(2, count);
        return [
          for (var i = 0; i < n; i++) ...[
            local(Mat2D.rotation(i * 2 * math.pi / n)),
            local(Mat2D.rotation(i * 2 * math.pi / n) * flipX),
          ],
        ];
    }
  }

  Map<String, dynamic> toJson() => {'kind': kind.name, 'c': [center.dx, center.dy], 'n': count, 'a': angle};

  static SymmetrySpec fromJson(dynamic j) {
    if (j == null) return SymmetrySpec.none;
    final m = j as Map<String, dynamic>;
    final c = m['c'] as List?;
    return SymmetrySpec(
      kind: SymmetryKind.values.firstWhere((k) => k.name == m['kind'], orElse: () => SymmetryKind.none),
      center: c == null ? Offset.zero : Offset((c[0] as num).toDouble(), (c[1] as num).toDouble()),
      count: m['n'] as int? ?? 6,
      angle: (m['a'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// Pixel selection: alpha of [mask] = how selected a pixel is.
class SelectionMask {
  const SelectionMask(this.mask, this.bounds);
  final TilePlane mask;
  final Rect bounds;
}

// ---------------------------------------------------------------------------
// Composition & project
// ---------------------------------------------------------------------------

class Comp {
  const Comp({
    required this.id,
    required this.name,
    required this.width,
    required this.height,
    this.background = const Color(0xFFFFFFFF),
    this.infinite = false,
    this.layers = const [],
    this.timeline = const Timeline(),
    this.guides = const [],
    this.artboards = const [],
    this.selection,
    this.savedSelections = const {},
    this.assist = AssistSpec.none,
    this.symmetry = SymmetrySpec.none,
  });

  final String id, name;
  final int width, height;

  /// Paper colour; null = transparent.
  final Color? background;

  /// Infinite canvas: painting is not clipped to width x height.
  final bool infinite;

  /// Bottom to top.
  final List<Layer> layers;
  final Timeline timeline;
  final List<Guide> guides;
  final List<Artboard> artboards;
  final SelectionMask? selection;
  final Map<String, SelectionMask> savedSelections;
  final AssistSpec assist;
  final SymmetrySpec symmetry;

  Rect get rect => Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
  Size get size => Size(width.toDouble(), height.toDouble());

  Comp copyWith({
    String? name,
    int? width,
    int? height,
    Object? background = _unset,
    bool? infinite,
    List<Layer>? layers,
    Timeline? timeline,
    List<Guide>? guides,
    List<Artboard>? artboards,
    Object? selection = _unset,
    Map<String, SelectionMask>? savedSelections,
    AssistSpec? assist,
    SymmetrySpec? symmetry,
  }) =>
      Comp(
        id: id,
        name: name ?? this.name,
        width: width ?? this.width,
        height: height ?? this.height,
        background: identical(background, _unset) ? this.background : background as Color?,
        infinite: infinite ?? this.infinite,
        layers: layers ?? this.layers,
        timeline: timeline ?? this.timeline,
        guides: guides ?? this.guides,
        artboards: artboards ?? this.artboards,
        selection: identical(selection, _unset) ? this.selection : selection as SelectionMask?,
        savedSelections: savedSelections ?? this.savedSelections,
        assist: assist ?? this.assist,
        symmetry: symmetry ?? this.symmetry,
      );

  Layer? layer(String? id) => findLayer(layers, id);

  Comp updateLayer(String id, Layer Function(Layer) f) => copyWith(layers: mapLayer(layers, id, f));

  /// Composite transform of a layer including its parent chain.
  Mat2D worldMatrix(Layer l, double frame, [int guard = 0]) {
    final m = l.props.matrixAt(frame);
    final pid = l.props.parentId;
    if (pid == null || guard > 32) return m;
    final parent = layer(pid);
    if (parent == null) return m;
    return worldMatrix(parent, frame, guard + 1) * m;
  }
}

enum ColorMode { rgb, cmyk, grayscale, indexed }

extension ColorModeLabel on ColorMode {
  String get label => switch (this) {
        ColorMode.rgb => 'RGB',
        ColorMode.cmyk => 'CMYK',
        ColorMode.grayscale => tr('Escala de grises', 'Grayscale'),
        ColorMode.indexed => tr('Indexado', 'Indexed'),
      };
}

class DocMeta {
  const DocMeta({
    this.dpi = 300,
    this.colorMode = ColorMode.rgb,
    this.bitDepth = 8,
    this.profile = 'sRGB IEC61966-2.1',
    this.indexedColors = 256,
    this.softProof = false,
  });
  final double dpi;
  final ColorMode colorMode;
  final int bitDepth;
  final String profile;
  final int indexedColors;

  /// Simulated CMYK print preview.
  final bool softProof;

  DocMeta copyWith({double? dpi, ColorMode? colorMode, int? bitDepth, String? profile, int? indexedColors, bool? softProof}) => DocMeta(
        dpi: dpi ?? this.dpi,
        colorMode: colorMode ?? this.colorMode,
        bitDepth: bitDepth ?? this.bitDepth,
        profile: profile ?? this.profile,
        indexedColors: indexedColors ?? this.indexedColors,
        softProof: softProof ?? this.softProof,
      );

  Map<String, dynamic> toJson() =>
      {'dpi': dpi, 'mode': colorMode.name, 'depth': bitDepth, 'profile': profile, 'indexed': indexedColors, 'proof': softProof};

  static DocMeta fromJson(dynamic j) {
    if (j == null) return const DocMeta();
    final m = j as Map<String, dynamic>;
    return DocMeta(
      dpi: (m['dpi'] as num?)?.toDouble() ?? 300,
      colorMode: ColorMode.values.firstWhere((c) => c.name == m['mode'], orElse: () => ColorMode.rgb),
      bitDepth: m['depth'] as int? ?? 8,
      profile: m['profile'] as String? ?? 'sRGB IEC61966-2.1',
      indexedColors: m['indexed'] as int? ?? 256,
      softProof: m['proof'] as bool? ?? false,
    );
  }
}

/// The whole (immutable) document: a set of compositions – the main one plus
/// symbols / nested comps – and shared binary assets (audio…).
class Project {
  const Project({
    required this.comps,
    required this.mainId,
    this.meta = const DocMeta(),
    this.assets = const {},
    this.palette = const [],
  });

  final Map<String, Comp> comps;
  final String mainId;
  final DocMeta meta;
  final Map<String, Uint8List> assets;

  /// Document swatches (ARGB).
  final List<int> palette;

  Comp get main => comps[mainId]!;

  Comp comp(String id) => comps[id] ?? main;

  Project withComp(Comp c) => Project(comps: {...comps, c.id: c}, mainId: mainId, meta: meta, assets: assets, palette: palette);

  Project withoutComp(String id) => id == mainId
      ? this
      : Project(comps: {...comps}..remove(id), mainId: mainId, meta: meta, assets: assets, palette: palette);

  Project copyWith({Map<String, Comp>? comps, String? mainId, DocMeta? meta, Map<String, Uint8List>? assets, List<int>? palette}) => Project(
        comps: comps ?? this.comps,
        mainId: mainId ?? this.mainId,
        meta: meta ?? this.meta,
        assets: assets ?? this.assets,
        palette: palette ?? this.palette,
      );

  factory Project.blank({
    int width = 1920,
    int height = 1080,
    Color? background = const Color(0xFFFFFFFF),
    String name = '',
    DocMeta meta = const DocMeta(),
    int fps = 12,
    int frames = 24,
    bool infinite = false,
  }) {
    final id = newId('C');
    final layer = PaintLayer.create(tr('Capa 1', 'Layer 1'));
    final comp = Comp(
      id: id,
      name: name.isEmpty ? tr('Sin título', 'Untitled') : name,
      width: width,
      height: height,
      background: background,
      infinite: infinite,
      layers: [
        layer.withProps(layer.props.copyWith(xf: Xform(ax: width / 2, ay: height / 2))),
      ],
      timeline: Timeline(fps: fps, length: frames),
      symmetry: SymmetrySpec(center: Offset(width / 2, height / 2)),
    );
    return Project(comps: {id: comp}, mainId: id, meta: meta);
  }
}
