import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drawly/app/doc_layers.dart';
import 'package:drawly/app/document_controller.dart';
import 'package:drawly/app/easy_defaults.dart';
import 'package:drawly/app/settings.dart';
import 'package:drawly/core/i18n.dart';
import 'package:drawly/engine/rig.dart';
import 'package:drawly/engine/tiles.dart';
import 'package:drawly/model/layer.dart';
import 'package:drawly/model/layer_fx.dart';
import 'package:drawly/model/specs.dart';
import 'package:drawly/ui/easy/easy_layers.dart';
import 'package:drawly/ui/theme.dart';

Future<void> _pumpLayers(WidgetTester tester, DocumentController doc, {double width = 320, double height = 560}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(Settings(), Brightness.dark),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            height: height,
            child: EasyLayers(doc: doc),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DocumentController doc;

  setUp(() {
    doc = DocumentController(easyProject(width: 64, height: 48), title: 't');
  });

  tearDown(() => doc.dispose());

  testWidgets('shows Drawing above Background in top-to-bottom order and Drawing is active', (tester) async {
    await _pumpLayers(tester, doc);

    final drawingName = tr('Dibujo', 'Drawing');
    final bgName = tr('Fondo', 'Background');

    expect(find.text(drawingName), findsOneWidget);
    expect(find.text(bgName), findsOneWidget);

    final drawingDy = tester.getTopLeft(find.text(drawingName)).dy;
    final bgDy = tester.getTopLeft(find.text(bgName)).dy;
    expect(drawingDy, lessThan(bgDy));

    final drawingLayer = doc.comp.layers.last;
    expect(doc.activeLayerId, drawingLayer.id);
    expect(tester.getSize(find.byKey(ValueKey('easy.layer.${drawingLayer.id}'))).height, 56);
  });

  testWidgets('tapping eye on Background hides it and undo restores visibility', (tester) async {
    await _pumpLayers(tester, doc);

    final bgLayer = doc.comp.layers.first;
    expect(bgLayer.props.visible, isTrue);

    await tester.tap(find.byKey(Key('easy.layer.visibility.${bgLayer.id}')));
    await tester.pumpAndSettle();
    expect(doc.comp.layer(bgLayer.id)!.props.visible, isFalse);

    doc.undo();
    await tester.pumpAndSettle();
    expect(doc.comp.layer(bgLayer.id)!.props.visible, isTrue);
  });

  testWidgets('new layer adds on top, delete with confirmation removes it, and delete is disabled with one layer', (tester) async {
    await _pumpLayers(tester, doc);
    expect(doc.comp.layers.length, 2);

    await tester.tap(find.byKey(const Key('easy.layers.add')));
    await tester.pumpAndSettle();
    expect(doc.comp.layers.length, 3);
    final added = doc.comp.layers.last;
    expect(doc.activeLayerId, added.id);

    // Delete added layer with confirmation
    await tester.tap(find.byKey(const Key('easy.layers.delete')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text(tr('Eliminar', 'Delete')));
    await tester.pumpAndSettle();
    expect(doc.comp.layers.length, 2);

    // Delete remaining top layer so only 1 layer remains
    await tester.tap(find.byKey(const Key('easy.layers.delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(tr('Eliminar', 'Delete')));
    await tester.pumpAndSettle();
    expect(doc.comp.layers.length, 1);

    // Now delete button is disabled: tapping does not open confirmation dialog
    await tester.tap(find.byKey(const Key('easy.layers.delete')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(doc.comp.layers.length, 1);
  });

  testWidgets('TextLayer shows advanced badge with disabled lock and isEasyEditable matches rules', (tester) async {
    final drawing = doc.comp.layers.last;
    expect(isEasyEditable(drawing), isTrue);

    doc.addTextLayer(const TextSpec(text: 'Hola'));
    final textLayer = doc.comp.layers.last;
    expect(isEasyEditable(textLayer), isFalse);

    // Extra checks on PaintLayer restrictions
    final masked = (drawing as PaintLayer).withProps(drawing.props.copyWith(mask: TilePlane.empty));
    final withFx = drawing.withProps(drawing.props.copyWith(fx: const LayerFx(shadow: true)));
    final withRig = drawing.withRig(const LayerRig(skeleton: Skeleton([Bone(id: 'b1', name: 'B1', head: Offset.zero, tail: Offset(10, 0))])));
    final withParent = drawing.withProps(drawing.props.copyWith(parentId: 'other'));
    final withBlend = drawing.withProps(drawing.props.copyWith(blend: LayerBlend.multiply));
    expect(isEasyEditable(masked), isFalse);
    expect(isEasyEditable(withFx), isFalse);
    expect(isEasyEditable(withRig), isFalse);
    expect(isEasyEditable(withParent), isFalse);
    expect(isEasyEditable(withBlend), isFalse);

    await _pumpLayers(tester, doc);

    expect(find.byKey(Key('easy.layer.badge.${textLayer.id}')), findsOneWidget);
    expect(find.byKey(Key('easy.layer.badge.${drawing.id}')), findsNothing);

    // Lock tap on TextLayer should be disabled (no-op)
    await tester.tap(find.byKey(Key('easy.layer.lock.${textLayer.id}')));
    await tester.pumpAndSettle();
    expect(doc.comp.layer(textLayer.id)!.props.locked, isFalse);

    // Eye tap on TextLayer still works
    await tester.tap(find.byKey(Key('easy.layer.visibility.${textLayer.id}')));
    await tester.pumpAndSettle();
    expect(doc.comp.layer(textLayer.id)!.props.visible, isFalse);
  });

  testWidgets('dragging opacity slider updates props.opacity as a single undo step', (tester) async {
    await _pumpLayers(tester, doc);

    final activeId = doc.activeLayerId!;
    expect(doc.comp.layer(activeId)!.props.opacity, 1.0);

    final slider = find.byKey(const Key('easy.layers.opacity'));
    expect(slider, findsOneWidget);

    await tester.drag(slider, const Offset(-100, 0));
    await tester.pumpAndSettle();
    expect(doc.comp.layer(activeId)!.props.opacity, lessThan(1.0));

    // Single undo restores opacity back to 1.0
    doc.undo();
    await tester.pumpAndSettle();
    expect(doc.comp.layer(activeId)!.props.opacity, 1.0);
  });

  testWidgets('dragging reorder handle reorders doc.comp.layers', (tester) async {
    await _pumpLayers(tester, doc);

    final bg = doc.comp.layers[0];
    final drawing = doc.comp.layers[1];

    // Drag Drawing (top row, index 0) down past Background (bottom row, index 1)
    final handle = find.byKey(Key('easy.layer.drag.${drawing.id}'));
    await tester.timedDrag(handle, const Offset(0, 80), const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(doc.comp.layers.map((l) => l.id).toList(), [drawing.id, bg.id]);
  });
}
