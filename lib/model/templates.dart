import 'dart:math' as math;
import 'dart:ui';

import '../core/i18n.dart';
import '../core/ids.dart';
import 'document.dart';
import 'layer.dart';
import 'vector.dart';

enum TemplateKind { blank, comicPage, storyboard, pixelArt, animation, webtoon }

class DocTemplate {
  const DocTemplate({
    required this.id,
    required this.es,
    required this.en,
    required this.category,
    required this.width,
    required this.height,
    this.dpi = 300,
    this.fps = 12,
    this.frames = 1,
    this.background = const Color(0xFFFFFFFF),
    this.kind = TemplateKind.blank,
    this.rows = 0,
    this.columns = 0,
  });

  final String id, es, en, category;
  final int width, height, fps, frames, rows, columns;
  final double dpi;
  final Color? background;
  final TemplateKind kind;

  String get label => tr(es, en);

  Project build({String? name}) {
    final p = Project.blank(
      width: width,
      height: height,
      background: background,
      name: name ?? label,
      meta: DocMeta(dpi: dpi),
      fps: fps,
      frames: frames,
    );

    if (kind != TemplateKind.comicPage &&
        kind != TemplateKind.storyboard &&
        kind != TemplateKind.webtoon) {
      return p;
    }

    final margin = width * 0.04;
    final gutter = width * 0.015;
    final rects = panelGrid(
      p.main.rect,
      rows: rows,
      columns: columns,
      margin: margin,
      gutter: gutter,
    );

    final strokeWidth = math.max(2.0, width / 400.0);
    final shapes = [
      for (final r in rects)
        VShape(
          paths: [VPath.rect(r)],
          stroke: VStroke(color: const Color(0xFF000000), width: strokeWidth),
        ),
    ];

    final panelLayer = VectorLayer(
      newId('L'),
      LayerProps(
        name: tr('Viñetas', 'Panels'),
        xf: Xform(ax: width / 2, ay: height / 2),
      ),
      CelTrack.single(VectorArt(shapes)),
    );

    final guides = <Guide>[
      Guide(true, margin),
      Guide(true, width - margin),
      Guide(false, margin),
      Guide(false, height - margin),
    ];

    var timeline = p.main.timeline;
    if (kind == TemplateKind.storyboard && rects.isNotEmpty) {
      final count = rects.length;
      final shotLen = math.max(1, frames ~/ count);
      final scenes = <Scene>[];
      var cursor = 0;
      for (var i = 0; i < count; i++) {
        final len = i == count - 1 ? math.max(1, frames - cursor) : shotLen;
        scenes.add(Scene(
          id: newId('sc'),
          name: '${tr('Plano', 'Shot')} ${i + 1}',
          start: cursor,
          length: len,
        ));
        cursor += len;
      }
      timeline = timeline.copyWith(scenes: scenes);
    }

    return p.withComp(
      p.main.copyWith(
        layers: [...p.main.layers, panelLayer],
        guides: [...p.main.guides, ...guides],
        timeline: timeline,
      ),
    );
  }
}

const String kTplPrint = 'print';
const String kTplScreen = 'screen';
const String kTplSocial = 'social';
const String kTplComic = 'comic';
const String kTplStoryboard = 'storyboard';
const String kTplPixel = 'pixel';
const String kTplAnimation = 'animation';

String templateCategoryLabel(String category) => switch (category) {
      kTplPrint => tr('Impresión', 'Print'),
      kTplScreen => tr('Pantalla', 'Screen'),
      kTplSocial => tr('Redes sociales', 'Social media'),
      kTplComic => tr('Cómic y webtoon', 'Comic & webtoon'),
      kTplStoryboard => tr('Storyboard', 'Storyboard'),
      kTplPixel => tr('Pixel art', 'Pixel art'),
      kTplAnimation => tr('Animación', 'Animation'),
      _ => category,
    };

const List<DocTemplate> kTemplates = [
  // Print
  DocTemplate(id: 'a4', es: 'A4', en: 'A4', category: kTplPrint, width: 2480, height: 3508),
  DocTemplate(id: 'a5', es: 'A5', en: 'A5', category: kTplPrint, width: 1748, height: 2480),
  DocTemplate(id: 'letter', es: 'Carta', en: 'Letter', category: kTplPrint, width: 2550, height: 3300),

  // Screen
  DocTemplate(id: 'hd', es: 'Full HD', en: 'Full HD', category: kTplScreen, width: 1920, height: 1080, dpi: 72),
  DocTemplate(id: '4k', es: '4K', en: '4K', category: kTplScreen, width: 3840, height: 2160, dpi: 72),
  DocTemplate(id: 'square', es: 'Cuadrado', en: 'Square', category: kTplScreen, width: 2048, height: 2048, dpi: 72),

  // Social
  DocTemplate(id: 'ig_post', es: 'Publicación de Instagram', en: 'Instagram post', category: kTplSocial, width: 1080, height: 1080, dpi: 72),
  DocTemplate(id: 'ig_story', es: 'Historia de Instagram', en: 'Instagram story', category: kTplSocial, width: 1080, height: 1920, dpi: 72),
  DocTemplate(id: 'yt_thumb', es: 'Miniatura de YouTube', en: 'YouTube thumbnail', category: kTplSocial, width: 1280, height: 720, dpi: 72),
  DocTemplate(id: 'banner', es: 'Cabecera', en: 'Header', category: kTplSocial, width: 1500, height: 500, dpi: 72),

  // Comic & Webtoon
  DocTemplate(id: 'comic_b5', es: 'Página de cómic B5', en: 'B5 comic page', category: kTplComic, width: 2079, height: 2953, kind: TemplateKind.comicPage, rows: 3, columns: 2),
  DocTemplate(id: 'manga_4', es: 'Página de 4 viñetas', en: '4-panel page', category: kTplComic, width: 2079, height: 2953, kind: TemplateKind.comicPage, rows: 2, columns: 2),
  DocTemplate(id: 'strip_3', es: 'Tira de 3 viñetas', en: '3-panel strip', category: kTplComic, width: 3000, height: 1000, kind: TemplateKind.comicPage, rows: 1, columns: 3),
  DocTemplate(id: 'webtoon', es: 'Webtoon', en: 'Webtoon', category: kTplComic, width: 1600, height: 12800, dpi: 72, kind: TemplateKind.webtoon, rows: 8, columns: 1),

  // Storyboard
  DocTemplate(id: 'story_6', es: 'Storyboard de 6 planos', en: '6-shot storyboard', category: kTplStoryboard, width: 1920, height: 1080, dpi: 72, fps: 24, frames: 144, kind: TemplateKind.storyboard, rows: 2, columns: 3),

  // Pixel art
  DocTemplate(id: 'px_32', es: 'Pixel art 32x32', en: 'Pixel art 32x32', category: kTplPixel, width: 32, height: 32, dpi: 72, background: null, kind: TemplateKind.pixelArt),
  DocTemplate(id: 'px_64', es: 'Pixel art 64x64', en: 'Pixel art 64x64', category: kTplPixel, width: 64, height: 64, dpi: 72, background: null, kind: TemplateKind.pixelArt),
  DocTemplate(id: 'px_128', es: 'Pixel art 128x128', en: 'Pixel art 128x128', category: kTplPixel, width: 128, height: 128, dpi: 72, background: null, kind: TemplateKind.pixelArt),
  DocTemplate(id: 'px_320', es: 'Pixel art 320x180', en: 'Pixel art 320x180', category: kTplPixel, width: 320, height: 180, dpi: 72, background: null, kind: TemplateKind.pixelArt),

  // Animation
  DocTemplate(id: 'anim_hd', es: 'Animación HD 24 fps', en: 'HD animation 24 fps', category: kTplAnimation, width: 1920, height: 1080, dpi: 72, fps: 24, frames: 48, kind: TemplateKind.animation),
  DocTemplate(id: 'anim_12', es: 'Animación 12 fps', en: 'Animation 12 fps', category: kTplAnimation, width: 1280, height: 720, dpi: 72, fps: 12, frames: 24, kind: TemplateKind.animation),
  DocTemplate(id: 'gif_480', es: 'GIF cuadrado', en: 'Square GIF', category: kTplAnimation, width: 480, height: 480, dpi: 72, fps: 12, frames: 24, kind: TemplateKind.animation),
  DocTemplate(id: 'sprite_64', es: 'Sprite 64x64', en: '64x64 sprite', category: kTplAnimation, width: 64, height: 64, dpi: 72, fps: 8, frames: 8, background: null, kind: TemplateKind.animation),
];

/// Panel rectangles, row by row.
List<Rect> panelGrid(
  Rect page, {
  required int rows,
  required int columns,
  double margin = 0,
  double gutter = 0,
}) {
  if (rows <= 0 || columns <= 0) return const <Rect>[];
  final cellW = (page.width - 2 * margin - (columns - 1) * gutter) / columns;
  final cellH = (page.height - 2 * margin - (rows - 1) * gutter) / rows;
  if (cellW <= 0 || cellH <= 0) return const <Rect>[];
  return <Rect>[
    for (var r = 0; r < rows; r++)
      for (var c = 0; c < columns; c++)
        Rect.fromLTWH(
          page.left + margin + c * (cellW + gutter),
          page.top + margin + r * (cellH + gutter),
          cellW,
          cellH,
        ),
  ];
}
