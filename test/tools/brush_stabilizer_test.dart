import 'dart:ui';

import 'package:drawly/app/app_state.dart';
import 'package:drawly/engine/brush/stabilizer.dart';
import 'package:drawly/engine/brush/tips.dart';
import 'package:drawly/engine/tiles.dart';
import 'package:drawly/model/document.dart';
import 'package:drawly/model/layer.dart';
import 'package:drawly/tools/brush_tool.dart';
import 'package:drawly/tools/tool.dart';
import 'package:flutter_test/flutter_test.dart';

/// The brush tool feeds strokes through the stabilizer chosen in the settings.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final app = AppState.I;
  setUpAll(() async {
    await BrushTips.instance.ensureLoaded();
    // a brush without a tapered start, so a single dab is clearly visible
    app.ts.selectBrush(app.ts.brushes.firstWhere((b) => b.id == 'round_brush'));
  });

  tearDown(() {
    while (app.docs.isNotEmpty) {
      app.closeDocument(app.docs.first);
    }
    app.settings
      ..stabilizerMode = StabilizerMode.brush
      ..stabilizerStrength = 0.5
      ..stabilizerCatchUp = true;
  });

  Future<Rect?> drag(List<Offset> pts) async {
    final d = app.addDocument(Project.blank(width: 200, height: 200, background: null), title: 'stab');
    final tool = BrushTool('brush');
    ToolEvent ev(Offset p, int i) => ToolEvent(doc: p, view: d.view.toView(p), timeMs: i * 16.0);
    tool.onDown(ev(pts.first, 0));
    for (var i = 1; i < pts.length; i++) {
      tool.onMove(ev(pts[i], i));
    }
    tool.onUp(ev(pts.last, pts.length));
    final plane = (d.activeLayer! as PaintLayer).cels.at(d.frame) ?? TilePlane.empty;
    return plane.contentBounds();
  }

  final line = [for (var x = 20; x <= 60; x += 2) Offset(x.toDouble(), 100)];

  test('rope without catch-up: a drag shorter than the rope leaves only the first dab', () async {
    app.settings
      ..stabilizerMode = StabilizerMode.rope
      ..stabilizerStrength = 1
      ..stabilizerCatchUp = false;
    final b = await drag(line);
    expect(b, isNotNull);
    expect(b!.right, lessThan(40), reason: 'the 40 px drag stays inside the 90 px rope');
  });

  test('rope with catch-up: the stroke still reaches the pointer', () async {
    app.settings
      ..stabilizerMode = StabilizerMode.rope
      ..stabilizerStrength = 1
      ..stabilizerCatchUp = true;
    final b = await drag(line);
    expect(b!.right, greaterThan(58));
  });

  test('per-brush mode draws the whole drag', () async {
    final b = await drag(line);
    expect(b!.left, lessThan(22));
    expect(b.right, greaterThan(58));
  });
}
