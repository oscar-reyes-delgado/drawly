import 'package:flutter/material.dart';

import '../../app/app_state.dart';
import '../../core/i18n.dart';
import '../../model/document.dart';
import '../../model/templates.dart';
import '../theme.dart';
import '../widgets.dart';

class _Preset {
  const _Preset(this.es, this.en, this.w, this.h, {this.dpi = 72, this.fps = 12, this.frames = 1, this.transparent = false, this.group = 0});
  final String es, en;
  final int w, h, fps, frames, group;
  final double dpi;
  final bool transparent;
  String get label => tr(es, en);
}

const List<String> _groupsEs = ['Pantalla', 'Impresión', 'Redes sociales', 'Animación', 'Pixel art', 'Viñetas'];
const List<String> _groupsEn = ['Screen', 'Print', 'Social media', 'Animation', 'Pixel art', 'Panels'];

/// Index of the group that lists the panel templates of `kTemplates`.
const int _kPanelGroup = 5;

const List<_Preset> _presets = [
  _Preset('Full HD', 'Full HD', 1920, 1080),
  _Preset('4K', '4K', 3840, 2160),
  _Preset('Cuadrado 2048', 'Square 2048', 2048, 2048),
  _Preset('A4', 'A4', 2480, 3508, dpi: 300, group: 1),
  _Preset('A5', 'A5', 1748, 2480, dpi: 300, group: 1),
  _Preset('Carta', 'Letter', 2550, 3300, dpi: 300, group: 1),
  _Preset('Cómic B5', 'B5 comic', 2079, 2953, dpi: 300, group: 1),
  _Preset('Publicación 1:1', 'Post 1:1', 1080, 1080, group: 2),
  _Preset('Historia 9:16', 'Story 9:16', 1080, 1920, group: 2),
  _Preset('Miniatura 16:9', 'Thumbnail 16:9', 1280, 720, group: 2),
  _Preset('Webtoon', 'Webtoon', 1600, 12800, group: 2),
  _Preset('HD 24 fps', 'HD 24 fps', 1920, 1080, fps: 24, frames: 48, group: 3),
  _Preset('720p 12 fps', '720p 12 fps', 1280, 720, fps: 12, frames: 24, group: 3),
  _Preset('GIF cuadrado', 'Square GIF', 480, 480, fps: 12, frames: 24, group: 3),
  _Preset('Storyboard', 'Storyboard', 1920, 1080, fps: 24, frames: 144, group: 3),
  _Preset('32 × 32', '32 × 32', 32, 32, transparent: true, group: 4),
  _Preset('64 × 64', '64 × 64', 64, 64, transparent: true, group: 4),
  _Preset('128 × 128', '128 × 128', 128, 128, transparent: true, group: 4),
  _Preset('Sprite 64 · 8 f', 'Sprite 64 · 8 f', 64, 64, fps: 8, frames: 8, transparent: true, group: 4),
];

/// Asks for the properties of a new document.
Future<Project?> showNewDocumentDialog(BuildContext context) => showDialog<Project>(context: context, builder: (_) => const _NewDocumentDialog());

class _NewDocumentDialog extends StatefulWidget {
  const _NewDocumentDialog();

  @override
  State<_NewDocumentDialog> createState() => _NewDocumentDialogState();
}

class _NewDocumentDialogState extends State<_NewDocumentDialog> {
  late final TextEditingController _name = TextEditingController(text: AppState.I.untitledName());
  double _w = 1920, _h = 1080, _dpi = 72, _fps = 12, _frames = 24;

  /// 0 white, 1 transparent, 2 black, 3 background colour
  int _bg = 0;
  bool _infinite = false;
  ColorMode _mode = ColorMode.rgb;
  int _group = 0;
  int _rev = 0;

  void _apply(_Preset p) => setState(() {
        _w = p.w.toDouble();
        _h = p.h.toDouble();
        _dpi = p.dpi;
        _fps = p.fps.toDouble();
        _frames = p.frames.toDouble();
        _bg = p.transparent ? 1 : 0;
        _rev++;
      });

  void _create() {
    final bg = switch (_bg) {
      1 => null,
      2 => const Color(0xFF000000),
      3 => AppState.I.ts.bg,
      _ => const Color(0xFFFFFFFF),
    };
    Navigator.pop(
      context,
      Project.blank(
        width: _w.round(),
        height: _h.round(),
        background: bg,
        name: _name.text.trim(),
        meta: DocMeta(dpi: _dpi, colorMode: _mode),
        fps: _fps.round(),
        frames: _frames.round(),
        infinite: _infinite,
      ),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final groups = I18n.instance.lang == 'es' ? _groupsEs : _groupsEn;
    // phones: one scrolling column with the fields first, then the presets
    final narrow = MediaQuery.sizeOf(context).width < 700;
    final presets = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(spacing: 4, runSpacing: 4, children: [
                  for (var i = 0; i < groups.length; i++) MiniToggle(label: groups[i], value: _group == i, onChanged: (_) => setState(() => _group = i)),
                ]),
                const SizedBox(height: 10),
                // panel templates build the page with its panels, guides and scenes
                if (_group == _kPanelGroup)
                  for (final t in kTemplates.where((t) => t.kind != TemplateKind.blank && t.rows * t.columns > 0))
                    InkWell(
                      key: ValueKey('tpl-${t.id}'),
                      borderRadius: BorderRadius.circular(6),
                      onTap: () => Navigator.pop(context, t.build(name: _name.text.trim().isEmpty ? null : _name.text.trim())),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                        child: Row(children: [
                          Expanded(child: Text(t.label, style: kSmall)),
                          Text('${t.width} × ${t.height}', style: kTiny.copyWith(color: context.dim)),
                        ]),
                      ),
                    ),
                for (final p in _presets.where((p) => p.group == _group))
                  InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () => _apply(p),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                      child: Row(children: [
                        Expanded(child: Text(p.label, style: kSmall)),
                        Text('${p.w} × ${p.h}', style: kTiny.copyWith(color: context.dim)),
                      ]),
                    ),
                  ),
              ]);
    final fields = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                TextField(controller: _name, style: kSmall, decoration: InputDecoration(labelText: tr('Nombre', 'Name'))),
                const SizedBox(height: 12),
                Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                  NumField(key: ValueKey('w$_rev'), value: _w, min: 1, max: 30000, width: 100, label: tr('Ancho', 'Width'), suffix: 'px', onSubmitted: (v) => setState(() => _w = v)),
                  PanelButton(
                    icon: Icons.swap_horiz,
                    tooltip: tr('Intercambiar ancho y alto', 'Swap width and height'),
                    onTap: () => setState(() {
                      final t = _w;
                      _w = _h;
                      _h = t;
                      _rev++;
                    }),
                  ),
                  NumField(key: ValueKey('h$_rev'), value: _h, min: 1, max: 30000, width: 100, label: tr('Alto', 'Height'), suffix: 'px', onSubmitted: (v) => setState(() => _h = v)),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  NumField(key: ValueKey('d$_rev'), value: _dpi, min: 1, max: 2400, width: 100, label: tr('Resolución', 'Resolution'), suffix: 'ppp', onSubmitted: (v) => setState(() => _dpi = v)),
                  const SizedBox(width: 28),
                  Expanded(
                    child: MiniDropdown<ColorMode>(
                      value: _mode,
                      width: 130,
                      tooltip: tr('Modo de color', 'Colour mode'),
                      items: [for (final m in ColorMode.values) (m, m.label)],
                      onChanged: (m) => setState(() => _mode = m),
                    ),
                  ),
                ]),
                const SizedBox(height: 14),
                Text(tr('Fondo', 'Background'), style: kTiny.copyWith(color: context.dim)),
                const SizedBox(height: 5),
                Wrap(spacing: 4, runSpacing: 4, children: [
                  MiniToggle(label: tr('Blanco', 'White'), value: _bg == 0, onChanged: (_) => setState(() => _bg = 0)),
                  MiniToggle(label: tr('Transparente', 'Transparent'), value: _bg == 1, onChanged: (_) => setState(() => _bg = 1)),
                  MiniToggle(label: tr('Negro', 'Black'), value: _bg == 2, onChanged: (_) => setState(() => _bg = 2)),
                  MiniToggle(label: tr('Color de fondo', 'Background colour'), value: _bg == 3, onChanged: (_) => setState(() => _bg = 3)),
                ]),
                const SizedBox(height: 14),
                Text(tr('Animación', 'Animation'), style: kTiny.copyWith(color: context.dim)),
                const SizedBox(height: 6),
                Wrap(spacing: 28, runSpacing: 8, children: [
                  NumField(key: ValueKey('f$_rev'), value: _fps, min: 1, max: 240, width: 100, label: 'FPS', onSubmitted: (v) => setState(() => _fps = v)),
                  NumField(key: ValueKey('n$_rev'), value: _frames, min: 1, max: 100000, width: 100, label: tr('Fotogramas', 'Frames'), onSubmitted: (v) => setState(() => _frames = v)),
                ]),
                const SizedBox(height: 12),
                MiniToggle(label: tr('Lienzo infinito', 'Infinite canvas'), icon: Icons.all_inclusive, value: _infinite, onChanged: (v) => setState(() => _infinite = v)),
              ]);
    return AlertDialog(
      title: Text(tr('Nuevo documento', 'New document'), style: const TextStyle(fontSize: 18)),
      contentPadding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
      content: SizedBox(
        width: narrow ? double.maxFinite : 620,
        child: SingleChildScrollView(
          child: narrow
              ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [fields, const Divider(height: 28), presets])
              : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(width: 250, child: presets),
                  Container(width: 1, height: 330, margin: const EdgeInsets.symmetric(horizontal: 16), color: cs.outlineVariant),
                  Expanded(child: fields),
                ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Cancelar', 'Cancel'))),
        FilledButton(onPressed: _create, child: Text(tr('Crear', 'Create'))),
      ],
    );
  }
}
