import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../platform/io.dart';
import 'audio_sync.dart';

/// [AudioBackend] on top of the audioplayers plugin. Native platforms play
/// from a temporary copy of each asset (written once); the web plays bytes.
class PluginAudioBackend implements AudioBackend {
  final Map<String, String> _files = {};

  Future<Source> _source(String key, Uint8List bytes, AudioFormat format) async {
    if (kIsWeb || !hasFileSystem) return BytesSource(bytes, mimeType: format.mime);
    var path = _files[key];
    if (path == null || !await fileExists(path)) {
      final dir = p.join((await tempDir()) ?? '.', 'drawly_audio');
      await ensureDir(dir);
      path = p.join(dir, '$key.${format.ext}');
      if (!await writeFileBytes(path, bytes)) return BytesSource(bytes, mimeType: format.mime);
      _files[key] = path;
    }
    return DeviceFileSource(path, mimeType: format.mime);
  }

  @override
  Future<AudioVoice> voice(String assetId, Uint8List bytes, AudioFormat format) async {
    final player = AudioPlayer();
    await player.setReleaseMode(ReleaseMode.stop);
    await player.setSource(await _source(assetId, bytes, format));
    return _PluginVoice(player);
  }

  @override
  Future<double?> durationOf(Uint8List bytes, AudioFormat format) async {
    final player = AudioPlayer();
    try {
      await player.setSource(await _source('probe_${bytes.length}_${bytes.hashCode}', bytes, format));
      final d = await player.getDuration();
      return d == null ? null : d.inMicroseconds / 1e6;
    } catch (_) {
      return null;
    } finally {
      await player.dispose();
    }
  }
}

class _PluginVoice implements AudioVoice {
  _PluginVoice(this.player);
  final AudioPlayer player;

  @override
  Future<void> play({required double from}) async {
    if (from > 0) await player.seek(Duration(microseconds: (from * 1e6).round()));
    await player.resume();
  }

  @override
  Future<void> setVolume(double v) => player.setVolume(v.clamp(0.0, 1.0));

  @override
  Future<void> stop() => player.stop();

  @override
  Future<void> dispose() => player.dispose();
}
