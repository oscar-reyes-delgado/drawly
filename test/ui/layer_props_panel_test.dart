import 'package:drawly/app/doc_layers.dart';
import 'package:drawly/app/document_controller.dart';
import 'package:drawly/app/settings.dart';
import 'package:drawly/model/anim.dart';
import 'package:drawly/model/document.dart';
import 'package:drawly/ui/panels/layer_props_panel.dart';
import 'package:drawly/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DocumentController _doc({bool withLayer = true}) {
  final d = DocumentController(Project.blank(width: 64, height: 64), title: 't');
  if (withLayer) {
    d.addPaintLayer();
  } else {
    d.selectLayer(null);
  }
  return d;
}

Future<void> _pump(WidgetTester tester, DocumentController d) async {
  tester.view.physicalSize = const Size(400, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: buildTheme(Settings(), Brightness.dark),
    home: Scaffold(body: SizedBox(width: 320, child: LayerPropsPanel(doc: d))),
  ));
  await tester.pump();
}

Future<void> _submit(WidgetTester tester, Finder field, String text) async {
  await tester.enterText(find.descendant(of: field, matching: find.byType(TextField)), text);
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pump();
}

void main() {
  testWidgets('shows a hint when no layer is active', (tester) async {
    await _pump(tester, _doc(withLayer: false));
    expect(find.text('Ninguna capa seleccionada'), findsOneWidget);
  });

  testWidgets('typing 25 in X moves the layer and undo reverts it', (tester) async {
    final d = _doc();
    await _pump(tester, d);
    final id = d.activeLayerId!;
    await _submit(tester, find.byKey(ValueKey('field-x-$id')), '25');
    expect(d.activeLayer!.props.valueAt(Prop.x, d.frame.toDouble()), 25);
    d.undo();
    await tester.pump();
    expect(d.activeLayer!.props.xf.x, 0);
  });

  testWidgets('animated X shows the interpolated value of the current frame', (tester) async {
    final d = _doc();
    final id = d.activeLayerId!;
    final track = AnimTrack.none.withKey(const AnimKey(0, 0, Ease.linear)).withKey(const AnimKey(10, 100, Ease.linear));
    d.updateProps('anim', id, (p) => p.copyWith(tracks: {Prop.x: track}));
    d.frame = 5;
    await _pump(tester, d);
    final field = tester.widget<TextField>(find.descendant(of: find.byKey(ValueKey('field-x-$id')), matching: find.byType(TextField)));
    expect(double.parse(field.controller!.text), closeTo(50, 0.05));
  });

  testWidgets('the rotation diamond adds and removes a key at the current frame', (tester) async {
    final d = _doc();
    d.frame = 3;
    await _pump(tester, d);
    await tester.tap(find.byKey(const ValueKey('key-rotation')));
    await tester.pump();
    expect(d.activeLayer!.props.tracks[Prop.rotation]?.keyAt(3), isNotNull);
    await tester.tap(find.byKey(const ValueKey('key-rotation')));
    await tester.pump();
    expect(d.activeLayer!.props.tracks[Prop.rotation]?.keyAt(3), isNull);
  });

  testWidgets('enabling the shadow and changing its blur edits fx', (tester) async {
    final d = _doc();
    await _pump(tester, d);
    await tester.tap(find.text('Efectos'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('fx-shadow')));
    await tester.pumpAndSettle();
    expect(d.activeLayer!.props.fx.shadow, isTrue);
    final before = d.activeLayer!.props.fx.shadowBlur;
    final blur = find.ancestor(of: find.text('Desenfoque'), matching: find.byType(Row)).first;
    final slider = find.descendant(of: blur, matching: find.byType(Slider));
    await tester.tapAt(tester.getTopRight(slider) - const Offset(8, -10));
    await tester.pump();
    expect(d.activeLayer!.props.fx.shadowBlur, isNot(before));
  });

  testWidgets('reset restores the transform in a single undo step', (tester) async {
    final d = _doc();
    final id = d.activeLayerId!;
    d.updateProps('t', id, (p) => p.copyWith(xf: p.xf.copyWith(x: 10, y: 20, sx: 2, sy: 3, rot: 45)));
    final steps = d.history.index;
    await _pump(tester, d);
    await tester.tap(find.byKey(const ValueKey('reset-transform')));
    await tester.pump();
    final xf = d.activeLayer!.props.xf;
    expect([xf.x, xf.y, xf.sx, xf.sy, xf.rot], [0, 0, 1, 1, 0]);
    expect(d.history.index, steps + 1);
  });
}
