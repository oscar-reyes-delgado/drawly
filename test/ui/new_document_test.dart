import 'package:drawly/app/app_state.dart';
import 'package:drawly/model/document.dart';
import 'package:drawly/model/layer.dart';
import 'package:drawly/ui/dialogs/new_document.dart';
import 'package:drawly/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the panel group builds a comic page with its panel layer', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    Project? result;
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(AppState.I.settings, Brightness.dark),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(onPressed: () async => result = await showNewDocumentDialog(context), child: const Text('open')),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Viñetas'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tpl-manga_4')));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    final comp = result!.main;
    expect([comp.width, comp.height], [2079, 2953]);
    final top = comp.layers.last;
    expect(top, isA<VectorLayer>());
    expect((top as VectorLayer).cels.at(0)!.shapes, hasLength(4));
    expect(comp.guides, hasLength(4));
  });
}
