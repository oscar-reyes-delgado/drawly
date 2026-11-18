import 'package:drawly/app/app_state.dart';
import 'package:drawly/app/commands.dart';
import 'package:drawly/model/document.dart';
import 'package:drawly/tools/registry.dart';
import 'package:drawly/ui/edit_commands.dart';
import 'package:drawly/ui/file_commands.dart';
import 'package:drawly/ui/interchange_commands.dart';
import 'package:drawly/ui/menu_bar.dart';
import 'package:drawly/ui/shell.dart';
import 'package:drawly/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final app = AppState.I;
  registerTools(app);
  kCommandContributors..add(registerShellCommands)..add(registerFileCommands)..add(registerDialogCommands)..add(registerInterchangeCommands);
  registerCommands(app);

  test('every command of a menu category appears exactly once, with no stray dividers', () {
    for (final cat in kMenuOrder) {
      final entries = menuEntries(app.commands, cat);
      expect(entries.first, isNot('-'), reason: '$cat');
      expect(entries.last, isNot('-'), reason: '$cat');
      for (var i = 1; i < entries.length; i++) {
        expect(entries[i] == '-' && entries[i - 1] == '-', isFalse, reason: '$cat');
      }
      final ids = entries.where((e) => e != '-').toList();
      expect(ids.toSet().length, ids.length, reason: 'duplicates in $cat');
      final expected = {for (final c in app.commands.all) if (c.category == cat) c.id};
      expect(ids.toSet(), expected, reason: '$cat');
    }
  });

  test('no two commands share a default shortcut', () {
    final seen = <String, String>{};
    for (final c in app.commands.all) {
      for (final s in c.shortcut.split('|').where((s) => s.isNotEmpty)) {
        expect(seen[s], isNull, reason: '$s is used by ${seen[s]} and ${c.id}');
        seen[s] = c.id;
      }
    }
  });

  testWidgets('the File menu opens and lists Save with its shortcut', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    if (app.docs.isEmpty) app.addDocument(Project.blank(width: 64, height: 64), title: 'menu');

    await tester.pumpWidget(MaterialApp(theme: buildTheme(app.settings, Brightness.dark), home: const Scaffold(body: AppMenuBar())));
    await tester.tap(find.text('Archivo'));
    await tester.pumpAndSettle();
    expect(find.text('Guardar'), findsOneWidget);
    expect(find.text('Ctrl+S'), findsOneWidget);
  });
}
