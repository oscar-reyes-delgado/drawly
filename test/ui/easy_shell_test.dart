import 'package:drawly/app/app_state.dart';
import 'package:drawly/app/commands.dart';
import 'package:drawly/app/doc_layers.dart';
import 'package:drawly/app/doc_timeline.dart';
import 'package:drawly/app/easy_defaults.dart';
import 'package:drawly/main.dart';
import 'package:drawly/tools/registry.dart';
import 'package:drawly/ui/canvas/canvas_view.dart';
import 'package:drawly/ui/easy/easy_layers.dart';
import 'package:drawly/ui/easy/easy_shell.dart';
import 'package:drawly/ui/easy/easy_toolbar.dart';
import 'package:drawly/ui/easy/mode_chooser.dart';
import 'package:drawly/ui/shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void _setup(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final app = AppState.I;
  if (app.toolMap.isEmpty) {
    registerTools(app);
    kCommandContributors.add(registerShellCommands);
    registerCommands(app);
  }
  while (app.docs.isNotEmpty) {
    app.closeDocument(app.docs.first);
  }
}

void main() {
  testWidgets('first start asks for the mode; choosing Easy shows the easy shell', (tester) async {
    _setup(tester, const Size(1280, 800));
    AppState.I.settings.uiMode = '';
    await tester.pumpWidget(const DrawlyApp());
    await tester.pump();
    expect(find.byType(ModeChooser), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('mode.easy')));
    // no document: the home screen waits for the disk with a spinner, so no pumpAndSettle
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(EasyShell), findsOneWidget);
    expect(AppState.I.settings.uiMode, 'easy');
    await tester.pump(const Duration(milliseconds: 20)); // let thumbnail renders finish
  });

  testWidgets('switching modes keeps the same document, project and history', (tester) async {
    _setup(tester, const Size(1280, 800));
    final app = AppState.I;
    app.settings.uiMode = 'easy';
    final d = app.addDocument(easyProject(width: 64, height: 48), title: 'pelota');
    d.addPaintLayer(name: 'extra');
    final project = d.project;
    final steps = d.history.index;
    await tester.pumpWidget(const DrawlyApp());
    await tester.pump();
    expect(find.byType(EasyShell), findsOneWidget);
    expect(find.byType(CanvasView), findsOneWidget);
    for (final t in EasyTool.values) {
      expect(find.byKey(Key('easy.tool.${t.name}')), findsOneWidget);
    }
    expect(find.byType(EasyLayers), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('easy.menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('easy.toAdvanced')));
    await tester.pumpAndSettle();
    expect(find.byType(Shell), findsOneWidget);
    expect(app.doc, same(d));
    expect(d.project, same(project), reason: 'changing the interface never touches the project');
    expect(d.history.index, steps);

    await tester.tap(find.byKey(const ValueKey('to-easy')));
    await tester.pumpAndSettle();
    expect(find.byType(EasyShell), findsOneWidget);
    expect(d.project, same(project));
    await tester.pump(const Duration(milliseconds: 20)); // let thumbnail renders finish
  });

  testWidgets('easy mode: a quick Space tap plays and pauses', (tester) async {
    _setup(tester, const Size(1280, 800));
    final app = AppState.I;
    app.settings.uiMode = 'easy';
    final d = app.addDocument(easyProject(width: 64, height: 48), title: 'esp');
    d.setLength(4);
    await tester.pumpWidget(const DrawlyApp());
    await tester.pump();
    app.focusNode.requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    expect(app.playback.playing, isTrue);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    expect(app.playback.playing, isFalse);
    await tester.pump(const Duration(milliseconds: 20)); // let thumbnail renders finish
  });

  testWidgets('easy shell fits a phone: layers go to a drawer, no overflow', (tester) async {
    _setup(tester, const Size(390, 844));
    final app = AppState.I;
    app.settings.uiMode = 'easy';
    app.addDocument(easyProject(width: 64, height: 48), title: 'tel');
    await tester.pumpWidget(const DrawlyApp());
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('easy.openLayers')));
    await tester.pumpAndSettle();
    expect(find.text('Dibujo'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 20));
  });
}
