import 'package:drawly/app/settings.dart';
import 'package:drawly/ui/easy/tutorial.dart';
import 'package:drawly/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('nine steps with unique ids and text', () {
    final steps = bouncingBallSteps();
    expect(steps, hasLength(9));
    expect(steps.map((s) => s.id).toSet(), hasLength(9));
    expect(steps.every((s) => s.title.isNotEmpty && s.text.isNotEmpty), isTrue);
  });

  test('the controller advances with snapshots, skips done steps and never goes back', () {
    final c = TutorialController(bouncingBallSteps());
    c.update(const TutorialSnapshot());
    expect(c.index, 0);
    c.update(const TutorialSnapshot(hasDocument: true));
    expect(c.index, 1);
    c.update(const TutorialSnapshot(hasDocument: true, toolId: 'brush', brushId: 'fineliner'));
    expect(c.index, 2);
    // several steps done at once
    c.update(const TutorialSnapshot(hasDocument: true, toolId: 'brush', brushId: 'fineliner', framesWithDrawing: 1, frameCount: 2, onion: true));
    expect(c.index, 5);
    // a later snapshot that would fail earlier steps does not go back
    c.update(const TutorialSnapshot());
    expect(c.index, 5);
    c.update(const TutorialSnapshot(hasDocument: true, toolId: 'brush', brushId: 'fineliner', framesWithDrawing: 4, frameCount: 4, onion: true, playing: true, exported: true));
    expect(c.finished, isTrue);
    expect(c.skipped, isFalse);
  });

  test('skip and restart', () {
    final c = TutorialController(bouncingBallSteps());
    c.skip();
    expect(c.skipped, isTrue);
    expect(c.finished, isTrue);
    c.restart();
    expect(c.index, 0);
    expect(c.finished, isFalse);
  });

  testWidgets('the bubble points at the target, counts steps, and touches still reach the app', (tester) async {
    final c = TutorialController(bouncingBallSteps());
    c.update(const TutorialSnapshot(hasDocument: true, toolId: 'brush', brushId: 'fineliner', framesWithDrawing: 1));
    expect(c.index, 3);
    var pressed = 0;
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Settings(), Brightness.dark),
      home: Scaffold(
        body: TutorialOverlay(
          controller: c,
          child: Center(
            child: ElevatedButton(key: const ValueKey('easy.addFrame'), onPressed: () => pressed++, child: const Text('+')),
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
    expect(find.text(bouncingBallSteps()[3].title), findsOneWidget);
    expect(find.text('4 / 9'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('easy.addFrame')));
    expect(pressed, 1);
    await tester.tap(find.byKey(const ValueKey('tutorial.skip')));
    await tester.pump();
    expect(c.skipped, isTrue);
    expect(find.byKey(const ValueKey('tutorial.bubble')), findsNothing);
  });

  testWidgets('tiny screens do not throw; restarting does not reuse the old hole', (tester) async {
    tester.view.physicalSize = const Size(240, 150);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = TutorialController(bouncingBallSteps());
    c.update(const TutorialSnapshot(hasDocument: true, toolId: 'brush', brushId: 'fineliner', framesWithDrawing: 1));
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Settings(), Brightness.dark),
      home: Scaffold(
        body: TutorialOverlay(
          controller: c,
          child: Align(alignment: Alignment.topLeft, child: SizedBox(key: const ValueKey('easy.addFrame'), width: 40, height: 40)),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);
    c.skip();
    await tester.pump();
    c.restart();
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Settings(), Brightness.dark),
      home: Scaffold(body: TutorialOverlay(controller: c, child: const SizedBox.expand())),
    ));
    final state = tester.state(find.byType(TutorialOverlay));
    expect((state as dynamic).debugHole, isNull, reason: 'step 1 target is not in the tree');
  });
}
