import 'package:flutter/material.dart';

import '../../app/settings.dart';
import '../../core/i18n.dart';
import '../theme.dart';

/// Short settings dialog for the easy mode. [onAdvancedMode] switches the
/// interface; [onRestartTutorial] starts the tutorial again.
Future<void> showEasyPrefs(BuildContext context, {required Settings settings, required VoidCallback onAdvancedMode, VoidCallback? onRestartTutorial}) =>
    showDialog<void>(
      context: context,
      builder: (ctx) => _EasyPrefs(settings: settings, onAdvancedMode: onAdvancedMode, onRestartTutorial: onRestartTutorial),
    );

class _EasyPrefs extends StatelessWidget {
  const _EasyPrefs({required this.settings, required this.onAdvancedMode, this.onRestartTutorial});
  final Settings settings;
  final VoidCallback onAdvancedMode;
  final VoidCallback? onRestartTutorial;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 440, maxHeight: size.height - 32),
        child: ListenableBuilder(
          listenable: settings,
          builder: (context, _) => Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 4),
              child: Row(children: [
                Expanded(child: Text(tr('Ajustes', 'Settings'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600))),
                IconButton(tooltip: tr('Cerrar', 'Close'), icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ]),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _rows(context)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  List<Widget> _rows(BuildContext context) {
    final s = settings;
    void up(void Function(Settings s) f) => s.update(f);

    Widget choices<T>(String label, T value, List<(T, String)> items, ValueChanged<T> onPick, {String? keyPrefix}) => _Row(
          label: label,
          child: Wrap(spacing: 6, runSpacing: 6, children: [
            for (final (v, text) in items)
              ChoiceChip(
                key: keyPrefix == null ? null : ValueKey('$keyPrefix.$text'),
                label: Text(text),
                selected: v == value,
                onSelected: (_) => onPick(v),
              ),
          ]),
        );

    Widget toggle(String label, bool value, ValueChanged<bool> onChanged, {Key? key}) => SizedBox(
          height: 52,
          child: Row(children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
            Switch(key: key, value: value, onChanged: onChanged),
          ]),
        );

    final sizes = const [(1920, 1080), (1080, 1080), (1080, 1920), (1280, 720)];
    final currentSize = (s.easyWidth, s.easyHeight);
    final gamma = s.pressureGamma;
    final pressure = (gamma - 0.6).abs() < 0.05 ? 0.6 : ((gamma - 1.6).abs() < 0.05 ? 1.6 : 1.0);
    return [
      choices<ThemeMode>(tr('Tema', 'Theme'), s.themeMode, [
        (ThemeMode.light, tr('Claro', 'Light')),
        (ThemeMode.dark, tr('Oscuro', 'Dark')),
        (ThemeMode.system, tr('Sistema', 'System')),
      ], (v) => up((x) => x.themeMode = v)),
      choices<String>(tr('Idioma', 'Language'), s.lang, const [('es', 'Español'), ('en', 'English'), ('pt', 'Português'), ('fr', 'Français')],
          (v) => up((x) => x.lang = v)),
      choices<(int, int)>(tr('Tamaño nuevo por defecto', 'Default new size'), currentSize, [for (final z in sizes) (z, '${z.$1}×${z.$2}')], (v) => up((x) {
            x.easyWidth = v.$1;
            x.easyHeight = v.$2;
          })),
      choices<int>(tr('Fotogramas por segundo', 'Frames per second'), s.easyFps, const [(8, '8'), (12, '12'), (24, '24')], (v) => up((x) => x.easyFps = v),
          keyPrefix: 'fps'),
      toggle(tr('Guardado automático', 'Autosave'), s.autosaveMinutes > 0, (v) => up((x) => x.autosaveMinutes = v ? 3 : 0),
          key: const ValueKey('prefs.autosave')),
      choices<double>(tr('Sensibilidad del lápiz', 'Pen sensitivity'), pressure, [
        (0.6, tr('Suave', 'Soft')),
        (1.0, tr('Normal', 'Normal')),
        (1.6, tr('Firme', 'Firm')),
      ], (v) => up((x) => x.pressureGamma = v)),
      toggle(tr('Dibujar con un dedo', 'Draw with one finger'), s.fingerDraws, (v) => up((x) => x.fingerDraws = v)),
      toggle(tr('Mostrar ayudas', 'Show hints'), s.easyHints, (v) => up((x) => x.easyHints = v)),
      if (onRestartTutorial != null)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () {
              Navigator.pop(context);
              onRestartTutorial!();
            },
            icon: const Icon(Icons.school_outlined),
            label: Text(tr('Repetir el tutorial', 'Replay the tutorial')),
          ),
        ),
      choices<double>(tr('Tamaño de la interfaz', 'Interface size'), s.uiScale, const [(1.0, '100 %'), (1.25, '125 %'), (1.5, '150 %')],
          (v) => up((x) => x.uiScale = v)),
      const SizedBox(height: 12),
      SizedBox(
        height: 48,
        child: OutlinedButton.icon(
          key: const ValueKey('prefs.toAdvanced'),
          onPressed: () {
            Navigator.pop(context);
            onAdvancedMode();
          },
          icon: const Icon(Icons.tune),
          label: Text(tr('Cambiar a Modo Avanzado', 'Switch to Advanced mode')),
        ),
      ),
    ];
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 13, color: context.dim)),
          const SizedBox(height: 6),
          child,
        ]),
      );
}
