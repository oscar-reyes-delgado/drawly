import 'package:flutter/material.dart';

import '../../app/app_state.dart';
import '../../core/i18n.dart';
import '../../model/specs.dart';
import '../theme.dart';
import '../widgets.dart';

/// Edits the content and style of a text layer. Returns null when cancelled.
Future<TextSpec?> showTextDialog(BuildContext context, TextSpec initial, {bool isNew = true}) =>
    showDialog<TextSpec>(context: context, builder: (_) => _TextDialog(initial, isNew));

class _TextDialog extends StatefulWidget {
  const _TextDialog(this.initial, this.isNew);
  final TextSpec initial;
  final bool isNew;

  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  late TextSpec _spec = widget.initial;
  late final TextEditingController _text = TextEditingController(text: widget.initial.text);

  static const List<String> _fonts = ['', 'Roboto', 'Arial', 'Times New Roman', 'Courier New', 'Georgia', 'Verdana', 'Comic Sans MS', 'Impact', 'Segoe UI', 'Segoe Script'];

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _set(TextSpec s) => setState(() => _spec = s);

  @override
  Widget build(BuildContext context) {
    final s = _spec;
    final ts = AppState.I.ts;
    return AlertDialog(
      title: Text(widget.isNew ? tr('Nuevo texto', 'New text') : tr('Editar texto', 'Edit text'), style: const TextStyle(fontSize: 18)),
      contentPadding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(
              controller: _text,
              autofocus: true,
              minLines: 3,
              maxLines: 7,
              style: TextStyle(fontSize: 15, fontFamily: s.font.isEmpty ? null : s.font, fontWeight: s.bold ? FontWeight.bold : null, fontStyle: s.italic ? FontStyle.italic : null),
              decoration: InputDecoration(hintText: tr('Escribe aquí…', 'Type here…')),
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              MiniDropdown<String>(
                value: _fonts.contains(s.font) ? s.font : '',
                width: 170,
                tooltip: tr('Tipografía', 'Typeface'),
                items: [for (final f in _fonts) (f, f.isEmpty ? tr('Predeterminada', 'Default') : f)],
                onChanged: (f) => _set(s.copyWith(font: f)),
              ),
              NumField(value: s.size, min: 4, max: 2000, width: 84, suffix: 'px', onSubmitted: (v) => _set(s.copyWith(size: v))),
              PanelButton(icon: Icons.format_bold, tooltip: tr('Negrita', 'Bold'), selected: s.bold, onTap: () => _set(s.copyWith(bold: !s.bold))),
              PanelButton(icon: Icons.format_italic, tooltip: tr('Cursiva', 'Italic'), selected: s.italic, onTap: () => _set(s.copyWith(italic: !s.italic))),
              PanelButton(icon: Icons.format_underlined, tooltip: tr('Subrayado', 'Underline'), selected: s.underline, onTap: () => _set(s.copyWith(underline: !s.underline))),
              const VSep(),
              PanelButton(icon: Icons.format_align_left, tooltip: tr('Izquierda', 'Left'), selected: s.align == 0, onTap: () => _set(s.copyWith(align: 0))),
              PanelButton(icon: Icons.format_align_center, tooltip: tr('Centro', 'Centre'), selected: s.align == 1, onTap: () => _set(s.copyWith(align: 1))),
              PanelButton(icon: Icons.format_align_right, tooltip: tr('Derecha', 'Right'), selected: s.align == 2, onTap: () => _set(s.copyWith(align: 2))),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Text(tr('Color', 'Colour'), style: kSmall.copyWith(color: context.dim)),
              const SizedBox(width: 8),
              Swatch(color: s.color, size: 24, tooltip: tr('Usar el color frontal', 'Use the foreground colour'), onTap: () => _set(s.copyWith(color: ts.fg))),
              const SizedBox(width: 20),
              Text(tr('Contorno', 'Outline'), style: kSmall.copyWith(color: context.dim)),
              const SizedBox(width: 8),
              Swatch(color: s.strokeColor, size: 24, tooltip: tr('Usar el color de fondo', 'Use the background colour'), onTap: () => _set(s.copyWith(strokeColor: ts.bg))),
              const SizedBox(width: 8),
              Expanded(child: MiniSlider(label: '', value: s.strokeWidth, min: 0, max: 40, suffix: ' px', onChanged: (v) => _set(s.copyWith(strokeWidth: v.roundToDouble())))),
            ]),
            MiniSlider(label: tr('Espaciado', 'Spacing'), value: s.letterSpacing, min: -10, max: 60, width: 480, suffix: ' px', onChanged: (v) => _set(s.copyWith(letterSpacing: v.roundToDouble()))),
            MiniSlider(label: tr('Interlineado', 'Line height'), value: s.lineHeight, min: 0.6, max: 3, decimals: 2, width: 480, onChanged: (v) => _set(s.copyWith(lineHeight: v))),
            MiniSlider(
              label: tr('Ancho de caja (0 = sin ajuste)', 'Box width (0 = no wrap)'),
              value: s.boxWidth,
              min: 0,
              max: 4000,
              width: 480,
              suffix: ' px',
              onChanged: (v) => _set(s.copyWith(boxWidth: v.roundToDouble())),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Text(tr('Animación', 'Animation'), style: kSmall.copyWith(color: context.dim)),
              const SizedBox(width: 8),
              MiniDropdown<TextAnimKind>(value: s.anim, width: 170, items: [for (final a in TextAnimKind.values) (a, a.label)], onChanged: (a) => _set(s.copyWith(anim: a))),
              const SizedBox(width: 8),
              if (s.anim != TextAnimKind.none)
                MiniDropdown<TextUnit>(
                  value: s.animUnit,
                  width: 120,
                  items: [(TextUnit.letter, tr('Por letra', 'By letter')), (TextUnit.word, tr('Por palabra', 'By word')), (TextUnit.line, tr('Por línea', 'By line'))],
                  onChanged: (u) => _set(s.copyWith(animUnit: u)),
                ),
            ]),
            if (s.anim != TextAnimKind.none) ...[
              MiniSlider(label: tr('Retardo entre unidades', 'Delay between units'), value: s.animStagger, min: 0, max: 24, decimals: 1, width: 480, suffix: ' f', onChanged: (v) => _set(s.copyWith(animStagger: v))),
              MiniSlider(label: tr('Duración por unidad', 'Duration per unit'), value: s.animDuration, min: 1, max: 60, width: 480, suffix: ' f', onChanged: (v) => _set(s.copyWith(animDuration: v.roundToDouble()))),
              MiniSlider(label: tr('Cantidad', 'Amount'), value: s.animAmount, min: 0, max: 200, width: 480, onChanged: (v) => _set(s.copyWith(animAmount: v.roundToDouble()))),
            ],
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Cancelar', 'Cancel'))),
        FilledButton(onPressed: () => Navigator.pop(context, _spec.copyWith(text: _text.text)), child: Text(tr('Aceptar', 'OK'))),
      ],
    );
  }
}
