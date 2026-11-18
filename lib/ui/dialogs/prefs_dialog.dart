import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_state.dart';
import '../../app/commands.dart';
import '../../app/key_combo.dart';
import '../../app/settings.dart';
import '../../core/color_utils.dart';
import '../../core/i18n.dart';
import '../theme.dart';
import '../widgets.dart';

Future<void> showPrefsDialog(BuildContext context) => showDialog<void>(context: context, builder: (_) => const _PrefsDialog());

class _PrefsDialog extends StatefulWidget {
  const _PrefsDialog();

  @override
  State<_PrefsDialog> createState() => _PrefsDialogState();
}

class _PrefsDialogState extends State<_PrefsDialog> {
  int _tab = 0;
  String _filter = '';
  String? _capturing;

  Settings get s => AppState.I.settings;

  void _up(void Function(Settings s) f) => setState(() => s.update(f));

  Widget _row(String label, Widget control, {String? help}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: kSmall),
              if (help != null) Text(help, style: kTiny.copyWith(color: context.dim)),
            ]),
          ),
          const SizedBox(width: 12),
          control,
        ]),
      );

  Widget _switch(String label, bool value, void Function(Settings s, bool v) set, {String? help}) =>
      _row(label, Switch(value: value, onChanged: (v) => _up((x) => set(x, v))), help: help);

  Widget _general() => Column(children: [
        _row(
          tr('Tema', 'Theme'),
          MiniDropdown<ThemeMode>(
            value: s.themeMode,
            width: 150,
            items: [(ThemeMode.dark, tr('Oscuro', 'Dark')), (ThemeMode.light, tr('Claro', 'Light')), (ThemeMode.system, tr('Del sistema', 'System'))],
            onChanged: (v) => _up((x) => x.themeMode = v),
          ),
        ),
        _row(
          tr('Idioma', 'Language'),
          MiniDropdown<String>(value: s.lang, width: 150, items: [for (final l in I18n.languages) (l.$1, l.$2)], onChanged: (v) => _up((x) => x.lang = v)),
        ),
        _row(
          tr('Escala de la interfaz', 'Interface scale'),
          MiniDropdown<double>(
            value: s.uiScale,
            width: 150,
            items: const [(0.85, '85 %'), (1.0, '100 %'), (1.15, '115 %'), (1.3, '130 %'), (1.5, '150 %'), (1.75, '175 %'), (2.0, '200 %')],
            onChanged: (v) => _up((x) => x.uiScale = v),
          ),
        ),
        _row(
          tr('Color de acento', 'Accent colour'),
          Row(mainAxisSize: MainAxisSize.min, children: [
            for (final c in const [0xFF4F8CFF, 0xFF7C5CFF, 0xFFE0559B, 0xFFEF6C3A, 0xFFE0A21B, 0xFF2EAD6B, 0xFF19A7B8])
              Padding(
                padding: const EdgeInsets.only(left: 5),
                child: Swatch(color: Color(c), size: 22, radius: 11, selected: s.accent.toARGB32() == c, onTap: () => _up((x) => x.accent = Color(c))),
              ),
          ]),
        ),
        _switch(tr('Modo zurdo', 'Left-handed mode'), s.leftHanded, (x, v) => x.leftHanded = v, help: tr('Coloca las herramientas a la derecha', 'Places the tools on the right')),
        _switch(tr('Alto contraste', 'High contrast'), s.highContrast, (x, v) => x.highContrast = v),
        _row(
          tr('Simular daltonismo', 'Simulate colour blindness'),
          MiniDropdown<ColorBlindness>(
            value: s.colorBlind,
            width: 150,
            items: [
              (ColorBlindness.none, tr('Ninguno', 'None')),
              (ColorBlindness.protanopia, tr('Protanopía', 'Protanopia')),
              (ColorBlindness.deuteranopia, tr('Deuteranopía', 'Deuteranopia')),
              (ColorBlindness.tritanopia, tr('Tritanopía', 'Tritanopia')),
              (ColorBlindness.achromatopsia, tr('Acromatopsia', 'Achromatopsia')),
            ],
            onChanged: (v) => _up((x) => x.colorBlind = v),
          ),
        ),
        _switch(tr('Reducir animaciones', 'Reduce motion'), s.reduceMotion, (x, v) => x.reduceMotion = v),
        _switch(tr('Mostrar consejos', 'Show tips'), s.showTips, (x, v) => x.showTips = v),
      ]);

  Widget _input() => Column(children: [
        _switch(tr('Simular presión con ratón o dedo', 'Simulate pressure with mouse or finger'), s.simulatePressure, (x, v) => x.simulatePressure = v,
            help: tr('Los trazos rápidos salen más finos', 'Fast strokes come out thinner')),
        _switch(tr('Dibujar con un dedo', 'Draw with one finger'), s.fingerDraws, (x, v) => x.fingerDraws = v,
            help: tr('Desactívalo para dibujar solo con lápiz y mover con el dedo', 'Turn off to draw with the stylus only and pan with a finger')),
        _switch(tr('Dos dedos: deshacer · Tres dedos: rehacer', 'Two-finger tap: undo · Three: redo'), s.twoFingerUndo, (x, v) => x.twoFingerUndo = v),
        _switch(tr('La rueda del ratón hace zoom', 'Mouse wheel zooms'), s.wheelZooms, (x, v) => x.wheelZooms = v, help: tr('Con Ctrl se invierte', 'Ctrl inverts it')),
        _row(
          tr('Curva de presión del lápiz', 'Pen pressure curve'),
          MiniSlider(label: '', value: s.pressureGamma, min: 0.3, max: 3, decimals: 2, width: 210, onChanged: (v) => _up((x) => x.pressureGamma = v)),
          help: tr('Menos de 1: más suave · Más de 1: más firme', 'Below 1: softer · Above 1: firmer'),
        ),
        _switch(tr('Teclas adhesivas', 'Sticky keys'), s.stickyKeys, (x, v) => x.stickyKeys = v),
        const Divider(height: 22),
        _row(
          tr('Pasos de deshacer (0 = sin límite)', 'Undo steps (0 = unlimited)'),
          NumField(value: s.historyLimit.toDouble(), min: 0, max: 5000, onSubmitted: (v) => _up((x) => x.historyLimit = v.round())),
        ),
        _switch(tr('Historial no lineal', 'Non-linear history'), s.nonLinearHistory, (x, v) => x.nonLinearHistory = v,
            help: tr('Conserva los pasos posteriores al editar desde un estado anterior', 'Keeps later steps when editing from an earlier state')),
        _row(
          tr('Autoguardado (minutos, 0 = no)', 'Autosave (minutes, 0 = off)'),
          NumField(value: s.autosaveMinutes.toDouble(), min: 0, max: 120, onSubmitted: (v) => _up((x) => x.autosaveMinutes = v.round())),
        ),
        _switch(tr('Reproducir a baja resolución', 'Low-resolution playback'), s.lowResPlayback, (x, v) => x.lowResPlayback = v),
        _row(
          tr('Caché de fotogramas (MB)', 'Frame cache (MB)'),
          NumField(value: s.frameCacheMb.toDouble(), min: 64, max: 8192, onSubmitted: (v) => _up((x) => x.frameCacheMb = v.round())),
        ),
        const Divider(height: 22),
        _switch(tr('Marca de agua al exportar', 'Watermark on export'), s.watermarkEnabled, (x, v) => x.watermarkEnabled = v),
        if (s.watermarkEnabled)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: TextFormField(
              initialValue: s.watermark,
              style: kSmall,
              decoration: InputDecoration(labelText: tr('Texto de la marca de agua', 'Watermark text')),
              onChanged: (v) => s.update((x) => x.watermark = v),
            ),
          ),
      ]);

  Widget _shortcuts() {
    final reg = AppState.I.commands;
    final q = _filter.toLowerCase();
    final list = reg.all.where((c) => q.isEmpty || c.label().toLowerCase().contains(q) || reg.shortcutOf(c.id).toLowerCase().contains(q)).toList();
    return Column(children: [
      Row(children: [
        Expanded(
          child: TextField(
            style: kSmall,
            decoration: InputDecoration(prefixIcon: const Icon(Icons.search, size: 16), hintText: tr('Buscar comando o atajo…', 'Search command or shortcut…')),
            onChanged: (v) => setState(() => _filter = v),
          ),
        ),
        const SizedBox(width: 8),
        TextButton(
          onPressed: () => _up((x) {
            x.shortcuts = {};
            reg.invalidateShortcuts();
          }),
          child: Text(tr('Restablecer todos', 'Reset all'), style: kSmall),
        ),
      ]),
      const SizedBox(height: 8),
      SizedBox(
        height: 360,
        child: ListView.builder(
          itemExtent: 32,
          itemCount: list.length,
          itemBuilder: (_, i) {
            final c = list[i];
            final key = reg.shortcutOf(c.id);
            final custom = s.shortcuts.containsKey(c.id);
            final capturing = _capturing == c.id;
            return Row(children: [
              SizedBox(width: 90, child: Text(commandCategoryLabel(c.category), style: kTiny.copyWith(color: context.dim), overflow: TextOverflow.ellipsis)),
              Expanded(child: Text(c.label(), style: kSmall, overflow: TextOverflow.ellipsis)),
              if (custom)
                PanelButton(
                  icon: Icons.undo,
                  size: 24,
                  iconSize: 14,
                  tooltip: tr('Volver al predeterminado', 'Back to default'),
                  onTap: () => _up((x) {
                    x.shortcuts = {...x.shortcuts}..remove(c.id);
                    reg.invalidateShortcuts();
                  }),
                ),
              _KeyCapture(
                text: capturing ? tr('Pulsa las teclas…', 'Press the keys…') : (key.isEmpty ? '—' : key.split('|').first),
                active: capturing,
                highlighted: custom,
                onStart: () => setState(() => _capturing = c.id),
                onCancel: () => setState(() => _capturing = null),
                onCaptured: (combo) => _up((x) {
                  x.shortcuts = {...x.shortcuts, c.id: combo == null ? '' : combo.toString()};
                  reg.invalidateShortcuts();
                  _capturing = null;
                }),
              ),
            ]);
          },
        ),
      ),
      Text(tr('Clic en un atajo para cambiarlo · Retroceso lo quita · Esc cancela', 'Click a shortcut to change it · Backspace clears it · Esc cancels'), style: kTiny.copyWith(color: context.dim)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final tabs = [tr('General', 'General'), tr('Entrada y rendimiento', 'Input & performance'), tr('Atajos de teclado', 'Keyboard shortcuts')];
    return AlertDialog(
      title: Text(tr('Preferencias', 'Preferences'), style: const TextStyle(fontSize: 18)),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      content: SizedBox(
        width: 560,
        height: 470,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            for (var i = 0; i < tabs.length; i++)
              Padding(padding: const EdgeInsets.only(right: 6), child: MiniToggle(label: tabs[i], value: _tab == i, onChanged: (_) => setState(() => _tab = i))),
          ]),
          const SizedBox(height: 12),
          Expanded(child: _tab == 2 ? _shortcuts() : SingleChildScrollView(child: _tab == 0 ? _general() : _input())),
        ]),
      ),
      actions: [FilledButton(onPressed: () => Navigator.pop(context), child: Text(tr('Cerrar', 'Close')))],
    );
  }
}

class _KeyCapture extends StatefulWidget {
  const _KeyCapture({required this.text, required this.active, required this.highlighted, required this.onStart, required this.onCancel, required this.onCaptured});
  final String text;
  final bool active, highlighted;
  final VoidCallback onStart, onCancel;
  final ValueChanged<KeyCombo?> onCaptured;

  @override
  State<_KeyCapture> createState() => _KeyCaptureState();
}

class _KeyCaptureState extends State<_KeyCapture> {
  final FocusNode _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Focus(
      focusNode: _focus,
      onKeyEvent: (_, e) {
        if (!widget.active || e is! KeyDownEvent) return KeyEventResult.ignored;
        if (e.logicalKey == LogicalKeyboardKey.escape) {
          widget.onCancel();
          return KeyEventResult.handled;
        }
        if (e.logicalKey == LogicalKeyboardKey.backspace) {
          widget.onCaptured(null);
          return KeyEventResult.handled;
        }
        final combo = KeyCombo.fromEvent(e);
        if (combo == null) return KeyEventResult.handled;
        widget.onCaptured(combo);
        return KeyEventResult.handled;
      },
      child: GestureDetector(
        onTap: () {
          _focus.requestFocus();
          widget.onStart();
        },
        child: Container(
          width: 150,
          height: 24,
          alignment: Alignment.center,
          margin: const EdgeInsets.only(left: 6),
          decoration: BoxDecoration(
            color: widget.active ? cs.primary.withValues(alpha: 0.2) : cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: widget.active ? cs.primary : Colors.transparent),
          ),
          child: Text(widget.text, style: kTiny.copyWith(color: widget.highlighted ? cs.primary : cs.onSurface), overflow: TextOverflow.ellipsis),
        ),
      ),
    );
  }
}
