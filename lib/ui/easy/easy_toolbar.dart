import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/app_state.dart';
import '../../app/settings.dart';
import '../../app/tool_state.dart';
import '../../core/i18n.dart';
import '../../engine/brush/preset.dart';
import '../../engine/brush/stabilizer.dart';
import '../theme.dart';

/// The seven beginner tools. Each maps to an existing tool (and a brush preset).
enum EasyTool { pencil, brush, eraser, bucket, eyedropper, select, transform }

extension EasyToolX on EasyTool {
  /// Identifier of the underlying canvas tool.
  String get toolId => switch (this) {
        EasyTool.pencil || EasyTool.brush => 'brush',
        EasyTool.eraser => 'eraser',
        EasyTool.bucket => 'bucket',
        EasyTool.eyedropper => 'eyedropper',
        EasyTool.select => 'marquee',
        EasyTool.transform => 'transform',
      };

  /// Brush preset id associated with this tool, if any.
  String? get presetId => switch (this) {
        EasyTool.pencil => 'fineliner',
        EasyTool.brush => 'round_brush',
        _ => null,
      };

  /// Localised short name for this tool.
  String get label => switch (this) {
        EasyTool.pencil => tr('Lápiz', 'Pencil'),
        EasyTool.brush => tr('Pincel', 'Brush'),
        EasyTool.eraser => tr('Borrador', 'Eraser'),
        EasyTool.bucket => tr('Cubeta', 'Fill'),
        EasyTool.eyedropper => tr('Cuentagotas', 'Eyedropper'),
        EasyTool.select => tr('Selección', 'Select'),
        EasyTool.transform => tr('Transformar', 'Transform'),
      };

  /// One short sentence for the tooltip.
  String get help => switch (this) {
        EasyTool.pencil => tr('Dibuja líneas finas y limpias.', 'Draw clean, fine lines.'),
        EasyTool.brush => tr('Pinta trazos suaves con el pincel.', 'Paint smooth strokes with the brush.'),
        EasyTool.eraser => tr('Borra partes del dibujo.', 'Erase parts of your drawing.'),
        EasyTool.bucket => tr('Rellena una zona cerrada de color.', 'Fill a closed area with colour.'),
        EasyTool.eyedropper => tr('Toma un color del lienzo.', 'Pick a colour from the canvas.'),
        EasyTool.select => tr('Selecciona un área para mover o editar.', 'Select an area to move or edit.'),
        EasyTool.transform => tr('Mueve, escala o rota la selección o capa.', 'Move, scale or rotate the selection or layer.'),
      };

  /// Icon representing this tool.
  IconData get icon => switch (this) {
        EasyTool.pencil => Icons.edit_outlined,
        EasyTool.brush => Icons.brush_outlined,
        EasyTool.eraser => Icons.cleaning_services_outlined,
        EasyTool.bucket => Icons.format_color_fill,
        EasyTool.eyedropper => Icons.colorize,
        EasyTool.select => Icons.crop_free,
        EasyTool.transform => Icons.open_with,
      };
}

/// Which easy tool is active given the real tool id and the active brush.
EasyTool? easyToolFor(String toolId, ToolState ts) => switch (toolId) {
      'brush' => ts.brushFor('brush').id == 'fineliner' ? EasyTool.pencil : EasyTool.brush,
      'eraser' => EasyTool.eraser,
      'bucket' => EasyTool.bucket,
      'eyedropper' => EasyTool.eyedropper,
      'marquee' => EasyTool.select,
      'transform' => EasyTool.transform,
      _ => null,
    };

/// Vertical (or horizontal on phones) bar with the seven tools, a size button
/// and a colour button. Tapping a tool calls [onSelectTool] with the real tool id
/// after selecting the preset in [ts] when the tool has one.
class EasyToolbar extends StatelessWidget {
  const EasyToolbar({
    super.key,
    required this.ts,
    required this.activeToolId,
    required this.onSelectTool,
    required this.onOpenColors,
    this.axis = Axis.vertical,
  });

  final ToolState ts;
  final String activeToolId;
  final ValueChanged<String> onSelectTool;
  final VoidCallback onOpenColors;
  final Axis axis;

  BrushPreset? _resolvePreset(EasyTool tool) {
    final pid = tool.presetId;
    if (pid == null) return null;
    for (final b in ts.brushes) {
      if (b.id == pid) return b;
    }
    final cat = tool == EasyTool.pencil ? 'ink' : 'paint';
    for (final b in ts.brushes) {
      if (b.category == cat) return b;
    }
    return null;
  }

  void _selectTool(EasyTool tool) {
    final preset = _resolvePreset(tool);
    if (preset != null) ts.selectBrush(preset);
    onSelectTool(tool.toolId);
  }

  void _openSizePanel(BuildContext context, String slot) {
    if (axis == Axis.horizontal) {
      showModalBottomSheet<void>(
        context: context,
        builder: (_) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: _SizePanel(ts: ts, slot: slot),
          ),
        ),
      );
    } else {
      showDialog<void>(
        context: context,
        barrierColor: Colors.black26,
        builder: (_) => Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(left: 72),
            child: Material(
              color: context.panel,
              elevation: 8,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 260,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.line),
                ),
                child: _SizePanel(ts: ts, slot: slot),
              ),
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ts,
      builder: (context, _) {
        final active = easyToolFor(activeToolId, ts);
        final sizeEnabled = activeToolId == 'brush' || activeToolId == 'eraser';
        final slot = activeToolId == 'eraser' ? 'eraser' : 'brush';
        final activeBrush = ts.brushFor(slot);

        final gap = SizedBox(width: axis == Axis.horizontal ? 4 : 0, height: axis == Axis.vertical ? 4 : 0);
        final divider = axis == Axis.vertical
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: SizedBox(width: 32, child: Divider(color: context.line, height: 1)),
              )
            : Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: SizedBox(height: 32, child: VerticalDivider(color: context.line, width: 1)),
              );

        final children = <Widget>[
          for (var i = 0; i < EasyTool.values.length; i++) ...[
            if (i > 0) gap,
            _ToolButton(
              key: Key('easy.tool.${EasyTool.values[i].name}'),
              tool: EasyTool.values[i],
              selected: active == EasyTool.values[i],
              onTap: () => _selectTool(EasyTool.values[i]),
            ),
          ],
          divider,
          _SizeButton(
            key: const Key('easy.size'),
            brushSize: activeBrush.size,
            enabled: sizeEnabled,
            onTap: sizeEnabled ? () => _openSizePanel(context, slot) : null,
          ),
          gap,
          _ColorButton(
            key: const Key('easy.color'),
            color: ts.fg,
            onTap: onOpenColors,
          ),
        ];

        return Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: context.panel,
            border: Border(
              right: axis == Axis.vertical ? BorderSide(color: context.line) : BorderSide.none,
              top: axis == Axis.horizontal ? BorderSide(color: context.line) : BorderSide.none,
            ),
          ),
          child: axis == Axis.vertical
              ? SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, children: children),
                )
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(mainAxisSize: MainAxisSize.min, children: children),
                ),
        );
      },
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({super.key, required this.tool, required this.selected, required this.onTap});

  final EasyTool tool;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Semantics(
      selected: selected,
      button: true,
      label: tool.label,
      child: Tooltip(
        message: '${tool.label} — ${tool.help}',
        child: Material(
          color: selected ? cs.primary.withValues(alpha: 0.18) : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: selected ? cs.primary : Colors.transparent, width: 1.5),
          ),
          child: InkWell(
            canRequestFocus: false,
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: SizedBox(
              width: 48,
              height: 48,
              child: Center(
                child: Icon(
                  tool.icon,
                  size: 24,
                  color: selected ? cs.primary : cs.onSurface.withValues(alpha: 0.88),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SizeButton extends StatelessWidget {
  const _SizeButton({super.key, required this.brushSize, required this.enabled, required this.onTap});

  final double brushSize;
  final bool enabled;
  final VoidCallback? onTap;

  static double _circleDiameter(double size) {
    final t = (math.log(size.clamp(1.0, 200.0)) / math.log(200.0)).clamp(0.0, 1.0);
    return 6.0 + 26.0 * t;
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final diameter = _circleDiameter(brushSize);
    final label = brushSize.round().toString();
    return Semantics(
      button: true,
      enabled: enabled,
      label: tr('Tamaño', 'Size'),
      child: Tooltip(
        message: '${tr('Tamaño', 'Size')} — ${tr('Ajusta el grosor y suavizado del trazo.', 'Adjust stroke size and smoothing.')}',
        child: Opacity(
          opacity: enabled ? 1.0 : 0.35,
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              canRequestFocus: false,
              borderRadius: BorderRadius.circular(10),
              onTap: onTap,
              child: SizedBox(
                width: 48,
                height: 50,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      height: 32,
                      child: Center(
                        child: Container(
                          width: diameter,
                          height: diameter,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: cs.onSurface.withValues(alpha: 0.88),
                          ),
                        ),
                      ),
                    ),
                    Text(
                      label,
                      style: TextStyle(fontSize: 13, height: 1.0, color: cs.onSurface.withValues(alpha: 0.88)),
                      maxLines: 1,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ColorButton extends StatelessWidget {
  const _ColorButton({super.key, required this.color, required this.onTap});

  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Semantics(
      button: true,
      label: tr('Color', 'Colour'),
      child: Tooltip(
        message: '${tr('Color', 'Colour')} — ${tr('Elige el color del trazo.', 'Choose the stroke colour.')}',
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            canRequestFocus: false,
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: SizedBox(
              width: 48,
              height: 48,
              child: Center(
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color,
                    border: Border.all(color: Colors.white.withValues(alpha: 0.9), width: 2),
                    boxShadow: [BoxShadow(color: cs.outline.withValues(alpha: 0.6), spreadRadius: 1)],
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

class _SizePanel extends StatefulWidget {
  const _SizePanel({required this.ts, required this.slot});

  final ToolState ts;
  final String slot;

  @override
  State<_SizePanel> createState() => _SizePanelState();
}

class _SizePanelState extends State<_SizePanel> {
  bool _moreOpen = false;

  static double _sizeToT(double size) => (math.log(size.clamp(1.0, 200.0)) / math.log(200.0)).clamp(0.0, 1.0);
  static double _tToSize(double t) => math.exp(t * math.log(200.0)).clamp(1.0, 200.0);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.ts,
      builder: (context, _) {
        final brush = widget.ts.brushFor(widget.slot);
        final cs = context.cs;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(tr('Tamaño', 'Size'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const Spacer(),
                Text('${brush.size.round()} px', style: TextStyle(fontSize: 13, color: context.dim)),
              ],
            ),
            Slider(
              key: const Key('easy.size.slider'),
              value: _sizeToT(brush.size),
              onChanged: (t) => widget.ts.updateBrush(brush.copyWith(size: _tToSize(t))),
            ),
            InkWell(
              key: const Key('easy.size.more'),
              canRequestFocus: false,
              borderRadius: BorderRadius.circular(8),
              onTap: () => setState(() => _moreOpen = !_moreOpen),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    children: [
                      Text(tr('Más', 'More'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface)),
                      const Spacer(),
                      Icon(_moreOpen ? Icons.expand_less : Icons.expand_more, size: 24, color: cs.onSurface),
                    ],
                  ),
                ),
              ),
            ),
            if (_moreOpen) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Text(tr('Opacidad', 'Opacity'), style: const TextStyle(fontSize: 13)),
                  const Spacer(),
                  Text('${(brush.opacity * 100).round()}%', style: TextStyle(fontSize: 13, color: context.dim)),
                ],
              ),
              Slider(
                key: const Key('easy.size.opacity'),
                value: brush.opacity.clamp(0.0, 1.0),
                onChanged: (v) => widget.ts.updateBrush(brush.copyWith(opacity: v)),
              ),
              Text(tr('Estabilizar', 'Stabilise'), style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 6),
              const EasyStabilizerChoice(),
            ],
          ],
        );
      },
    );
  }
}

/// Stabilizer choices for beginners plus a 0–10 level (stored in the app settings).
class EasyStabilizerChoice extends StatelessWidget {
  const EasyStabilizerChoice({super.key, this.settings});
  final Settings? settings;

  /// id, label, mode, default strength when picked
  static List<(String, String, StabilizerMode, double)> get presets => [
        ('none', tr('No', 'Off'), StabilizerMode.smooth, 0),
        ('soft', tr('Suave', 'Soft'), StabilizerMode.smooth, 0.4),
        ('strong', tr('Fuerte', 'Strong'), StabilizerMode.average, 0.7),
        ('rope', tr('Cuerda', 'Rope'), StabilizerMode.rope, 0.6),
        ('super', tr('Súper', 'Super'), StabilizerMode.superStable, 0.8),
        ('dynamic', tr('Dinámico', 'Dynamic'), StabilizerMode.dynamic, 0.6),
        ('slow', tr('Lento', 'Slow'), StabilizerMode.slow, 0.6),
      ];

  /// Choice matching the current settings (by mode; level 0 = off), or null.
  static String? current(Settings s) {
    if (s.stabilizerMode == StabilizerMode.brush) return null;
    if (s.stabilizerStrength == 0) return 'none';
    if (s.stabilizerMode == StabilizerMode.smooth) return 'soft';
    for (final (id, _, mode, _) in presets) {
      if (id != 'none' && s.stabilizerMode == mode) return id;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final s = settings ?? AppState.I.settings;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final cur = current(s);
        final level = stabilizerLevel(s.stabilizerStrength);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final (id, label, mode, strength) in presets)
              Tooltip(
                message: id == 'none' ? tr('Sin estabilizador', 'No stabilizer') : mode.help,
                child: ChoiceChip(
                  key: Key('easy.stab.$id'),
                  label: Text(label),
                  selected: cur == id,
                  onSelected: (_) => s.update((x) {
                    x.stabilizerMode = mode;
                    x.stabilizerStrength = strength;
                    x.stabilizerCatchUp = true;
                  }),
                ),
              ),
          ]),
          if (cur != null && cur != 'none') ...[
            const SizedBox(height: 8),
            Row(children: [
              Text(tr('Nivel', 'Level'), style: const TextStyle(fontSize: 13)),
              Expanded(
                child: Slider(
                  key: const Key('easy.stab.level'),
                  value: level.clamp(1, 10).toDouble(),
                  min: 1,
                  max: 10,
                  divisions: 9,
                  label: '$level',
                  onChanged: (v) => s.update((x) => x.stabilizerStrength = stabilizerStrengthOf(v.round())),
                ),
              ),
              SizedBox(width: 28, child: Text('$level', textAlign: TextAlign.end, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
            ]),
          ],
        ]);
      },
    );
  }
}
