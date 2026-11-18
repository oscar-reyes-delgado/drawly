import 'dart:convert';

import 'package:drawly/app/doc_layers.dart';
import 'package:drawly/app/doc_timeline.dart';
import 'package:drawly/app/document_controller.dart';
import 'package:drawly/engine/tiles.dart';
import 'package:drawly/io/lottie_export.dart';
import 'package:drawly/model/anim.dart';
import 'package:drawly/model/document.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Lottie export checked through the document, as the «Export Lottie» command uses it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a document with an animated paint layer exports as Lottie with its motion', () async {
    final d = DocumentController(Project.blank(width: 64, height: 48, frames: 12, fps: 12), title: 'l');
    const r = Rect.fromLTWH(8, 8, 16, 16);
    d.addPaintLayer(name: 'ball', pixels: TilePlane.empty.drawn((c) => c.drawRect(r, Paint()..color = const Color(0xFFFF0000)), area: r));
    final id = d.activeLayerId!;
    d.setLayerProp(id, Prop.x, 0, forceKey: true);
    d.frame = 10;
    d.setLayerProp(id, Prop.x, 30);

    final res = await exportLottie(d.project, compId: d.compId);
    final j = jsonDecode(res.json) as Map<String, dynamic>;
    expect([j['w'], j['h'], j['fr'], j['op']], [64, 48, 12, 12]);
    final layers = (j['layers'] as List).cast<Map<String, dynamic>>();
    final ball = layers.firstWhere((l) => l['nm'] == 'ball');
    expect(ball['ty'], 2);
    final assets = (j['assets'] as List).cast<Map<String, dynamic>>();
    expect(assets.firstWhere((a) => a['id'] == ball['refId'])['p'], startsWith('data:image/png;base64,'));
    final p = (ball['ks'] as Map)['p'] as Map;
    expect(p['s'], isTrue);
    final xKeys = (p['x'] as Map)['k'] as List;
    expect([for (final k in xKeys) (k as Map)['t']], containsAll([0, 10]));
  });
}
