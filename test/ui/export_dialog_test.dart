import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drawly/app/document_controller.dart';
import 'package:drawly/app/settings.dart';
import 'package:drawly/core/i18n.dart';
import 'package:drawly/io/image_export.dart';
import 'package:drawly/model/document.dart';
import 'package:drawly/ui/dialogs/export_dialog.dart';
import 'package:drawly/ui/theme.dart';

Future<ExportOptions?> _openDialog(
  WidgetTester tester,
  DocumentController doc, {
  ExportKind initial = ExportKind.still,
  required void Function(ExportOptions? result) onResult,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(Settings(), Brightness.dark),
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              final res = await showExportDialog(context, doc, initial: initial);
              onResult(res);
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('outputSize scales dimensions and clamps to at least 1', () {
    const half = ExportOptions(kind: ExportKind.still, scale: 0.5);
    expect(half.outputSize(320, 200), (width: 160, height: 100));

    const tiny = ExportOptions(kind: ExportKind.still, scale: 0.1);
    expect(tiny.outputSize(4, 3), (width: 1, height: 1));
  });

  test('frameCount and extension match kind and format', () {
    expect(const ExportOptions(kind: ExportKind.still, rangeStart: 2, rangeEnd: 8).frameCount, 1);
    expect(const ExportOptions(kind: ExportKind.svg, rangeStart: 2, rangeEnd: 8).frameCount, 1);
    expect(const ExportOptions(kind: ExportKind.animation, rangeStart: 2, rangeEnd: 8).frameCount, 6);
    expect(const ExportOptions(kind: ExportKind.sequence, rangeStart: 2, rangeEnd: 8).frameCount, 6);
    expect(const ExportOptions(kind: ExportKind.spriteSheet, rangeStart: 2, rangeEnd: 8).frameCount, 6);

    expect(const ExportOptions(kind: ExportKind.still, still: StillFormat.png).extension, 'png');
    expect(const ExportOptions(kind: ExportKind.still, still: StillFormat.jpg).extension, 'jpg');
    expect(const ExportOptions(kind: ExportKind.still, still: StillFormat.webp).extension, 'webp');
    expect(const ExportOptions(kind: ExportKind.animation, anim: AnimFormat.gif).extension, 'gif');
    expect(const ExportOptions(kind: ExportKind.animation, anim: AnimFormat.apng).extension, 'png');
    expect(const ExportOptions(kind: ExportKind.animation, anim: AnimFormat.webp).extension, 'webp');
    expect(const ExportOptions(kind: ExportKind.sequence).extension, 'png');
    expect(const ExportOptions(kind: ExportKind.spriteSheet).extension, 'png');
    expect(const ExportOptions(kind: ExportKind.svg).extension, 'svg');
  });

  testWidgets('choosing Animation and tapping Export returns timeline range', (tester) async {
    final project = Project.blank(width: 320, height: 200, frames: 24);
    final withRange = project.withComp(
      project.main.copyWith(timeline: project.main.timeline.copyWith(loopStart: 3, loopEnd: 15)),
    );
    final doc = DocumentController(withRange, title: 't');
    ExportOptions? result;

    await _openDialog(tester, doc, onResult: (r) => result = r);
    await tester.tap(find.text(tr('Animación', 'Animation')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(tr('Exportar', 'Export')).last);
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.kind, ExportKind.animation);
    expect(result!.rangeStart, 3);
    expect(result!.rangeEnd, 15);
  });

  testWidgets('quality slider appears for jpg and hides for png', (tester) async {
    final doc = DocumentController(Project.blank(width: 320, height: 200), title: 't');
    await _openDialog(tester, doc, onResult: (_) {});

    expect(find.text(tr('Calidad', 'Quality')), findsNothing);

    await tester.tap(find.text('PNG'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('JPG'));
    await tester.pumpAndSettle();

    expect(find.text(tr('Calidad', 'Quality')), findsOneWidget);
  });

  testWidgets('Cancel returns null', (tester) async {
    final doc = DocumentController(Project.blank(width: 320, height: 200), title: 't');
    ExportOptions? result = const ExportOptions(kind: ExportKind.still);

    await _openDialog(tester, doc, onResult: (r) => result = r);
    await tester.tap(find.text(tr('Cancelar', 'Cancel')));
    await tester.pumpAndSettle();

    expect(result, isNull);
  });

  testWidgets('tapping 50 % updates summary to 160 × 100', (tester) async {
    final doc = DocumentController(Project.blank(width: 320, height: 200), title: 't');
    await _openDialog(tester, doc, onResult: (_) {});

    await tester.tap(find.text('50 %'));
    await tester.pumpAndSettle();

    expect(find.textContaining('160 × 100'), findsOneWidget);
  });

  testWidgets('svg mode warns when active layer is not a vector layer', (tester) async {
    final doc = DocumentController(Project.blank(width: 320, height: 200), title: 't');
    await _openDialog(tester, doc, onResult: (_) {});

    await tester.tap(find.text('SVG'));
    await tester.pumpAndSettle();

    expect(find.text(tr('La capa activa no es vectorial', 'The active layer is not a vector layer')), findsOneWidget);
  });
}
