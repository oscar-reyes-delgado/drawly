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
import 'package:drawly/ui/easy/easy_timeline.dart';
import 'package:drawly/ui/library/animation_player.dart';
import 'package:drawly/ui/library/library_page.dart';
import 'package:drawly/ui/easy/easy_toolbar.dart';
import 'package:drawly/ui/easy/mode_chooser.dart';
import 'package:drawly/ui/shell.dart';
import 'package:drawly/ui/timeline/timeline_panel.dart';
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

  testWidgets('tools column and frame strip fold and unfold, and remember it', (tester) async {
    _setup(tester, const Size(1280, 800));
    final app = AppState.I;
    app.settings
      ..uiMode = 'easy'
      ..tutorialDone = true
      ..panelVisible = {};
    addTearDown(() => app.settings.tutorialDone = false);
    final d = app.addDocument(easyProject(width: 64, height: 48), title: 'fold');
    await tester.pumpWidget(const DrawlyApp());
    await tester.pump();
    expect(find.byType(EasyToolbar), findsOneWidget);
    expect(find.byType(EasyTimeline), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('easy.tools.toggle')));
    await tester.pumpAndSettle();
    expect(find.byType(EasyToolbar), findsNothing);
    expect(app.settings.panelVisible['easy.tools'], isFalse);

    await tester.tap(find.byKey(const ValueKey('easy.timeline.toggle')), warnIfMissed: true);
    await tester.pump(const Duration(milliseconds: 300));
    expect(app.settings.panelVisible['easy.timeline'], isFalse);
    expect(find.byType(EasyTimeline), findsNothing);
    await tester.tap(find.byKey(const ValueKey('easy.mini.add')));
    await tester.pump();
    expect(d.timeline.length, 2, reason: 'the folded bar still adds frames');
    expect(find.text('2 / 2'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('easy.tools.toggle')));
    await tester.tap(find.byKey(const ValueKey('easy.timeline.toggle')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(EasyToolbar), findsOneWidget);
    expect(find.byType(EasyTimeline), findsOneWidget);
    app.settings.panelVisible = {};
    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('watch button plays the document full screen in both modes; advanced opens the library', (tester) async {
    _setup(tester, const Size(1280, 800));
    final app = AppState.I;
    app.settings
      ..uiMode = 'easy'
      ..tutorialDone = true;
    addTearDown(() => app.settings.tutorialDone = false);
    app.addDocument(easyProject(width: 64, height: 48), title: 'ver');
    await tester.pumpWidget(const DrawlyApp());
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('easy.watch')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(AnimationPlayerPage), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('player.close')));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 200)); // the player fades out while still ticking
    }

    app.settings.update((s) => s.uiMode = 'advanced');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('watch-animation')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(AnimationPlayerPage), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('player.close')));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 200)); // the player fades out while still ticking
    }

    await tester.tap(find.byKey(const ValueKey('open-library')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(ProjectLibraryView), findsOneWidget);
    app.settings.uiMode = 'easy';
  });

  testWidgets('the frame viewer can be enlarged and resized in both modes', (tester) async {
    _setup(tester, const Size(1280, 800));
    final app = AppState.I;
    app.settings
      ..uiMode = 'easy'
      ..tutorialDone = true
      ..panelVisible = {}
      ..easyTimelineHeight = 0
      ..advTimelineHeight = 0;
    addTearDown(() => app.settings
      ..tutorialDone = false
      ..easyTimelineHeight = 0
      ..advTimelineHeight = 0);
    app.addDocument(easyProject(width: 64, height: 48), title: 'grande');
    await tester.pumpWidget(const DrawlyApp());
    await tester.pump();
    final normal = tester.getSize(find.byType(EasyTimeline)).height;
    await tester.tap(find.byKey(const ValueKey('easy.timeline.expand')));
    await tester.pump(const Duration(milliseconds: 50));
    final big = tester.getSize(find.byType(EasyTimeline)).height;
    expect(big, greaterThan(normal * 2), reason: 'expand makes the frames much bigger');
    await tester.tap(find.byKey(const ValueKey('easy.timeline.expand')));
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.getSize(find.byType(EasyTimeline)).height, closeTo(normal, 1));
    await tester.drag(find.byKey(const ValueKey('easy.timeline.resize')), const Offset(0, -60));
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.getSize(find.byType(EasyTimeline)).height, closeTo(normal + 60, 25), reason: 'dragging up makes it taller');
    expect(app.settings.easyTimelineHeight, greaterThan(normal));

    app.settings.update((s) => s.uiMode = 'advanced');
    await tester.pump(const Duration(milliseconds: 300));
    final advNormal = tester.getSize(find.byType(TimelinePanel)).height;
    await tester.tap(find.byKey(const ValueKey('maximize-timeline')));
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.getSize(find.byType(TimelinePanel)).height, greaterThan(advNormal * 2));
    expect(tester.takeException(), isNull, reason: 'the side panels still fit');
    await tester.drag(find.byKey(const ValueKey('timeline-resize')), const Offset(0, 100));
    await tester.pump(const Duration(milliseconds: 50));
    expect(app.settings.advTimelineHeight, greaterThan(advNormal));
    expect(tester.takeException(), isNull);
    app.settings.uiMode = 'easy';
    await tester.pump(const Duration(milliseconds: 20));
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
