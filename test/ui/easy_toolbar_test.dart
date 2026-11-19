import 'dart:ui' show Tristate;

import 'package:drawly/app/settings.dart';
import 'package:drawly/app/tool_state.dart';
import 'package:drawly/ui/easy/easy_toolbar.dart';
import 'package:drawly/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: buildTheme(Settings(), Brightness.dark),
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('pencil and brush select fineliner and round_brush and easyToolFor matches', (tester) async {
    final ts = ToolState();
    String? selectedTool;

    await tester.pumpWidget(_wrap(EasyToolbar(
      ts: ts,
      activeToolId: 'brush',
      onSelectTool: (id) => selectedTool = id,
      onOpenColors: () {},
    )));

    await tester.tap(find.byKey(const Key('easy.tool.pencil')));
    await tester.pump();
    expect(selectedTool, 'brush');
    expect(ts.brush.id, 'fineliner');
    expect(easyToolFor('brush', ts), EasyTool.pencil);

    await tester.tap(find.byKey(const Key('easy.tool.brush')));
    await tester.pump();
    expect(selectedTool, 'brush');
    expect(ts.brush.id, 'round_brush');
    expect(easyToolFor('brush', ts), EasyTool.brush);
  });

  testWidgets('select, transform and bucket emit marquee, transform and bucket', (tester) async {
    final ts = ToolState();
    final calls = <String>[];

    await tester.pumpWidget(_wrap(EasyToolbar(
      ts: ts,
      activeToolId: 'brush',
      onSelectTool: calls.add,
      onOpenColors: () {},
    )));

    await tester.tap(find.byKey(const Key('easy.tool.select')));
    await tester.tap(find.byKey(const Key('easy.tool.transform')));
    await tester.tap(find.byKey(const Key('easy.tool.bucket')));
    await tester.pump();

    expect(calls, ['marquee', 'transform', 'bucket']);
  });

  testWidgets('eraser button has selected state when activeToolId is eraser', (tester) async {
    final ts = ToolState();

    await tester.pumpWidget(_wrap(EasyToolbar(
      ts: ts,
      activeToolId: 'eraser',
      onSelectTool: (_) {},
      onOpenColors: () {},
    )));

    final eraserSemantics = tester.getSemantics(find.byKey(const Key('easy.tool.eraser')));
    expect(eraserSemantics.flagsCollection.isSelected, Tristate.isTrue);

    final brushSemantics = tester.getSemantics(find.byKey(const Key('easy.tool.brush')));
    expect(brushSemantics.flagsCollection.isSelected, Tristate.isFalse);
  });

  testWidgets('size panel slider changes size and More -> Estabilizar changes smoothing', (tester) async {
    final ts = ToolState();
    ts.selectBrush(ts.brushes.firstWhere((b) => b.id == 'round_brush'));
    final initialSize = ts.brush.size;
    final initialSmoothing = ts.brush.smoothing;

    await tester.pumpWidget(_wrap(EasyToolbar(
      ts: ts,
      activeToolId: 'brush',
      onSelectTool: (_) {},
      onOpenColors: () {},
    )));

    await tester.tap(find.byKey(const Key('easy.size')));
    await tester.pumpAndSettle();

    final sizeSlider = find.byType(Slider).first;
    await tester.drag(sizeSlider, const Offset(80, 0));
    await tester.pump();
    expect(ts.brush.size, isNot(initialSize));

    await tester.tap(find.byKey(const Key('easy.size.more')));
    await tester.pumpAndSettle();

    final smoothSlider = find.byKey(const Key('easy.size.smoothing'));
    expect(smoothSlider, findsOneWidget);
    await tester.drag(smoothSlider, const Offset(80, 0));
    await tester.pump();
    expect(ts.brush.smoothing, isNot(initialSmoothing));
  });

  testWidgets('size button is disabled when bucket is active', (tester) async {
    final ts = ToolState();

    await tester.pumpWidget(_wrap(EasyToolbar(
      ts: ts,
      activeToolId: 'bucket',
      onSelectTool: (_) {},
      onOpenColors: () {},
    )));

    final sizeSemantics = tester.getSemantics(find.byKey(const Key('easy.size')));
    expect(sizeSemantics.flagsCollection.isEnabled, Tristate.isFalse);

    await tester.tap(find.byKey(const Key('easy.size')));
    await tester.pumpAndSettle();
    expect(find.byType(Slider), findsNothing);
  });

  testWidgets('horizontal axis at width 360 has no overflow', (tester) async {
    final ts = ToolState();
    var colorOpened = false;

    await tester.pumpWidget(_wrap(SizedBox(
      width: 360,
      child: EasyToolbar(
        ts: ts,
        activeToolId: 'brush',
        onSelectTool: (_) {},
        onOpenColors: () => colorOpened = true,
        axis: Axis.horizontal,
      ),
    )));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.byKey(const Key('easy.color')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('easy.color')));
    await tester.pump();
    expect(colorOpened, isTrue);
  });

  testWidgets('falls back to category ink/paint when fineliner/round_brush are absent', (tester) async {
    final ts = ToolState();
    ts.brushes = ts.brushes.where((b) => b.id != 'fineliner' && b.id != 'round_brush').toList();

    await tester.pumpWidget(_wrap(EasyToolbar(
      ts: ts,
      activeToolId: 'brush',
      onSelectTool: (_) {},
      onOpenColors: () {},
    )));

    await tester.tap(find.byKey(const Key('easy.tool.pencil')));
    await tester.pump();
    expect(ts.brush.category, 'ink');

    await tester.tap(find.byKey(const Key('easy.tool.brush')));
    await tester.pump();
    expect(ts.brush.category, 'paint');
  });
}
