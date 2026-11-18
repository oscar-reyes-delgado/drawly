import 'dart:ui';

import '../core/i18n.dart';
import '../core/mat2d.dart';
import '../engine/tiles.dart';
import '../model/anim.dart';
import '../model/document.dart';
import '../model/layer.dart';
import 'document_controller.dart';

/// Resamples a plane through an affine transform.
TilePlane transformPlane(TilePlane p, Mat2D m, {FilterQuality quality = FilterQuality.high}) {
  final b = p.bounds;
  if (b == null || m.isIdentity) return p;
  if (m.isTranslation && m.tx == m.tx.roundToDouble() && m.ty == m.ty.roundToDouble()) {
    return p.translated(m.tx, m.ty);
  }
  // flatten first so tile seams never get baked in
  final src = p.toImage(b);
  final nb = m.mapRect(b).roundedOut;
  final out = TilePlane.empty.drawn((c) {
    c.transform(m.storage);
    c.drawImage(src, b.topLeft, Paint()..filterQuality = quality);
  }, area: nb);
  src.dispose();
  return out;
}

AnimTrack _scaleTrack(AnimTrack t, double s, [double o = 0]) => AnimTrack([for (final k in t.keys) k.copyWith(value: k.value * s + o)]);

/// Applies the document-space transform [m] to a layer so that it looks the
/// same relative to the transformed canvas.
Layer transformLayerBy(Layer l, Mat2D m) {
  final p = l.props;
  final lin = Mat2D(m.a, m.b, m.c, m.d, 0, 0);
  final simple = m.b == 0 && m.c == 0 && m.a > 0 && m.d > 0;
  final bakes = l is PaintLayer || l is VectorLayer || l is GroupLayer || (simple && (l is TextLayer || l is ParticleLayer));
  if (!bakes) {
    // keep the content, move the layer transform instead
    return l.withProps(p.copyWith(xf: Xform.fromMatrix(m * p.xf.matrix, ax: p.xf.ax, ay: p.xf.ay)));
  }
  final a = m.apply(Offset(p.xf.ax, p.xf.ay));
  final d = lin.apply(Offset(p.xf.x, p.xf.y));
  var tracks = p.tracks;
  if (simple && tracks.isNotEmpty) {
    tracks = {
      for (final e in tracks.entries)
        e.key: switch (e.key) {
          Prop.x => _scaleTrack(e.value, m.a),
          Prop.y => _scaleTrack(e.value, m.d),
          Prop.anchorX => _scaleTrack(e.value, m.a, m.tx),
          Prop.anchorY => _scaleTrack(e.value, m.d, m.ty),
          _ => e.value,
        },
    };
  }
  final props = p.copyWith(
    xf: p.xf.copyWith(ax: a.dx, ay: a.dy, x: d.dx, y: d.dy, rot: m.determinant < 0 ? -p.xf.rot : p.xf.rot),
    tracks: tracks,
    mask: p.mask == null ? null : transformPlane(p.mask!, m),
  );
  switch (l) {
    case PaintLayer():
      return PaintLayer(l.id, props, l.cels.mapDrawings((pl) => transformPlane(pl, m)), rig: l.rig?.transformed(m));
    case VectorLayer():
      return VectorLayer(l.id, props, l.cels.mapDrawings((art) => art.mapped((s) => s.transformed(m))));
    case GroupLayer():
      return GroupLayer(l.id, props, l.children.map((c) => transformLayerBy(c, m)).toList(), passThrough: l.passThrough);
    case TextLayer():
      final t = l.text;
      return TextLayer(
        l.id,
        props,
        t.copyWith(
          pos: m.apply(t.pos),
          size: t.size * m.d,
          boxWidth: t.boxWidth * m.a,
          strokeWidth: t.strokeWidth * m.d,
          letterSpacing: t.letterSpacing * m.a,
          path: t.path?.transformed(m),
        ),
      );
    case ParticleLayer():
      final s = l.spec;
      final k = (m.a + m.d) / 2;
      return ParticleLayer(
        l.id,
        props,
        s.copyWith(
          emitter: m.mapRect(s.emitter),
          speed: s.speed * k,
          size: s.size * k,
          gravityX: s.gravityX * k,
          gravityY: s.gravityY * k,
          floorY: s.floorY == null ? null : s.floorY! * m.d + m.ty,
        ),
      );
    default:
      return l.withProps(props);
  }
}

/// Canvas / image level operations.
extension DocImage on DocumentController {
  Comp _transformed(Comp c, Mat2D m, int w, int h) => c.copyWith(
        width: w,
        height: h,
        layers: c.layers.map((l) => transformLayerBy(l, m)).toList(),
        selection: null,
        guides: [
          for (final g in c.guides)
            if (m.b == 0 && m.c == 0)
              Guide(g.vertical, g.vertical ? g.pos * m.a + m.tx : g.pos * m.d + m.ty)
            else
              // rotated canvases swap the guide orientation
              Guide(!g.vertical, g.vertical ? (m.b * g.pos + m.ty) : (m.c * g.pos + m.tx)),
        ],
        artboards: [for (final a in c.artboards) a.copyWith(rect: m.mapRect(a.rect))],
        symmetry: c.symmetry.copyWith(center: m.apply(c.symmetry.center)),
        assist: c.assist.copyWith(points: c.assist.points.map(m.apply).toList()),
      );

  void _applyCanvas(String label, Mat2D m, int w, int h) {
    if (w < 1 || h < 1) return;
    viewInitialized = false;
    applyComp(label, (c) => _transformed(c, m, w, h));
  }

  /// Changes the canvas size keeping the artwork anchored at ([ax], [ay])
  /// (each 0 = start, 0.5 = centre, 1 = end).
  void resizeCanvas(int w, int h, {double ax = 0.5, double ay = 0.5}) {
    final dx = ((w - comp.width) * ax).roundToDouble(), dy = ((h - comp.height) * ay).roundToDouble();
    _applyCanvas(tr('Tamaño de lienzo', 'Canvas size'), Mat2D.translation(dx, dy), w, h);
  }

  /// Scales the whole image (raster layers are resampled, vectors stay exact).
  void resizeImage(int w, int h) {
    _applyCanvas(tr('Tamaño de imagen', 'Image size'), Mat2D.scale(w / comp.width, h / comp.height), w, h);
  }

  void cropTo(Rect r) {
    final rr = r.roundedOut;
    _applyCanvas(tr('Recortar', 'Crop'), Mat2D.translation(-rr.left, -rr.top), rr.width.toInt(), rr.height.toInt());
  }

  void cropToSelection() {
    final s = comp.selection;
    if (s != null) cropTo(s.bounds.intersect(comp.rect));
  }

  void rotateCanvas90({bool clockwise = true}) {
    final w = comp.width.toDouble(), h = comp.height.toDouble();
    final m = clockwise ? Mat2D(0, 1, -1, 0, h, 0) : Mat2D(0, -1, 1, 0, 0, w);
    _applyCanvas(tr('Rotar lienzo 90°', 'Rotate canvas 90°'), m, comp.height, comp.width);
  }

  void rotateCanvas180() {
    _applyCanvas(tr('Rotar lienzo 180°', 'Rotate canvas 180°'), Mat2D(-1, 0, 0, -1, comp.width.toDouble(), comp.height.toDouble()), comp.width, comp.height);
  }

  void flipCanvas({bool horizontal = true}) {
    final m = horizontal ? Mat2D(-1, 0, 0, 1, comp.width.toDouble(), 0) : Mat2D(1, 0, 0, -1, 0, comp.height.toDouble());
    _applyCanvas(horizontal ? tr('Voltear lienzo horizontal', 'Flip canvas horizontal') : tr('Voltear lienzo vertical', 'Flip canvas vertical'), m, comp.width, comp.height);
  }

  /// Crops the canvas to the bounds of everything painted.
  Future<void> trimCanvas() async {
    await run(tr('Recortar a contenido', 'Trim to content'), () async {
      Rect? b;
      for (final l in walkLayers(comp.layers)) {
        if (!l.visible) continue;
        if (l is PaintLayer) {
          for (final p in l.cels.drawings.values) {
            final cb = await p.contentBounds();
            if (cb != null) b = b == null ? cb : b.expandToInclude(cb);
          }
        } else if (l is VectorLayer) {
          for (final a in l.cels.drawings.values) {
            final vb = a.bounds;
            if (vb != null) b = b == null ? vb : b.expandToInclude(vb);
          }
        }
      }
      if (b != null && b.width >= 1 && b.height >= 1) cropTo(b);
    });
  }

  /// Mirrors / flips only the active layer.
  void flipActiveLayer({bool horizontal = true}) {
    final l = activeLayer;
    if (l == null) return;
    final cx = comp.selection?.bounds.center.dx ?? comp.width / 2, cy = comp.selection?.bounds.center.dy ?? comp.height / 2;
    final m = horizontal ? Mat2D(-1, 0, 0, 1, cx * 2, 0) : Mat2D(1, 0, 0, -1, 0, cy * 2);
    updateLayer(tr('Voltear capa', 'Flip layer'), l.id, (x) => transformLayerBy(x, m));
  }

  void setBackground(Color? color) => applyComp(tr('Color de fondo', 'Background colour'), (c) => c.copyWith(background: color), mergeKey: 'bg');

  void setMeta(DocMeta meta) => apply(tr('Propiedades del documento', 'Document properties'), project.copyWith(meta: meta), mergeKey: 'meta');

  void setInfinite(bool v) => applyComp(tr('Lienzo infinito', 'Infinite canvas'), (c) => c.copyWith(infinite: v));
}
