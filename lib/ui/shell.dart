import 'package:flutter/material.dart';

import '../app/app_state.dart';
import '../app/commands.dart';
import '../app/document_controller.dart';
import '../core/i18n.dart';
import '../tools/registry.dart';
import 'canvas/canvas_view.dart';
import 'dialogs/command_palette.dart';
import 'dialogs/new_document.dart';
import 'dialogs/prefs_dialog.dart';
import 'dialogs/prompts.dart';
import 'menu_bar.dart';
import 'panels/brush_panel.dart';
import 'panels/color_panel.dart';
import 'panels/layer_props_panel.dart';
import 'panels/layers_panel.dart';
import 'panels/tool_options_bar.dart';
import 'theme.dart';
import 'timeline/timeline_panel.dart';
import 'widgets.dart';

/// Commands that need the widget tree (dialogs); registered once at start-up.
void registerShellCommands(CommandRegistry r, AppState app) {
  BuildContext? ctx() => app.context;

  Future<void> newDocument() async {
    final c = ctx();
    if (c == null) return;
    final p = await showNewDocumentDialog(c);
    if (p != null) app.addDocument(p, title: app.untitledName());
  }

  r.add(Command(id: 'file.new', category: CommandCategory.file, label: () => tr('Nuevo documento…', 'New document…'), run: newDocument, shortcut: 'Ctrl+N', needsDocument: false));
  r.add(Command(
    id: 'file.close',
    category: CommandCategory.file,
    label: () => tr('Cerrar documento', 'Close document'),
    run: () {
      final d = app.doc;
      if (d != null) closeWithConfirm(app, d);
    },
    shortcut: 'Ctrl+W',
  ));
  r.add(Command(
    id: 'app.palette',
    category: CommandCategory.help,
    label: () => tr('Paleta de comandos…', 'Command palette…'),
    run: () {
      final c = ctx();
      if (c != null) showCommandPalette(c);
    },
    shortcut: 'Ctrl+K',
    needsDocument: false,
  ));
  r.add(Command(
    id: 'app.prefs',
    category: CommandCategory.help,
    label: () => tr('Preferencias…', 'Preferences…'),
    run: () {
      final c = ctx();
      if (c != null) showPrefsDialog(c);
    },
    shortcut: 'Ctrl+,',
    needsDocument: false,
  ));
}

/// Main window: tool bar, document tabs, canvas, side panels and status bar.
class Shell extends StatelessWidget {
  const Shell({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppState.I;
    return Focus(
      focusNode: app.focusNode,
      autofocus: true,
      onKeyEvent: app.handleKey,
      child: Scaffold(
        backgroundColor: context.workspace,
        body: ListenableBuilder(
          listenable: app,
          builder: (context, _) {
            final doc = app.doc;
            return Column(children: [
              _TopBar(app: app),
              if (doc != null)
                Container(
                  decoration: BoxDecoration(color: context.panel, border: Border(bottom: BorderSide(color: context.line))),
                  child: ToolOptionsBar(ts: app.ts, toolId: app.activeToolId),
                ),
              Expanded(
                child: Row(children: [
                  if (doc != null) _ToolBar(app: app),
                  Expanded(
                    child: doc == null
                        ? EmptyWorkspace(onNew: () => app.commands.run('file.new'), onOpen: () => app.commands.run('file.open'))
                        : CanvasView(key: ValueKey(doc), doc: doc),
                  ),
                  if (doc != null) SizedBox(width: 280, child: SidePanels(doc: doc)),
                ]),
              ),
              if (doc != null)
                Container(
                  height: 190,
                  decoration: BoxDecoration(color: context.panel, border: Border(top: BorderSide(color: context.line))),
                  child: TimelinePanel(key: ValueKey(doc), doc: doc, playback: app.playback),
                ),
              _StatusBar(app: app),
            ]);
          },
        ),
      ),
    );
  }
}

/// Right-hand column. The layer, colour and brush panels plug in here.
class SidePanels extends StatelessWidget {
  const SidePanels({super.key, required this.doc});
  final DocumentController doc;

  @override
  Widget build(BuildContext context) {
    final ts = AppState.I.ts;
    // Material (not a coloured Container) so ListTiles inside keep their ink.
    return Material(
      color: context.panel,
      shape: Border(left: BorderSide(color: context.line)),
      child: DefaultTabController(
        length: 4,
        child: Column(children: [
          TabBar(
            labelStyle: kSmall,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [Tab(height: 32, text: tr('Capas', 'Layers')), Tab(height: 32, text: tr('Color', 'Colour')), Tab(height: 32, text: tr('Pinceles', 'Brushes')), Tab(height: 32, text: tr('Propiedades', 'Properties'))],
          ),
          Expanded(
            child: TabBarView(children: [
              LayersPanel(doc: doc, onCommand: (id) => AppState.I.commands.run(id)),
              SingleChildScrollView(child: ColorPanel(ts: ts)),
              BrushPanel(ts: ts),
              LayerPropsPanel(doc: doc),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final d = app.doc;
    return Container(
      height: 38,
      decoration: BoxDecoration(color: context.panel, border: Border(bottom: BorderSide(color: context.line))),
      child: Row(children: [
        const SizedBox(width: 8),
        const AppMenuBar(),
        const VSep(),
        PanelButton(icon: Icons.add, tooltip: tr('Nuevo', 'New'), onTap: () => app.commands.run('file.new')),
        PanelButton(icon: Icons.undo, tooltip: tr('Deshacer', 'Undo'), onTap: d != null && d.history.canUndo ? () => app.commands.run('edit.undo') : null),
        PanelButton(icon: Icons.redo, tooltip: tr('Rehacer', 'Redo'), onTap: d != null && d.history.canRedo ? () => app.commands.run('edit.redo') : null),
        const VSep(),
        Expanded(
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: app.docs.length,
            itemBuilder: (_, i) {
              final t = app.docs[i];
              final active = i == app.activeIndex;
              return InkWell(
                onTap: () => app.activate(i),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(width: 2, color: active ? context.cs.primary : Colors.transparent))),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    ListenableBuilder(
                      listenable: t,
                      builder: (context, _) => Text('${t.title}${t.dirty ? ' •' : ''}', style: kSmall.copyWith(color: active ? context.cs.onSurface : context.dim)),
                    ),
                    const SizedBox(width: 6),
                    InkWell(onTap: () => closeWithConfirm(app, t), child: Icon(Icons.close, size: 14, color: context.dim)),
                  ]),
                ),
              );
            },
          ),
        ),
        PanelButton(icon: Icons.search, tooltip: tr('Comandos (Ctrl+K)', 'Commands (Ctrl+K)'), onTap: () => app.commands.run('app.palette')),
        PanelButton(icon: Icons.settings_outlined, tooltip: tr('Preferencias', 'Preferences'), onTap: () => app.commands.run('app.prefs')),
        const SizedBox(width: 8),
      ]),
    );
  }
}

class _ToolBar extends StatelessWidget {
  const _ToolBar({required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final cur = app.activeToolId;
    return Container(
      width: 44,
      decoration: BoxDecoration(color: context.panel, border: Border(right: BorderSide(color: context.line))),
      child: ListView(padding: const EdgeInsets.symmetric(vertical: 6), children: [
        for (final id in kToolbarOrder)
          if (app.toolMap[id] case final t?)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: PanelButton(
                  icon: t.icon,
                  size: 34,
                  selected: id == cur,
                  tooltip: t.shortcut.isEmpty ? t.label : '${t.label} (${t.shortcut})',
                  onTap: () => app.setTool(id),
                  child: t.buildIcon(18, id == cur ? context.cs.primary : context.cs.onSurface),
                ),
              ),
            ),
      ]),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final d = app.doc;
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(color: context.panel, border: Border(top: BorderSide(color: context.line))),
      child: ValueListenableBuilder<String?>(
        valueListenable: app.message,
        builder: (_, msg, _) => Row(children: [
          Expanded(child: Text(msg ?? app.tool.hint, style: kTiny.copyWith(color: context.dim), overflow: TextOverflow.ellipsis)),
          if (d != null)
            ListenableBuilder(
              listenable: d.viewSignal,
              builder: (_, _) => Text('${(d.view.zoom * 100).round()} %  ·  ${d.comp.width}×${d.comp.height}', style: kTiny.copyWith(color: context.dim)),
            ),
        ]),
      ),
    );
  }
}

/// Closes [d], asking first when it has unsaved changes. Returns whether it closed.
Future<bool> closeWithConfirm(AppState app, DocumentController d) async {
  final ctx = app.context;
  if (d.dirty && ctx != null) {
    final ok = await confirmDialog(
      ctx,
      title: tr('¿Cerrar sin guardar?', 'Close without saving?'),
      message: tr('«${d.title}» tiene cambios sin guardar que se perderán.', '“${d.title}” has unsaved changes that will be lost.'),
      ok: tr('Cerrar sin guardar', 'Close without saving'),
      danger: true,
    );
    if (!ok) return false;
  }
  app.closeDocument(d);
  return true;
}
