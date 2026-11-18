import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drawly/app/doc_layers.dart';
import 'package:drawly/app/document_controller.dart';
import 'package:drawly/app/settings.dart';
import 'package:drawly/core/i18n.dart';
import 'package:drawly/engine/tiles.dart';
import 'package:drawly/model/document.dart';
import 'package:drawly/model/filter_spec.dart';
import 'package:drawly/model/layer.dart';
import 'package:drawly/model/specs.dart';
import 'package:drawly/ui/panels/layers_panel.dart';
import 'package:drawly/ui/theme.dart';
import 'package:drawly/ui/widgets.dart';

Finder _row(String id) => find.byKey(ValueKey('layer-row:$id'));
Finder _name(String id) => find.byKey(ValueKey('layer-name:$id'));
Finder _control(String kind, String id) => find.byKey(ValueKey('layer-$kind:$id'));

Future<void> _pumpPanel(WidgetTester tester, DocumentController doc, {void Function(String)? onCommand, double width = 320, TargetPlatform platform = TargetPlatform.android}) async {
  await tester.pumpWidget(MaterialApp(
    theme: buildTheme(Settings(), Brightness.dark).copyWith(platform: platform),
    home: Scaffold(body: Align(alignment: Alignment.topLeft, child: SizedBox(width: width, height: 540, child: LayersPanel(doc: doc, onCommand: onCommand ?? (_) {})))),
  ));
  await tester.pumpAndSettle();
}

Future<void> _select(WidgetTester tester, String id) async {
  await tester.tap(_name(id));
  await tester.pump(kDoubleTapTimeout);
  await tester.pumpAndSettle();
}

Future<void> _editName(WidgetTester tester, String id) async {
  await tester.tap(_name(id));
  await tester.pump(const Duration(milliseconds: 60));
  await tester.tap(_name(id));
  await tester.pumpAndSettle();
  expect(_control('name-editor', id), findsOneWidget);
}

Future<void> _dragLayer(WidgetTester tester, String source, String target, double heightFraction, {bool longPress = true}) async {
  final targetRect = tester.getRect(_row(target));
  final gesture = await tester.startGesture(tester.getCenter(_name(source)));
  if (longPress) await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
  await gesture.moveBy(const Offset(24, 0));
  await tester.pump();
  await gesture.moveTo(Offset(targetRect.center.dx, targetRect.top + targetRect.height * heightFraction));
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DocumentController doc;

  setUp(() {
    doc = DocumentController(Project.blank(width: 64, height: 64), title: 't');
  });

  tearDown(() => doc.dispose());

  testWidgets('shows three 36-pixel rows in top-to-bottom order and listens to additions', (tester) async {
    doc.addPaintLayer();
    doc.addPaintLayer();
    await _pumpPanel(tester, doc);
    final layers = doc.comp.layers.reversed.toList();
    for (var i = 0; i < layers.length; i++) {
      expect(find.text(layers[i].name), findsOneWidget);
      expect(tester.getSize(_row(layers[i].id)).height, 36);
      if (i > 0) expect(tester.getTopLeft(_row(layers[i].id)).dy - tester.getTopLeft(_row(layers[i - 1].id)).dy, 36);
    }
    doc.addPaintLayer(name: 'Live addition');
    await tester.pump();
    expect(find.text('Live addition'), findsOneWidget);
    expect(tester.getTopLeft(_name(doc.activeLayerId!)).dy, lessThan(tester.getTopLeft(_name(layers.first.id)).dy));
  });

  testWidgets('eye toggles visibility through undoable document edits', (tester) async {
    doc.addPaintLayer();
    final id = doc.comp.layers.first.id;
    final activeId = doc.activeLayerId;
    await _pumpPanel(tester, doc);
    await tester.tap(_control('visibility', id));
    await tester.pumpAndSettle();
    expect(doc.comp.layer(id)!.props.visible, isFalse);
    expect(doc.activeLayerId, activeId);
    expect(tester.widget<PanelButton>(_control('visibility', id)).icon, Icons.visibility_off_outlined);
    doc.undo();
    await tester.pumpAndSettle();
    expect(doc.comp.layer(id)!.props.visible, isTrue);
    expect(tester.widget<PanelButton>(_control('visibility', id)).icon, Icons.visibility_outlined);
  });

  testWidgets('row taps select and Ctrl or Shift taps add to the highlighted selection', (tester) async {
    doc.addPaintLayer();
    doc.addPaintLayer();
    final ids = doc.comp.layers.map((layer) => layer.id).toList();
    await _pumpPanel(tester, doc);
    await _select(tester, ids[0]);
    expect(doc.activeLayerId, ids[0]);
    expect(doc.selectedLayers, {ids[0]});
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await _select(tester, ids[1]);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(doc.activeLayerId, ids[1]);
    expect(doc.selectedLayers, {ids[0], ids[1]});
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await _select(tester, ids[2]);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(doc.selectedLayers, ids.toSet());
    for (final id in ids) {
      expect(tester.widget<Semantics>(_control('selection', id)).properties.selected, isTrue);
    }
    final activeColor = (tester.widget<Container>(_row(ids[2])).decoration! as BoxDecoration).color;
    final selectedColor = (tester.widget<Container>(_row(ids[0])).decoration! as BoxDecoration).color;
    expect(activeColor, isNot(selectedColor));
    await _select(tester, ids[0]);
    expect(doc.selectedLayers, {ids[0]});
    expect(tester.widget<Semantics>(_control('selection', ids[1])).properties.selected, isFalse);
  });

  testWidgets('collapsed groups hide descendants and expanding preserves hierarchy and reverse sibling order', (tester) async {
    final lower = PaintLayer.create('Lower child');
    final upper = PaintLayer.create('Upper child');
    final leaf = PaintLayer.create('Nested child');
    final nested = GroupLayer('nested', const LayerProps(name: 'Nested group'), [leaf]);
    final group = GroupLayer('group', const LayerProps(name: 'Parent group', collapsed: true), [lower, nested, upper]);
    doc.addLayer(group);
    await _pumpPanel(tester, doc);
    for (final layer in [lower, upper, nested, leaf]) {
      expect(find.text(layer.name), findsNothing);
    }
    await tester.tap(_control('collapse', group.id));
    await tester.pumpAndSettle();
    final ids = [group.id, upper.id, nested.id, leaf.id, lower.id];
    for (var i = 1; i < ids.length; i++) {
      expect(tester.getTopLeft(_row(ids[i])).dy, tester.getTopLeft(_row(ids[i - 1])).dy + 36);
    }
    expect(tester.getTopLeft(_name(upper.id)).dx - tester.getTopLeft(_name(group.id)).dx, 16);
    expect(tester.getTopLeft(_name(leaf.id)).dx - tester.getTopLeft(_name(group.id)).dx, 32);
    doc.undo();
    await tester.pumpAndSettle();
    expect(find.text(leaf.name), findsNothing);
    expect(doc.comp.layer(group.id)!.props.collapsed, isTrue);
  });

  testWidgets('opacity dragging updates the active layer and merges into one undo step', (tester) async {
    doc.addPaintLayer();
    final id = doc.activeLayerId!;
    final otherId = doc.comp.layers.first.id;
    await _pumpPanel(tester, doc);
    final before = doc.history.entries.length;
    final rect = tester.getRect(find.descendant(of: find.byKey(const ValueKey('layer-opacity')), matching: find.byType(Slider)));
    Offset point(double fraction) => Offset(rect.left + 24 + (rect.width - 48) * fraction, rect.center.dy);
    final gesture = await tester.startGesture(point(0.9));
    await tester.pump();
    await gesture.moveTo(point(0.7));
    await tester.pump();
    await gesture.moveTo(point(0.3));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(doc.comp.layer(id)!.props.opacity, inExclusiveRange(0.05, 0.6));
    expect(doc.comp.layer(otherId)!.props.opacity, 1);
    expect(doc.history.entries.length, before + 1);
    doc.undo();
    await tester.pumpAndSettle();
    expect(doc.comp.layer(id)!.props.opacity, 1);
    expect(tester.widget<MiniSlider>(find.byKey(const ValueKey('layer-opacity'))).value, 100);
  });

  testWidgets('toolbar delegates every required command id', (tester) async {
    final commands = <String>[];
    const ids = ['layer.newPaint', 'layer.newVector', 'layer.newGroup', 'layer.duplicate', 'layer.delete', 'layer.mergeDown'];
    await _pumpPanel(tester, doc, onCommand: commands.add);
    for (final id in ids) {
      expect(tester.widget(find.byKey(ValueKey(id))), isA<PanelButton>());
      await tester.tap(find.byKey(ValueKey(id)));
      await tester.pumpAndSettle();
    }
    expect(commands, ids);
  });

  testWidgets('locking is undoable and updates the row icon', (tester) async {
    final id = doc.activeLayerId!;
    await _pumpPanel(tester, doc);
    await tester.tap(_control('lock', id));
    await tester.pumpAndSettle();
    expect(doc.activeLayer!.locked, isTrue);
    expect(tester.widget<PanelButton>(_control('lock', id)).icon, Icons.lock_outline);
    doc.undo();
    await tester.pumpAndSettle();
    expect(doc.activeLayer!.locked, isFalse);
  });

  testWidgets('double tapping a name edits it and Enter commits an undoable rename', (tester) async {
    final id = doc.activeLayerId!;
    final original = doc.activeLayer!.name;
    await _pumpPanel(tester, doc);
    await _editName(tester, id);
    await tester.enterText(_control('name-editor', id), 'Ink outline');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(doc.activeLayer!.name, 'Ink outline');
    expect(find.text('Ink outline'), findsOneWidget);
    expect(_control('name-editor', id), findsNothing);
    doc.undo();
    await tester.pumpAndSettle();
    expect(find.text(original), findsOneWidget);
  });

  testWidgets('Escape cancels renaming and empty names leave the document unchanged', (tester) async {
    final id = doc.activeLayerId!;
    final original = doc.activeLayer!.name;
    await _pumpPanel(tester, doc);
    await _editName(tester, id);
    await tester.enterText(_control('name-editor', id), 'Discarded');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(doc.activeLayer!.name, original);
    expect(doc.history.canUndo, isFalse);
    await _editName(tester, id);
    await tester.enterText(_control('name-editor', id), '   ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(doc.activeLayer!.name, original);
    expect(doc.history.canUndo, isFalse);
  });

  testWidgets('blend dropdown edits the active layer and follows undo and selection', (tester) async {
    doc.addPaintLayer();
    final id = doc.activeLayerId!;
    await _pumpPanel(tester, doc);
    await tester.tap(find.byKey(const ValueKey('layer-blend')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(LayerBlend.multiply.label));
    await tester.pumpAndSettle();
    expect(doc.comp.layer(id)!.blend, LayerBlend.multiply);
    doc.undo();
    await tester.pumpAndSettle();
    expect(doc.comp.layer(id)!.blend, LayerBlend.normal);
    doc.updateProps('Set other blend', doc.comp.layers.first.id, (p) => p.copyWith(blend: LayerBlend.screen, opacity: 0.4));
    await tester.pump();
    await _select(tester, doc.comp.layers.first.id);
    expect(tester.widget<MiniDropdown<LayerBlend>>(find.byKey(const ValueKey('layer-blend'))).value, LayerBlend.screen);
    expect(tester.widget<MiniSlider>(find.byKey(const ValueKey('layer-opacity'))).value, 40);
  });

  testWidgets('long-press row drags reorder above and below and can be undone', (tester) async {
    doc.addPaintLayer();
    doc.addPaintLayer();
    final ids = doc.comp.layers.map((layer) => layer.id).toList();
    await _pumpPanel(tester, doc);
    await _dragLayer(tester, ids[0], ids[2], 0.15);
    expect(doc.comp.layers.map((layer) => layer.id), [ids[1], ids[2], ids[0]]);
    doc.undo();
    await tester.pumpAndSettle();
    expect(doc.comp.layers.map((layer) => layer.id), ids);
    await _dragLayer(tester, ids[2], ids[0], 0.85);
    expect(doc.comp.layers.map((layer) => layer.id), [ids[2], ids[0], ids[1]]);
  });

  testWidgets('desktop rows can be dragged without a long press', (tester) async {
    doc.addPaintLayer();
    final ids = doc.comp.layers.map((layer) => layer.id).toList();
    await _pumpPanel(tester, doc, platform: TargetPlatform.windows);
    await _dragLayer(tester, ids[0], ids[1], 0.15, longPress: false);
    expect(doc.comp.layers.map((layer) => layer.id), ids.reversed);
  });

  testWidgets('dropping into a group nests the layer and dragging above it moves the layer out', (tester) async {
    final id = doc.activeLayerId!;
    const group = GroupLayer('group', LayerProps(name: 'Group', collapsed: true), []);
    doc.addLayer(group);
    await _pumpPanel(tester, doc);
    await _dragLayer(tester, id, group.id, 0.5);
    expect(doc.comp.layers.map((layer) => layer.id), [group.id]);
    expect((doc.comp.layer(group.id)! as GroupLayer).children.single.id, id);
    expect(_row(id), findsNothing);
    await tester.tap(_control('collapse', group.id));
    await tester.pumpAndSettle();
    await _dragLayer(tester, id, group.id, 0.15);
    expect(doc.comp.layers.map((layer) => layer.id), [group.id, id]);
    expect((doc.comp.layer(group.id)! as GroupLayer).children, isEmpty);
  });

  testWidgets('a group cannot be dropped on itself or a descendant', (tester) async {
    final leaf = PaintLayer.create('Leaf');
    final group = GroupLayer('group', const LayerProps(name: 'Group'), [leaf]);
    doc.addLayer(group);
    final project = doc.project;
    final historyLength = doc.history.entries.length;
    await _pumpPanel(tester, doc);
    await _dragLayer(tester, group.id, leaf.id, 0.15);
    expect(identical(doc.project, project), isTrue);
    await _dragLayer(tester, group.id, group.id, 0.5);
    expect(identical(doc.project, project), isTrue);
    expect(doc.history.entries.length, historyLength);
  });

  testWidgets('all layer types show distinct icons with mask and ARGB colour markers', (tester) async {
    final paint = doc.activeLayer!;
    final layers = <Layer>[
      paint.withProps(paint.props.copyWith(mask: TilePlane.empty, maskEnabled: false, colorTag: 0xFFFF8800)),
      VectorLayer.create('Vector'),
      const TextLayer('text', LayerProps(name: 'Text'), TextSpec(text: 'Sample')),
      const GroupLayer('group', LayerProps(name: 'Group'), []),
      const AdjustLayer('adjust', LayerProps(name: 'Adjust'), FilterSpec(type: 'blur')),
      InstanceLayer('instance', const LayerProps(name: 'Instance'), doc.compId),
      const ParticleLayer('particles', LayerProps(name: 'Particles'), ParticleSpec()),
    ];
    doc.applyComp('Set layer types', (comp) => comp.copyWith(layers: layers));
    await _pumpPanel(tester, doc, width: 260);
    final icons = {for (final layer in layers) tester.widget<Icon>(_control('type', layer.id)).icon};
    expect(icons.length, layers.length);
    expect(_control('mask', paint.id), findsOneWidget);
    expect(tester.widget<Swatch>(_control('color', paint.id)).color, const Color(0xFFFF8800));
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty composition shows the localized empty state without active-layer controls', (tester) async {
    doc.applyComp('Clear layers', (comp) => comp.copyWith(layers: []));
    await _pumpPanel(tester, doc);
    expect(find.text(tr('Sin capas', 'No layers')), findsOneWidget);
    expect(find.byType(MiniSlider), findsNothing);
    expect(find.byType(MiniDropdown<LayerBlend>), findsNothing);
    expect(find.byKey(const ValueKey('layer.newPaint')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
