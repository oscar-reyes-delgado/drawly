import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/app_state.dart';
import '../../app/document_controller.dart';
import '../../core/i18n.dart';
import '../canvas/canvas_view.dart';
import '../panels/color_panel.dart';
import 'easy_color_bar.dart';
import 'easy_export_sheet.dart';
import 'easy_prefs.dart';
import 'easy_layers.dart';
import 'easy_timeline.dart';
import 'easy_toolbar.dart';
import 'tutorial.dart';
import '../../model/layer.dart';
import '../shell.dart';
import '../theme.dart';
import '../../app/doc_frames.dart';
import '../../app/doc_timeline.dart';
import '../../app/frame_thumbs.dart';
import '../../platform/io.dart' as io;
import '../file_commands.dart';
import '../library/animation_player.dart';
import '../library/library_page.dart';
import '../../platform/video_encoder.dart';

/// Real tool ids reachable from the easy toolbar.
final List<String> kEasyToolIds = {for (final t in EasyTool.values) t.toolId}.toList();

/// Colour sheet of the easy mode: basic colours, recent and favourites, with
/// «More colours…» opening the full picker.
void showEasyColors(BuildContext context) {
  final app = AppState.I;
  showModalBottomSheet<void>(
    context: context,
    builder: (sheet) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
        child: ListenableBuilder(
          listenable: app.settings,
          builder: (context, _) => EasyColorBar(
            ts: app.ts,
            favorites: app.settings.favoriteColors,
            onFavoritesChanged: (f) => app.settings.update((s) => s.favoriteColors = f),
            onMore: () {
              Navigator.pop(sheet);
              showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => SafeArea(child: SingleChildScrollView(child: ColorPanel(ts: app.ts))),
              );
            },
          ),
        ),
      ),
    ),
  );
}

/// Switches between the easy and the advanced interface. The open documents,
/// their history and the active tool are kept: only the interface changes.
void setUiMode(AppState app, String mode) {
  if (app.settings.uiMode == mode) return;
  app.tool.onCancel();
  if (mode == 'easy' && !kEasyToolIds.contains(app.ts.toolId)) app.setTool('brush');
  app.settings.update((s) => s.uiMode = mode);
}

/// Beginner interface: big buttons, few tools, a simple timeline.
///
/// Five zones: top bar (back, title, undo/redo, save state, settings, export,
/// mode), tools on the left, canvas in the centre, layers on the right and the
/// timeline at the bottom. On narrow screens the layers go to a drawer.
class EasyShell extends StatelessWidget {
  const EasyShell({super.key});

  static const double compactWidth = 760;

  /// Frame thumbnails of the easy timeline, shared by every document.
  static final FrameThumbnailCache thumbs = FrameThumbnailCache(height: 64);

  /// First-run tutorial (bouncing ball).
  static final TutorialController tutorial = TutorialController(bouncingBallSteps());

  /// Set when an export finishes, for the last tutorial step.
  static final ValueNotifier<bool> exported = ValueNotifier(false);

  /// Layer panel shown on wide screens (the user can hide it).
  static final ValueNotifier<bool> layersVisible = ValueNotifier(true);

  @override
  Widget build(BuildContext context) {
    final app = AppState.I;
    return Focus(
      focusNode: app.focusNode,
      autofocus: true,
      onKeyEvent: app.handleKey,
      child: ListenableBuilder(
        listenable: Listenable.merge([app, app.settings, layersVisible]),
        builder: (context, _) => LayoutBuilder(builder: (context, box) {
          final doc = app.doc;
          final compact = box.maxWidth < compactWidth;
          final short = box.maxHeight < 560;
          final panels = app.settings.panelVisible;
          final toolsOpen = panels['easy.tools'] ?? true;
          final timelineOpen = panels['easy.timeline'] ?? !short;
          return Scaffold(
            backgroundColor: context.workspace,
            endDrawer: compact && doc != null
                ? Drawer(width: math.min(340.0, box.maxWidth * 0.88), child: SafeArea(child: _LayersBox(doc: doc)))
                : null,
            body: SafeArea(
              child: _TutorialHost(child: Column(children: [
                _EasyTopBar(app: app, compact: compact),
                Expanded(
                  child: doc == null
                      ? const EasyHome()
                      : Row(children: [
                          _FoldingTools(
                            open: toolsOpen,
                            onToggle: () => togglePanel(app, 'easy.tools', toolsOpen),
                            child: EasyToolbar(
                              ts: app.ts,
                              activeToolId: app.activeToolId,
                              onSelectTool: app.setTool,
                              onOpenColors: () => showEasyColors(context),
                            ),
                          ),
                          Expanded(child: CanvasView(key: ValueKey(doc), doc: doc)),
                          if (!compact && layersVisible.value) SizedBox(width: 260, child: _LayersBox(doc: doc)),
                        ]),
                ),
                if (doc != null)
                  Container(
                    decoration: BoxDecoration(color: context.panel, border: Border(top: BorderSide(color: context.line))),
                    child: _FoldingTimeline(
                      open: timelineOpen,
                      doc: doc,
                      onToggle: () => togglePanel(app, 'easy.timeline', timelineOpen),
                      autoHeight: short ? 112 : (compact ? 124 : 140),
                      maxHeight: math.max(160.0, box.maxHeight * 0.6),
                      builder: (h) => EasyTimeline(key: ValueKey(doc), doc: doc, playback: app.playback, thumbs: thumbs, height: h),
                    ),
                  ),
              ])),
            ),
          );
        }),
      ),
    );
  }
}

class _LayersBox extends StatelessWidget {
  const _LayersBox({required this.doc});
  final DocumentController doc;

  @override
  Widget build(BuildContext context) => Material(
        color: context.panel,
        shape: Border(left: BorderSide(color: context.line)),
        child: EasyLayers(doc: doc),
      );
}

/// Big square button used across the easy interface.
class EasyButton extends StatelessWidget {
  const EasyButton({super.key, required this.icon, required this.tooltip, this.onTap, this.selected = false, this.size = 44, this.label});
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool selected;
  final double size;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final enabled = onTap != null;
    final fg = !enabled ? context.dim.withValues(alpha: 0.5) : (selected ? cs.primary : cs.onSurface);
    final child = Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 24, color: fg),
      if (label != null) ...[const SizedBox(width: 6), Text(label!, style: TextStyle(fontSize: 13, color: fg))],
    ]);
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        selected: selected,
        enabled: enabled,
        label: tooltip,
        child: Material(
          color: selected ? cs.primary.withValues(alpha: 0.18) : Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: selected ? cs.primary : Colors.transparent)),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: size, minHeight: size),
              child: Padding(padding: EdgeInsets.symmetric(horizontal: label == null ? 0 : 10), child: Center(widthFactor: 1, child: child)),
            ),
          ),
        ),
      ),
    );
  }
}

class _EasyTopBar extends StatelessWidget {
  const _EasyTopBar({required this.app, required this.compact});
  final AppState app;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final d = app.doc;
    Widget saveState() {
      if (d == null) return const SizedBox.shrink();
      return ListenableBuilder(
        listenable: d,
        builder: (context, _) => Tooltip(
          message: d.dirty ? tr('Hay cambios sin guardar', 'There are unsaved changes') : tr('Todo guardado', 'Everything saved'),
          child: Icon(d.dirty ? Icons.cloud_upload_outlined : Icons.cloud_done_outlined, size: 20, color: d.dirty ? context.dim : context.cs.primary),
        ),
      );
    }

    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(color: context.panel, border: Border(bottom: BorderSide(color: context.line))),
      child: Row(children: [
        EasyButton(
          key: const ValueKey('easy.back'),
          icon: Icons.arrow_back,
          tooltip: tr('Cerrar el proyecto', 'Close the project'),
          onTap: d == null ? null : () => closeWithConfirm(app, d),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: d == null
              ? const Text('Drawly', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600))
              : ListenableBuilder(
                  listenable: d,
                  builder: (context, _) => Text(d.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
        ),
        saveState(),
        const SizedBox(width: 6),
        EasyButton(icon: Icons.undo, tooltip: tr('Deshacer (Ctrl+Z)', 'Undo (Ctrl+Z)'), onTap: d != null && d.history.canUndo ? () => app.commands.run('edit.undo') : null),
        EasyButton(icon: Icons.redo, tooltip: tr('Rehacer (Ctrl+Y)', 'Redo (Ctrl+Y)'), onTap: d != null && d.history.canRedo ? () => app.commands.run('edit.redo') : null),
        // phones: no room for Save, and the easy mode saves by itself
        if (!compact) EasyButton(icon: Icons.save_outlined, tooltip: tr('Guardar (Ctrl+S)', 'Save (Ctrl+S)'), onTap: d == null ? null : () => app.commands.run('file.save')),
        EasyButton(
          key: const ValueKey('easy.export'),
          icon: Icons.ios_share,
          tooltip: tr('Exportar la animación', 'Export the animation'),
          label: compact ? null : tr('Exportar', 'Export'),
          onTap: d == null ? null : () => showEasyExportFor(context, d),
        ),
        EasyButton(
          key: const ValueKey('easy.watch'),
          icon: Icons.play_circle_outline,
          tooltip: tr('Ver la animación a pantalla completa', 'Watch the animation full screen'),
          onTap: d == null ? null : () => showAnimationPlayer(context, d.project, title: d.title),
        ),
        if (!compact && d != null)
          EasyButton(
            icon: Icons.layers_outlined,
            tooltip: tr('Mostrar u ocultar las capas', 'Show or hide the layers'),
            selected: EasyShell.layersVisible.value,
            onTap: () => EasyShell.layersVisible.value = !EasyShell.layersVisible.value,
          ),
        if (compact && d != null)
          Builder(
            builder: (context) => EasyButton(
              key: const ValueKey('easy.openLayers'),
              icon: Icons.layers_outlined,
              tooltip: tr('Capas', 'Layers'),
              onTap: () => Scaffold.of(context).openEndDrawer(),
            ),
          ),
        PopupMenuButton<String>(
          key: const ValueKey('easy.menu'),
          tooltip: tr('Más opciones', 'More options'),
          icon: const Icon(Icons.more_vert),
          onSelected: (id) => switch (id) {
            'mode' => setUiMode(app, 'advanced'),
            'app.prefs' => openEasyPrefs(context),
            _ => app.commands.run(id),
          },
          itemBuilder: (context) => [
            PopupMenuItem(value: 'file.new', child: Text(tr('Nuevo proyecto', 'New project'))),
            if (compact) PopupMenuItem(value: 'file.save', enabled: d != null, child: Text(tr('Guardar', 'Save'))),
            PopupMenuItem(value: 'file.open', child: Text(tr('Abrir…', 'Open…'))),
            PopupMenuItem(value: 'file.importImage', enabled: d != null, child: Text(tr('Importar imagen…', 'Import image…'))),
            PopupMenuItem(value: 'file.importSequence', enabled: d != null, child: Text(tr('Importar secuencia de imágenes…', 'Import image sequence…'))),
            PopupMenuItem(value: 'file.importAudio', enabled: d != null, child: Text(tr('Importar audio…', 'Import audio…'))),
            PopupMenuItem(
              value: 'anim.recordVoice',
              enabled: d != null,
              child: Text(app.voice.recording ? tr('Detener grabación', 'Stop recording') : tr('Grabar voz', 'Record voice')),
            ),
            PopupMenuItem(value: 'app.prefs', child: Text(tr('Ajustes', 'Settings'))),
            const PopupMenuDivider(),
            PopupMenuItem(key: const ValueKey('easy.toAdvanced'), value: 'mode', child: Text(tr('Cambiar a Modo Avanzado', 'Switch to Advanced mode'))),
          ],
        ),
      ]),
    );
  }
}

/// Start screen of the easy mode (the project library with play buttons).
class EasyHome extends StatelessWidget {
  const EasyHome({super.key});

  @override
  Widget build(BuildContext context) => const ProjectLibraryView();
}

/// Opens the easy export sheet wired to the real export functions.
Future<void> showEasyExportFor(BuildContext context, DocumentController d) async {
  final app = AppState.I;
  final video = await VideoEncoder.isAvailable();
  if (!context.mounted) return;
  String? watermark() => app.settings.watermarkEnabled && app.settings.watermark.isNotEmpty ? app.settings.watermark : null;
  await showEasyExport(
    context,
    d,
    EasyExportActions(
      pickFolder: pickExportFolder,
      write: (o, dir, onProgress, cancel) async =>
          _markExported(await deliverExports(await writeExport(d, o, dir, watermark: o.watermark ? watermark() : null, onProgress: onProgress, cancel: cancel))),
      writeVideo: video
          ? (dir, scale, onProgress, cancel) async =>
              _markExported(await deliverExports(await writeMp4(d, dir, scale: scale, watermark: watermark(), onProgress: onProgress, cancel: cancel)))
          : null,
      reveal: io.isDesktopOS ? io.revealInFileManager : null,
    ),
  );
}

/// Settings of the easy mode, with the switch to the advanced interface.
void openEasyPrefs(BuildContext context) {
  final app = AppState.I;
  showEasyPrefs(context, settings: app.settings, onAdvancedMode: () => setUiMode(app, 'advanced'), onRestartTutorial: () {
    EasyShell.exported.value = false;
    EasyShell.tutorial.restart();
    app.settings.update((s) => s
      ..tutorialDone = false
      ..easyHints = true);
  });
}

List<String> _markExported(List<String> paths) {
  if (paths.isNotEmpty) EasyShell.exported.value = true;
  return paths;
}

/// Feeds the tutorial with what happens in the app and shows it until it is
/// finished or skipped (then it is remembered in the settings).
class _TutorialHost extends StatelessWidget {
  const _TutorialHost({required this.child});
  final Widget child;

  static TutorialSnapshot snapshot(AppState app) {
    final d = app.doc;
    if (d == null) return TutorialSnapshot(toolId: app.activeToolId, brushId: app.ts.brush.id, exported: EasyShell.exported.value);
    final l = d.activeLayer;
    var drawn = 0;
    if (l is PaintLayer) {
      for (var f = 0; f < d.timeline.length; f++) {
        if (l.cels.at(f)?.isNotEmpty ?? false) drawn++;
      }
    }
    return TutorialSnapshot(
      hasDocument: true,
      toolId: app.activeToolId,
      brushId: app.ts.brush.id,
      frameCount: d.timeline.length,
      framesWithDrawing: drawn,
      onion: d.onion.enabled,
      playing: app.playback.playing,
      exported: EasyShell.exported.value,
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = AppState.I;
    final s = app.settings;
    if (s.tutorialDone || !s.easyHints) return child;
    final d = app.doc;
    final t = EasyShell.tutorial;
    return ListenableBuilder(
      listenable: Listenable.merge([app, app.ts, app.playback, EasyShell.exported, t, ?d]),
      builder: (context, _) {
        t.update(snapshot(app));
        if (t.finished) {
          WidgetsBinding.instance.addPostFrameCallback((_) => s.update((x) => x.tutorialDone = true));
          return child;
        }
        return TutorialOverlay(controller: t, child: child);
      },
    );
  }
}

/// Opens or folds an easy-mode panel and remembers it.
void togglePanel(AppState app, String key, bool open) => app.settings.update((s) => s.panelVisible = {...s.panelVisible, key: !open});

/// Left tool column that folds into a thin strip (like an expandable menu).
class _FoldingTools extends StatelessWidget {
  const _FoldingTools({required this.open, required this.onToggle, required this.child});
  final bool open;
  final VoidCallback onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final app = AppState.I;
    final current = easyToolFor(app.activeToolId, app.ts);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      width: open ? 68 : 36,
      decoration: BoxDecoration(color: context.panel, border: Border(right: BorderSide(color: context.line))),
      child: open
          ? Column(children: [
              Expanded(child: child),
              _FoldButton(key: const ValueKey('easy.tools.toggle'), icon: Icons.chevron_left, tooltip: tr('Ocultar herramientas', 'Hide tools'), onTap: onToggle),
            ])
          : Column(children: [
              _FoldButton(key: const ValueKey('easy.tools.toggle'), icon: Icons.chevron_right, tooltip: tr('Mostrar herramientas', 'Show tools'), onTap: onToggle),
              if (current != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Tooltip(message: current.label, child: Icon(current.icon, size: 22, color: context.cs.primary)),
                ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => showEasyColors(context),
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(color: app.ts.fg, shape: BoxShape.circle, border: Border.all(color: context.line, width: 2)),
                ),
              ),
            ]),
    );
  }
}

/// Timeline that folds into a slim bar with play, frame counter and «+».
/// Frame strip that folds into a slim bar, and can be made taller by dragging
/// its top edge or with the «expand» button (the height is remembered).
class _FoldingTimeline extends StatefulWidget {
  const _FoldingTimeline({required this.open, required this.doc, required this.onToggle, required this.autoHeight, required this.maxHeight, required this.builder});
  final bool open;
  final DocumentController doc;
  final VoidCallback onToggle;
  final double autoHeight, maxHeight;
  final Widget Function(double height) builder;

  @override
  State<_FoldingTimeline> createState() => _FoldingTimelineState();
}

class _FoldingTimelineState extends State<_FoldingTimeline> {
  /// Height while dragging (saved to the settings when the drag ends).
  double? _drag;

  double get _saved {
    final s = AppState.I.settings.easyTimelineHeight;
    return s > 0 ? s : widget.autoHeight;
  }

  double get _height => (_drag ?? _saved).clamp(math.min(100.0, widget.maxHeight), widget.maxHeight);

  bool get _expanded => _height >= widget.maxHeight * 0.9;

  void _save(double h) {
    final value = (h - widget.autoHeight).abs() < 4 ? 0.0 : h;
    AppState.I.settings.update((s) => s.easyTimelineHeight = value);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppState.I;
    final doc = widget.doc;
    final open = widget.open;
    final grip = SizedBox(
      height: 24,
      child: Row(children: [
        const SizedBox(width: 44),
        Expanded(
          child: GestureDetector(
            key: const ValueKey('easy.timeline.resize'),
            behavior: HitTestBehavior.opaque,
            onVerticalDragUpdate: open ? (d) => setState(() => _drag = (_drag ?? _height) - d.delta.dy) : null,
            onVerticalDragEnd: open
                ? (_) {
                    final h = _height;
                    setState(() => _drag = null);
                    _save(h);
                  }
                : null,
            child: InkWell(
              key: const ValueKey('easy.timeline.toggle'),
              onTap: widget.onToggle,
              child: Tooltip(
                message: open
                    ? tr('Toca para plegar · arrastra para cambiar la altura', 'Tap to fold · drag to change the height')
                    : tr('Mostrar fotogramas', 'Show frames'),
                child: Center(
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(width: 36, height: 4, decoration: BoxDecoration(color: context.line, borderRadius: BorderRadius.circular(2))),
                    const SizedBox(width: 6),
                    Icon(open ? Icons.expand_more : Icons.expand_less, size: 18, color: context.dim),
                  ]),
                ),
              ),
            ),
          ),
        ),
        SizedBox(
          width: 44,
          child: open
              ? IconButton(
                  key: const ValueKey('easy.timeline.expand'),
                  iconSize: 18,
                  tooltip: _expanded ? tr('Tamaño normal', 'Normal size') : tr('Agrandar fotogramas', 'Enlarge frames'),
                  icon: Icon(_expanded ? Icons.close_fullscreen : Icons.open_in_full, color: context.dim),
                  onPressed: () => _save(_expanded ? widget.autoHeight : widget.maxHeight),
                )
              : null,
        ),
      ]),
    );
    if (open) return Column(mainAxisSize: MainAxisSize.min, children: [grip, widget.builder(_height)]);
    return ListenableBuilder(
      listenable: Listenable.merge([doc, doc.frameSignal, app.playback]),
      builder: (context, _) => Column(mainAxisSize: MainAxisSize.min, children: [
        grip,
        SizedBox(
          height: 44,
          child: Row(children: [
            const SizedBox(width: 6),
            EasyButton(
              key: const ValueKey('easy.mini.play'),
              icon: app.playback.playing ? Icons.pause : Icons.play_arrow,
              tooltip: app.playback.playing ? tr('Pausar', 'Pause') : tr('Reproducir', 'Play'),
              selected: app.playback.playing,
              onTap: app.playback.toggle,
            ),
            EasyButton(icon: Icons.chevron_left, tooltip: tr('Fotograma anterior', 'Previous frame'), onTap: () => doc.stepFrame(-1)),
            Text('${doc.frame + 1} / ${doc.timeline.length}', style: const TextStyle(fontSize: 14)),
            EasyButton(icon: Icons.chevron_right, tooltip: tr('Fotograma siguiente', 'Next frame'), onTap: () => doc.stepFrame(1)),
            const Spacer(),
            EasyButton(
              key: const ValueKey('easy.mini.add'),
              icon: Icons.add,
              tooltip: tr('Añadir un fotograma', 'Add a frame'),
              onTap: () => doc.insertFrames(),
            ),
            const SizedBox(width: 6),
          ]),
        ),
      ]),
    );
  }
}

class _FoldButton extends StatelessWidget {
  const _FoldButton({super.key, required this.icon, required this.tooltip, required this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(height: 44, width: double.infinity, child: Icon(icon, size: 22, color: context.dim)),
        ),
      );
}
