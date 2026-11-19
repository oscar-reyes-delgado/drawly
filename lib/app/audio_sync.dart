import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import '../model/document.dart';

/// Container format of an audio asset, sniffed from its first bytes.
enum AudioFormat { wav, mp3, ogg, unknown }

AudioFormat sniffAudio(Uint8List b) {
  bool at(int i, List<int> sig) => b.length >= i + sig.length && [for (var k = 0; k < sig.length; k++) b[i + k] == sig[k]].every((x) => x);
  if (at(0, const [0x52, 0x49, 0x46, 0x46]) && at(8, const [0x57, 0x41, 0x56, 0x45])) return AudioFormat.wav;
  if (at(0, const [0x4F, 0x67, 0x67, 0x53])) return AudioFormat.ogg;
  if (at(0, const [0x49, 0x44, 0x33]) || (b.length > 1 && b[0] == 0xFF && (b[1] & 0xE0) == 0xE0)) return AudioFormat.mp3;
  return AudioFormat.unknown;
}

extension AudioFormatX on AudioFormat {
  String get ext => switch (this) { AudioFormat.wav => 'wav', AudioFormat.mp3 => 'mp3', AudioFormat.ogg => 'ogg', AudioFormat.unknown => 'bin' };
  String get mime => switch (this) { AudioFormat.wav => 'audio/wav', AudioFormat.mp3 => 'audio/mpeg', AudioFormat.ogg => 'audio/ogg', AudioFormat.unknown => 'application/octet-stream' };
}

/// When and how one clip sounds if playback starts at a given frame.
class AudioCue {
  const AudioCue({required this.clip, required this.delay, required this.offset, required this.length});
  final AudioClip clip;

  /// Seconds from the start of playback until the clip begins (0 = already playing).
  final double delay;

  /// Seconds into the source file where playback starts (includes the trim).
  final double offset;

  /// Seconds the clip sounds from that point.
  final double length;
}

/// Cues for every audible clip of [t] when playback starts at [frame]
/// (clips that already ended are left out).
List<AudioCue> audioCuesAt(Timeline t, double frame) {
  final now = frame / t.fps;
  final out = <AudioCue>[];
  for (final c in t.audio) {
    if (c.muted || c.volume <= 0 || c.playLength <= 0) continue;
    final start = c.startFrame / t.fps;
    final end = start + c.playLength;
    if (now >= end) continue;
    final delay = math.max(0.0, start - now);
    final into = math.max(0.0, now - start);
    out.add(AudioCue(clip: c, delay: delay, offset: c.trimStart + into, length: c.playLength - into));
  }
  return out;
}

/// Volume of [c] (0..1) [t] seconds after the clip's (trimmed) start, with fades.
double clipVolumeAt(AudioClip c, double t) {
  var v = c.volume.clamp(0.0, 1.0);
  if (c.fadeIn > 0 && t < c.fadeIn) v *= (t / c.fadeIn).clamp(0.0, 1.0);
  final left = c.playLength - t;
  if (c.fadeOut > 0 && left < c.fadeOut) v *= (left / c.fadeOut).clamp(0.0, 1.0);
  return v;
}

/// One sound being played; implemented by the platform player.
abstract class AudioVoice {
  Future<void> play({required double from});
  Future<void> setVolume(double v);
  Future<void> stop();
  Future<void> dispose();
}

/// Creates voices; the app uses the audioplayers implementation, tests a fake.
abstract class AudioBackend {
  Future<AudioVoice> voice(String assetId, Uint8List bytes, AudioFormat format);

  /// Duration of an audio file in seconds, or null when the platform cannot tell.
  Future<double?> durationOf(Uint8List bytes, AudioFormat format);
}

/// Plays the audio clips of the document in step with the timeline playback.
/// [start] (re)starts every clip from a frame; [stop] silences everything.
class AudioSync {
  AudioSync(this.backend);
  final AudioBackend backend;

  final List<_Playing> _playing = [];
  int _generation = 0;
  Timer? _fader;

  /// Clips currently sounding or waiting to start (for tests).
  int get activeVoices => _playing.length;

  Future<void> start(Project project, Timeline t, double frame, {double speed = 1}) async {
    await stop();
    if (speed != 1) return; // pitch-correct speed changes are not supported: stay silent
    final gen = _generation;
    for (final cue in audioCuesAt(t, frame)) {
      final bytes = project.assets[cue.clip.assetId];
      if (bytes == null) continue;
      final p = _Playing(cue);
      _playing.add(p);
      p.timer = Timer(Duration(microseconds: (cue.delay * 1e6).round()), () async {
        if (gen != _generation) return;
        try {
          final v = await backend.voice(cue.clip.assetId, bytes, sniffAudio(bytes));
          if (gen != _generation) {
            await v.dispose();
            return;
          }
          p.voice = v;
          p.clock = Stopwatch()..start();
          final into = cue.offset - cue.clip.trimStart;
          p.startedAt = into;
          await v.setVolume(clipVolumeAt(cue.clip, into));
          await v.play(from: cue.offset);
        } catch (_) {
          // a clip that cannot be played stays silent; the animation goes on
        }
      });
    }
    _fader = Timer.periodic(const Duration(milliseconds: 50), (_) => _fade());
  }

  void _fade() {
    for (final p in [..._playing]) {
      final v = p.voice, clock = p.clock;
      if (v == null || clock == null) continue;
      final t = p.startedAt + clock.elapsedMicroseconds / 1e6;
      if (t >= p.cue.clip.playLength) {
        _playing.remove(p);
        unawaited(v.stop().then((_) => v.dispose()));
        continue;
      }
      unawaited(v.setVolume(clipVolumeAt(p.cue.clip, t)));
    }
  }

  Future<void> stop() async {
    _generation++;
    _fader?.cancel();
    _fader = null;
    final all = [..._playing];
    _playing.clear();
    for (final p in all) {
      p.timer?.cancel();
      final v = p.voice;
      if (v != null) {
        try {
          await v.stop();
          await v.dispose();
        } catch (_) {}
      }
    }
  }

  Future<void> dispose() => stop();
}

class _Playing {
  _Playing(this.cue);
  final AudioCue cue;
  Timer? timer;
  AudioVoice? voice;
  Stopwatch? clock;
  double startedAt = 0;
}
