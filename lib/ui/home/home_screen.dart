import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../app/autosave.dart';
import '../../app/document_controller.dart';
import '../../app/easy_defaults.dart';
import '../../app/project_library.dart';
import '../../app/settings.dart';
import '../../core/i18n.dart';
import '../../model/document.dart';
import '../../platform/io.dart';
import '../dialogs/prompts.dart';
import '../easy/easy_shell.dart';
import '../theme.dart';
import '../widgets.dart';

enum _CardAction { rename, duplicate, delete }

/// Start screen of the easy mode: quick new project, the projects folder with
/// thumbnails, recent files, crash recovery and the mode switch.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.settings,
    required this.library,
    required this.onCreate,
    required this.onOpen,
    required this.onOpenFile,
    required this.onSwitchMode,
    this.autosave,
    this.onRestore,
    this.onSettings,
    this.onPreview,
    this.onBack,
    this.switchToEasy = false,
    this.title = 'Drawly',
  });

  final Settings settings;
  final ProjectLibrary? library;
  final void Function(Project project, String name, String? path) onCreate;
  final Future<void> Function(String path) onOpen;
  final VoidCallback onOpenFile;
  final VoidCallback onSwitchMode;
  final AutosaveService? autosave;
  final void Function(DocumentController restored)? onRestore;
  final VoidCallback? onSettings;

  /// Plays a project full screen without opening it (the ▶ on each card).
  final Future<void> Function(String path)? onPreview;

  /// Shows a back arrow (when the screen is opened as a page).
  final VoidCallback? onBack;

  /// The mode button offers the easy mode instead of the advanced one.
  final bool switchToEasy;
  final String title;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  ProjectSort _sort = ProjectSort.modified;
  List<ProjectEntry> _entries = const [];
  bool _loadingLibrary = false;

  List<RecoveryEntry> _recoverable = const [];
  final Set<String> _damagedIds = {};
  final Set<String> _restoringIds = {};

  List<String> _recentOutside = const [];

  final Map<String, Future<Uint8List?>> _thumbCache = {};

  @override
  void initState() {
    super.initState();
    widget.settings.addListener(_onSettingsChanged);
    _reloadAll();
  }

  @override
  void didUpdateWidget(HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings != widget.settings) {
      oldWidget.settings.removeListener(_onSettingsChanged);
      widget.settings.addListener(_onSettingsChanged);
    }
    if (oldWidget.library?.dir != widget.library?.dir ||
        oldWidget.autosave != widget.autosave ||
        oldWidget.settings != widget.settings) {
      _thumbCache.clear();
      _reloadAll();
    }
  }

  @override
  void dispose() {
    widget.settings.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    if (mounted) {
      unawaited(_loadRecentOutside());
    }
  }

  Future<void> _reloadAll() async {
    await Future.wait([
      _loadLibrary(),
      _loadRecoverable(),
      _loadRecentOutside(),
    ]);
  }

  Future<void> _loadLibrary() async {
    final lib = widget.library;
    if (lib == null) {
      if (mounted) setState(() => _entries = const []);
      return;
    }
    if (mounted) setState(() => _loadingLibrary = true);
    try {
      final list = await lib.list(
        sort: _sort,
        descending: _sort == ProjectSort.modified,
      );
      if (!mounted) return;
      final activeKeys = {for (final e in list) _thumbKey(e)};
      _thumbCache.removeWhere((k, _) => !activeKeys.contains(k));
      setState(() {
        _entries = list;
        _loadingLibrary = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingLibrary = false);
    }
  }

  Future<void> _loadRecoverable() async {
    final svc = widget.autosave;
    if (svc == null) {
      if (mounted) setState(() => _recoverable = const []);
      return;
    }
    try {
      final list = await svc.listRecoverable();
      if (!mounted) return;
      setState(() => _recoverable = list);
    } catch (_) {
      if (mounted) setState(() => _recoverable = const []);
    }
  }

  Future<void> _loadRecentOutside() async {
    final lib = widget.library;
    if (lib == null) {
      if (mounted) setState(() => _recentOutside = const []);
      return;
    }
    final libDir = p.normalize(p.absolute(lib.dir));
    final outside = <String>[];
    final missing = <String>[];
    for (final path in List<String>.from(widget.settings.recentFiles)) {
      final norm = p.normalize(p.absolute(path));
      if (p.equals(p.dirname(norm), libDir)) continue;
      if (await fileExists(path)) {
        outside.add(path);
      } else {
        missing.add(path);
      }
    }
    if (missing.isNotEmpty) {
      for (final m in missing) {
        widget.settings.removeRecent(m);
      }
    }
    if (mounted) {
      setState(() => _recentOutside = outside);
    }
  }

  String _thumbKey(ProjectEntry e) => '${e.path}|${e.modified.microsecondsSinceEpoch}';

  Future<Uint8List?> _thumbnailFuture(ProjectEntry e) {
    final lib = widget.library!;
    return _thumbCache.putIfAbsent(_thumbKey(e), () => lib.thumbnail(e.path));
  }

  Future<String> _nextFreeName() async {
    final base = tr('Animación', 'Animation');
    final lib = widget.library;
    if (lib == null) return '$base 1';
    final entries = _loadingLibrary ? await lib.list() : _entries;
    final used = entries.map((e) => e.name.toLowerCase()).toSet();
    var k = 1;
    while (used.contains('${base.toLowerCase()} $k')) {
      k++;
    }
    return '$base $k';
  }

  Future<void> _createQuickProject() async {
    final name = await _nextFreeName();
    final project = easyProjectFromSettings(widget.settings, name: name);
    final path = widget.library?.uniquePath(name);
    widget.onCreate(project, name, path);
  }

  Future<void> _openCustomizeDialog() async {
    final defaultName = await _nextFreeName();
    if (!mounted) return;
    final res = await showDialog<({String name, int width, int height, int fps, bool transparent})>(
      context: context,
      builder: (ctx) => _CustomizeProjectDialog(
        initialName: defaultName,
        initialWidth: widget.settings.easyWidth,
        initialHeight: widget.settings.easyHeight,
        initialFps: widget.settings.easyFps,
      ),
    );
    if (res == null) return;
    final project = easyProject(
      name: res.name,
      width: res.width,
      height: res.height,
      fps: res.fps,
      background: res.transparent ? null : const Color(0xFFFFFFFF),
    );
    final path = widget.library?.uniquePath(res.name);
    widget.onCreate(project, res.name, path);
  }

  Future<void> _restoreEntry(RecoveryEntry entry) async {
    final svc = widget.autosave;
    if (svc == null || _restoringIds.contains(entry.id)) return;
    setState(() => _restoringIds.add(entry.id));
    try {
      final controller = await svc.restore(entry);
      if (!mounted) return;
      setState(() {
        _restoringIds.remove(entry.id);
        _recoverable = _recoverable.where((e) => e.id != entry.id).toList();
      });
      widget.onRestore?.call(controller);
      // the reopened document gets its own copy from now on: drop the old one
      await svc.discard(entry);
    } on FormatException {
      if (!mounted) return;
      setState(() {
        _restoringIds.remove(entry.id);
        _damagedIds.add(entry.id);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _restoringIds.remove(entry.id));
      _showMessage(tr('No se pudo recuperar la copia: $e', 'Could not recover copy: $e'));
    }
  }

  Future<void> _discardEntry(RecoveryEntry entry) async {
    final svc = widget.autosave;
    if (svc == null) return;
    await svc.discard(entry);
    if (!mounted) return;
    _damagedIds.remove(entry.id);
    await _loadRecoverable();
  }

  Future<void> _handleCardAction(ProjectEntry entry, _CardAction action) async {
    final lib = widget.library;
    if (lib == null) return;
    switch (action) {
      case _CardAction.rename:
        final next = await promptText(
          context,
          title: tr('Renombrar proyecto', 'Rename project'),
          initial: entry.name,
          label: tr('Nombre', 'Name'),
          ok: tr('Renombrar', 'Rename'),
        );
        if (next == null || !mounted) return;
        try {
          await lib.rename(entry.path, next);
          _thumbCache.remove(_thumbKey(entry));
          await _loadLibrary();
        } catch (e) {
          if (mounted) _showMessage('$e');
        }
      case _CardAction.duplicate:
        try {
          await lib.duplicate(entry.path);
          await _loadLibrary();
        } catch (e) {
          if (mounted) _showMessage('$e');
        }
      case _CardAction.delete:
        final ok = await confirmDialog(
          context,
          title: tr('Eliminar proyecto', 'Delete project'),
          message: tr(
            'Se eliminará «${entry.name}». No se puede deshacer.',
            '"${entry.name}" will be deleted. This cannot be undone.',
          ),
          ok: tr('Eliminar', 'Delete'),
          danger: true,
        );
        if (!ok || !mounted) return;
        try {
          await lib.delete(entry.path);
          _thumbCache.remove(_thumbKey(entry));
          await _loadLibrary();
        } catch (e) {
          if (mounted) _showMessage('$e');
        }
    }
  }

  void _showMessage(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final lib = widget.library;
    return Scaffold(
      backgroundColor: context.workspace,
      body: SafeArea(
        child: Column(
          children: [
            _Header(
              onSettings: widget.onSettings,
              onSwitchMode: widget.onSwitchMode,
              onBack: widget.onBack,
              switchToEasy: widget.switchToEasy,
              title: widget.title,
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final compact = width < 520;
                  final pad = compact ? 14.0 : 24.0;
                  final cols = width < 420 ? 1 : (width / 240).floor().clamp(2, 5);

                  return SingleChildScrollView(
                    padding: EdgeInsets.all(pad),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1240),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (widget.autosave != null && _recoverable.isNotEmpty) ...[
                              for (final entry in _recoverable) ...[
                                _RecoveryBanner(
                                  entry: entry,
                                  damaged: _damagedIds.contains(entry.id),
                                  restoring: _restoringIds.contains(entry.id),
                                  onRecover: () => _restoreEntry(entry),
                                  onDiscard: () => _discardEntry(entry),
                                ),
                                const SizedBox(height: 12),
                              ],
                              const SizedBox(height: 8),
                            ],
                            _ActionStrip(
                              compact: compact,
                              onNew: _createQuickProject,
                              onCustomize: _openCustomizeDialog,
                              onOpenFile: widget.onOpenFile,
                            ),
                            if (lib != null) ...[
                              const SizedBox(height: 24),
                              _ProjectsHeader(
                                sort: _sort,
                                onSortChanged: (s) {
                                  if (_sort == s) return;
                                  setState(() => _sort = s);
                                  _loadLibrary();
                                },
                              ),
                              const SizedBox(height: 12),
                              if (_loadingLibrary && _entries.isEmpty)
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 40),
                                  child: Center(child: CircularProgressIndicator()),
                                )
                              else if (_entries.isEmpty)
                                _EmptyProjectsNotice()
                              else
                                GridView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: cols,
                                    crossAxisSpacing: 14,
                                    mainAxisSpacing: 14,
                                    childAspectRatio: cols == 1 ? 1.55 : 1.05,
                                  ),
                                  itemCount: _entries.length,
                                  itemBuilder: (context, index) {
                                    final entry = _entries[index];
                                    return _ProjectCard(
                                      key: ValueKey('easy.home.project.${entry.path}'),
                                      entry: entry,
                                      thumbnailFuture: _thumbnailFuture(entry),
                                      onTap: () => widget.onOpen(entry.path),
                                      onPreview: widget.onPreview == null ? null : () => widget.onPreview!(entry.path),
                                      onAction: (action) => _handleCardAction(entry, action),
                                    );
                                  },
                                ),
                              if (_recentOutside.isNotEmpty) ...[
                                const SizedBox(height: 28),
                                _RecentOutsideSection(
                                  paths: _recentOutside,
                                  onOpen: widget.onOpen,
                                ),
                              ],
                            ],
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onSettings, required this.onSwitchMode, this.onBack, this.switchToEasy = false, this.title = 'Drawly'});

  final VoidCallback? onSettings;
  final VoidCallback onSwitchMode;
  final VoidCallback? onBack;
  final bool switchToEasy;
  final String title;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 420;
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: context.panel,
        border: Border(bottom: BorderSide(color: context.line)),
      ),
      child: Row(
        children: [
          if (onBack != null)
            EasyButton(key: const ValueKey('easy.home.back'), icon: Icons.arrow_back, tooltip: tr('Volver', 'Back'), onTap: onBack)
          else
            Icon(Icons.brush_rounded, size: 24, color: context.cs.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
          if (onSettings != null)
            EasyButton(
              key: const ValueKey('easy.home.settings'),
              icon: Icons.settings_outlined,
              tooltip: tr('Ajustes', 'Settings'),
              onTap: onSettings,
            ),
          const SizedBox(width: 6),
          EasyButton(
            key: const ValueKey('easy.home.switchMode'),
            icon: Icons.tune,
            tooltip: switchToEasy ? tr('Cambiar a Modo Fácil', 'Switch to Easy mode') : tr('Cambiar a Modo Avanzado', 'Switch to Advanced mode'),
            label: switchToEasy
                ? (compact ? tr('Fácil', 'Easy') : tr('Modo Fácil', 'Easy mode'))
                : (compact ? tr('Avanzado', 'Advanced') : tr('Modo Avanzado', 'Advanced mode')),
            onTap: onSwitchMode,
          ),
        ],
      ),
    );
  }
}

class _RecoveryBanner extends StatelessWidget {
  const _RecoveryBanner({
    required this.entry,
    required this.damaged,
    required this.restoring,
    required this.onRecover,
    required this.onDiscard,
  });

  final RecoveryEntry entry;
  final bool damaged;
  final bool restoring;
  final VoidCallback onRecover;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final bg = damaged ? cs.error.withValues(alpha: 0.14) : cs.primary.withValues(alpha: 0.14);
    final border = damaged ? cs.error : cs.primary;
    final message = damaged
        ? tr('La copia está dañada', 'The recovery copy is damaged')
        : tr(
            'Drawly se cerró sin guardar. ¿Recuperar «${entry.title}»?',
            'Drawly closed without saving. Recover "${entry.title}"?',
          );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                damaged ? Icons.error_outline : Icons.restore_rounded,
                size: 24,
                color: border,
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  message,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!damaged) ...[
                FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size(44, 44)),
                  onPressed: restoring ? null : onRecover,
                  child: Text(tr('Recuperar', 'Recover'), style: const TextStyle(fontSize: 13)),
                ),
                const SizedBox(width: 8),
              ],
              OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size(44, 44)),
                onPressed: restoring ? null : onDiscard,
                child: Text(tr('Descartar', 'Discard'), style: const TextStyle(fontSize: 13)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionStrip extends StatelessWidget {
  const _ActionStrip({
    required this.compact,
    required this.onNew,
    required this.onCustomize,
    required this.onOpenFile,
  });

  final bool compact;
  final VoidCallback onNew;
  final VoidCallback onCustomize;
  final VoidCallback onOpenFile;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final newCard = Material(
      key: const ValueKey('easy.home.new'),
      color: cs.primary.withValues(alpha: 0.18),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: cs.primary, width: 1.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onNew,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 72, minWidth: 160),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add_rounded, size: 28, color: cs.primary),
                const SizedBox(width: 10),
                Text(
                  tr('+ Nuevo', '+ New'),
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: cs.primary),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final customizeLink = Tooltip(
      message: tr('Elegir tamaño, fps y fondo', 'Choose size, fps and background'),
      child: TextButton.icon(
        key: const ValueKey('easy.home.customize'),
        style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
        onPressed: onCustomize,
        icon: const Icon(Icons.tune_rounded, size: 20),
        label: Text(tr('Personalizar…', 'Customize…'), style: const TextStyle(fontSize: 14)),
      ),
    );

    final openButton = Tooltip(
      message: tr('Abrir un archivo .drawly desde el dispositivo', 'Open a .drawly file from the device'),
      child: OutlinedButton.icon(
        key: const ValueKey('easy.home.openFile'),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(44, 48),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        ),
        onPressed: onOpenFile,
        icon: const Icon(Icons.folder_open_rounded, size: 24),
        label: Text(tr('Abrir…', 'Open…'), style: const TextStyle(fontSize: 14)),
      ),
    );

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          newCard,
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [customizeLink, openButton],
          ),
        ],
      );
    }

    return Wrap(
      spacing: 14,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        newCard,
        customizeLink,
        openButton,
      ],
    );
  }
}

class _ProjectsHeader extends StatelessWidget {
  const _ProjectsHeader({required this.sort, required this.onSortChanged});

  final ProjectSort sort;
  final ValueChanged<ProjectSort> onSortChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          tr('Mis proyectos', 'My projects'),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        SegmentedButton<ProjectSort>(
          style: const ButtonStyle(
            minimumSize: WidgetStatePropertyAll(Size(44, 44)),
            textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 13)),
          ),
          segments: [
            ButtonSegment(
              value: ProjectSort.modified,
              label: Text(tr('Recientes', 'Recent')),
            ),
            ButtonSegment(
              value: ProjectSort.name,
              label: Text(tr('Nombre', 'Name')),
            ),
          ],
          selected: {sort},
          showSelectedIcon: false,
          onSelectionChanged: (s) {
            if (s.isNotEmpty) onSortChanged(s.first);
          },
        ),
      ],
    );
  }
}

class _EmptyProjectsNotice extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 36),
      decoration: BoxDecoration(
        color: context.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.line),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome_motion_outlined, size: 36, color: context.dim),
          const SizedBox(height: 12),
          Text(
            tr(
              'Aún no tienes proyectos. Toca + Nuevo para empezar.',
              'You have no projects yet. Tap + New to start.',
            ),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: context.dim),
          ),
        ],
      ),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({
    super.key,
    required this.entry,
    required this.thumbnailFuture,
    required this.onTap,
    required this.onAction,
    this.onPreview,
  });

  final ProjectEntry entry;
  final Future<Uint8List?> thumbnailFuture;
  final VoidCallback onTap;
  final VoidCallback? onPreview;
  final ValueChanged<_CardAction> onAction;

  void _openContextMenu(BuildContext context, Offset globalPos) async {
    final box = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final pos = RelativeRect.fromRect(
      globalPos & const Size(1, 1),
      Offset.zero & box.size,
    );
    final selected = await showMenu<_CardAction>(
      context: context,
      position: pos,
      items: _menuItems(),
    );
    if (selected != null) onAction(selected);
  }

  List<PopupMenuEntry<_CardAction>> _menuItems() => [
        PopupMenuItem(
          value: _CardAction.rename,
          child: Text(tr('Renombrar', 'Rename'), style: const TextStyle(fontSize: 13)),
        ),
        PopupMenuItem(
          value: _CardAction.duplicate,
          child: Text(tr('Duplicar', 'Duplicate'), style: const TextStyle(fontSize: 13)),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: _CardAction.delete,
          child: Text(tr('Eliminar', 'Delete'), style: const TextStyle(fontSize: 13)),
        ),
      ];

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: context.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: GestureDetector(
        onLongPressStart: (details) => _openContextMenu(context, details.globalPosition),
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ColoredBox(
                  color: context.cs.surfaceContainerLowest,
                  child: FutureBuilder<Uint8List?>(
                    future: thumbnailFuture,
                    builder: (context, snap) {
                      final bytes = snap.data;
                      if (bytes == null) {
                        return Stack(fit: StackFit.expand, children: [
                          Center(child: Icon(Icons.movie_creation_outlined, size: 32, color: context.dim)),
                          if (onPreview != null) _PlayBadge(path: entry.path, onTap: onPreview!),
                        ]);
                      }
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          const CustomPaint(painter: CheckerPainter(cell: 8)),
                          Image.memory(bytes, fit: BoxFit.contain, gaplessPlayback: true),
                          if (onPreview != null) _PlayBadge(path: entry.path, onTap: onPreview!),
                        ],
                      );
                    },
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            entry.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _formatRelativeDate(entry.modified),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 13, color: context.dim),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuButton<_CardAction>(
                      key: ValueKey('easy.home.menu.${entry.name}'),
                      tooltip: tr('Opciones del proyecto', 'Project options'),
                      icon: const Icon(Icons.more_vert, size: 24),
                      padding: const EdgeInsets.all(10),
                      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                      onSelected: onAction,
                      itemBuilder: (_) => _menuItems(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentOutsideSection extends StatelessWidget {
  const _RecentOutsideSection({required this.paths, required this.onOpen});

  final List<String> paths;
  final Future<void> Function(String path) onOpen;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          tr('Recientes fuera de la carpeta', 'Recent outside folder'),
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: context.panel,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.line),
          ),
          child: Column(
            children: [
              for (var i = 0; i < paths.length; i++) ...[
                if (i > 0) Divider(height: 1, color: context.line),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(
                    children: [
                      Icon(Icons.insert_drive_file_outlined, size: 22, color: context.dim),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.basenameWithoutExtension(paths[i]),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                            ),
                            Text(
                              paths[i],
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 13, color: context.dim),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                        onPressed: () => onOpen(paths[i]),
                        child: Text(tr('Abrir', 'Open'), style: const TextStyle(fontSize: 13)),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _CustomizeProjectDialog extends StatefulWidget {
  const _CustomizeProjectDialog({
    required this.initialName,
    required this.initialWidth,
    required this.initialHeight,
    required this.initialFps,
  });

  final String initialName;
  final int initialWidth;
  final int initialHeight;
  final int initialFps;

  @override
  State<_CustomizeProjectDialog> createState() => _CustomizeProjectDialogState();
}

class _CustomizeProjectDialogState extends State<_CustomizeProjectDialog> {
  static const _presets = <(int, int)>[
    (1920, 1080),
    (1080, 1080),
    (1080, 1920),
    (1280, 720),
  ];
  static const _fpsOptions = [8, 12, 24];

  late final TextEditingController _nameCtrl = TextEditingController(text: widget.initialName);
  late int _width = widget.initialWidth;
  late int _height = widget.initialHeight;
  late int _fps = _fpsOptions.contains(widget.initialFps) ? widget.initialFps : 12;
  bool _customSize = false;
  bool _transparent = false;

  @override
  void initState() {
    super.initState();
    _customSize = !_presets.any((p) => p.$1 == _width && p.$2 == _height);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameCtrl.text.trim().isEmpty ? widget.initialName : _nameCtrl.text.trim();
    Navigator.pop(context, (
      name: name,
      width: _width.clamp(16, 16384),
      height: _height.clamp(16, 16384),
      fps: _fps,
      transparent: _transparent,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr('Nuevo proyecto', 'New project'), style: const TextStyle(fontSize: 17)),
      content: SizedBox(
        width: fitDialogWidth(context, 420),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nameCtrl,
                decoration: InputDecoration(labelText: tr('Nombre', 'Name')),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 14),
              Text(tr('Tamaño', 'Size'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final preset in _presets)
                    _ChoiceChipButton(
                      label: '${preset.$1}×${preset.$2}',
                      selected: !_customSize && _width == preset.$1 && _height == preset.$2,
                      onTap: () => setState(() {
                        _customSize = false;
                        _width = preset.$1;
                        _height = preset.$2;
                      }),
                    ),
                  _ChoiceChipButton(
                    label: tr('Otro', 'Custom'),
                    selected: _customSize,
                    onTap: () => setState(() => _customSize = true),
                  ),
                ],
              ),
              if (_customSize) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: NumField(
                        value: _width.toDouble(),
                        min: 16,
                        max: 16384,
                        label: tr('Ancho', 'Width'),
                        suffix: 'px',
                        onSubmitted: (v) => setState(() => _width = v.round()),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: NumField(
                        value: _height.toDouble(),
                        min: 16,
                        max: 16384,
                        label: tr('Alto', 'Height'),
                        suffix: 'px',
                        onSubmitted: (v) => setState(() => _height = v.round()),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 14),
              Text(tr('Fotogramas por segundo (FPS)', 'Frames per second (FPS)'),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final f in _fpsOptions)
                    _ChoiceChipButton(
                      label: '$f fps',
                      selected: _fps == f,
                      onTap: () => setState(() => _fps = f),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Text(tr('Fondo', 'Background'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _ChoiceChipButton(
                    label: tr('Blanco', 'White'),
                    selected: !_transparent,
                    onTap: () => setState(() => _transparent = false),
                  ),
                  _ChoiceChipButton(
                    label: tr('Transparente', 'Transparent'),
                    selected: _transparent,
                    onTap: () => setState(() => _transparent = true),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
          onPressed: () => Navigator.pop(context),
          child: Text(tr('Cancelar', 'Cancel')),
        ),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(44, 44)),
          onPressed: _submit,
          child: Text(tr('Crear', 'Create')),
        ),
      ],
    );
  }
}

class _ChoiceChipButton extends StatelessWidget {
  const _ChoiceChipButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Material(
      color: selected ? cs.primary.withValues(alpha: 0.18) : cs.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: selected ? cs.primary : context.line),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Center(
              widthFactor: 1,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected ? cs.primary : cs.onSurface,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _formatRelativeDate(DateTime date) {
  final now = DateTime.now();
  final diff = now.difference(date);
  if (!diff.isNegative) {
    if (diff.inMinutes < 1) return tr('ahora mismo', 'just now');
    if (diff.inMinutes < 60) return tr('hace ${diff.inMinutes} min', '${diff.inMinutes} min ago');
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(date.year, date.month, date.day);
    final days = today.difference(day).inDays;
    if (days == 0) return tr('hace ${math.max(1, diff.inHours)} h', '${math.max(1, diff.inHours)} hr ago');
    if (days == 1) return tr('ayer', 'yesterday');
  }
  final d = date.day.toString().padLeft(2, '0');
  final m = date.month.toString().padLeft(2, '0');
  return '$d/$m/${date.year}';
}

/// Round play button over a project thumbnail: plays the animation without opening it.
class _PlayBadge extends StatelessWidget {
  const _PlayBadge({required this.path, required this.onTap});
  final String path;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.bottomRight,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Tooltip(
            message: tr('Ver la animación', 'Watch the animation'),
            child: Material(
              color: Colors.black54,
              shape: const CircleBorder(),
              child: InkWell(
                key: ValueKey('easy.home.play.$path'),
                customBorder: const CircleBorder(),
                onTap: onTap,
                child: const SizedBox(width: 44, height: 44, child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 30)),
              ),
            ),
          ),
        ),
      );
}
