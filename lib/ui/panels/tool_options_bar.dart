import 'package:flutter/material.dart';

import '../../app/doc_selection.dart';
import '../../app/tool_state.dart';
import '../../core/i18n.dart';
import '../../model/gradient.dart';
import '../../model/layer.dart';
import '../theme.dart';
import '../widgets.dart';

/// Horizontal bar (height 36) with the options of the active tool.
class ToolOptionsBar extends StatelessWidget {
  const ToolOptionsBar({super.key, required this.ts, required this.toolId});

  final ToolState ts;

  /// Active tool identifier (may be a temporary tool).
  final String toolId;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      width: double.infinity,
      decoration: BoxDecoration(
        color: context.panel,
        border: Border(bottom: BorderSide(color: context.line)),
      ),
      child: ListenableBuilder(
        listenable: ts,
        builder: (context, _) {
          final items = _buildItems(context);
          return Align(
            alignment: Alignment.centerLeft,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: items,
              ),
            ),
          );
        },
      ),
    );
  }

  List<Widget> _buildItems(BuildContext context) {
    switch (toolId) {
      case 'brush':
      case 'eraser':
      case 'smudge':
        return _brushOptions(context);
      case 'marquee':
      case 'lasso':
      case 'polylasso':
        return _selectionOptions(context, isMarquee: toolId == 'marquee');
      case 'wand':
        return _wandOptions(context);
      case 'bucket':
        return _bucketOptions(context);
      case 'gradient':
        return _gradientOptions(context);
      case 'shape':
        return _shapeOptions(context);
      case 'text':
        return _textOptions(context);
      case 'eyedropper':
        return _eyedropperOptions(context);
      case 'liquify':
        return _liquifyOptions(context);
      case 'move':
        return _moveOptions(context);
      default:
        return [
          Text(_toolName(toolId), style: kSmall.copyWith(color: context.dim)),
          const VSep(),
          Text(tr('Sin opciones', 'No options'), style: kSmall.copyWith(color: context.dim)),
        ];
    }
  }

  List<Widget> _liquifyOptions(BuildContext context) => [
        MiniDropdown<LiquifyMode>(
          key: const ValueKey('opt_liquify_mode'),
          value: ts.liquifyMode,
          items: [for (final m in LiquifyMode.values) (m, m.label)],
          onChanged: (m) => ts.set(() => ts.liquifyMode = m),
        ),
        const VSep(),
        MiniSlider(key: const ValueKey('opt_liquify_size'), label: tr('Tamaño', 'Size'), value: ts.liquifySize, min: 4, max: 800, log: true, suffix: ' px', onChanged: (v) => ts.set(() => ts.liquifySize = v)),
        MiniSlider(key: const ValueKey('opt_liquify_strength'), label: tr('Fuerza', 'Strength'), value: ts.liquifyStrength, min: 0.01, max: 1, display: 100, suffix: '%', onChanged: (v) => ts.set(() => ts.liquifyStrength = v)),
      ];

  List<Widget> _brushOptions(BuildContext context) {
    final b = ts.brushFor(ts.slotOf(toolId));
    return [
      Text(b.name, style: kSmall.copyWith(fontWeight: FontWeight.w600)),
      const VSep(),
      MiniSlider(
        key: const ValueKey('opt_brush_size'),
        label: tr('Tamaño', 'Size'),
        value: b.size,
        min: 0.5,
        max: 500,
        log: true,
        decimals: b.size < 10 ? 1 : 0,
        suffix: ' px',
        width: 190,
        onChanged: (v) => ts.updateBrush(b.copyWith(size: v)),
      ),
      const SizedBox(width: 8),
      MiniSlider(
        key: const ValueKey('opt_brush_opacity'),
        label: tr('Opacidad', 'Opacity'),
        value: b.opacity,
        min: 0,
        max: 1,
        display: 100,
        decimals: 0,
        suffix: '%',
        width: 190,
        onChanged: (v) => ts.updateBrush(b.copyWith(opacity: v)),
      ),
      if (toolId == 'brush') ...[
        const VSep(),
        Text(tr('Fusión', 'Blend'), style: kTiny.copyWith(color: context.dim)),
        const SizedBox(width: 6),
        MiniDropdown<LayerBlend>(
          key: const ValueKey('opt_stroke_blend'),
          value: ts.strokeBlend,
          items: [for (final m in LayerBlend.values) (m, m.label)],
          tooltip: tr('Modo de fusión del trazo', 'Stroke blend mode'),
          onChanged: (v) => ts.set(() => ts.strokeBlend = v),
        ),
      ],
    ];
  }

  List<Widget> _selectModeButtons() {
    const modes = [
      (SelectMode.replace, Icons.crop_square),
      (SelectMode.add, Icons.add_box_outlined),
      (SelectMode.subtract, Icons.indeterminate_check_box_outlined),
      (SelectMode.intersect, Icons.filter_none),
    ];
    String tip(SelectMode m) => switch (m) {
          SelectMode.replace => tr('Reemplazar', 'Replace'),
          SelectMode.add => tr('Añadir', 'Add'),
          SelectMode.subtract => tr('Restar', 'Subtract'),
          SelectMode.intersect => tr('Intersecar', 'Intersect'),
        };
    return [
      for (final (mode, icon) in modes) ...[
        PanelButton(
          key: ValueKey('opt_select_mode_${mode.name}'),
          icon: icon,
          tooltip: tip(mode),
          selected: ts.selectMode == mode,
          onTap: () => ts.set(() => ts.selectMode = mode),
        ),
        const SizedBox(width: 2),
      ],
    ];
  }

  List<Widget> _selectionOptions(BuildContext context, {required bool isMarquee}) {
    return [
      ..._selectModeButtons(),
      if (isMarquee) ...[
        const VSep(),
        MiniDropdown<String>(
          key: const ValueKey('opt_marquee_shape'),
          value: ts.marqueeShape,
          items: [
            ('rect', tr('Rectángulo', 'Rectangle')),
            ('ellipse', tr('Elipse', 'Ellipse')),
          ],
          tooltip: tr('Forma de marco', 'Marquee shape'),
          onChanged: (v) => ts.set(() => ts.marqueeShape = v),
        ),
      ],
      const VSep(),
      MiniSlider(
        key: const ValueKey('opt_select_feather'),
        label: tr('Calado', 'Feather'),
        value: ts.selectFeather,
        min: 0,
        max: 100,
        decimals: 0,
        suffix: ' px',
        width: 190,
        onChanged: (v) => ts.set(() => ts.selectFeather = v),
      ),
      const SizedBox(width: 8),
      MiniToggle(
        key: const ValueKey('opt_select_aa'),
        label: tr('Suavizado', 'Anti-alias'),
        value: ts.selectAntiAlias,
        onChanged: (v) => ts.set(() => ts.selectAntiAlias = v),
      ),
    ];
  }

  List<Widget> _wandOptions(BuildContext context) {
    return [
      ..._selectModeButtons(),
      const VSep(),
      MiniSlider(
        key: const ValueKey('opt_tolerance'),
        label: tr('Tolerancia', 'Tolerance'),
        value: ts.tolerance.toDouble(),
        min: 0,
        max: 255,
        decimals: 0,
        width: 200,
        onChanged: (v) => ts.set(() => ts.tolerance = v.round()),
      ),
      const SizedBox(width: 8),
      MiniToggle(
        key: const ValueKey('opt_contiguous'),
        label: tr('Contiguo', 'Contiguous'),
        value: ts.contiguous,
        onChanged: (v) => ts.set(() => ts.contiguous = v),
      ),
      const VSep(),
      MiniDropdown<SampleSource>(
        key: const ValueKey('opt_sample_source'),
        value: ts.sampleSource,
        items: [for (final s in SampleSource.values) (s, s.label)],
        tooltip: tr('Origen de muestreo', 'Sample source'),
        onChanged: (v) => ts.set(() => ts.sampleSource = v),
      ),
    ];
  }

  List<Widget> _bucketOptions(BuildContext context) {
    return [
      MiniSlider(
        key: const ValueKey('opt_tolerance'),
        label: tr('Tolerancia', 'Tolerance'),
        value: ts.tolerance.toDouble(),
        min: 0,
        max: 255,
        decimals: 0,
        width: 200,
        onChanged: (v) => ts.set(() => ts.tolerance = v.round()),
      ),
      const SizedBox(width: 8),
      MiniToggle(
        key: const ValueKey('opt_contiguous'),
        label: tr('Contiguo', 'Contiguous'),
        value: ts.contiguous,
        onChanged: (v) => ts.set(() => ts.contiguous = v),
      ),
      const VSep(),
      MiniDropdown<SampleSource>(
        key: const ValueKey('opt_sample_source'),
        value: ts.sampleSource,
        items: [for (final s in SampleSource.values) (s, s.label)],
        tooltip: tr('Origen de muestreo', 'Sample source'),
        onChanged: (v) => ts.set(() => ts.sampleSource = v),
      ),
      const VSep(),
      MiniSlider(
        key: const ValueKey('opt_fill_expand'),
        label: tr('Expandir', 'Expand'),
        value: ts.fillExpand,
        min: 0,
        max: 20,
        decimals: 0,
        suffix: ' px',
        width: 190,
        onChanged: (v) => ts.set(() => ts.fillExpand = v),
      ),
      const SizedBox(width: 8),
      MiniSlider(
        key: const ValueKey('opt_fill_gap'),
        label: tr('Cerrar huecos', 'Gap close'),
        value: ts.fillGap.toDouble(),
        min: 0,
        max: 20,
        decimals: 0,
        suffix: ' px',
        width: 220,
        onChanged: (v) => ts.set(() => ts.fillGap = v.round()),
      ),
      const SizedBox(width: 8),
      MiniSlider(
        key: const ValueKey('opt_fill_opacity'),
        label: tr('Opacidad', 'Opacity'),
        value: ts.fillOpacity,
        min: 0,
        max: 1,
        display: 100,
        decimals: 0,
        suffix: '%',
        width: 190,
        onChanged: (v) => ts.set(() => ts.fillOpacity = v),
      ),
    ];
  }

  List<Widget> _gradientOptions(BuildContext context) {
    return [
      MiniDropdown<GradientKind>(
        key: const ValueKey('opt_gradient_kind'),
        value: ts.gradientKind,
        items: [for (final k in GradientKind.values) (k, k.label)],
        tooltip: tr('Tipo de degradado', 'Gradient type'),
        onChanged: (v) => ts.set(() => ts.gradientKind = v),
      ),
      const VSep(),
      MiniToggle(
        key: const ValueKey('opt_gradient_transparent'),
        label: tr('A transparente', 'To transparent'),
        value: ts.gradientToTransparent,
        onChanged: (v) => ts.set(() => ts.gradientToTransparent = v),
      ),
      const SizedBox(width: 8),
      MiniToggle(
        key: const ValueKey('opt_gradient_repeat'),
        label: tr('Repetir', 'Repeat'),
        value: ts.gradientRepeat,
        onChanged: (v) => ts.set(() => ts.gradientRepeat = v),
      ),
      const VSep(),
      MiniSlider(
        key: const ValueKey('opt_gradient_opacity'),
        label: tr('Opacidad', 'Opacity'),
        value: ts.gradientOpacity,
        min: 0,
        max: 1,
        display: 100,
        decimals: 0,
        suffix: '%',
        width: 190,
        onChanged: (v) => ts.set(() => ts.gradientOpacity = v),
      ),
    ];
  }

  List<Widget> _shapeOptions(BuildContext context) {
    final kind = ts.shapeKind;
    return [
      MiniDropdown<ShapeKind>(
        key: const ValueKey('opt_shape_kind'),
        value: kind,
        items: [for (final k in ShapeKind.values) (k, k.label)],
        tooltip: tr('Tipo de forma', 'Shape type'),
        onChanged: (v) => ts.set(() => ts.shapeKind = v),
      ),
      const VSep(),
      MiniToggle(
        key: const ValueKey('opt_shape_fill'),
        label: tr('Relleno', 'Fill'),
        value: ts.shapeFill,
        onChanged: (v) => ts.set(() => ts.shapeFill = v),
      ),
      const SizedBox(width: 6),
      MiniToggle(
        key: const ValueKey('opt_shape_stroke'),
        label: tr('Trazo', 'Stroke'),
        value: ts.shapeStroke,
        onChanged: (v) => ts.set(() => ts.shapeStroke = v),
      ),
      const SizedBox(width: 8),
      MiniSlider(
        key: const ValueKey('opt_shape_stroke_width'),
        label: tr('Grosor', 'Width'),
        value: ts.shapeStrokeWidth,
        min: 0.5,
        max: 100,
        decimals: 1,
        suffix: ' px',
        width: 190,
        onChanged: (v) => ts.set(() => ts.shapeStrokeWidth = v),
      ),
      if (kind == ShapeKind.roundRect) ...[
        const VSep(),
        Text(tr('Radio', 'Radius'), style: kTiny.copyWith(color: context.dim)),
        const SizedBox(width: 6),
        NumField(
          key: const ValueKey('opt_shape_radius'),
          value: ts.shapeRadius,
          min: 0,
          max: 500,
          decimals: 0,
          suffix: ' px',
          width: 64,
          onSubmitted: (v) => ts.set(() => ts.shapeRadius = v),
        ),
      ],
      if (kind == ShapeKind.polygon || kind == ShapeKind.star) ...[
        const VSep(),
        Text(tr('Lados', 'Sides'), style: kTiny.copyWith(color: context.dim)),
        const SizedBox(width: 6),
        NumField(
          key: const ValueKey('opt_shape_sides'),
          value: ts.shapeSides.toDouble(),
          min: 3,
          max: 32,
          decimals: 0,
          width: 52,
          onSubmitted: (v) => ts.set(() => ts.shapeSides = v.round()),
        ),
      ],
      if (kind == ShapeKind.star) ...[
        const SizedBox(width: 8),
        MiniSlider(
          key: const ValueKey('opt_star_ratio'),
          label: tr('Proporción', 'Ratio'),
          value: ts.starRatio,
          min: 0.1,
          max: 0.95,
          decimals: 2,
          width: 200,
          onChanged: (v) => ts.set(() => ts.starRatio = v),
        ),
      ],
    ];
  }

  List<Widget> _textOptions(BuildContext context) {
    const aligns = [
      (0, Icons.format_align_left),
      (1, Icons.format_align_center),
      (2, Icons.format_align_right),
    ];
    String alignTip(int a) => switch (a) {
          0 => tr('Alinear a la izquierda', 'Align left'),
          1 => tr('Centrar', 'Align centre'),
          _ => tr('Alinear a la derecha', 'Align right'),
        };
    return [
      Text(tr('Tamaño', 'Size'), style: kTiny.copyWith(color: context.dim)),
      const SizedBox(width: 6),
      NumField(
        key: const ValueKey('opt_font_size'),
        value: ts.fontSize,
        min: 4,
        max: 1000,
        decimals: 0,
        suffix: ' px',
        width: 68,
        onSubmitted: (v) => ts.set(() => ts.fontSize = v),
      ),
      const VSep(),
      PanelButton(
        key: const ValueKey('opt_font_bold'),
        icon: Icons.format_bold,
        tooltip: tr('Negrita', 'Bold'),
        selected: ts.fontBold,
        onTap: () => ts.set(() => ts.fontBold = !ts.fontBold),
      ),
      const SizedBox(width: 2),
      PanelButton(
        key: const ValueKey('opt_font_italic'),
        icon: Icons.format_italic,
        tooltip: tr('Cursiva', 'Italic'),
        selected: ts.fontItalic,
        onTap: () => ts.set(() => ts.fontItalic = !ts.fontItalic),
      ),
      const VSep(),
      for (final (a, icon) in aligns) ...[
        PanelButton(
          key: ValueKey('opt_text_align_$a'),
          icon: icon,
          tooltip: alignTip(a),
          selected: ts.textAlign == a,
          onTap: () => ts.set(() => ts.textAlign = a),
        ),
        const SizedBox(width: 2),
      ],
    ];
  }

  List<Widget> _eyedropperOptions(BuildContext context) {
    return [
      MiniToggle(
        key: const ValueKey('opt_pick_all_layers'),
        label: tr('Todas las capas', 'All layers'),
        value: ts.pickAllLayers,
        onChanged: (v) => ts.set(() => ts.pickAllLayers = v),
      ),
      const VSep(),
      Text(tr('Muestra', 'Sample'), style: kTiny.copyWith(color: context.dim)),
      const SizedBox(width: 6),
      MiniDropdown<int>(
        key: const ValueKey('opt_pick_radius'),
        value: ts.pickRadius,
        items: const [
          (0, '1×1'),
          (1, '3×3'),
          (2, '5×5'),
          (5, '11×11'),
        ],
        tooltip: tr('Tamaño de muestra', 'Sample size'),
        onChanged: (v) => ts.set(() => ts.pickRadius = v),
      ),
    ];
  }

  List<Widget> _moveOptions(BuildContext context) {
    return [
      MiniToggle(
        key: const ValueKey('opt_move_auto_select'),
        label: tr('Selección automática', 'Auto-select'),
        value: ts.moveAutoSelect,
        onChanged: (v) => ts.set(() => ts.moveAutoSelect = v),
      ),
    ];
  }

  String _toolName(String id) => switch (id) {
        'hand' => tr('Mano', 'Hand'),
        'zoom' => tr('Lupa', 'Zoom'),
        'rotateView' => tr('Rotar vista', 'Rotate view'),
        _ => id,
      };
}
