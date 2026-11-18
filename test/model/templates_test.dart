import 'dart:ui';

import 'package:drawly/model/layer.dart';
import 'package:drawly/model/templates.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('template ids are unique and every template builds with matching properties', () {
    final ids = kTemplates.map((t) => t.id).toSet();
    expect(ids.length, kTemplates.length);

    for (final tpl in kTemplates) {
      final project = tpl.build();
      final main = project.main;
      expect(main.width, tpl.width, reason: tpl.id);
      expect(main.height, tpl.height, reason: tpl.id);
      expect(main.background, tpl.background, reason: tpl.id);
      expect(main.timeline.fps, tpl.fps, reason: tpl.id);
      expect(main.timeline.length, tpl.frames, reason: tpl.id);
      expect(project.meta.dpi, tpl.dpi, reason: tpl.id);
      expect(tpl.label, isNotEmpty, reason: tpl.id);
    }
  });

  test('manga_4 and strip_3 add a top VectorLayer with panel shapes inside the page', () {
    final manga = kTemplates.firstWhere((t) => t.id == 'manga_4').build();
    final mangaTop = manga.main.layers.last;
    expect(mangaTop, isA<VectorLayer>());
    final mangaShapes = (mangaTop as VectorLayer).cels.at(0)!.shapes;
    expect(mangaShapes.length, 4);
    for (final s in mangaShapes) {
      final b = s.path.getBounds();
      expect(manga.main.rect.contains(b.topLeft), isTrue);
      expect(manga.main.rect.contains(b.bottomRight), isTrue);
    }
    expect(manga.main.guides.length, 4);

    final strip = kTemplates.firstWhere((t) => t.id == 'strip_3').build();
    final stripTop = strip.main.layers.last as VectorLayer;
    expect(stripTop.cels.at(0)!.shapes.length, 3);
  });

  test('panelGrid computes exact panel rectangles with margin and gutter', () {
    final rects = panelGrid(
      const Rect.fromLTWH(0, 0, 100, 100),
      rows: 2,
      columns: 2,
      margin: 10,
      gutter: 4,
    );
    expect(rects, const [
      Rect.fromLTWH(10, 10, 38, 38),
      Rect.fromLTWH(52, 10, 38, 38),
      Rect.fromLTWH(10, 52, 38, 38),
      Rect.fromLTWH(52, 52, 38, 38),
    ]);
  });

  test('story_6 has 6 contiguous scenes covering 144 frames and pixelArt templates have null background', () {
    final story = kTemplates.firstWhere((t) => t.id == 'story_6').build();
    final scenes = story.main.timeline.scenes;
    expect(scenes.length, 6);
    var expectedStart = 0;
    for (final sc in scenes) {
      expect(sc.start, expectedStart);
      expect(sc.length, 24);
      expectedStart = sc.end;
    }
    expect(expectedStart, 144);

    final pixelTemplates = kTemplates.where((t) => t.kind == TemplateKind.pixelArt).toList();
    expect(pixelTemplates.length, 4);
    for (final tpl in pixelTemplates) {
      expect(tpl.background, isNull, reason: tpl.id);
      expect(tpl.build().main.background, isNull, reason: tpl.id);
    }
  });

  test('templateCategoryLabel returns non-empty text for all 7 categories', () {
    const categories = [
      kTplPrint,
      kTplScreen,
      kTplSocial,
      kTplComic,
      kTplStoryboard,
      kTplPixel,
      kTplAnimation,
    ];
    for (final c in categories) {
      expect(templateCategoryLabel(c), isNotEmpty, reason: c);
    }
  });
}
