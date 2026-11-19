import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:record/record.dart';

import '../core/i18n.dart';
import '../engine/audio/wav.dart';
import '../platform/io.dart' as io;
import 'doc_timeline.dart';
import 'document_controller.dart';
import 'playback.dart';

/// Records a voice clip while the animation plays (like dubbing): the clip is
/// added to the timeline at the frame where recording started.
class VoiceRecorder extends ChangeNotifier {
  VoiceRecorder([this._recorder]);
  AudioRecorder? _recorder;
  DocumentController? _doc;
  Playback? _playback;
  int _startFrame = 0;
  String? _path;

  bool get recording => _doc != null;

  /// Starts recording on [doc]; also starts [playback]. Returns an error message, or null.
  Future<String?> start(DocumentController doc, Playback playback) async {
    if (recording) return null;
    if (kIsWeb || !io.hasFileSystem) return tr('Grabar voz no está disponible en la web', 'Voice recording is not available on the web');
    final rec = _recorder ??= AudioRecorder();
    if (!await rec.hasPermission()) return tr('Drawly no tiene permiso para usar el micrófono', 'Drawly has no permission to use the microphone');
    final dir = p.join((await io.tempDir()) ?? '.', 'drawly_voice');
    await io.ensureDir(dir);
    final path = p.join(dir, 'voz_${DateTime.now().millisecondsSinceEpoch}.wav');
    await rec.start(const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 44100, numChannels: 1), path: path);
    _doc = doc;
    _playback = playback;
    _startFrame = doc.frame;
    _path = path;
    playback.play();
    notifyListeners();
    return null;
  }

  /// Stops and adds the clip. Returns its length in seconds, or null when nothing was recorded.
  Future<double?> stop() async {
    final doc = _doc, rec = _recorder;
    if (doc == null || rec == null) return null;
    _doc = null;
    _playback?.stop();
    notifyListeners();
    final path = await rec.stop() ?? _path;
    if (path == null) return null;
    final bytes = await io.readFileBytes(path);
    await io.deleteFile(path);
    if (bytes == null || !isWav(bytes)) return null;
    final seconds = decodeWav(bytes).duration;
    if (seconds <= 0.05) return null;
    doc.addAudioClip(tr('Voz', 'Voice'), bytes, seconds, kind: 'voice', startFrame: _startFrame);
    return seconds;
  }

  @override
  void dispose() {
    _recorder?.dispose();
    super.dispose();
  }
}
