import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:ui';

import '../core/mat2d.dart';
import '../model/document.dart';
import '../model/layer.dart';
import '../model/layer_fx.dart';
import '../model/specs.dart';
import '../model/vector.dart';
import 'brush/stroke.dart';
import 'filters.dart';
import 'particles.dart';
import 'text_render.dart';
import 'rig_deform.dart';
import 'tiles.dart';
import 'vector_render.dart';

/// Onion-skin (ghost frames) settings.
class OnionSkin {
  const OnionSkin({
    this.enabled = false,
    this.before = 2,
    this.after = 1,
    this.beforeColor = const Color(0xFFE53935),
    this.afterColor = const Color(0xFF1E88E5),
    this.opacity = 0.45,
    this.byKeys = true,
    this.allLayers = false,
    this.tint = true,
  });

  final bool enabled;
  final int before, after;
  final Color beforeColor, afterColor;
  final double opacity;

  /// Step through drawings (keys) instead of raw frames.
  final bool byKeys;
  final bool allLayers;
  final bool tint;

  OnionSkin copyWith({
    bool? enabled,
    int? before,
    int? after,
    Color? beforeColor,
    Color? afterColor,
    double? opacity,
    bool? byKeys,
    bool? allLayers,
    bool? tint,
  }) =>
      OnionSkin(
        enabled: enabled ?? this.enabled,
        before: before ?? this.before,
        after: after ?? this.after,
        beforeColor: beforeColor ?? this.beforeColor,
        afterColor: afterColor ?? this.afterColor,
        opacity: opacity ?? this.opacity,
        byKeys: byKeys ?? this.byKeys,
        allLayers: allLayers ?? this.allLayers,
        tint: tint ?? this.tint,
      );
}

/// An edit in progress that must show up in the composite before it is
/// committed to the document (live stroke, filter preview, transform…).
class LiveEdit {
  LiveEdit({
    required this.layerId,
    this.replace,
    this.stroke,
    this.onMask = false,
    this.replaceArt,
    this.replaceText,
    this.overlay,
    this.hideContent = false,
  });

  final String layerId;

  /// Replacement pixels for the layer's current drawing.
  final TilePlane? replace;

  /// Stroke composited over the current drawing (or the mask).
  final StrokeComposite? stroke;
  final bool onMask;
  final VectorArt? replaceArt;
  final TextSpec? replaceText;

  /// Extra painter in layer space, drawn above the layer content.
  final void Function(Canvas canvas)? overlay;
  final bool hideContent;
}

class RenderOptions {
  const RenderOptions({
    required this.frame,
    required this.cull,
    this.quality = FilterQuality.none,
    this.live,
    this.onion,
    this.onionLayerId,
    this.forExport = false,
    this.background = true,
    this.useCamera = false,
    this.lightTable = 0,
    this.activeLayerId,
    this.depth = 0,
    this.docMode = true,
    this.hidden = const {},
  });

  final double frame;

  /// Visible region in composition coordinates.
  final Rect cull;
  final FilterQuality quality;
  final LiveEdit? live;
  final OnionSkin? onion;
  final String? onionLayerId;

  /// Skip draft layers and editor-only decoration.
  final bool forExport;
  final bool background;
  final bool useCamera;

  /// 0..1: fades every layer except the active one (light-table mode).
  final double lightTable;
  final String? activeLayerId;
  final int depth;

  /// Apply document colour mode (grayscale / CMYK soft proof).
  final bool docMode;

  /// Layer ids to skip (e.g. while rendering a single layer).
  final Set<String> hidden;

  RenderOptions copyWith({double? frame, Rect? cull, bool? background, int? depth, bool clearLive = false, bool? docMode, bool? useCamera}) => RenderOptions(
        frame: frame ?? this.frame,
        cull: cull ?? this.cull,
        quality: quality,
        live: clearLive ? null : live,
        onion: clearLive ? null : onion,
        onionLayerId: onionLayerId,
        forExport: forExport,
        background: background ?? this.background,
        useCamera: useCamera ?? this.useCamera,
        lightTable: clearLive ? 0 : lightTable,
        activeLayerId: activeLayerId,
        depth: depth ?? this.depth,
        docMode: docMode ?? this.docMode,
        hidden: hidden,
      );
}

/// Draws a [Project] composition onto a canvas: blend modes, opacity,
/// clipping groups, masks, layer effects, adjustment layers, tweens,
/// parenting, camera, nested compositions, onion skin and live edits.
class Compositor {
  Compositor(this.project);

  final Project project;

  static final Paint _dstOut = Paint()..blendMode = BlendMode.dstOut;
  static final Paint _dstIn = Paint()..blendMode = BlendMode.dstIn;

  void paintComp(Canvas c, Comp comp, RenderOptions o) {
    c.save();
    final bg = comp.background;
    if (!comp.infinite) c.clipRect(comp.rect);

    // The paper is painted as the bottom of the layer stack so adjustment
    // layers affect it too.
    void paper(Canvas cc) {
      if (o.background && bg != null) cc.drawRect(comp.infinite ? o.cull : comp.rect, Paint()..color = bg);
    }

    void body(Canvas cc) => _paintList(cc, comp, comp.layers, 0, comp.layers.length, o, under: paper);

    final meta = project.meta;
    if (o.docMode && o.depth == 0 && meta.colorMode == ColorMode.grayscale) {
      c.saveLayer(null, Paint()..colorFilter = ColorFilter.matrix(saturationMatrix(0)));
      body(c);
      c.restore();
    } else if (o.docMode && o.depth == 0 && (meta.softProof || meta.colorMode == ColorMode.cmyk) && Shaders.instance.has('softproof')) {
      _snapshotFiltered(c, comp, o, 0, body, (cc, img, origin, scale) => paintSoftProof(cc, img));
    } else {
      body(c);
    }
    c.restore();
  }

  bool _visible(Layer l, RenderOptions o) {
    if (!l.props.visible) return false;
    if (o.forExport && l.props.draft) return false;
    if (o.hidden.contains(l.id)) return false;
    return true;
  }

  // ---- layer lists --------------------------------------------------------

  void _paintList(Canvas c, Comp comp, List<Layer> layers, int from, int to, RenderOptions o, {void Function(Canvas)? under}) {
    for (var i = to - 1; i >= from; i--) {
      final l = layers[i];
      if (l is AdjustLayer && !l.props.clip && _visible(l, o)) {
        _paintAdjust(c, comp, l, o, (cc) => _paintList(cc, comp, layers, from, i, o, under: under));
        _paintRange(c, comp, layers, i + 1, to, o);
        return;
      }
    }
    if (under != null) under(c);
    _paintRange(c, comp, layers, from, to, o);
  }

  void _paintRange(Canvas c, Comp comp, List<Layer> layers, int from, int to, RenderOptions o) {
    var i = from;
    while (i < to) {
      final base = layers[i];
      var j = i + 1;
      while (j < to && layers[j].props.clip) {
        j++;
      }
      if (j == i + 1) {
        _paintLayer(c, comp, base, o);
      } else {
        _paintClipGroup(c, comp, base, layers.sublist(i + 1, j), o);
      }
      i = j;
    }
  }

  /// [base] plus the layers clipped to it.
  void _paintClipGroup(Canvas c, Comp comp, Layer base, List<Layer> clipped, RenderOptions o) {
    if (!_visible(base, o)) return;
    final op = _opacity(base, o);
    if (op <= 0) return;
    final lp = Paint()..blendMode = base.blend.mode;
    if (op < 1) lp.color = Color.fromRGBO(0, 0, 0, op);
    _withCamera(c, comp, base, o, () {
      c.saveLayer(null, lp);
      _clipContent(c, comp, base, clipped, clipped.length, o);
      c.restore();
    });
  }

  void _clipContent(Canvas c, Comp comp, Layer base, List<Layer> clipped, int upTo, RenderOptions o) {
    // a clipped adjustment layer filters everything below it inside the group
    for (var k = upTo - 1; k >= 0; k--) {
      final l = clipped[k];
      if (l is AdjustLayer && _visible(l, o)) {
        _paintAdjust(c, comp, l, o, (cc) => _clipContent(cc, comp, base, clipped, k, o));
        _clipTops(c, comp, base, clipped, k + 1, upTo, o);
        return;
      }
    }
    _paintPlain(c, comp, base, o);
    _clipTops(c, comp, base, clipped, 0, upTo, o);
  }

  void _clipTops(Canvas c, Comp comp, Layer base, List<Layer> clipped, int from, int to, RenderOptions o) {
    for (var k = from; k < to; k++) {
      final l = clipped[k];
      if (l is AdjustLayer || !_visible(l, o)) continue;
      final op = _opacity(l, o);
      if (op <= 0) continue;
      final lp = Paint();
      if (op < 1) lp.color = Color.fromRGBO(0, 0, 0, op);
      if (l.blend == LayerBlend.normal) {
        lp.blendMode = BlendMode.srcATop;
        c.saveLayer(null, lp);
        _paintPlain(c, comp, l, o);
        c.restore();
      } else {
        // keep the blend mode: mask the layer by the base alpha first
        lp.blendMode = l.blend.mode;
        c.saveLayer(null, lp);
        _paintPlain(c, comp, l, o);
        c.saveLayer(null, _dstIn);
        _paintPlain(c, comp, base, o);
        c.restore();
        c.restore();
      }
    }
  }

  // ---- single layer -------------------------------------------------------

  double _opacity(Layer l, RenderOptions o) {
    var op = l.props.opacityAt(o.frame);
    if (o.lightTable > 0 && o.activeLayerId != null && l.id != o.activeLayerId && !o.forExport) {
      op *= 1 - o.lightTable;
    }
    return op.clamp(0.0, 1.0);
  }

  void _withCamera(Canvas c, Comp comp, Layer l, RenderOptions o, void Function() body) {
    final cam = comp.timeline.camera;
    if (!o.useCamera || !cam.enabled) {
      body();
      return;
    }
    c.save();
    c.transform(cam.matrixAt(o.frame, comp.size, depth: l.props.depth, fps: comp.timeline.fps.toDouble()).storage);
    final blur = cam.blurAt(l.props.depth);
    if (blur > 0.2) {
      c.saveLayer(null, Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur, tileMode: TileMode.decal));
      body();
      c.restore();
    } else {
      body();
    }
    c.restore();
  }

  bool _needsIsolation(Layer l, RenderOptions o) {
    final p = l.props;
    if (p.hasMask || p.fx.any) return true;
    final live = o.live;
    if (live != null && live.layerId == l.id && (live.stroke != null || live.overlay != null)) return true;
    if (l is GroupLayer && !l.passThrough) return true;
    return false;
  }

  void _paintLayer(Canvas c, Comp comp, Layer l, RenderOptions o) {
    if (!_visible(l, o) || l is AdjustLayer) return;
    final op = _opacity(l, o);
    if (op <= 0) return;
    _withCamera(c, comp, l, o, () {
      if (op >= 1 && l.blend == LayerBlend.normal && !_needsIsolation(l, o)) {
        _paintPlain(c, comp, l, o);
        return;
      }
      final lp = Paint()..blendMode = l.blend.mode;
      if (op < 1) lp.color = Color.fromRGBO(0, 0, 0, op);
      c.saveLayer(null, lp);
      _paintPlain(c, comp, l, o);
      c.restore();
    });
  }

  /// Layer at full opacity / normal blend: transform, effects, content,
  /// live edits and mask. Must be isolated by the caller when
  /// [_needsIsolation] says so.
  void _paintPlain(Canvas c, Comp comp, Layer l, RenderOptions o) {
    final p = l.props;
    final m = comp.worldMatrix(l, o.frame);
    c.save();
    if (!m.isIdentity) c.transform(m.storage);

    final live = (o.live != null && o.live!.layerId == l.id) ? o.live : null;
    void content(Canvas cc) => _content(cc, comp, l, o, live);

    final fx = p.fx;
    if (fx.any) _fxBehind(c, fx, content);
    content(c);
    if (fx.any) _fxFront(c, fx, content);

    if (live?.overlay != null) live!.overlay!(c);

    // a live edit of the mask may replace it (liquify) and/or stroke onto it
    final mask = (live != null && live.onMask && live.replace != null) ? live.replace : p.mask;
    if (mask != null && p.maskEnabled) {
      if (live != null && live.onMask && live.stroke != null) {
        c.saveLayer(null, _dstOut);
        mask.paint(c);
        live.stroke!.paintOnto(c, mask);
        c.restore();
      } else {
        mask.paint(c, paint: _dstOut);
      }
    } else if (live != null && live.onMask && live.stroke != null) {
      c.saveLayer(null, _dstOut);
      live.stroke!.paintOnto(c, TilePlane.empty);
      c.restore();
    }
    c.restore();
  }

  void _content(Canvas c, Comp comp, Layer l, RenderOptions o, LiveEdit? live) {
    final cull = c.getLocalClipBounds();
    final tilePaint = TilePlane.paintFor(o.quality);
    final frame = o.frame.floor();
    switch (l) {
      case PaintLayer():
        _onion(c, comp, l, o, (cc, f) => l.cels.at(f)?.paint(cc, cull: cull, paint: tilePaint), (f) => l.cels.drawingIdAt(f), l.cels);
        if (live?.hideContent ?? false) return;
        final plane = (live != null && !live.onMask ? live.replace : null) ?? l.cels.at(frame) ?? TilePlane.empty;
        // bones deform the drawing, except while a stroke is being painted on it
        final rig = l.rig;
        final rigged = rig != null && (live == null || live.stroke == null) && paintRigged(c, plane, rig, o.frame, quality: o.quality == FilterQuality.none ? FilterQuality.low : o.quality);
        if (!rigged) plane.paint(c, cull: cull, paint: tilePaint);
        if (live != null && !live.onMask && live.stroke != null) {
          live.stroke!.paintOnto(c, plane, cull: cull, tilePaint: tilePaint);
        }
      case VectorLayer():
        _onion(c, comp, l, o, (cc, f) {
          final a = l.cels.at(f);
          if (a != null) paintVectorArt(cc, a, cull: cull);
        }, (f) => l.cels.drawingIdAt(f), l.cels);
        if (live?.hideContent ?? false) return;
        final art = live?.replaceArt ?? l.cels.at(frame);
        if (art != null) paintVectorArt(c, art, cull: cull);
      case TextLayer():
        if (live?.hideContent ?? false) return;
        TextRender.paint(c, live?.replaceText ?? l.text, o.frame);
      case GroupLayer():
        _paintList(c, comp, l.children, 0, l.children.length, o);
      case InstanceLayer():
        final sub = project.comps[l.compId];
        if (sub == null || o.depth > 8 || sub.id == comp.id) return;
        final len = math.max(1, sub.timeline.length);
        double f;
        if (l.fixedFrame != null) {
          f = l.fixedFrame!.toDouble();
        } else {
          f = (o.frame - l.start) * l.speed;
          f = l.loop ? ((f % len) + len) % len : f.clamp(0.0, len - 1.0);
        }
        paintComp(c, sub, o.copyWith(frame: f, cull: cull, background: false, depth: o.depth + 1, clearLive: true, useCamera: false));
      case ParticleLayer():
        paintParticles(c, l.spec, o.frame);
      case AdjustLayer():
        break;
    }
  }

  void _onion<T>(
    Canvas c,
    Comp comp,
    Layer l,
    RenderOptions o,
    void Function(Canvas, int frame) draw,
    int? Function(int frame) drawingAt,
    CelTrack<T> track,
  ) {
    final onion = o.onion;
    if (onion == null || !onion.enabled || o.forExport) return;
    if (!onion.allLayers && l.id != o.onionLayerId) return;
    final frame = o.frame.floor();
    final current = drawingAt(frame);

    void ghost(int f, Color tint, double alpha) {
      final d = drawingAt(f);
      if (d == null || d == current) return;
      final lp = Paint()..color = Color.fromRGBO(0, 0, 0, alpha.clamp(0.0, 1.0));
      if (onion.tint) lp.colorFilter = ColorFilter.mode(tint, BlendMode.srcIn);
      c.saveLayer(null, lp);
      draw(c, f);
      c.restore();
    }

    // previous
    var f = frame;
    for (var k = 1; k <= onion.before; k++) {
      int? pf;
      if (onion.byKeys) {
        final cur = track.exposureAt(f)?.frame ?? f;
        pf = track.prevKeyFrame(cur);
      } else {
        pf = f - 1;
      }
      if (pf == null || pf < 0) break;
      f = pf;
      ghost(f, onion.beforeColor, onion.opacity * (1 - (k - 1) / (onion.before + 0.0) * 0.75));
    }
    // next
    f = frame;
    for (var k = 1; k <= onion.after; k++) {
      final nf = onion.byKeys ? track.nextKeyFrame(f) : f + 1;
      if (nf == null || nf >= comp.timeline.length + 240) break;
      f = nf;
      ghost(f, onion.afterColor, onion.opacity * (1 - (k - 1) / (onion.after + 0.0) * 0.75));
    }
  }

  // ---- layer effects ------------------------------------------------------

  void _fxBehind(Canvas c, LayerFx fx, void Function(Canvas) content) {
    if (fx.shadow) {
      c.saveLayer(
        null,
        Paint()
          ..imageFilter = ui.ImageFilter.blur(sigmaX: fx.shadowBlur * 0.5 + 0.01, sigmaY: fx.shadowBlur * 0.5 + 0.01, tileMode: TileMode.decal)
          ..colorFilter = ColorFilter.mode(fx.shadowColor.withValues(alpha: 1), BlendMode.srcIn)
          ..color = Color.fromRGBO(0, 0, 0, fx.shadowOpacity.clamp(0.0, 1.0)),
      );
      c.translate(fx.shadowDx, fx.shadowDy);
      content(c);
      c.restore();
    }
    if (fx.glow && !fx.innerGlow) {
      c.saveLayer(
        null,
        Paint()
          ..imageFilter = ui.ImageFilter.blur(sigmaX: fx.glowBlur * 0.5 + 0.01, sigmaY: fx.glowBlur * 0.5 + 0.01, tileMode: TileMode.decal)
          ..colorFilter = ColorFilter.mode(fx.glowColor.withValues(alpha: 1), BlendMode.srcIn)
          ..color = Color.fromRGBO(0, 0, 0, fx.glowOpacity.clamp(0.0, 1.0))
          ..blendMode = BlendMode.screen,
      );
      content(c);
      // a second pass makes the halo denser near the shape
      content(c);
      c.restore();
    }
    if (fx.stroke && fx.strokeWidth > 0) {
      c.saveLayer(
        null,
        Paint()
          ..imageFilter = ui.ImageFilter.dilate(radiusX: fx.strokeWidth, radiusY: fx.strokeWidth)
          ..colorFilter = ColorFilter.mode(fx.strokeColor.withValues(alpha: 1), BlendMode.srcIn)
          ..color = Color.fromRGBO(0, 0, 0, fx.strokeOpacity.clamp(0.0, 1.0)),
      );
      content(c);
      c.restore();
    }
  }

  void _fxFront(Canvas c, LayerFx fx, void Function(Canvas) content) {
    if (fx.overlay) {
      c.drawPaint(Paint()
        ..color = fx.overlayColor.withValues(alpha: fx.overlayColor.a * fx.overlayOpacity)
        ..blendMode = BlendMode.srcATop);
    }
    if (fx.glow && fx.innerGlow) {
      c.saveLayer(null, Paint()..blendMode = BlendMode.srcATop);
      c.drawPaint(Paint()..color = fx.glowColor.withValues(alpha: fx.glowOpacity.clamp(0.0, 1.0)));
      c.saveLayer(
        null,
        Paint()
          ..blendMode = BlendMode.dstOut
          ..imageFilter = ui.ImageFilter.compose(
            outer: ui.ImageFilter.blur(sigmaX: fx.glowBlur * 0.5 + 0.01, sigmaY: fx.glowBlur * 0.5 + 0.01, tileMode: TileMode.decal),
            inner: ui.ImageFilter.erode(radiusX: fx.glowBlur * 0.5, radiusY: fx.glowBlur * 0.5),
          ),
      );
      content(c);
      c.restore();
      c.restore();
    }
    if (fx.bevel && fx.bevelSize > 0) {
      final a = degToRad(fx.bevelAngle);
      // light comes from the bevel angle; highlight on the lit edge
      final dx = math.cos(a) * fx.bevelSize, dy = -math.sin(a) * fx.bevelSize;
      void rim(Color color, double opacity, double sx, double sy) {
        c.saveLayer(null, Paint()..blendMode = BlendMode.srcATop);
        c.saveLayer(null, Paint()..colorFilter = ColorFilter.mode(color.withValues(alpha: opacity.clamp(0.0, 1.0)), BlendMode.srcIn));
        content(c);
        c.restore();
        c.saveLayer(
          null,
          Paint()
            ..blendMode = BlendMode.dstOut
            ..imageFilter = ui.ImageFilter.blur(sigmaX: fx.bevelSize * 0.35 + 0.01, sigmaY: fx.bevelSize * 0.35 + 0.01, tileMode: TileMode.decal),
        );
        c.translate(sx, sy);
        content(c);
        c.restore();
        c.restore();
      }

      rim(const Color(0xFFFFFFFF), fx.bevelHighlight, -dx, -dy);
      rim(const Color(0xFF000000), fx.bevelShadow, dx, dy);
    }
  }

  // ---- adjustment layers --------------------------------------------------

  void _paintAdjust(Canvas c, Comp comp, AdjustLayer adj, RenderOptions o, void Function(Canvas) below) {
    final op = _opacity(adj, o);
    if (op <= 0) {
      below(c);
      return;
    }
    final spec = adj.filter;
    final mask = adj.props.hasMask ? adj.props.mask : null;
    final live = (o.live != null && o.live!.layerId == adj.id && o.live!.onMask) ? o.live!.stroke : null;
    final partial = op < 1 || mask != null || live != null;

    void applyMask(Canvas cc) {
      if (mask != null && live != null) {
        cc.saveLayer(null, _dstOut);
        mask.paint(cc);
        live.paintOnto(cc, mask);
        cc.restore();
      } else if (mask != null) {
        mask.paint(cc, paint: _dstOut);
      } else if (live != null) {
        cc.saveLayer(null, _dstOut);
        live.paintOnto(cc, TilePlane.empty);
        cc.restore();
      }
    }

    if (isMatrixFilter(spec)) {
      final cf = ColorFilter.matrix(filterMatrix(spec));
      if (!partial) {
        c.saveLayer(null, Paint()..colorFilter = cf);
        below(c);
        c.restore();
      } else {
        below(c);
        c.saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, op));
        c.saveLayer(null, Paint()..colorFilter = cf);
        below(c);
        c.restore();
        applyMask(c);
        c.restore();
      }
      return;
    }

    if (partial) below(c);
    _snapshotFiltered(c, comp, o, filterMargin(spec), below, (cc, img, origin, scale) {
      paintFiltered(cc, img, spec, origin: origin, scale: scale, extent: comp.rect);
    }, opacity: op, after: partial ? applyMask : null, isolate: partial);
  }

  /// Renders [below] into an offscreen image covering the visible region
  /// (document aligned, at most screen resolution), then draws it back
  /// through [filter].
  void _snapshotFiltered(
    Canvas c,
    Comp comp,
    RenderOptions o,
    double margin,
    void Function(Canvas) below,
    void Function(Canvas canvas, ui.Image image, Offset origin, double scale) filter, {
    double opacity = 1,
    void Function(Canvas)? after,
    bool isolate = false,
  }) {
    var clip = c.getLocalClipBounds();
    if (clip.width > 1e7 || clip.height > 1e7 || clip.isEmpty) clip = o.cull;
    clip = clip.intersect(o.cull.inflate(1));
    if (clip.isEmpty || clip.width <= 0 || clip.height <= 0) return;
    var region = clip.inflate(margin).roundedOut;
    if (!comp.infinite) region = region.intersect(comp.rect.inflate(margin));
    if (region.width < 1 || region.height < 1) return;

    final total = Mat2D.fromStorage(c.getTransform()).scaleFactor;
    var s = total.isFinite && total > 0 ? math.min(1.0, total) : 1.0;
    const maxDim = 8192.0;
    if (region.width * s > maxDim) s = maxDim / region.width;
    if (region.height * s > maxDim) s = maxDim / region.height;
    final w = math.max(1, (region.width * s).ceil()), h = math.max(1, (region.height * s).ceil());

    final img = renderToImage(w, h, (cc) {
      cc.scale(s);
      cc.translate(-region.left, -region.top);
      cc.clipRect(region);
      below(cc);
    });

    c.save();
    c.clipRect(clip);
    if (isolate) c.saveLayer(clip, Paint()..color = Color.fromRGBO(0, 0, 0, opacity.clamp(0.0, 1.0)));
    c.save();
    c.translate(region.left, region.top);
    c.scale(1 / s);
    filter(c, img, region.topLeft, s);
    c.restore();
    if (after != null) after(c);
    if (isolate) c.restore();
    c.restore();
    img.dispose();
  }
}

/// Renders one frame of [comp] into an image.
///
/// [region] defaults to the composition rect; [scale] resizes the output.
ui.Image renderCompImage(
  Project project,
  Comp comp,
  double frame, {
  Rect? region,
  double scale = 1,
  bool background = true,
  bool forExport = true,
  bool useCamera = true,
  LiveEdit? live,
  FilterQuality quality = FilterQuality.none,
  Set<String> hidden = const {},
  bool docMode = true,
}) {
  final r = region ?? comp.rect;
  final w = math.max(1, (r.width * scale).round()), h = math.max(1, (r.height * scale).round());
  return renderToImage(w, h, (c) {
    c.scale(w / r.width, h / r.height);
    c.translate(-r.left, -r.top);
    c.clipRect(r);
    Compositor(project).paintComp(
      c,
      comp,
      RenderOptions(
        frame: frame,
        cull: r,
        quality: scale == 1 ? quality : (scale < 1 ? FilterQuality.medium : FilterQuality.low),
        forExport: forExport,
        background: background,
        useCamera: useCamera,
        live: live,
        hidden: hidden,
        docMode: docMode,
      ),
    );
  });
}

/// Flattens a single layer (with its mask and effects) into a tile plane in
/// composition space.
TilePlane rasterizeLayer(Project project, Comp comp, Layer layer, double frame, {Rect? area}) {
  final r = (area ?? comp.rect).roundedOut;
  final others = <String>{
    for (final l in walkLayers(comp.layers))
      if (l.id != layer.id) l.id,
  };
  // keep ancestors visible so nested layers still render
  var parent = parentGroupOf(comp.layers, layer.id);
  while (parent != null) {
    others.remove(parent.id);
    parent = parentGroupOf(comp.layers, parent.id);
  }
  if (layer is GroupLayer) {
    for (final l in walkLayers(layer.children)) {
      others.remove(l.id);
    }
  }
  final img = renderCompImage(project, comp, frame, region: r, background: false, forExport: false, useCamera: false, hidden: others, docMode: false);
  final plane = TilePlane.fromImage(img, origin: r.topLeft);
  img.dispose();
  return plane;
}
