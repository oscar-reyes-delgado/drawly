import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/document_controller.dart';
import '../../app/file_ops.dart';
import '../../core/i18n.dart';
import '../../io/image_export.dart';
import '../dialogs/export_dialog.dart';
import '../theme.dart';

/// What the sheet needs from the app (injected so it can be tested without files).
class EasyExportActions {
  const EasyExportActions({required this.pickFolder, required this.write, this.writeVideo, this.reveal});

  /// Asks where to save; null = cancelled.
  final Future<String?> Function() pickFolder;

  /// Usually `writeExport`.
  final Future<List<String>> Function(ExportOptions o, String dir, void Function(double) onProgress, CancelToken cancel) write;

  /// MP4 export; null when the platform has no video encoder (the «Video» button is then hidden).
  final Future<List<String>> Function(String dir, double scale, void Function(double) onProgress, CancelToken cancel)? writeVideo;
  final Future<bool> Function(String path)? reveal;
}

/// Bottom sheet with «Video», «GIF» and «Image (PNG)», a size choice and
/// «More options…» (the full export dialog). Shows progress with Cancel.
Future<void> showEasyExport(BuildContext context, DocumentController doc, EasyExportActions actions) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _EasyExportSheet(doc: doc, actions: actions),
    );

class _EasyExportSheet extends StatefulWidget {
  const _EasyExportSheet({required this.doc, required this.actions});

  final DocumentController doc;
  final EasyExportActions actions;

  @override
  State<_EasyExportSheet> createState() => _EasyExportSheetState();
}

class _EasyExportSheetState extends State<_EasyExportSheet> {
  late double _scale;
  bool _transparent = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final maxSide = math.max(widget.doc.comp.width, widget.doc.comp.height);
    _scale = maxSide > 1920 ? 0.5 : 1.0;
  }

  ({int width, int height}) get _outputSize => (
        width: math.max(1, (widget.doc.comp.width * _scale).round()),
        height: math.max(1, (widget.doc.comp.height * _scale).round()),
      );

  Future<void> _runExport(
    Future<List<String>> Function(String dir, void Function(double) onProgress, CancelToken cancel) task,
  ) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final dir = await widget.actions.pickFolder();
      if (dir == null || !mounted) return;
      final cancel = CancelToken();
      final paths = await showDialog<List<String>>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _ExportProgressDialog(
          cancel: cancel,
          run: (onProgress) => task(dir, onProgress, cancel),
        ),
      );
      if (!mounted) return;
      await _showOutcomeDialog(cancel: cancel, paths: paths ?? const []);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showOutcomeDialog({required CancelToken cancel, required List<String> paths}) async {
    if (cancel.isCancelled) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr('Exportación cancelada', 'Export cancelled')),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(tr('Cerrar', 'Close'))),
          ],
        ),
      );
      return;
    }
    if (paths.isEmpty) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr('No se pudo exportar', 'Export failed')),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(tr('Cerrar', 'Close'))),
          ],
        ),
      );
      return;
    }
    final firstPath = paths.first;
    final label = paths.length == 1 ? firstPath : '$firstPath (+${paths.length - 1})';
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('¡Listo!', 'Done!')),
        content: Text(label, softWrap: true, style: const TextStyle(fontSize: 13)),
        actions: [
          if (widget.actions.reveal != null)
            TextButton(
              onPressed: () => widget.actions.reveal!(firstPath),
              child: Text(tr('Mostrar en la carpeta', 'Show in folder')),
            ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(tr('Cerrar', 'Close')),
          ),
        ],
      ),
    );
  }

  Future<void> _exportVideo() => _runExport((dir, onProgress, cancel) => widget.actions.writeVideo!(dir, _scale, onProgress, cancel));

  Future<void> _exportGif() {
    final tl = widget.doc.timeline;
    final opts = ExportOptions(
      kind: ExportKind.animation,
      anim: AnimFormat.gif,
      scale: _scale,
      rangeStart: tl.rangeStart,
      rangeEnd: tl.rangeEnd,
    );
    return _runExport((dir, onProgress, cancel) => widget.actions.write(opts, dir, onProgress, cancel));
  }

  Future<void> _exportPng() {
    final opts = ExportOptions(
      kind: ExportKind.still,
      still: StillFormat.png,
      frame: widget.doc.frame,
      scale: _scale,
      transparent: _transparent,
    );
    return _runExport((dir, onProgress, cancel) => widget.actions.write(opts, dir, onProgress, cancel));
  }

  Future<void> _openMoreOptions() async {
    final initial = widget.doc.timeline.length > 1 ? ExportKind.animation : ExportKind.still;
    final opts = await showExportDialog(context, widget.doc, initial: initial);
    if (opts == null || !mounted) return;
    await _runExport((dir, onProgress, cancel) => widget.actions.write(opts, dir, onProgress, cancel));
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final out = _outputSize;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    tr('Exportar', 'Export'),
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: cs.onSurface),
                  ),
                ),
                Tooltip(
                  message: tr('Cerrar', 'Close'),
                  child: IconButton(
                    constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, size: 24),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (widget.actions.writeVideo != null) ...[
              _ExportCard(
                icon: Icons.videocam_outlined,
                title: tr('Vídeo (MP4)', 'Video (MP4)'),
                subtitle: tr('Para compartir en redes', 'Share on social media'),
                tooltip: tr('Exportar la animación como vídeo MP4', 'Export the animation as an MP4 video'),
                onTap: _busy ? null : _exportVideo,
              ),
              const SizedBox(height: 8),
            ],
            _ExportCard(
              icon: Icons.gif_box_outlined,
              title: tr('GIF animado', 'Animated GIF'),
              subtitle: tr('Se repite solo', 'Loops automatically'),
              tooltip: tr('Exportar la animación como GIF en bucle', 'Export the animation as a looping GIF'),
              onTap: _busy ? null : _exportGif,
            ),
            const SizedBox(height: 8),
            _ExportCard(
              icon: Icons.image_outlined,
              title: tr('Imagen (PNG)', 'Image (PNG)'),
              subtitle: tr('Solo este fotograma', 'This frame only'),
              tooltip: tr('Exportar el fotograma actual como imagen PNG', 'Export the current frame as a PNG image'),
              onTap: _busy ? null : _exportPng,
              footer: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: _busy ? null : () => setState(() => _transparent = !_transparent),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: Row(
                    children: [
                      Checkbox(
                        value: _transparent,
                        onChanged: _busy ? null : (v) => setState(() => _transparent = v ?? true),
                      ),
                      Expanded(
                        child: Text(
                          tr('Fondo transparente', 'Transparent background'),
                          style: TextStyle(fontSize: 13, color: cs.onSurface),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Text(
                  tr('Tamaño', 'Size'),
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${out.width} × ${out.height} px',
                    textAlign: TextAlign.end,
                    style: TextStyle(fontSize: 13, color: context.dim),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _ScaleChoice(
                    label: tr('Pequeño (50 %)', 'Small (50%)'),
                    tooltip: tr('Exportar a la mitad de tamaño', 'Export at half size'),
                    selected: _scale == 0.5,
                    onTap: _busy ? null : () => setState(() => _scale = 0.5),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ScaleChoice(
                    label: tr('Normal (100 %)', 'Normal (100%)'),
                    tooltip: tr('Exportar al tamaño del proyecto', 'Export at project size'),
                    selected: _scale == 1.0,
                    onTap: _busy ? null : () => setState(() => _scale = 1.0),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ScaleChoice(
                    label: tr('Grande (200 %)', 'Large (200%)'),
                    tooltip: tr('Exportar al doble de tamaño', 'Export at double size'),
                    selected: _scale == 2.0,
                    onTap: _busy ? null : () => setState(() => _scale = 2.0),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Tooltip(
              message: tr('Abrir todas las opciones de exportación', 'Open all export options'),
              child: SizedBox(
                height: 44,
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _openMoreOptions,
                  icon: const Icon(Icons.tune, size: 24),
                  label: Text(tr('Más opciones…', 'More options…'), style: const TextStyle(fontSize: 13)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExportCard extends StatelessWidget {
  const _ExportCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.tooltip,
    required this.onTap,
    this.footer,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String tooltip;
  final VoidCallback? onTap;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Material(
      color: context.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: context.line),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: tooltip,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onTap,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 60),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    children: [
                      Icon(icon, size: 24, color: cs.primary),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: cs.onSurface)),
                            const SizedBox(height: 2),
                            Text(subtitle, style: TextStyle(fontSize: 13, color: context.dim)),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right, size: 24, color: context.dim),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (footer != null)
            Container(
              decoration: BoxDecoration(border: Border(top: BorderSide(color: context.line))),
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: footer,
            ),
        ],
      ),
    );
  }
}

class _ScaleChoice extends StatelessWidget {
  const _ScaleChoice({required this.label, required this.tooltip, required this.selected, required this.onTap});

  final String label;
  final String tooltip;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: selected ? cs.primary.withValues(alpha: 0.18) : context.panel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: selected ? cs.primary : context.line),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Center(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                    color: selected ? cs.primary : cs.onSurface,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ExportProgressDialog extends StatefulWidget {
  const _ExportProgressDialog({required this.cancel, required this.run});

  final CancelToken cancel;
  final Future<List<String>> Function(void Function(double) onProgress) run;

  @override
  State<_ExportProgressDialog> createState() => _ExportProgressDialogState();
}

class _ExportProgressDialogState extends State<_ExportProgressDialog> {
  double _progress = 0;
  bool _cancelling = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    List<String> result = const [];
    try {
      result = await widget.run((p) {
        if (!mounted) return;
        setState(() => _progress = p.clamp(0.0, 1.0));
      });
    } on ExportCancelled {
      result = const [];
    } catch (_) {
      result = const [];
    }
    if (mounted) Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final pct = (_progress * 100).round();
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: Text(tr('Exportando…', 'Exporting…')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LinearProgressIndicator(value: _progress),
            const SizedBox(height: 10),
            Text('$pct%', textAlign: TextAlign.end, style: TextStyle(fontSize: 13, color: context.dim)),
          ],
        ),
        actions: [
          SizedBox(
            height: 44,
            child: TextButton(
              onPressed: _cancelling
                  ? null
                  : () {
                      widget.cancel.cancel();
                      setState(() => _cancelling = true);
                    },
              child: Text(tr('Cancelar', 'Cancel'), style: const TextStyle(fontSize: 13)),
            ),
          ),
        ],
      ),
    );
  }
}
