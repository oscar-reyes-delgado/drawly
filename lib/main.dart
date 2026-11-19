import 'dart:ui';

import 'package:flutter/material.dart';

import 'app/app_state.dart';
import 'app/commands.dart';
import 'core/i18n.dart';
import 'ui/dialogs/prompts.dart';
import 'ui/easy/easy_shell.dart';
import 'ui/easy/mode_chooser.dart';
import 'ui/edit_commands.dart';
import 'ui/file_commands.dart';
import 'ui/interchange_commands.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  kCommandContributors..add(registerShellCommands)..add(registerFileCommands)..add(registerDialogCommands)..add(registerInterchangeCommands);
  await AppState.I.init();
  runApp(const DrawlyApp());
}

class DrawlyApp extends StatefulWidget {
  const DrawlyApp({super.key});

  @override
  State<DrawlyApp> createState() => _DrawlyAppState();
}

class _DrawlyAppState extends State<DrawlyApp> {
  late final AppLifecycleListener _lifecycle = AppLifecycleListener(onExitRequested: () => confirmAppExit(AppState.I));

  @override
  void initState() {
    super.initState();
    _lifecycle; // create it so window-close requests reach us
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppState.I;
    return ListenableBuilder(
      listenable: Listenable.merge([app.settings, I18n.instance]),
      builder: (context, _) => MaterialApp(
        title: 'Drawly',
        debugShowCheckedModeBanner: false,
        navigatorKey: app.navigatorKey,
        themeMode: app.settings.themeMode,
        theme: buildTheme(app.settings, Brightness.light),
        darkTheme: buildTheme(app.settings, Brightness.dark),
        home: switch (app.settings.uiMode) {
          'easy' => const EasyShell(),
          'advanced' => const Shell(),
          _ => const ModeChooser(),
        },
      ),
    );
  }
}

/// Asks before quitting when any open document has unsaved changes.
Future<AppExitResponse> confirmAppExit(AppState app) async {
  final dirty = app.docs.where((d) => d.dirty).toList();
  final ctx = app.context;
  if (dirty.isEmpty || ctx == null) return AppExitResponse.exit;
  final names = dirty.map((d) => '«${d.title}»').join(', ');
  final ok = await confirmDialog(
    ctx,
    title: tr('¿Salir sin guardar?', 'Quit without saving?'),
    message: tr('Hay cambios sin guardar en $names que se perderán.', 'There are unsaved changes in $names that will be lost.'),
    ok: tr('Salir sin guardar', 'Quit without saving'),
    danger: true,
  );
  return ok ? AppExitResponse.exit : AppExitResponse.cancel;
}
