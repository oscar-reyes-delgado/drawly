import 'package:drawly/app/settings.dart';
import 'package:drawly/app/tool_state.dart';
import 'package:drawly/core/color_utils.dart';
import 'package:drawly/engine/brush/preset.dart';
import 'package:drawly/ui/panels/brush_panel.dart';
import 'package:drawly/ui/panels/color_panel.dart';
import 'package:drawly/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child, {double width = 280}) => MaterialApp(
      theme: buildTheme(Settings(), Brightness.dark),
      home: Scaffold(
        body: SizedBox(width: width, height: 600, child: child),
      ),
    );

void main() {
  testWidgets('both panels render cleanly with a fresh ToolState', (tester) async {
    final ts = ToolState();
    await tester.pumpWidget(
      _wrap(
        Row(
          children: [
            SizedBox(width: 280, child: ColorPanel(ts: ts)),
            SizedBox(width: 280, child: BrushPanel(ts: ts)),
          ],
        ),
        width: 560,
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(ColorPanel), findsOneWidget);
    expect(find.byType(BrushPanel), findsOneWidget);
  });

  testWidgets('ColorPanel HEX input sets fg and swap exchanges fg and bg', (tester) async {
    final ts = ToolState();
    await tester.pumpWidget(_wrap(ColorPanel(ts: ts)));

    final hexField = find.byKey(const ValueKey('color_hex_field'));
    await tester.enterText(hexField, 'FF0000');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(ts.fg, const Color(0xFFFF0000));
    final prevFg = ts.fg;
    final prevBg = ts.bg;

    await tester.tap(find.byKey(const ValueKey('color_swap_btn')));
    await tester.pump();

    expect(ts.fg, prevBg);
    expect(ts.bg, prevFg);
  });

  testWidgets('ColorPanel dragging SV square changes fg while keeping hue', (tester) async {
    final ts = ToolState();
    ts.fg = const Color(0xFF3399CC);
    final initialHue = Hsv.fromColor(ts.fg).h;

    await tester.pumpWidget(_wrap(ColorPanel(ts: ts)));

    final svSquare = find.byKey(const ValueKey('color_sv_square'));
    final box = tester.getRect(svSquare);
    final start = Offset(box.left + box.width * 0.3, box.top + box.height * 0.4);
    await tester.dragFrom(start, const Offset(40, -25));
    await tester.pump();

    expect(ts.fg, isNot(const Color(0xFF3399CC)));
    expect(Hsv.fromColor(ts.fg).h, closeTo(initialHue, 1.5));
    expect(ts.colorHistory, isNotEmpty);
  });

  testWidgets('ColorPanel background swatch editing, reset, hue drag and palette', (tester) async {
    final ts = ToolState();
    await tester.pumpWidget(_wrap(ColorPanel(ts: ts)));

    // Select background swatch and set red channel to 100 via NumField.
    await tester.tap(find.byKey(const ValueKey('color_bg_swatch')));
    await tester.pump();

    final rField = find.descendant(of: find.byKey(const ValueKey('color_r_field')), matching: find.byType(TextField));
    await tester.enterText(rField, '100');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(ts.bg.r8, 100);

    // Drag hue bar.
    final hueBar = find.byKey(const ValueKey('color_hue_bar'));
    await tester.drag(hueBar, const Offset(0, 40));
    await tester.pump();
    expect(ts.colorHistory, isNotEmpty);

    // Reset restores black fg and white bg.
    await tester.tap(find.byKey(const ValueKey('color_reset_btn')));
    await tester.pump();
    expect(ts.fg, const Color(0xFF000000));
    expect(ts.bg, const Color(0xFFFFFFFF));

    // Switch back to foreground swatch, add fg to palette (creates a custom palette), then remove it.
    await tester.tap(find.byKey(const ValueKey('color_fg_swatch')));
    await tester.pump();
    ts.fg = const Color(0xFF123456);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('color_palette_add_btn')));
    await tester.pump();
    expect(ts.palette.builtin, isFalse);
    expect(ts.palette.colors, contains(0xFF123456));

    await tester.longPress(find.byTooltip('#123456 · clic derecho o mantener para quitar'));
    await tester.pump();
    expect(ts.palette.colors, isNot(contains(0xFF123456)));
  });

  testWidgets('BrushPanel tapping another brush changes active brush and size slider updates size', (tester) async {
    final ts = ToolState();
    final initialId = ts.brush.id;
    await tester.pumpWidget(_wrap(BrushPanel(ts: ts)));

    final other = ts.brushes.firstWhere((b) => b.id != initialId && b.category == 'sketch');
    await tester.tap(find.byKey(ValueKey('brush_item_${other.id}')));
    await tester.pump();
    expect(ts.brush.id, other.id);

    final beforeSize = ts.brush.size;
    final sizeSlider = find.descendant(of: find.byKey(const ValueKey('brush_size_slider')), matching: find.byType(Slider));
    await tester.drag(sizeSlider, const Offset(60, 0));
    await tester.pump();
    expect(ts.brush.size, isNot(beforeSize));
  });

  testWidgets('BrushPanel collapses categories and adjusts opacity, flow and hardness', (tester) async {
    final ts = ToolState();
    await tester.pumpWidget(_wrap(BrushPanel(ts: ts)));

    final firstSketch = ts.brushes.firstWhere((b) => b.category == 'sketch');
    expect(find.byKey(ValueKey('brush_item_${firstSketch.id}')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('brush_cat_sketch')));
    await tester.pump();
    expect(find.byKey(ValueKey('brush_item_${firstSketch.id}')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('brush_cat_sketch')));
    await tester.pump();
    expect(find.byKey(ValueKey('brush_item_${firstSketch.id}')), findsOneWidget);

    final opacityBefore = ts.brush.opacity;
    final flowBefore = ts.brush.flow;
    final hardnessBefore = ts.brush.hardness;

    Future<void> dragSliderLeft(Key key) async {
      final slider = find.descendant(of: find.byKey(key), matching: find.byType(Slider));
      final rect = tester.getRect(slider);
      await tester.tapAt(Offset(rect.left + rect.width * 0.3, rect.center.dy));
      await tester.pump();
    }

    await dragSliderLeft(const ValueKey('brush_opacity_slider'));
    await dragSliderLeft(const ValueKey('brush_flow_slider'));
    await dragSliderLeft(const ValueKey('brush_hardness_slider'));

    expect(ts.brush.opacity, lessThan(opacityBefore));
    expect(ts.brush.flow, lessThan(flowBefore));
    expect(ts.brush.hardness, lessThan(hardnessBefore));
    expect(brushCategoryLabel('sketch'), isNotEmpty);
  });
}
