import 'package:drawly/app/app_state.dart';
import 'package:drawly/app/commands.dart';
import 'package:drawly/model/document.dart';
import 'package:drawly/tools/registry.dart';
import 'package:drawly/ui/canvas/canvas_view.dart';
import 'package:drawly/ui/shell.dart';
import 'package:drawly/ui/theme.dart';
import 'package:drawly/ui/timeline/timeline_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pumpShell(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final app = AppState.I;
  if (app.toolMap.isEmpty) {
    registerTools(app);
    kCommandContributors.add(registerShellCommands);
    registerCommands(app);
  }
  app.addDocument(Project.blank(width: 320, height: 200), title: 'm');
  Shell.timelineVisible.value = null;
  await tester.pumpWidget(MaterialApp(navigatorKey: app.navigatorKey, theme: buildTheme(app.settings, Brightness.dark), home: const Shell()));
  await tester.pump();
}

void main() {
  testWidgets('on a phone in portrait the side panels go to a drawer and nothing overflows', (tester) async {
    await _pumpShell(tester, const Size(390, 844));
    expect(tester.takeException(), isNull);
    expect(find.byType(SidePanels), findsNothing);
    expect(tester.getSize(find.byType(CanvasView)).width, greaterThan(300), reason: 'the canvas gets the width');

    await tester.tap(find.byKey(const ValueKey('open-panels')));
    await tester.pumpAndSettle();
    expect(find.byType(SidePanels), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the timeline can be hidden and shown, and hides itself on short screens', (tester) async {
    await _pumpShell(tester, const Size(390, 844));
    expect(find.byType(TimelinePanel), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('toggle-timeline')));
    await tester.pump();
    expect(find.byType(TimelinePanel), findsNothing);

    await _pumpShell(tester, const Size(844, 390));
    expect(tester.takeException(), isNull);
    expect(find.byType(TimelinePanel), findsNothing);
    expect(find.byType(SidePanels), findsOneWidget, reason: 'wide enough for the side panels');
    await tester.tap(find.byKey(const ValueKey('toggle-timeline')));
    await tester.pump();
    expect(find.byType(TimelinePanel), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a tablet in portrait lays out without overflow', (tester) async {
    await _pumpShell(tester, const Size(820, 1180));
    expect(tester.takeException(), isNull);
    expect(find.byType(SidePanels), findsOneWidget);
  });
}
