import 'package:drawly/app/settings.dart';
import 'package:drawly/engine/tiles.dart';
import 'package:drawly/model/document.dart';
import 'package:drawly/model/layer.dart';
import 'package:drawly/ui/library/animation_player.dart';
import 'package:drawly/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Project _threeFrames() {
  final p = Project.blank(width: 64, height: 48, fps: 10, frames: 3);
  final layer = p.main.layers.first as PaintLayer;
  final drawings = <int, TilePlane>{};
  for (var i = 0; i < 3; i++) {
    final r = Rect.fromLTWH(i * 16.0, 8, 12, 12);
    drawings[i + 1] = TilePlane.empty.drawn((c) => c.drawRect(r, Paint()..color = const Color(0xFF000000)), area: r);
  }
  final next = layer.withCels(CelTrack(drawings: drawings, xs: const [Exposure(0, 1), Exposure(1, 2), Exposure(2, 3)]));
  return p.withComp(p.main.copyWith(layers: [next]));
}

void main() {
  Future<void> pump(WidgetTester tester, Project p, {bool autoPlay = false}) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Settings(), Brightness.dark),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AnimationPlayerPage(project: p, title: 'Pelota', autoPlay: autoPlay))),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    if (autoPlay) {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    } else {
      await tester.pumpAndSettle();
    }
  }

  testWidgets('shows the title and the first frame; play advances and loops', (tester) async {
    await pump(tester, _threeFrames());
    expect(find.text('Pelota'), findsOneWidget);
    expect(find.text('1 / 3'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('player.play')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.text('2 / 3'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('1 / 3'), findsOneWidget, reason: 'it loops back to the first frame');
    await tester.tap(find.byKey(const ValueKey('player.play')));
    await tester.pump();
  });

  testWidgets('without loop it stops on the last frame; the slider seeks', (tester) async {
    await pump(tester, _threeFrames());
    await tester.tap(find.byKey(const ValueKey('player.loop')));
    await tester.tap(find.byKey(const ValueKey('player.play')));
    await tester.pump();
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('3 / 3'), findsOneWidget);
    expect(find.byIcon(Icons.play_circle_filled), findsOneWidget, reason: 'stopped');
    await tester.drag(find.byKey(const ValueKey('player.slider')), const Offset(-500, 0));
    await tester.pump();
    expect(find.text('1 / 3'), findsOneWidget);
  });

  testWidgets('tapping the stage hides the controls; close leaves the player', (tester) async {
    await pump(tester, _threeFrames());
    await tester.tap(find.byKey(const ValueKey('player.stage')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('player.play')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('player.stage')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const ValueKey('player.close')));
    await tester.pumpAndSettle();
    expect(find.byType(AnimationPlayerPage), findsNothing);
  });

  testWidgets('autoplay starts on open; a single frame does not autoplay', (tester) async {
    await pump(tester, _threeFrames(), autoPlay: true);
    expect(find.byIcon(Icons.pause_circle_filled), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('player.play')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('player.close')));
    await tester.pumpAndSettle();
    await pump(tester, Project.blank(width: 32, height: 32, frames: 1), autoPlay: true);
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.byIcon(Icons.play_circle_filled), findsOneWidget);
  });
}
