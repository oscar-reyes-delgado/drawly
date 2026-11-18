import 'dart:math' as math;
import 'dart:typed_data';

import 'package:drawly/app/document_controller.dart';
import 'package:drawly/engine/audio/wav.dart';
import 'package:drawly/model/document.dart';
import 'package:drawly/ui/interchange_commands.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('importWavClip adds a clip with its duration and stores the bytes as an asset', () {
    const rate = 8000;
    final samples = Float32List.fromList([for (var i = 0; i < rate * 2; i++) math.sin(i * 2 * math.pi * 440 / rate) * 0.5]);
    final bytes = encodeWav(AudioBuffer(rate, [samples]));
    final d = DocumentController(Project.blank(width: 32, height: 32, frames: 12, fps: 12), title: 'a');
    d.frame = 3;

    final secs = importWavClip(d, 'voz.wav', bytes);
    expect(secs, closeTo(2, 0.01));
    final clip = d.timeline.audio.single;
    expect([clip.name, clip.startFrame], ['voz', 3]);
    expect(d.project.assets[clip.assetId], bytes);
    expect(d.timeline.length, greaterThanOrEqualTo(3 + 24), reason: 'timeline grows to fit the clip');
    d.undo();
    expect(d.timeline.audio, isEmpty);
  });

  test('importWavClip rejects files that are not WAV', () {
    final d = DocumentController(Project.blank(width: 32, height: 32), title: 'a');
    expect(() => importWavClip(d, 'x.wav', Uint8List.fromList([1, 2, 3, 4])), throwsFormatException);
    expect(d.timeline.audio, isEmpty);
  });
}
