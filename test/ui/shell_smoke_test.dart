import 'dart:ui' show AppExitResponse;

import 'package:drawly/app/app_state.dart';
import 'package:drawly/main.dart' show confirmAppExit;
import 'package:drawly/app/commands.dart';
import 'package:drawly/app/doc_layers.dart';
import 'package:drawly/core/mat2d.dart';
import 'package:drawly/engine/brush/tips.dart';
import 'package:drawly/engine/tiles.dart';
import 'package:drawly/model/layer.dart';
import 'package:drawly/model/document.dart';
import 'package:drawly/tools/registry.dart';
import 'package:drawly/ui/canvas/canvas_view.dart';
import 'package:drawly/ui/shell.dart';
import 'package:drawly/ui/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shell lays out canvas, panels and timeline with an open document', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final app = AppState.I;
    registerTools(app);
    kCommandContributors.add(registerShellCommands);
    registerCommands(app);
    app.addDocument(Project.blank(width: 320, height: 200), title: 'smoke');

    await tester.pumpWidget(MaterialApp(
      navigatorKey: app.navigatorKey,
      theme: buildTheme(app.settings, Brightness.dark),
      home: const Shell(),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);

    // every side tab builds without layout errors
    for (final tab in ['Color', 'Pinceles', 'Propiedades', 'Capas']) {
      final t = find.widgetWithText(Tab, tab);
      await tester.ensureVisible(t);
      await tester.pumpAndSettle();
      await tester.tap(t);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: tab);
    }

    // a command from the registry runs against the open document
    final before = app.doc!.comp.layers.length;
    expect(app.commands.run('layer.newPaint'), isTrue);
    await tester.pump();
    expect(app.doc!.comp.layers.length, before + 1);
    expect(app.commands.search('deshacer').first.id, 'edit.undo');
  });

  testWidgets('dragging on the canvas with the brush paints the active layer and is undoable', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final app = AppState.I;
    await tester.runAsync(() => BrushTips.instance.ensureLoaded());
    while (app.docs.isNotEmpty) {
      app.closeDocument(app.docs.first);
    }
    final d = app.addDocument(Project.blank(width: 320, height: 200), title: 'paint');
    d.addPaintLayer();
    app.setTool('brush');

    await tester.pumpWidget(MaterialApp(theme: buildTheme(app.settings, Brightness.dark), home: Scaffold(body: CanvasView(doc: d))));
    await tester.pump();
    await tester.pump();
    expect(d.view.zoom, greaterThan(0));

    final layerId = d.activeLayerId!;
    TilePlane plane() => (d.comp.layer(layerId)! as PaintLayer).cels.at(d.frame)!;
    expect(plane().keys, isEmpty);

    final center = tester.getCenter(find.byType(CanvasView));
    final g = await tester.startGesture(center - const Offset(60, 0), kind: PointerDeviceKind.mouse);
    for (var i = 1; i <= 12; i++) {
      await g.moveTo(center + Offset(-60 + i * 10.0, (i.isEven ? 4 : -4)));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump();

    expect(plane().keys, isNotEmpty, reason: 'the stroke must land on the layer');
    final pixels = await tester.runAsync(() => plane().readRgba(plane().bounds!.roundedOut));
    expect(pixels!.any((b) => b != 0), isTrue);

    d.undo();
    expect(plane().keys, isEmpty);
  });

  testWidgets('closing a document with unsaved changes asks first', (tester) async {
    final app = AppState.I;
    while (app.docs.isNotEmpty) {
      app.closeDocument(app.docs.first);
    }
    final d = app.addDocument(Project.blank(width: 64, height: 64), title: 'dirty');
    d.addPaintLayer();
    expect(d.dirty, isTrue);
    await tester.pumpWidget(MaterialApp(navigatorKey: app.navigatorKey, theme: buildTheme(app.settings, Brightness.dark), home: const Scaffold(body: SizedBox())));

    var closed = closeWithConfirm(app, d);
    await tester.pumpAndSettle();
    expect(find.text('¿Cerrar sin guardar?'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(await closed, isFalse);
    expect(app.docs, contains(d));

    closed = closeWithConfirm(app, d);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cerrar sin guardar'));
    await tester.pumpAndSettle();
    expect(await closed, isTrue);
    expect(app.docs, isNot(contains(d)));
  });

  testWidgets('quitting asks only when a document has unsaved changes', (tester) async {
    final app = AppState.I;
    while (app.docs.isNotEmpty) {
      app.closeDocument(app.docs.first);
    }
    await tester.pumpWidget(MaterialApp(navigatorKey: app.navigatorKey, theme: buildTheme(app.settings, Brightness.dark), home: const Scaffold(body: SizedBox())));
    expect(await confirmAppExit(app), AppExitResponse.exit);

    app.addDocument(Project.blank(width: 32, height: 32), title: 'unsaved').addPaintLayer();
    var r = confirmAppExit(app);
    await tester.pumpAndSettle();
    expect(find.text('¿Salir sin guardar?'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(await r, AppExitResponse.cancel);

    r = confirmAppExit(app);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salir sin guardar'));
    await tester.pumpAndSettle();
    expect(await r, AppExitResponse.exit);
  });
}
