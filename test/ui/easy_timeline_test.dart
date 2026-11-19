import 'package:drawly/app/app_state.dart';
import 'package:drawly/app/doc_frames.dart';
import 'package:drawly/app/document_controller.dart';
import 'package:drawly/app/easy_defaults.dart';
import 'package:drawly/app/frame_thumbs.dart';
import 'package:drawly/app/playback.dart';
import 'package:drawly/app/settings.dart';
import 'package:drawly/engine/tiles.dart';
import 'package:drawly/model/layer.dart';
import 'package:drawly/tools/registry.dart';
import 'package:drawly/ui/easy/easy_timeline.dart';
import 'package:drawly/ui/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Puts a distinct drawing on the «Dibujo» layer at every frame.
void _drawEveryFrame(DocumentController d) {
  final layer = d.comp.layers.last as PaintLayer;
  final n = d.frameCount;
  final drawings = <int, TilePlane>{};
  final xs = <Exposure>[];
  for (var f = 0; f < n; f++) {
    final r = Rect.fromLTWH(f * 4.0, 4, 4, 4);
    drawings[f + 1] = TilePlane.empty.drawn((c) => c.drawRect(r, Paint()..color = const Color(0xFF000000)), area: r);
    xs.add(Exposure(f, f + 1));
  }
  d.updateLayer('draw', layer.id, (l) => (l as PaintLayer).withCels(CelTrack(drawings: drawings, xs: xs)));
}

int? _id(DocumentController d, int f) => (d.comp.layers.last as PaintLayer).cels.drawingIdAt(f);

void main() {
  final app = AppState.I;
  late DocumentController doc;
  late Playback playback;
  late FrameThumbnailCache thumbs;

  Future<void> pump(WidgetTester tester, {int frames = 1}) async {
    tester.view.physicalSize = const Size(1000, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    if (app.toolMap.isEmpty) registerTools(app);
    while (app.docs.isNotEmpty) {
      app.closeDocument(app.docs.first);
    }
    doc = app.addDocument(easyProject(width: 64, height: 48), title: 't');
    if (frames > 1) doc.insertFrames(count: frames - 1);
    doc.frame = 0;
    doc.history.clear(doc.history.current);
    playback = Playback(app);
    thumbs = FrameThumbnailCache(height: 40);
    addTearDown(() {
      playback.stop();
      thumbs.dispose();
    });

    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Settings(), Brightness.dark),
      home: Scaffold(body: Align(alignment: Alignment.bottomCenter, child: EasyTimeline(doc: doc, playback: playback, thumbs: thumbs, height: 130))),
    ));
    await tester.pump();
  }

  /// Drains the thumbnail queue (zero-length timers) before the test body ends.
  Future<void> finish(WidgetTester tester) async {
    thumbs.paused = true;
    await tester.pump(const Duration(milliseconds: 10));
  }

  testWidgets('one card; «+» adds a frame and selects it; tapping a card selects it', (tester) async {
    await pump(tester);
    expect(find.byKey(const ValueKey('easy.frame.0')), findsOneWidget);
    expect(find.byKey(const ValueKey('easy.frame.1')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('easy.addFrame')));
    await tester.pump();
    expect(doc.frameCount, 2);
    expect(doc.frame, 1);
    expect(find.byKey(const ValueKey('easy.frame.1')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('easy.frame.0')));
    await tester.pump();
    expect(doc.frame, 0);
    await finish(tester);
  });

  testWidgets('context menu duplicates and deletes; delete is disabled with one frame', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('easy.frame.0')), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    final del = tester.widget<PopupMenuItem<String>>(find.byKey(const ValueKey('easy.menu.delete')));
    expect(del.enabled, isFalse);
    await tester.tap(find.text('Duplicar'));
    await tester.pumpAndSettle();
    expect(doc.frameCount, 2);
    await tester.tap(find.byKey(const ValueKey('easy.addFrame')));
    await tester.pump();
    expect(doc.frameCount, 3);
    await tester.tap(find.byKey(const ValueKey('easy.frame.2')), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('easy.menu.delete')));
    await tester.pumpAndSettle();
    expect(doc.frameCount, 2);
    await finish(tester);
  });

  testWidgets('Shift + tap selects a range; Reverse swaps its drawings', (tester) async {
    await pump(tester, frames: 3);
    _drawEveryFrame(doc);
    final a = _id(doc, 0), b = _id(doc, 1);
    await tester.tap(find.byKey(const ValueKey('easy.frame.0')));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tap(find.byKey(const ValueKey('easy.frame.1')));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('easy.frame.1')), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Invertir'));
    await tester.pumpAndSettle();
    expect([_id(doc, 0), _id(doc, 1)], [b, a]);
    await finish(tester);
  });

  testWidgets('long-press drag of the first card behind the third reorders', (tester) async {
    await pump(tester, frames: 3);
    _drawEveryFrame(doc);
    final ids = [_id(doc, 0), _id(doc, 1), _id(doc, 2)];
    await tester.pump();
    final from = tester.getCenter(find.byKey(const ValueKey('easy.frame.0')));
    final to = tester.getCenter(find.byKey(const ValueKey('easy.frame.2')));
    final g = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 500));
    await g.moveBy(const Offset(10, 0));
    await tester.pump();
    await g.moveTo(to);
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();
    expect([_id(doc, 0), _id(doc, 1), _id(doc, 2)], [ids[1], ids[2], ids[0]]);
    await finish(tester);
  });

  testWidgets('onion toggle, fps choice and play pause thumbnails', (tester) async {
    await pump(tester, frames: 4);
    expect(doc.onion.enabled, isFalse);
    await tester.tap(find.byKey(const ValueKey('easy.onion')));
    await tester.pump();
    expect(doc.onion.enabled, isTrue);

    await tester.tap(find.byKey(const ValueKey('easy.fps')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('24 fps').last);
    await tester.pumpAndSettle();
    expect(doc.timeline.fps, 24);

    await tester.tap(find.byKey(const ValueKey('easy.play')));
    await tester.pump();
    expect(playback.playing, isTrue);
    expect(thumbs.paused, isTrue);
    await tester.tap(find.byKey(const ValueKey('easy.play')));
    await tester.pump();
    expect(playback.playing, isFalse);
    expect(thumbs.paused, isFalse);
    await finish(tester);
  });

  testWidgets('phone width: no overflow', (tester) async {
    await pump(tester, frames: 3);
    tester.view.physicalSize = const Size(360, 640);
    await tester.pump();
    expect(tester.takeException(), isNull);
    await finish(tester);
  });
}
