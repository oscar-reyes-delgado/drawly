import 'dart:io';

import 'package:drawly/app/app_state.dart';
import 'package:drawly/app/commands.dart';
import 'package:drawly/model/document.dart';
import 'package:drawly/model/filter_spec.dart';
import 'package:drawly/model/specs.dart';
import 'package:drawly/tools/registry.dart';
import 'package:drawly/ui/dialogs/command_palette.dart';
import 'package:drawly/ui/dialogs/export_dialog.dart';
import 'package:drawly/ui/dialogs/filter_dialog.dart';
import 'package:drawly/ui/dialogs/new_document.dart';
import 'package:drawly/ui/dialogs/prefs_dialog.dart';
import 'package:drawly/ui/dialogs/prompts.dart';
import 'package:drawly/ui/dialogs/text_dialog.dart';
import 'package:drawly/ui/shell.dart';
import 'package:drawly/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phone screens (portrait and landscape, large system text): the main window,
/// its panels and every dialog lay out without overflow. Uses the real Roboto
/// font from the Flutter SDK, since the default test font is much wider.
const _phones = [Size(412, 891), Size(891, 412)];

Future<bool> _loadRealFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) return false;
  final dir = '$root/bin/cache/artifacts/material_fonts';
  if (!File('$dir/roboto-regular.ttf').existsSync()) return false;
  ByteData read(String f) => ByteData.sublistView(File('$dir/$f').readAsBytesSync());
  final roboto = FontLoader('Roboto');
  for (final f in ['roboto-regular.ttf', 'roboto-medium.ttf', 'roboto-bold.ttf']) {
    roboto.addFont(Future.value(read(f)));
  }
  await roboto.load();
  await (FontLoader('MaterialIcons')..addFont(Future.value(read('materialicons-regular.otf')))).load();
  return true;
}

Widget _app(AppState app, Widget home) => MaterialApp(
      navigatorKey: app.navigatorKey,
      builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: const TextScaler.linear(1.3)), child: w!),
      theme: buildTheme(app.settings, Brightness.dark),
      home: home,
    );

/// Collects layout errors while [body] runs.
Future<List<String>> _errorsDuring(Future<void> Function() body) async {
  final errors = <String>[];
  final old = FlutterError.onError;
  FlutterError.onError = (d) => errors.add(d.exceptionAsString().split('\n').first);
  try {
    await body();
  } finally {
    FlutterError.onError = old;
  }
  return errors;
}

void main() {
  var realFonts = false;
  setUpAll(() async => realFonts = await _loadRealFonts());

  final app = AppState.I;
  void ensureApp() {
    if (app.toolMap.isEmpty) {
      registerTools(app);
      kCommandContributors.add(registerShellCommands);
      registerCommands(app);
    }
    if (app.doc == null) app.addDocument(Project.blank(width: 320, height: 200), title: 'phone');
  }

  for (final size in _phones) {
    testWidgets('main window, tools and side panels at $size', (tester) async {
      if (!realFonts) return markTestSkipped('Flutter SDK fonts not found');
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      ensureApp();
      Shell.timelineVisible.value = true;
      addTearDown(() => Shell.timelineVisible.value = null);
      final errors = await _errorsDuring(() async {
        await tester.pumpWidget(_app(app, const Shell()));
        await tester.pump();
        for (final id in kToolbarOrder) {
          app.setTool(id);
          await tester.pump();
        }
        app.setTool('brush');
        final open = find.byKey(const ValueKey('open-panels'));
        if (open.evaluate().isNotEmpty) {
          await tester.tap(open);
          await tester.pumpAndSettle();
        }
        for (final tab in ['Capas', 'Color', 'Pinceles', 'Propiedades']) {
          final t = find.widgetWithText(Tab, tab);
          await tester.ensureVisible(t);
          await tester.pumpAndSettle();
          await tester.tap(t);
          await tester.pumpAndSettle();
        }
      });
      expect(errors, isEmpty);
    });

    final dialogs = <String, void Function(BuildContext)>{
      'new document': (c) => showNewDocumentDialog(c),
      'export': (c) => showExportDialog(c, app.doc!),
      'preferences': (c) => showPrefsDialog(c),
      'canvas size': (c) => showCanvasSizeDialog(c, app.doc!.comp),
      'image size': (c) => showImageSizeDialog(c, app.doc!.comp),
      'text': (c) => showTextDialog(c, const TextSpec()),
      'command palette': (c) => showCommandPalette(c),
      'filter': (c) => showFilterDialog(c, app.doc!, kFilters.first.defaults),
    };
    for (final e in dialogs.entries) {
      testWidgets('${e.key} dialog at $size', (tester) async {
        if (!realFonts) return markTestSkipped('Flutter SDK fonts not found');
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        ensureApp();
        late BuildContext ctx;
        final errors = await _errorsDuring(() async {
          await tester.pumpWidget(_app(app, Builder(builder: (c) {
            ctx = c;
            return const Scaffold();
          })));
          e.value(ctx);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
        });
        expect(errors, isEmpty);
      });
    }
  }
}
