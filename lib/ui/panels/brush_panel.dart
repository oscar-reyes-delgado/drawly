import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/tool_state.dart';
import '../../core/i18n.dart';
import '../../engine/brush/preset.dart';
import '../theme.dart';
import '../widgets.dart';

/// Brush list grouped by category, with size / opacity / hardness controls for the active brush.
class BrushPanel extends StatelessWidget {
  const BrushPanel({super.key, required this.ts});

  final ToolState ts;

  @override
  Widget build(BuildContext context) => _BrushPanelBody(ts: ts);
}

class _BrushPanelBody extends StatefulWidget {
  const _BrushPanelBody({required this.ts});

  final ToolState ts;

  @override
  State<_BrushPanelBody> createState() => _BrushPanelBodyState();
}

class _BrushPanelBodyState extends State<_BrushPanelBody> {
  final Set<String> _collapsed = {};

  List<(String category, List<BrushPreset> brushes)> _grouped(List<BrushPreset> all) {
    final map = <String, List<BrushPreset>>{};
    for (final b in all) {
      map.putIfAbsent(b.category, () => []).add(b);
    }
    final ordered = <(String, List<BrushPreset>)>[];
    for (final cat in kBrushCategories) {
      final list = map.remove(cat);
      if (list != null && list.isNotEmpty) ordered.add((cat, list));
    }
    for (final entry in map.entries) {
      if (entry.value.isNotEmpty) ordered.add((entry.key, entry.value));
    }
    return ordered;
  }

  IconData _brushIcon(BrushPreset b) {
    if (b.erase) return Icons.auto_fix_normal;
    if (b.engine == BrushEngine.smudge) return Icons.blur_on;
    if (b.engine == BrushEngine.mixer) return Icons.palette;
    if (!b.antialias) return Icons.grid_on;
    return Icons.brush;
  }

  Widget _buildHeader(BuildContext context, BrushPreset active) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth.isFinite ? constraints.maxWidth : 240.0;
        return Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 48,
                decoration: BoxDecoration(
                  color: context.cs.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: context.line),
                ),
                clipBehavior: Clip.antiAlias,
                child: CustomPaint(
                  key: const ValueKey('brush_stroke_preview'),
                  painter: _StrokePreviewPainter(brush: active, color: context.cs.onSurface),
                  child: const SizedBox.expand(),
                ),
              ),
              const SizedBox(height: 6),
              MiniSlider(
                key: const ValueKey('brush_size_slider'),
                label: tr('Tamaño', 'Size'),
                value: active.size,
                min: 0.5,
                max: 500,
                log: true,
                decimals: active.size < 10 ? 1 : 0,
                suffix: ' px',
                width: w,
                onChanged: (v) => widget.ts.updateBrush(active.copyWith(size: v)),
              ),
              MiniSlider(
                key: const ValueKey('brush_opacity_slider'),
                label: tr('Opacidad', 'Opacity'),
                value: active.opacity,
                min: 0,
                max: 1,
                display: 100,
                suffix: '%',
                width: w,
                onChanged: (v) => widget.ts.updateBrush(active.copyWith(opacity: v)),
              ),
              MiniSlider(
                key: const ValueKey('brush_flow_slider'),
                label: tr('Flujo', 'Flow'),
                value: active.flow,
                min: 0,
                max: 1,
                display: 100,
                suffix: '%',
                width: w,
                onChanged: (v) => widget.ts.updateBrush(active.copyWith(flow: v)),
              ),
              MiniSlider(
                key: const ValueKey('brush_hardness_slider'),
                label: tr('Dureza', 'Hardness'),
                value: active.hardness,
                min: 0,
                max: 1,
                display: 100,
                suffix: '%',
                width: w,
                onChanged: (v) => widget.ts.updateBrush(active.copyWith(hardness: v)),
              ),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _buildCategoryChildren(BuildContext context, List<(String, List<BrushPreset>)> groups, String activeId) {
    final cs = context.cs;
    final items = <Widget>[];
    for (final (cat, brushes) in groups) {
      final isCollapsed = _collapsed.contains(cat);
      items.add(
        InkWell(
          key: ValueKey('brush_cat_$cat'),
          canRequestFocus: false,
          onTap: () => setState(() {
            if (isCollapsed) {
              _collapsed.remove(cat);
            } else {
              _collapsed.add(cat);
            }
          }),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: Row(
              children: [
                Icon(isCollapsed ? Icons.chevron_right : Icons.expand_more, size: 16, color: context.dim),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    brushCategoryLabel(cat),
                    style: kTiny.copyWith(color: context.dim, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text('${brushes.length}', style: kTiny.copyWith(color: context.dim)),
              ],
            ),
          ),
        ),
      );
      if (!isCollapsed) {
        for (final b in brushes) {
          final active = b.id == activeId;
          final sizeText = '${b.size < 10 ? b.size.toStringAsFixed(1) : b.size.round()} px';
          items.add(
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              child: Material(
                color: active ? cs.primary.withValues(alpha: 0.16) : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                child: InkWell(
                  key: ValueKey('brush_item_${b.id}'),
                  canRequestFocus: false,
                  borderRadius: BorderRadius.circular(6),
                  onTap: () => widget.ts.selectBrush(b),
                  child: Container(
                    height: 30,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      border: active ? Border.all(color: cs.primary.withValues(alpha: 0.5)) : null,
                    ),
                    child: Row(
                      children: [
                        Icon(_brushIcon(b), size: 15, color: active ? cs.primary : context.dim),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            b.name,
                            style: kSmall.copyWith(color: active ? cs.primary : cs.onSurface),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(sizeText, style: kTiny.copyWith(color: context.dim)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }
      }
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.ts,
      builder: (context, _) {
        final ts = widget.ts;
        final active = ts.brush;
        final groups = _grouped(ts.brushes);
        final listItems = _buildCategoryChildren(context, groups, active.id);

        return LayoutBuilder(
          builder: (context, constraints) {
            // short panels (phone in landscape): everything scrolls together
            if (constraints.hasBoundedHeight && constraints.maxHeight < 360) {
              return ListView(children: [_buildHeader(context, active), const Divider(height: 1), const SizedBox(height: 4), ...listItems]);
            }
            if (constraints.hasBoundedHeight) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(context, active),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      children: listItems,
                    ),
                  ),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildHeader(context, active),
                const Divider(height: 1),
                const SizedBox(height: 4),
                ...listItems,
              ],
            );
          },
        );
      },
    );
  }
}

class _StrokePreviewPainter extends CustomPainter {
  const _StrokePreviewPainter({required this.brush, required this.color});

  final BrushPreset brush;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final d = brush.size.clamp(1.0, 40.0);
    final r = d / 2.0;
    final alpha = (brush.opacity * brush.flow).clamp(0.0, 1.0);
    final pad = r + 8.0;
    final span = math.max(1.0, size.width - pad * 2);
    final amp = math.max(0.0, (size.height - d) * 0.35);
    final cy = size.height / 2.0;
    final step = math.max(2.0, d * brush.spacing.clamp(0.08, 1.0));
    final count = math.max(16, (span / step).ceil());
    final paint = Paint()..color = color.withValues(alpha: alpha);

    for (var i = 0; i <= count; i++) {
      final t = i / count;
      final x = pad + t * span;
      final y = cy - math.sin(t * 2.0 * math.pi) * amp;
      canvas.drawCircle(Offset(x, y), r, paint);
    }
  }

  @override
  bool shouldRepaint(_StrokePreviewPainter old) =>
      old.brush.size != brush.size ||
      old.brush.opacity != brush.opacity ||
      old.brush.flow != brush.flow ||
      old.brush.hardness != brush.hardness ||
      old.brush.spacing != brush.spacing ||
      old.color != color;
}
