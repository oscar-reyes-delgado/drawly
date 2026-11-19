import 'dart:io';

import 'package:drawly/app/doc_frames.dart';
import 'package:drawly/app/document_controller.dart';
import 'package:drawly/app/easy_defaults.dart';
import 'package:drawly/app/file_ops.dart';
import 'package:drawly/platform/video_encoder.dart';
import 'package:drawly/ui/file_commands.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Runs on a device or desktop: `flutter test integration_test/video_mp4_test.dart -d windows`.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('MP4 export writes a valid file with the platform encoder', () async {
    expect(await VideoEncoder.isAvailable(), isTrue, reason: 'Windows and Android provide an encoder');
    final d = DocumentController(easyProject(width: 161, height: 99), title: 'clip');
    d.insertFrames(count: 5);
    final dir = Directory.systemTemp.createTempSync('drawly_mp4_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final progress = <double>[];
    final out = await writeMp4(d, dir.path, onProgress: progress.add);
    expect(out, hasLength(1));
    final bytes = File(out.single).readAsBytesSync();
    expect(bytes.length, greaterThan(200));
    expect(String.fromCharCodes(bytes.sublist(4, 8)), 'ftyp', reason: 'an ISO media (MP4) file');
    expect(progress.last, 1);

    final token = CancelToken();
    final cancelled = await writeMp4(d, dir.path, onProgress: (v) {
      if (v > 0.3) token.cancel();
    }, cancel: token);
    expect(cancelled, isEmpty);
    expect(File('${dir.path}/clip.mp4').existsSync(), isFalse, reason: 'a cancelled export leaves no file');
  });
}
