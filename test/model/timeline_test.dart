import 'dart:convert';
import 'dart:ui';

import 'package:drawly/model/anim.dart';
import 'package:drawly/model/document.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Timeline range', () {
    test('without loop points the range is the whole timeline', () {
      const t = Timeline(length: 24);
      expect(t.rangeStart, 0);
      expect(t.rangeEnd, 24);
    });

    test('with loop points', () {
      const t = Timeline(length: 24, loopStart: 5, loopEnd: 10);
      expect(t.rangeStart, 5);
      expect(t.rangeEnd, 10);
    });

    test('out of range values are clamped', () {
      expect(const Timeline(length: 24, loopStart: -3).rangeStart, 0);
      expect(const Timeline(length: 24, loopStart: 30).rangeStart, 23);
      expect(const Timeline(length: 24, loopEnd: 100).rangeEnd, 24);
      expect(const Timeline(length: 24, loopStart: 5, loopEnd: 2).rangeEnd, 6, reason: 'end stays after start');
      expect(const Timeline(length: 24, loopStart: 30, loopEnd: 100).rangeEnd, 24);
    });

    test('copyWith(loopStart: null) clears the value', () {
      const t = Timeline(length: 24, loopStart: 5, loopEnd: 10);
      final cleared = t.copyWith(loopStart: null);
      expect(cleared.loopStart, isNull);
      expect(cleared.loopEnd, 10);
      expect(t.copyWith(fps: 30).loopStart, 5, reason: 'omitted arguments are kept');
    });
  });

  test('Timeline JSON round trip', () {
    const t = Timeline(
      fps: 24,
      length: 96,
      loopStart: 4,
      loopEnd: 60,
      markers: [Marker(3, 'hit', 0xFF00FF00), Marker(40, 'beat')],
      scenes: [
        Scene(id: 'sc1', name: 'Intro', start: 0, length: 48, notes: 'wide', transition: 'fade', transitionFrames: 6),
        Scene(id: 'sc2', name: 'Close', start: 48, length: 48),
      ],
      camera: Camera(
        enabled: true,
        tracks: {
          Prop.x: AnimTrack([AnimKey(0, 0, Ease.linear), AnimKey(24, 120)]),
          Prop.zoom: AnimTrack([AnimKey(0, 1), AnimKey(48, 2.5, Ease(EaseType.bezier, 0.3, 0, 0.2, 1))]),
        },
        shakeAmp: 3,
        shakeFreq: 4,
        focalLength: 800,
        focusDepth: 10,
        aperture: 2,
      ),
      audio: [
        AudioClip(id: 'a1', name: 'song', assetId: 'asset1', startFrame: 12, volume: 0.8, fadeIn: 0.5, fadeOut: 1.5, trimStart: 0.25, trimEnd: 0.75, muted: true, duration: 30, kind: 'voice'),
      ],
    );

    final back = Timeline.fromJson(jsonDecode(jsonEncode(t.toJson())));
    expect(back.fps, 24);
    expect(back.length, 96);
    expect(back.loopStart, 4);
    expect(back.loopEnd, 60);

    expect(back.markers.length, 2);
    expect(back.markers[0].frame, 3);
    expect(back.markers[0].label, 'hit');
    expect(back.markers[0].color, 0xFF00FF00);
    expect(back.markers[1].color, 0xFFFFC107);

    expect(back.scenes.length, 2);
    final s = back.scenes[0];
    expect([s.id, s.name, s.notes, s.transition], ['sc1', 'Intro', 'wide', 'fade']);
    expect([s.start, s.length, s.transitionFrames], [0, 48, 6]);
    expect(back.scenes[1].transition, 'cut');

    final cam = back.camera;
    expect(cam.enabled, isTrue);
    expect([cam.shakeAmp, cam.shakeFreq, cam.focalLength, cam.focusDepth, cam.aperture], [3, 4, 800, 10, 2]);
    expect(cam.tracks.keys.toSet(), {Prop.x, Prop.zoom});
    expect(cam.tracks[Prop.zoom]!.keys[1].value, 2.5);
    expect(cam.tracks[Prop.zoom]!.keys[1].ease, const Ease(EaseType.bezier, 0.3, 0, 0.2, 1));
    expect(cam.valueAt(Prop.x, 12), closeTo(60, 1e-9));

    expect(back.audio.length, 1);
    final a = back.audio[0];
    expect([a.id, a.name, a.assetId, a.kind], ['a1', 'song', 'asset1', 'voice']);
    expect(a.startFrame, 12);
    expect([a.volume, a.fadeIn, a.fadeOut, a.trimStart, a.trimEnd, a.duration], [0.8, 0.5, 1.5, 0.25, 0.75, 30]);
    expect(a.muted, isTrue);

    final noLoop = Timeline.fromJson(jsonDecode(jsonEncode(const Timeline().toJson())));
    expect(noLoop.loopStart, isNull);
    expect(noLoop.loopEnd, isNull);
  });

  group('Camera.matrixAt', () {
    const comp = Size(400, 300);

    test('identity when disabled', () {
      const cam = Camera(tracks: {
        Prop.zoom: AnimTrack([AnimKey(0, 2)]),
      });
      expect(cam.matrixAt(0, comp).isIdentity, isTrue);
    });

    test('zoom 2 keeps the composition centre fixed', () {
      const cam = Camera(enabled: true, tracks: {
        Prop.zoom: AnimTrack([AnimKey(0, 2)]),
      });
      final m = cam.matrixAt(0, comp);
      final centre = m.apply(const Offset(200, 150));
      expect(centre.dx, closeTo(200, 1e-9));
      expect(centre.dy, closeTo(150, 1e-9));
      final corner = m.apply(Offset.zero);
      expect(corner.dx, closeTo(-200, 1e-9));
      expect(corner.dy, closeTo(-150, 1e-9));
    });
  });
}
