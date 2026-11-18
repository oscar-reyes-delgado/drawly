import 'package:drawly/app/app_state.dart';
import 'package:drawly/app/doc_layers.dart';
import 'package:drawly/app/doc_timeline.dart';
import 'package:drawly/app/document_controller.dart';
import 'package:drawly/app/playback.dart';
import 'package:drawly/app/settings.dart';
import 'package:drawly/model/document.dart';
import 'package:drawly/tools/view_tools.dart';
import 'package:drawly/ui/theme.dart';
import 'package:drawly/ui/timeline/timeline_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: buildTheme(Settings(), Brightness.dark),
      home: Scaffold(
        body: SizedBox(width: 800, height: 280, child: child),
      ),
    );

void main() {
  testWidgets('displays exposure blocks for keyframes at 0 and 3 across length 12', (tester) async {
    final doc = DocumentController(Project.blank(width: 64, height: 64, frames: 12), title: 't');
    doc.addKeyFrame(at: 3);
    final playback = Playback(AppState.I);
    addTearDown(() {
      playback.dispose();
      doc.dispose();
    });

    final layerId = doc.activeLayerId!;
    await tester.pumpWidget(_wrap(TimelinePanel(doc: doc, playback: playback)));

    final block0 = find.byKey(ValueKey('cel:$layerId:0'));
    final block3 = find.byKey(ValueKey('cel:$layerId:3'));
    expect(block0, findsOneWidget);
    expect(block3, findsOneWidget);
    expect(tester.getSize(block0).width, closeTo(3 * 14.0, 0.01));
    expect(tester.getSize(block3).width, closeTo(9 * 14.0, 0.01));
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('tapping ruler at frame 5 moves playhead to frame 5', (tester) async {
    final doc = DocumentController(Project.blank(width: 64, height: 64, frames: 12), title: 't');
    final playback = Playback(AppState.I);
    addTearDown(() {
      playback.dispose();
      doc.dispose();
    });

    await tester.pumpWidget(_wrap(TimelinePanel(doc: doc, playback: playback)));

    final ruler = find.byKey(const ValueKey('timeline.ruler'));
    final topLeft = tester.getTopLeft(ruler);
    await tester.tapAt(topLeft + const Offset(5 * 14.0 + 7.0, 12.0));
    await tester.pump();

    expect(doc.frame, 5);
  });

  testWidgets('double tapping an empty cell adds a keyframe at that frame', (tester) async {
    final doc = DocumentController(Project.blank(width: 64, height: 64, frames: 12), title: 't');
    doc.addKeyFrame(at: 3);
    final playback = Playback(AppState.I);
    addTearDown(() {
      playback.dispose();
      doc.dispose();
    });

    final layerId = doc.activeLayerId!;
    await tester.pumpWidget(_wrap(TimelinePanel(doc: doc, playback: playback)));

    final row = find.byKey(ValueKey('timeline.row.$layerId'));
    final target = tester.getTopLeft(row) + const Offset(7 * 14.0 + 7.0, 14.0);
    await tester.tapAt(target);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(target);
    await tester.pump(const Duration(milliseconds: 350));

    final cels = doc.celsOf(doc.activeLayer)!;
    expect(cels.hasKeyAt(7), isTrue);
    expect(find.byKey(ValueKey('cel:$layerId:7')), findsOneWidget);
  });

  testWidgets('play button toggles Playback.playing using AppState.I without init()', (tester) async {
    AppState.I.toolMap['brush'] ??= HandTool();
    final doc = AppState.I.addDocument(Project.blank(width: 64, height: 64, frames: 12), title: 't');
    final playback = AppState.I.playback;
    addTearDown(() {
      playback.stop();
      AppState.I.closeDocument(doc);
    });

    await tester.pumpWidget(_wrap(TimelinePanel(doc: doc, playback: playback)));

    expect(playback.playing, isFalse);
    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pump();

    expect(playback.playing, isTrue);
    expect(find.byIcon(Icons.pause), findsOneWidget);

    await tester.tap(find.byIcon(Icons.pause));
    await tester.pump();

    expect(playback.playing, isFalse);
  });

  testWidgets('changing FPS field updates doc.timeline.fps', (tester) async {
    final doc = DocumentController(Project.blank(width: 64, height: 64, frames: 12), title: 't');
    final playback = Playback(AppState.I);
    addTearDown(() {
      playback.dispose();
      doc.dispose();
    });

    await tester.pumpWidget(_wrap(TimelinePanel(doc: doc, playback: playback)));

    final fpsField = find.byKey(const ValueKey('timeline.fps'));
    expect(fpsField, findsOneWidget);
    await tester.enterText(fpsField, '24');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(doc.timeline.fps, 24);
  });

  testWidgets('dragging key dot moves keyframe to destination frame', (tester) async {
    final doc = DocumentController(Project.blank(width: 64, height: 64, frames: 12), title: 't');
    doc.addKeyFrame(at: 3);
    final playback = Playback(AppState.I);
    addTearDown(() {
      playback.dispose();
      doc.dispose();
    });

    final layerId = doc.activeLayerId!;
    await tester.pumpWidget(_wrap(TimelinePanel(doc: doc, playback: playback)));

    final keyHandle = find.byKey(ValueKey('celKey:$layerId:3'));
    expect(keyHandle, findsOneWidget);
    await tester.drag(keyHandle, const Offset(3 * 14.0, 0));
    await tester.pumpAndSettle();

    final cels = doc.celsOf(doc.activeLayer)!;
    expect(cels.hasKeyAt(3), isFalse);
    expect(cels.hasKeyAt(6), isTrue);
  });

  testWidgets('transport buttons, blank keys, group layers and compact ruler work cleanly', (tester) async {
    final doc = DocumentController(
      Project.blank(width: 64, height: 64, frames: 12),
      title: 't',
    );
    doc.addGroupLayer();
    final groupId = doc.activeLayerId!;
    doc.addBlankKey(at: 4); // ignored on group
    final paintLayer = doc.comp.layers.first;
    doc.selectLayer(paintLayer.id);
    doc.addBlankKey(at: 4);
    doc.toggleMarker(at: 6, label: 'M');
    doc.setLoopRange(2, 9);

    final playback = Playback(AppState.I);
    addTearDown(() {
      playback.dispose();
      doc.dispose();
    });

    await tester.pumpWidget(_wrap(TimelinePanel(doc: doc, playback: playback, frameWidth: 8)));

    // Group row appears in layer column and has no cel blocks.
    expect(find.byKey(ValueKey('timeline.row.$groupId')), findsOneWidget);
    expect(find.byKey(ValueKey('cel:$groupId:0')), findsNothing);
    // Blank exposure at 4 renders block without drawing number '0'.
    expect(find.byKey(ValueKey('cel:${paintLayer.id}:4')), findsOneWidget);
    expect(find.text('0'), findsNothing);

    // Transport buttons & loop toggle
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pump();
    expect(doc.frame, 1);

    await tester.tap(find.byIcon(Icons.last_page));
    await tester.pump();
    expect(doc.frame, 11);

    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pump();
    expect(doc.frame, 10);

    await tester.tap(find.byIcon(Icons.first_page));
    await tester.pump();
    expect(doc.frame, 0);

    final initialLoop = playback.loop;
    await tester.tap(find.byIcon(Icons.repeat));
    await tester.pump();
    expect(playback.loop, !initialLoop);
  });
}
