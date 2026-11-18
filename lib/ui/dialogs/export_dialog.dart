import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/document_controller.dart';
import '../../core/i18n.dart';
import '../../io/image_export.dart';
import '../../model/layer.dart';
import '../theme.dart';
import '../widgets.dart';

enum ExportKind { still, animation, sequence, spriteSheet, svg }

/// Options chosen in the dialog (pure data, no files touched).
class ExportOptions {
  const ExportOptions({
    required this.kind,
    this.still = StillFormat.png,
    this.anim = AnimFormat.gif,
    this.scale = 1,
    this.quality = 90,
    this.frame = 0,
    this.rangeStart = 0,
    this.rangeEnd = 1,
    this.columns = 0,
    this.padding = 0,
    this.watermark = false,
    this.transparent = true,
  });

  final ExportKind kind;
  final StillFormat still;
  final AnimFormat anim;
  final double scale; // 0.1 .. 8
  final int quality; // 1 .. 100, only jpg / webp
  final int frame; // still
  final int rangeStart, rangeEnd; // animation / sequence / spriteSheet, end exclusive
  final int columns, padding; // spriteSheet; columns 0 = automatic
  final bool watermark, transparent;

  ExportOptions copyWith({
    ExportKind? kind,
    StillFormat? still,
    AnimFormat? anim,
    double? scale,
    int? quality,
    int? frame,
    int? rangeStart,
    int? rangeEnd,
    int? columns,
    int? padding,
    bool? watermark,
    bool? transparent,
  }) =>
      ExportOptions(
        kind: kind ?? this.kind,
        still: still ?? this.still,
        anim: anim ?? this.anim,
        scale: scale ?? this.scale,
        quality: quality ?? this.quality,
        frame: frame ?? this.frame,
        rangeStart: rangeStart ?? this.rangeStart,
        rangeEnd: rangeEnd ?? this.rangeEnd,
        columns: columns ?? this.columns,
        padding: padding ?? this.padding,
        watermark: watermark ?? this.watermark,
        transparent: transparent ?? this.transparent,
      );

  /// Output size in pixels for a composition of [w] x [h].
  ({int width, int height}) outputSize(int w, int h) => (
        width: math.max(1, (w * scale).round()),
        height: math.max(1, (h * scale).round()),
      );

  /// Number of frames that will be rendered.
  int get frameCount => switch (kind) {
        ExportKind.still || ExportKind.svg => 1,
        ExportKind.animation || ExportKind.sequence || ExportKind.spriteSheet => math.max(1, rangeEnd - rangeStart),
      };

  /// File extension of the result ('png', 'gif', 'svg', …; 'png' for sequence and sprite sheet).
  String get extension => switch (kind) {
        ExportKind.still || ExportKind.sequence => still.ext,
        ExportKind.animation => anim.ext,
        ExportKind.spriteSheet => 'png',
        ExportKind.svg => 'svg',
      };
}

/// Shows the dialog; null when cancelled.
Future<ExportOptions?> showExportDialog(
  BuildContext context,
  DocumentController doc, {
  ExportKind initial = ExportKind.still,
}) =>
    showDialog<ExportOptions>(
      context: context,
      builder: (_) => _ExportDialog(doc: doc, initial: initial),
    );

class _ExportDialog extends StatefulWidget {
  const _ExportDialog({required this.doc, required this.initial});

  final DocumentController doc;
  final ExportKind initial;

  @override
  State<_ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<_ExportDialog> {
  late ExportOptions _opts;

  int get _maxTimelineLength => math.max(1, widget.doc.timeline.length);

  @override
  void initState() {
    super.initState();
    final tl = widget.doc.timeline;
    final maxLen = _maxTimelineLength;
    final start = tl.rangeStart.clamp(0, maxLen - 1);
    final end = tl.rangeEnd.clamp(start + 1, maxLen);
    _opts = ExportOptions(
      kind: widget.initial,
      frame: widget.doc.frame.clamp(0, maxLen - 1),
      rangeStart: start,
      rangeEnd: end,
    );
  }

  void _setRangeStart(int value) {
    final start = value.clamp(0, _opts.rangeEnd - 1);
    setState(() => _opts = _opts.copyWith(rangeStart: start));
  }

  void _setRangeEnd(int value) {
    final end = value.clamp(_opts.rangeStart + 1, _maxTimelineLength);
    setState(() => _opts = _opts.copyWith(rangeEnd: end));
  }

  String _kindLabel(ExportKind kind) => switch (kind) {
        ExportKind.still => tr('Imagen', 'Image'),
        ExportKind.animation => tr('Animación', 'Animation'),
        ExportKind.sequence => tr('Secuencia', 'Sequence'),
        ExportKind.spriteSheet => tr('Hoja de sprites', 'Sprite sheet'),
        ExportKind.svg => 'SVG',
      };

  IconData _kindIcon(ExportKind kind) => switch (kind) {
        ExportKind.still => Icons.image_outlined,
        ExportKind.animation => Icons.movie_outlined,
        ExportKind.sequence => Icons.collections_outlined,
        ExportKind.spriteSheet => Icons.grid_on_outlined,
        ExportKind.svg => Icons.polyline_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final comp = widget.doc.comp;
    final out = _opts.outputSize(comp.width, comp.height);
    final frames = _opts.frameCount;
    final frameWord = frames == 1 ? tr('fotograma', 'frame') : tr('fotogramas', 'frames');
    final summary = '${out.width} × ${out.height} px · $frames $frameWord · .${_opts.extension}';

    return Dialog(
      child: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(tr('Exportar', 'Export'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final kind in ExportKind.values) _KindChip(label: _kindLabel(kind), icon: _kindIcon(kind), selected: _opts.kind == kind, onTap: () => setState(() => _opts = _opts.copyWith(kind: kind))),
                ],
              ),
              const SizedBox(height: 14),
              const Divider(),
              const SizedBox(height: 12),
              ..._buildKindControls(),
              const SizedBox(height: 8),
              _buildScaleRow(),
              const SizedBox(height: 8),
              Row(
                children: [
                  MiniToggle(
                    label: tr('Marca de agua', 'Watermark'),
                    icon: Icons.branding_watermark_outlined,
                    value: _opts.watermark,
                    onChanged: (v) => setState(() => _opts = _opts.copyWith(watermark: v)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(6)),
                child: Text(summary, style: kSmall.copyWith(color: context.dim)),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Cancelar', 'Cancel'))),
                  const SizedBox(width: 8),
                  FilledButton(onPressed: () => Navigator.pop(context, _opts), child: Text(tr('Exportar', 'Export'))),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildKindControls() {
    switch (_opts.kind) {
      case ExportKind.still:
        final hasQuality = _opts.still == StillFormat.jpg || _opts.still == StillFormat.webp;
        return [
          _LabeledRow(
            label: tr('Formato', 'Format'),
            child: MiniDropdown<StillFormat>(
              value: _opts.still,
              items: [for (final f in StillFormat.values) (f, f.ext.toUpperCase())],
              onChanged: (f) => setState(() => _opts = _opts.copyWith(still: f)),
            ),
          ),
          const SizedBox(height: 8),
          _LabeledRow(
            label: tr('Fotograma', 'Frame'),
            child: NumField(
              value: _opts.frame.toDouble(),
              min: 0,
              max: (_maxTimelineLength - 1).toDouble(),
              onSubmitted: (v) => setState(() => _opts = _opts.copyWith(frame: v.round().clamp(0, _maxTimelineLength - 1))),
            ),
          ),
          if (hasQuality) ...[
            const SizedBox(height: 8),
            MiniSlider(
              label: tr('Calidad', 'Quality'),
              value: _opts.quality.toDouble(),
              min: 1,
              max: 100,
              suffix: '%',
              width: double.infinity,
              onChanged: (v) => setState(() => _opts = _opts.copyWith(quality: v.round().clamp(1, 100))),
            ),
          ],
          if (_opts.still.hasAlpha) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                MiniToggle(
                  label: tr('Fondo transparente', 'Transparent background'),
                  value: _opts.transparent,
                  onChanged: (v) => setState(() => _opts = _opts.copyWith(transparent: v)),
                ),
              ],
            ),
          ],
        ];
      case ExportKind.animation:
        return [
          _LabeledRow(
            label: tr('Formato', 'Format'),
            child: MiniDropdown<AnimFormat>(
              value: _opts.anim,
              items: [for (final f in AnimFormat.values) (f, f.name.toUpperCase())],
              onChanged: (f) => setState(() => _opts = _opts.copyWith(anim: f)),
            ),
          ),
          const SizedBox(height: 8),
          _buildRangeRow(),
        ];
      case ExportKind.sequence:
        return [
          _LabeledRow(
            label: tr('Formato', 'Format'),
            child: MiniDropdown<StillFormat>(
              value: _opts.still,
              items: [for (final f in StillFormat.values) (f, f.ext.toUpperCase())],
              onChanged: (f) => setState(() => _opts = _opts.copyWith(still: f)),
            ),
          ),
          const SizedBox(height: 8),
          _buildRangeRow(),
        ];
      case ExportKind.spriteSheet:
        return [
          _buildRangeRow(),
          const SizedBox(height: 8),
          _LabeledRow(
            label: tr('Columnas (0 = auto)', 'Columns (0 = auto)'),
            child: NumField(
              value: _opts.columns.toDouble(),
              min: 0,
              max: 256,
              onSubmitted: (v) => setState(() => _opts = _opts.copyWith(columns: v.round().clamp(0, 256))),
            ),
          ),
          const SizedBox(height: 8),
          _LabeledRow(
            label: tr('Separación', 'Padding'),
            child: NumField(
              value: _opts.padding.toDouble(),
              min: 0,
              max: 128,
              suffix: 'px',
              onSubmitted: (v) => setState(() => _opts = _opts.copyWith(padding: v.round().clamp(0, 128))),
            ),
          ),
        ];
      case ExportKind.svg:
        if (widget.doc.activeLayer is VectorLayer) return const [];
        return [
          Text(
            tr('La capa activa no es vectorial', 'The active layer is not a vector layer'),
            style: kSmall.copyWith(color: context.dim),
          ),
        ];
    }
  }

  Widget _buildRangeRow() {
    return _LabeledRow(
      label: tr('Rango', 'Range'),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          NumField(
            value: _opts.rangeStart.toDouble(),
            min: 0,
            max: (_opts.rangeEnd - 1).toDouble(),
            onSubmitted: (v) => _setRangeStart(v.round()),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text('–', style: kSmall.copyWith(color: context.dim)),
          ),
          NumField(
            value: _opts.rangeEnd.toDouble(),
            min: (_opts.rangeStart + 1).toDouble(),
            max: _maxTimelineLength.toDouble(),
            onSubmitted: (v) => _setRangeEnd(v.round()),
          ),
        ],
      ),
    );
  }

  Widget _buildScaleRow() {
    return Row(
      children: [
        Expanded(
          child: MiniSlider(
            label: tr('Escala', 'Scale'),
            value: _opts.scale.clamp(0.1, 8.0),
            min: 0.1,
            max: 8.0,
            log: true,
            display: 100,
            suffix: '%',
            width: double.infinity,
            onChanged: (v) => setState(() => _opts = _opts.copyWith(scale: v.clamp(0.1, 8.0))),
          ),
        ),
        const SizedBox(width: 8),
        for (final preset in const [(0.5, '50 %'), (1.0, '100 %'), (2.0, '200 %')]) ...[
          _ScalePresetChip(
            label: preset.$2,
            selected: (_opts.scale - preset.$1).abs() < 0.01,
            onTap: () => setState(() => _opts = _opts.copyWith(scale: preset.$1)),
          ),
          if (preset.$1 != 2.0) const SizedBox(width: 4),
        ],
      ],
    );
  }
}

class _KindChip extends StatelessWidget {
  const _KindChip({required this.label, required this.icon, required this.selected, required this.onTap});

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Material(
      color: selected ? cs.primary.withValues(alpha: 0.18) : cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: selected ? cs.primary : context.dim),
              const SizedBox(width: 6),
              Text(label, style: kSmall.copyWith(color: selected ? cs.primary : cs.onSurface, fontWeight: selected ? FontWeight.w600 : FontWeight.normal)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScalePresetChip extends StatelessWidget {
  const _ScalePresetChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Material(
      color: selected ? cs.primary.withValues(alpha: 0.18) : cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
          child: Text(label, style: kTiny.copyWith(color: selected ? cs.primary : cs.onSurface)),
        ),
      ),
    );
  }
}

class _LabeledRow extends StatelessWidget {
  const _LabeledRow({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label, style: kSmall.copyWith(color: context.dim))),
        child,
      ],
    );
  }
}
