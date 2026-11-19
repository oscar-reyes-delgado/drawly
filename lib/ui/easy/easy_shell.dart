import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/app_state.dart';
import '../../app/document_controller.dart';
import '../../core/i18n.dart';
import '../canvas/canvas_view.dart';
import '../panels/color_panel.dart';
import 'easy_color_bar.dart';
import 'easy_layers.dart';
import 'easy_timeline.dart';
import 'easy_toolbar.dart';
import '../shell.dart';
import '../theme.dart';
import '../../app/file_ops.dart';
import '../../app/frame_thumbs.dart';
import '../../app/project_library.dart';
import '../../model/document.dart';
import '../../platform/io.dart' as io;
import '../dialogs/prefs_dialog.dart';
import '../home/home_screen.dart';

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
        listenable: Listenable.merge([app, layersVisible, Shell.timelineVisible]),
        builder: (context, _) => LayoutBuilder(builder: (context, box) {
          final doc = app.doc;
          final compact = box.maxWidth < compactWidth;
          final short = box.maxHeight < 560;
          final showTimeline = Shell.timelineVisible.value ?? !short;
          return Scaffold(
            backgroundColor: context.workspace,
            endDrawer: compact && doc != null
                ? Drawer(width: math.min(340.0, box.maxWidth * 0.88), child: SafeArea(child: _LayersBox(doc: doc)))
                : null,
            body: SafeArea(
              child: Column(children: [
                _EasyTopBar(app: app, compact: compact),
                Expanded(
                  child: doc == null
                      ? const EasyHome()
                      : Row(children: [
                          Container(
                            width: 68,
                            decoration: BoxDecoration(color: context.panel, border: Border(right: BorderSide(color: context.line))),
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
                if (doc != null && showTimeline)
                  Container(
                    decoration: BoxDecoration(color: context.panel, border: Border(top: BorderSide(color: context.line))),
                    child: EasyTimeline(key: ValueKey(doc), doc: doc, playback: app.playback, thumbs: thumbs, height: short ? 112 : (compact ? 124 : 140)),
                  ),
              ]),
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
        EasyButton(icon: Icons.save_outlined, tooltip: tr('Guardar (Ctrl+S)', 'Save (Ctrl+S)'), onTap: d == null ? null : () => app.commands.run('file.save')),
        EasyButton(
          key: const ValueKey('easy.export'),
          icon: Icons.ios_share,
          tooltip: tr('Exportar la animación', 'Export the animation'),
          label: compact ? null : tr('Exportar', 'Export'),
          onTap: d == null ? null : () => app.commands.run('file.export'),
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
          onSelected: (id) => id == 'mode' ? setUiMode(app, 'advanced') : app.commands.run(id),
          itemBuilder: (context) => [
            PopupMenuItem(value: 'file.new', child: Text(tr('Nuevo proyecto', 'New project'))),
            PopupMenuItem(value: 'file.open', child: Text(tr('Abrir…', 'Open…'))),
            PopupMenuItem(value: 'file.importImage', enabled: d != null, child: Text(tr('Importar imagen…', 'Import image…'))),
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

/// Projects folder of the easy mode (null on the web).
final Future<ProjectLibrary?> easyLibrary = () async {
  if (!io.hasFileSystem) return null;
  try {
    return ProjectLibrary(await ProjectLibrary.defaultDir());
  } catch (_) {
    return null;
  }
}();

/// Start screen wired to the app: new projects are saved in the library at once.
class EasyHome extends StatelessWidget {
  const EasyHome({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppState.I;
    return FutureBuilder<ProjectLibrary?>(
      future: easyLibrary,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        return HomeScreen(
          settings: app.settings,
          library: snap.data,
          autosave: app.autosave,
          onCreate: (Project project, String name, String? path) async {
            final d = app.addDocument(project, title: name, path: path);
            if (path != null && await saveProjectTo(d, path)) app.settings.addRecent(path);
          },
          onOpen: (path) async {
            try {
              final c = await openProjectFrom(path);
              app.addDocument(c.project, title: c.title, path: c.filePath);
              c.dispose();
              app.settings.addRecent(path);
            } catch (e) {
              app.toast('${tr('No se pudo abrir', 'Could not open')}: $e');
            }
          },
          onOpenFile: () => app.commands.run('file.open'),
          onRestore: (restored) {
            final d = app.addDocument(restored.project, title: restored.title, path: restored.filePath);
            d.dirty = true;
            d.touch();
            restored.dispose();
          },
          onSwitchMode: () => setUiMode(app, 'advanced'),
          onSettings: () => showPrefsDialog(context),
        );
      },
    );
  }
}
