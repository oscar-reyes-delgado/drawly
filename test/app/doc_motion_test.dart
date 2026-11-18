import 'package:drawly/app/doc_layers.dart';
import 'package:drawly/app/doc_motion.dart';
import 'package:drawly/app/document_controller.dart';
import 'package:drawly/engine/tiles.dart';
import 'package:drawly/model/anim.dart';
import 'package:drawly/model/document.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bakeBounce writes a falling and bouncing X/Y path that never goes through the floor', () async {
    final d = DocumentController(Project.blank(width: 100, height: 200, frames: 80, background: null), title: 'b');
    const r = Rect.fromLTWH(40, 20, 20, 20);
    d.addPaintLayer(pixels: TilePlane.empty.drawn((c) => c.drawRect(r, Paint()..color = const Color(0xFF00AA00)), area: r));
    final id = d.activeLayerId!;

    expect(await d.bakeBounce(frames: 80), 80);
    final props = d.comp.layer(id)!.props;
    expect(props.tracks[Prop.y]!.keys, hasLength(80));
    expect(props.valueAt(Prop.y, 0), closeTo(0, 1e-9));
    final ys = [for (var f = 0; f < 80; f++) props.valueAt(Prop.y, f.toDouble())];
    final maxDrop = 200 - r.bottom;
    expect(ys.every((y) => y <= maxDrop + 0.01), isTrue, reason: 'floor at the bottom of the canvas');
    final impact = ys.indexWhere((y) => y > maxDrop - 0.5);
    expect(impact, greaterThan(0), reason: 'it reaches the floor');
    expect(ys.skip(impact).any((y) => y < maxDrop - 5), isTrue, reason: 'it bounces back up');
    expect(props.valueAt(Prop.x, 40), closeTo(0, 1e-9), reason: 'no horizontal drift without velocity');

    d.undo();
    expect(d.comp.layer(id)!.props.tracks[Prop.y], isNull);
  });

  test('bakeBounce on an empty layer does nothing', () async {
    final d = DocumentController(Project.blank(width: 64, height: 64), title: 'e');
    d.addPaintLayer();
    expect(await d.bakeBounce(), 0);
  });
}
