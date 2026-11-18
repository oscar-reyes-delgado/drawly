import 'package:drawly/app/doc_selection.dart';
import 'package:drawly/app/settings.dart';
import 'package:drawly/app/tool_state.dart';
import 'package:drawly/core/i18n.dart';
import 'package:drawly/tools/registry.dart';
import 'package:drawly/ui/panels/tool_options_bar.dart';
import 'package:drawly/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child, {double width = 1000}) => MaterialApp(
      theme: buildTheme(Settings(), Brightness.dark),
      home: Scaffold(
        body: SizedBox(width: width, child: child),
      ),
    );

void main() {
  setUp(() {
    I18n.instance.lang = 'es';
  });

  testWidgets('builds without exceptions for every tool in kToolbarOrder and unknown ids', (tester) async {
    final ts = ToolState();
    for (final id in [...kToolbarOrder, 'unknown_tool']) {
      await tester.pumpWidget(_wrap(ToolOptionsBar(ts: ts, toolId: id), width: 320));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'Failed for toolId=$id');
    }
  });

  testWidgets('marquee: tapping add button sets SelectMode.add', (tester) async {
    final ts = ToolState();
    expect(ts.selectMode, SelectMode.replace);

    await tester.pumpWidget(_wrap(ToolOptionsBar(ts: ts, toolId: 'marquee')));
    await tester.pump();

    await tester.tap(find.byTooltip('Añadir'));
    await tester.pump();

    expect(ts.selectMode, SelectMode.add);
  });

  testWidgets('bucket: tolerance slider and contiguous toggle update ToolState', (tester) async {
    final ts = ToolState();
    final initialTolerance = ts.tolerance;
    expect(ts.contiguous, isTrue);

    await tester.pumpWidget(_wrap(ToolOptionsBar(ts: ts, toolId: 'bucket')));
    await tester.pump();

    final slider = find.descendant(
      of: find.byKey(const ValueKey('opt_tolerance')),
      matching: find.byType(Slider),
    );
    await tester.drag(slider, const Offset(40, 0));
    await tester.pump();
    expect(ts.tolerance, isNot(initialTolerance));

    await tester.tap(find.text('Contiguo'));
    await tester.pump();
    expect(ts.contiguous, isFalse);
  });

  testWidgets('shape: star shows sides and ratio controls, rect hides them', (tester) async {
    final ts = ToolState();
    ts.shapeKind = ShapeKind.rect;

    await tester.pumpWidget(_wrap(ToolOptionsBar(ts: ts, toolId: 'shape')));
    await tester.pump();

    expect(find.byKey(const ValueKey('opt_shape_sides')), findsNothing);
    expect(find.byKey(const ValueKey('opt_star_ratio')), findsNothing);

    ts.set(() => ts.shapeKind = ShapeKind.star);
    await tester.pump();

    expect(find.byKey(const ValueKey('opt_shape_sides')), findsOneWidget);
    expect(find.byKey(const ValueKey('opt_star_ratio')), findsOneWidget);
  });

  testWidgets('brush: changing size slider updates ts.brush.size', (tester) async {
    final ts = ToolState();
    final initialSize = ts.brush.size;

    await tester.pumpWidget(_wrap(ToolOptionsBar(ts: ts, toolId: 'brush')));
    await tester.pump();

    final slider = find.descendant(
      of: find.byKey(const ValueKey('opt_brush_size')),
      matching: find.byType(Slider),
    );
    await tester.drag(slider, const Offset(45, 0));
    await tester.pump();

    expect(ts.brush.size, isNot(closeTo(initialSize, 0.01)));
  });

  testWidgets('hand: shows "Sin opciones" text', (tester) async {
    final ts = ToolState();

    await tester.pumpWidget(_wrap(ToolOptionsBar(ts: ts, toolId: 'hand')));
    await tester.pump();

    expect(find.text('Sin opciones'), findsOneWidget);
  });

  testWidgets('text and eyedropper options update ToolState', (tester) async {
    final ts = ToolState();

    await tester.pumpWidget(_wrap(ToolOptionsBar(ts: ts, toolId: 'text')));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('opt_font_bold')));
    await tester.pump();
    expect(ts.fontBold, isTrue);

    await tester.tap(find.byKey(const ValueKey('opt_text_align_1')));
    await tester.pump();
    expect(ts.textAlign, 1);

    await tester.pumpWidget(_wrap(ToolOptionsBar(ts: ts, toolId: 'eyedropper')));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('opt_pick_all_layers')));
    await tester.pump();
    expect(ts.pickAllLayers, isFalse);
  });
}
