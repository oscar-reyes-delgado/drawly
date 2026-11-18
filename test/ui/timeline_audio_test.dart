import 'dart:math' as math;
import 'dart:typed_data';

import 'package:drawly/app/app_state.dart';
import 'package:drawly/app/document_controller.dart';
import 'package:drawly/app/playback.dart';
import 'package:drawly/engine/audio/wav.dart';
import 'package:drawly/model/document.dart';
import 'package:drawly/ui/interchange_commands.dart';
import 'package:drawly/ui/theme.dart';
import 'package:drawly/ui/timeline/timeline_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('audio clips show as rows that can be muted and moved', (tester) async {
    tester.view.physicalSize = const Size(1200, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    const rate = 8000;
    final s = Float32List.fromList([for (var i = 0; i < rate; i++) math.sin(i * 0.3) * 0.8]);
    final d = DocumentController(Project.blank(width: 32, height: 32, frames: 24, fps: 12), title: 'a');
    importWavClip(d, 'voz.wav', encodeWav(AudioBuffer(rate, [s])));
    final clip = d.timeline.audio.single;

    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(AppState.I.settings, Brightness.dark),
      home: Scaffold(body: SizedBox(height: 300, child: TimelinePanel(doc: d, playback: Playback(AppState.I)))),
    ));
    await tester.pump();
    expect(find.text('voz'), findsOneWidget);
    expect(find.byKey(ValueKey('timeline.audioRow.${clip.id}')), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('timeline.audioMute.${clip.id}')));
    await tester.pump();
    expect(d.timeline.audio.single.muted, isTrue);

    await tester.drag(find.byKey(ValueKey('timeline.audioClip.${clip.id}')), const Offset(14.0 * 3, 0));
    await tester.pump();
    expect(d.timeline.audio.single.startFrame, 3);
  });
}
