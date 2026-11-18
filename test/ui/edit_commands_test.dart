import 'package:drawly/app/app_state.dart';
import 'package:drawly/app/commands.dart';
import 'package:drawly/app/doc_selection.dart';
import 'package:drawly/app/doc_layers.dart';
import 'package:drawly/app/document_controller.dart';
import 'package:drawly/engine/tiles.dart';
import 'package:drawly/engine/vectorize.dart';
import 'package:drawly/model/document.dart';
import 'package:drawly/model/layer.dart';
import 'package:drawly/tools/registry.dart';
import 'package:drawly/ui/edit_commands.dart';
import 'package:drawly/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final app = AppState.I;
  registerTools(app);
  kCommandContributors.add(registerDialogCommands);
  registerCommands(app);

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    while (app.docs.isNotEmpty) {
      app.closeDocument(app.docs.first);
    }
    app.addDocument(Project.blank(width: 100, height: 80), title: 'cmd');
    await tester.pumpWidget(MaterialApp(navigatorKey: app.navigatorKey, theme: buildTheme(app.settings, Brightness.dark), home: const Scaffold(body: SizedBox())));
  }

  test('there is one filter command per filter and they live in the Filter menu', () {
    final filters = app.commands.all.where((c) => c.id.startsWith('filter.')).toList();
    expect(filters, isNotEmpty);
    expect(filters.every((c) => c.category == CommandCategory.filter), isTrue);
  });

  testWidgets('Save selection asks for a name and stores the selection', (tester) async {
    await pumpApp(tester);
    final d = app.doc!;
    expect(app.commands.byId('select.save')!.isEnabled, isFalse);
    d.selectRect(const Rect.fromLTWH(10, 10, 20, 20));
    expect(app.commands.run('select.save'), isTrue);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'cara');
    await tester.tap(find.widgetWithText(FilledButton, 'Aceptar'));
    await tester.pumpAndSettle();
    expect(d.comp.savedSelections.keys, ['cara']);
  });

  testWidgets('Canvas size applies the size chosen in the dialog', (tester) async {
    await pumpApp(tester);
    final d = app.doc!;
    expect(app.commands.run('image.canvasSize'), isTrue);
    await tester.pumpAndSettle();
    final width = find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)).first;
    await tester.enterText(width, '150');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Aplicar'));
    await tester.pumpAndSettle();
    expect([d.comp.width, d.comp.height], [150, 80]);
  });

  test('vectorizeLayer traces a red square into a new vector layer', () async {
    final d = DocumentController(Project.blank(width: 64, height: 64, background: null), title: 'v');
    final r = const Rect.fromLTWH(16, 16, 24, 24);
    d.addPaintLayer(pixels: TilePlane.empty.drawn((c) => c.drawRect(r, Paint()..color = const Color(0xFFFF0000)), area: r));
    final before = d.comp.layers.length;
    expect(await vectorizeLayer(d, const VectorizeOptions(smooth: false)), isTrue);
    expect(d.comp.layers.length, before + 1);
    final v = d.comp.layers.last as VectorLayer;
    final art = v.cels.at(0)!;
    expect(art.shapes, isNotEmpty);
    final bounds = art.shapes.map((s) => s.path.getBounds()).reduce((a, b) => a.expandToInclude(b));
    expect((bounds.left - 16).abs() < 1.5 && (bounds.right - 40).abs() < 1.5, isTrue, reason: '$bounds');
    d.dispose();
  });
}
