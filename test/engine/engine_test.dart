import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:drawly/core/mat2d.dart';
import 'package:drawly/engine/brush/preset.dart';
import 'package:drawly/engine/brush/stroke.dart';
import 'package:drawly/engine/brush/tips.dart';
import 'package:drawly/engine/compositor.dart';
import 'package:drawly/engine/filters.dart';
import 'package:drawly/engine/tiles.dart';
import 'package:drawly/model/anim.dart';
import 'package:drawly/model/document.dart';
import 'package:drawly/model/filter_spec.dart';
import 'package:drawly/model/layer.dart';
import 'package:drawly/model/layer_fx.dart';
import 'package:flutter_test/flutter_test.dart';

const outDir = String.fromEnvironment('OUT_DIR');

Future<void> savePng(ui.Image img, String name) async {
  if (outDir.isEmpty) return;
  final bd = await img.toByteData(format: ui.ImageByteFormat.png);
  File('$outDir/$name').writeAsBytesSync(bd!.buffer.asUint8List());
}

List<int> at(Uint8List d, int w, int x, int y) => d.sublist((y * w + x) * 4, (y * w + x) * 4 + 4);

TilePlane solid(ui.Rect r, ui.Color c) => TilePlane.empty.drawn((cv) => cv.drawRect(r, ui.Paint()..color = c), area: r);

Project projectWith(List<Layer> layers, {int w = 300, int h = 300, ui.Color? bg = const ui.Color(0xFFFFFFFF)}) {
  final comp = Comp(id: 'c', name: 't', width: w, height: h, background: bg, layers: layers);
  return Project(comps: {'c': comp}, mainId: 'c');
}

PaintLayer paintLayer(String id, TilePlane px, {LayerProps? props}) => PaintLayer(id, props ?? LayerProps(name: id), CelTrack.single(px));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await BrushTips.instance.ensureLoaded();
    await Shaders.instance.ensureLoaded();
  });

  test('tile plane: draw across tiles, clear, translate, read back', () async {
    var p = TilePlane.empty;
    p = p.drawn((c) => c.drawRect(const ui.Rect.fromLTWH(200, 200, 200, 200), ui.Paint()..color = const ui.Color(0xFFFF0000)),
        area: const ui.Rect.fromLTWH(200, 200, 200, 200));
    expect(p.tileCount, 4);
    final d = await p.readRgba(const ui.Rect.fromLTWH(0, 0, 512, 512));
    expect(at(d, 512, 300, 300), [255, 0, 0, 255]);
    expect(at(d, 512, 100, 100), [0, 0, 0, 0]);
    expect(at(d, 512, 256, 256), [255, 0, 0, 255]); // tile seam
    final b = await p.contentBounds();
    expect(b, const ui.Rect.fromLTWH(200, 200, 200, 200));

    final cleared = p.cleared(const ui.Rect.fromLTWH(0, 0, 300, 512));
    final d2 = await cleared.readRgba(const ui.Rect.fromLTWH(0, 0, 512, 512));
    expect(at(d2, 512, 250, 300), [0, 0, 0, 0]);
    expect(at(d2, 512, 350, 300), [255, 0, 0, 255]);

    final moved = p.translated(256, 0);
    expect((await moved.contentBounds()), const ui.Rect.fromLTWH(456, 200, 200, 200));
    final moved2 = p.translated(10.0, -5.0);
    expect((await moved2.contentBounds()), const ui.Rect.fromLTWH(210, 195, 200, 200));
    final compact = await p.cleared(const ui.Rect.fromLTWH(0, 0, 1000, 1000).deflate(0)).compacted();
    expect(compact.isEmpty, isTrue);
  });

  test('brush strokes render (visual sample)', () async {
    final brushes = builtinBrushes();
    const rowH = 64, w = 900;
    final rows = brushes.where((b) => b.engine == BrushEngine.paint && !b.erase).toList();
    final img = renderToImage(w, rowH * rows.length, (c) {
      c.drawColor(const ui.Color(0xFFFFFFFF), ui.BlendMode.src);
      for (var i = 0; i < rows.length; i++) {
        final prev = renderBrushPreview(rows[i], width: w, height: rowH, color: const ui.Color(0xFF1A2A6C));
        c.drawImage(prev, ui.Offset(0, i * rowH.toDouble()), ui.Paint());
      }
    });
    await savePng(img, 'brushes.png');
    final d = await imageToRgba(img);
    var inked = 0;
    for (var i = 0; i < d.length; i += 4) {
      if (d[i] < 200) inked++;
    }
    expect(inked, greaterThan(5000));
  });

  test('paint stroke: opacity cap, eraser, selection clip, alpha lock', () async {
    final brush = builtinBrushes().firstWhere((b) => b.id == 'round_brush').copyWith(size: 40, hardness: 1, opacity: 0.5, flow: 1, pressureSize: 0, pressureFlow: 0, smoothing: 0, spacing: 0.05);
    PaintStroke stroke(BrushPreset b, {TilePlane? selection, bool lockAlpha = false}) {
      final s = PaintStroke(brush: b, color: const ui.Color(0xFF0000FF), selection: selection, lockAlpha: lockAlpha, simulatePressure: false);
      for (var x = 20.0; x <= 280; x += 4) {
        s.add(StrokeInput(ui.Offset(x, 150), timeMs: x));
      }
      // go back over the same path: must not get darker than the opacity cap
      for (var x = 280.0; x >= 20; x -= 4) {
        s.add(StrokeInput(ui.Offset(x, 150), timeMs: 600 - x));
      }
      s.finish();
      return s;
    }

    final s1 = stroke(brush);
    final layer = s1.commit(TilePlane.empty);
    var d = await layer.readRgba(const ui.Rect.fromLTWH(0, 0, 300, 300));
    expect(at(d, 300, 150, 150)[3], closeTo(128, 2)); // 50% cap although overlapped
    expect(at(d, 300, 150, 100)[3], 0);

    // eraser removes from an opaque layer
    final base = solid(const ui.Rect.fromLTWH(0, 0, 300, 300), const ui.Color(0xFFFF0000));
    final er = stroke(brush.copyWith(erase: true, opacity: 1));
    d = await er.commit(base).readRgba(const ui.Rect.fromLTWH(0, 0, 300, 300));
    expect(at(d, 300, 150, 150)[3], 0);
    expect(at(d, 300, 150, 60), [255, 0, 0, 255]);

    // selection restricts the stroke
    final sel = solid(const ui.Rect.fromLTWH(0, 0, 150, 300), const ui.Color(0xFFFFFFFF));
    final s3 = stroke(brush.copyWith(opacity: 1), selection: sel);
    d = await s3.commit(TilePlane.empty).readRgba(const ui.Rect.fromLTWH(0, 0, 300, 300));
    expect(at(d, 300, 100, 150)[3], 255);
    expect(at(d, 300, 200, 150)[3], 0);

    // alpha lock only recolours existing pixels
    final half = solid(const ui.Rect.fromLTWH(0, 0, 150, 300), const ui.Color(0xFFFF0000));
    final s4 = stroke(brush.copyWith(opacity: 1), lockAlpha: true);
    d = await s4.commit(half).readRgba(const ui.Rect.fromLTWH(0, 0, 300, 300));
    expect(at(d, 300, 100, 150), [0, 0, 255, 255]);
    expect(at(d, 300, 200, 150)[3], 0);
  });

  test('symmetry replicates dabs', () async {
    final brush = builtinBrushes().firstWhere((b) => b.id == 'fineliner').copyWith(size: 10, smoothing: 0);
    final sym = const SymmetrySpec(kind: SymmetryKind.quad, center: ui.Offset(150, 150)).transforms;
    final s = PaintStroke(brush: brush, color: const ui.Color(0xFF000000), symmetry: sym, simulatePressure: false);
    s.add(const StrokeInput(ui.Offset(50, 60)));
    s.add(const StrokeInput(ui.Offset(60, 60), timeMs: 10));
    s.finish();
    final d = await s.commit(TilePlane.empty).readRgba(const ui.Rect.fromLTWH(0, 0, 300, 300));
    expect(at(d, 300, 55, 60)[3], greaterThan(200));
    expect(at(d, 300, 245, 60)[3], greaterThan(200));
    expect(at(d, 300, 55, 240)[3], greaterThan(200));
    expect(at(d, 300, 245, 240)[3], greaterThan(200));
    expect(const SymmetrySpec(kind: SymmetryKind.mandala, count: 8).transforms.length, 16);
  });

  test('smudge drags paint', () async {
    final base = solid(const ui.Rect.fromLTWH(0, 0, 150, 300), const ui.Color(0xFFFF0000));
    final brush = builtinBrushes().firstWhere((b) => b.id == 'smudge').copyWith(size: 50, smudge: 0.9, smoothing: 0);
    final s = SmudgeStroke(brush: brush, source: base, color: const ui.Color(0xFF000000), simulatePressure: false);
    for (var x = 120.0; x <= 230; x += 3) {
      s.add(StrokeInput(ui.Offset(x, 150), timeMs: x));
    }
    s.finish();
    final d = await s.working.readRgba(const ui.Rect.fromLTWH(0, 0, 300, 300));
    // red was pulled to the right of the original edge
    expect(at(d, 300, 175, 150)[3], greaterThan(60));
    expect(at(d, 300, 175, 60)[3], 0);
    await savePng(s.working.toImage(const ui.Rect.fromLTWH(0, 0, 300, 300), background: const ui.Color(0xFFFFFFFF)), 'smudge.png');
  });

  test('compositor: blend, opacity, clipping, mask, adjustment', () async {
    final red = solid(const ui.Rect.fromLTWH(0, 0, 200, 200), const ui.Color(0xFFFF0000));
    final green = solid(const ui.Rect.fromLTWH(100, 100, 200, 200), const ui.Color(0xFF00FF00));
    Future<Uint8List> render(Project p) => imageToRgba(renderCompImage(p, p.main, 0));

    // normal + opacity
    var p = projectWith([paintLayer('a', red), paintLayer('b', green, props: const LayerProps(opacity: 0.5))]);
    var d = await render(p);
    expect(at(d, 300, 50, 50), [255, 0, 0, 255]);
    expect(at(d, 300, 150, 150)[0], closeTo(128, 2));
    expect(at(d, 300, 150, 150)[1], closeTo(128, 2));
    expect(at(d, 300, 250, 250)[1], closeTo(255, 1)); // 50% green over white
    expect(at(d, 300, 250, 250)[0], closeTo(128, 2));

    // multiply
    p = projectWith([paintLayer('a', red), paintLayer('b', green, props: const LayerProps(blend: LayerBlend.multiply))]);
    d = await render(p);
    expect(at(d, 300, 150, 150), [0, 0, 0, 255]);

    // clipping mask: green only where red exists
    p = projectWith([paintLayer('a', red), paintLayer('b', green, props: const LayerProps(clip: true))]);
    d = await render(p);
    expect(at(d, 300, 150, 150), [0, 255, 0, 255]);
    expect(at(d, 300, 250, 250), [255, 255, 255, 255]);

    // layer mask hides the left part of red
    final hide = solid(const ui.Rect.fromLTWH(0, 0, 100, 300), const ui.Color(0xFF000000));
    p = projectWith([paintLayer('a', red, props: LayerProps(mask: hide))]);
    d = await render(p);
    expect(at(d, 300, 50, 50), [255, 255, 255, 255]);
    expect(at(d, 300, 150, 50), [255, 0, 0, 255]);

    // matrix adjustment layer (invert) affects layers below only
    p = projectWith([paintLayer('a', red), AdjustLayer('adj', const LayerProps(), filterDef('invert').defaults), paintLayer('b', green)]);
    d = await render(p);
    expect(at(d, 300, 50, 50), [0, 255, 255, 255]);
    expect(at(d, 300, 250, 250), [0, 255, 0, 255]);
    expect(at(d, 300, 250, 50), [0, 0, 0, 255]); // inverted white paper

    // shader adjustment layer (threshold via LUT)
    p = projectWith([paintLayer('a', solid(const ui.Rect.fromLTWH(0, 0, 150, 300), const ui.Color(0xFF303030))), AdjustLayer('adj', const LayerProps(), filterDef('threshold').defaults)]);
    d = await render(p);
    expect(at(d, 300, 50, 50), [0, 0, 0, 255]);
    expect(at(d, 300, 250, 50), [255, 255, 255, 255]);

    // group with opacity
    p = projectWith([
      GroupLayer('g', const LayerProps(opacity: 0.5), [paintLayer('a', red), paintLayer('b', green)], passThrough: false),
    ]);
    d = await render(p);
    expect(at(d, 300, 150, 150)[1], closeTo(255, 1));
    expect(at(d, 300, 150, 150)[0], closeTo(128, 2));
  });

  test('shader filters stay anchored under canvas transforms', () async {
    // threshold adjustment rendered through a scaled + translated view must
    // match the plain render scaled the same way
    final p = projectWith([
      paintLayer('a', solid(const ui.Rect.fromLTWH(100, 0, 100, 300), const ui.Color(0xFF202020))),
      AdjustLayer('adj', const LayerProps(), filterDef('threshold').defaults),
    ]);
    final img = renderToImage(300, 300, (c) {
      c.translate(30, 20);
      c.scale(0.5);
      Compositor(p).paintComp(c, p.main, const RenderOptions(frame: 0, cull: ui.Rect.fromLTWH(0, 0, 300, 300)));
    });
    final d = await imageToRgba(img);
    // doc x=150 -> screen 30 + 75 = 105 (dark bar -> black), doc x=50 -> 55 (white)
    expect(at(d, 300, 105, 80), [0, 0, 0, 255]);
    expect(at(d, 300, 55, 80), [255, 255, 255, 255]);
    expect(at(d, 300, 10, 80)[3], 0); // outside the document
    await savePng(img, 'adjust_transformed.png');
  });

  test('layer effects and tween transform render', () async {
    final dot = TilePlane.empty.drawn((c) => c.drawCircle(const ui.Offset(150, 150), 40, ui.Paint()..color = const ui.Color(0xFF2E7D32)),
        area: const ui.Rect.fromLTWH(100, 100, 100, 100));
    final fx = const LayerProps().copyWith(
      fx: const LayerFx(shadow: true, stroke: true, strokeColor: ui.Color(0xFF000000), strokeWidth: 4, glow: false, bevel: true),
    );
    final p = projectWith([paintLayer('a', dot, props: fx)]);
    final img = renderCompImage(p, p.main, 0);
    final d = await imageToRgba(img);
    await savePng(img, 'fx.png');
    // outline just outside the circle is dark
    expect(at(d, 300, 150, 108)[0], lessThan(60));
    // drop shadow to the lower right is greyish
    expect(at(d, 300, 183, 183)[0], lessThan(235));

    // tween: x animated from 0 to 100 over 10 frames
    final tw = const LayerProps().copyWith(tracks: {
      Prop.x: const AnimTrack([AnimKey(0, 0, Ease.linear), AnimKey(10, 100, Ease.linear)]),
    });
    final p2 = projectWith([paintLayer('a', dot, props: tw)]);
    final d2 = await imageToRgba(renderCompImage(p2, p2.main, 5));
    expect(at(d2, 300, 200, 150)[1], greaterThan(100)); // centre moved to x=200
    expect(at(d2, 300, 120, 150), [255, 255, 255, 255]);
    expect(Mat2D.identity.isIdentity, isTrue);
  });
}
