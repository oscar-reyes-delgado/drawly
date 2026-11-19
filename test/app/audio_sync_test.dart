import 'dart:typed_data';

import 'package:drawly/app/audio_sync.dart';
import 'package:drawly/model/document.dart';
import 'package:flutter_test/flutter_test.dart';

class _Voice implements AudioVoice {
  _Voice(this.log, this.id);
  final List<String> log;
  final String id;
  final volumes = <double>[];
  @override
  Future<void> play({required double from}) async => log.add('play $id ${from.toStringAsFixed(2)}');
  @override
  Future<void> setVolume(double v) async => volumes.add(v);
  @override
  Future<void> stop() async => log.add('stop $id');
  @override
  Future<void> dispose() async => log.add('dispose $id');
}

class _Backend implements AudioBackend {
  final log = <String>[];
  final voices = <_Voice>[];
  @override
  Future<AudioVoice> voice(String assetId, Uint8List bytes, AudioFormat format) async {
    final v = _Voice(log, assetId);
    voices.add(v);
    return v;
  }

  @override
  Future<double?> durationOf(Uint8List bytes, AudioFormat format) async => 1;
}

AudioClip _clip(String id, {int start = 0, double duration = 4, double trimStart = 0, bool muted = false, double fadeIn = 0, double fadeOut = 0}) =>
    AudioClip(id: id, name: id, assetId: 'a$id', startFrame: start, duration: duration, trimStart: trimStart, muted: muted, fadeIn: fadeIn, fadeOut: fadeOut);

void main() {
  test('sniffAudio recognises WAV, MP3 and OGG headers', () {
    expect(sniffAudio(Uint8List.fromList('RIFF\x00\x00\x00\x00WAVEfmt '.codeUnits)), AudioFormat.wav);
    expect(sniffAudio(Uint8List.fromList('ID3\x04'.codeUnits)), AudioFormat.mp3);
    expect(sniffAudio(Uint8List.fromList([0xFF, 0xFB, 0x90, 0x00])), AudioFormat.mp3);
    expect(sniffAudio(Uint8List.fromList('OggS\x00'.codeUnits)), AudioFormat.ogg);
    expect(sniffAudio(Uint8List.fromList([1, 2, 3])), AudioFormat.unknown);
  });

  test('cues: delay before a clip, offset inside it, ended and muted clips skipped', () {
    final t = Timeline(fps: 10, length: 100, audio: [
      _clip('a', start: 0, duration: 4, trimStart: 1), // plays 3 s from source 1 s
      _clip('b', start: 20, duration: 2), // starts at 2 s
      _clip('c', start: 0, duration: 0.5), // already over at 1 s
      _clip('d', start: 0, muted: true),
    ]);
    final cues = audioCuesAt(t, 10); // 1 s
    expect(cues.map((c) => c.clip.id), ['a', 'b']);
    final a = cues[0], b = cues[1];
    expect(a.delay, 0);
    expect(a.offset, closeTo(2, 1e-9), reason: 'trim 1 s + 1 s already played');
    expect(a.length, closeTo(2, 1e-9));
    expect(b.delay, closeTo(1, 1e-9));
    expect(b.offset, 0);
  });

  test('fades scale the volume at both ends', () {
    final c = _clip('f', duration: 4, fadeIn: 1, fadeOut: 2);
    expect(clipVolumeAt(c, 0), 0);
    expect(clipVolumeAt(c, 0.5), closeTo(0.5, 1e-9));
    expect(clipVolumeAt(c, 1.5), 1);
    expect(clipVolumeAt(c, 3), closeTo(0.5, 1e-9));
  });

  test('start plays the clips that sound now and later; stop silences everything', () async {
    final backend = _Backend();
    final sync = AudioSync(backend);
    final project = Project(comps: const {}, mainId: '', assets: {'aa': Uint8List(4), 'ab': Uint8List(4)});
    final t = Timeline(fps: 10, length: 100, audio: [_clip('a', duration: 4), _clip('b', start: 1, duration: 4)]);
    await sync.start(project, t, 0);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(backend.log, contains('play aa 0.00'));
    expect(backend.log.where((l) => l.startsWith('play ab')), isEmpty, reason: 'b starts 0.1 s later');
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(backend.log, contains('play ab 0.00'));
    await sync.stop();
    expect(backend.log, containsAll(['stop aa', 'dispose aa', 'stop ab', 'dispose ab']));
    expect(sync.activeVoices, 0);
  });

  test('stopping before a delayed clip begins never plays it; other speeds stay silent', () async {
    final backend = _Backend();
    final sync = AudioSync(backend);
    final project = Project(comps: const {}, mainId: '', assets: {'aa': Uint8List(4)});
    final t = Timeline(fps: 10, length: 100, audio: [_clip('a', start: 5)]);
    await sync.start(project, t, 0);
    await sync.stop();
    await Future<void>.delayed(const Duration(milliseconds: 700));
    expect(backend.voices, isEmpty);
    await sync.start(project, t, 5, speed: 2);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(backend.voices, isEmpty);
    await sync.dispose();
  });
}
