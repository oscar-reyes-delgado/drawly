import 'package:flutter/material.dart';

import '../../app/app_state.dart';
import '../../core/i18n.dart';
import '../theme.dart';
import 'easy_shell.dart';

/// First start: asks once which interface to use. The choice can be changed
/// later from the menus and from the settings.
class ModeChooser extends StatelessWidget {
  const ModeChooser({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppState.I;
    Widget card(String mode, IconData icon, String title, String text) => ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Card(
            key: ValueKey('mode.$mode'),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => setUiMode(app, mode),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(icon, size: 40, color: context.cs.primary),
                  const SizedBox(height: 12),
                  Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Text(text, style: TextStyle(fontSize: 14, color: context.dim)),
                ]),
              ),
            ),
          ),
        );

    return Scaffold(
      backgroundColor: context.workspace,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('Drawly', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(tr('¿Cómo quieres empezar?', 'How do you want to start?'), style: TextStyle(fontSize: 16, color: context.dim)),
              const SizedBox(height: 24),
              Wrap(spacing: 16, runSpacing: 16, alignment: WrapAlignment.center, children: [
                card('easy', Icons.draw_outlined, tr('Modo Fácil', 'Easy mode'),
                    tr('Pocas herramientas y botones grandes. Dibuja y anima fotograma a fotograma en minutos.', 'Few tools and big buttons. Draw and animate frame by frame in minutes.')),
                card('advanced', Icons.tune, tr('Modo Avanzado', 'Advanced mode'),
                    tr('Todas las herramientas: pinceles, máscaras, efectos, vectores, huesos y más.', 'Every tool: brushes, masks, effects, vectors, bones and more.')),
              ]),
              const SizedBox(height: 16),
              Text(tr('Puedes cambiar de modo cuando quieras sin perder nada.', 'You can switch modes at any time without losing anything.'),
                  style: TextStyle(fontSize: 13, color: context.dim)),
            ]),
          ),
        ),
      ),
    );
  }
}
