import 'dart:convert';
import 'dart:io';

import 'package:drawly/app/doc_timeline.dart';
import 'package:drawly/app/document_controller.dart';
import 'package:drawly/io/image_export.dart';
import 'package:drawly/model/document.dart';
import 'package:drawly/ui/dialogs/export_dialog.dart';
import 'package:drawly/ui/file_commands.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late DocumentController doc;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('drawly_export_');
    doc = DocumentController(Project.blank(width: 40, height: 20), title: 'clip');
    doc.setLength(6);
  });
  tearDown(() {
    doc.dispose();
    dir.deleteSync(recursive: true);
  });

  test('still PNG at 50 % has half the size', () async {
    final out = await writeExport(doc, const ExportOptions(kind: ExportKind.still, scale: 0.5), dir.path);
    expect(out, hasLength(1));
    final im = img.decodePng(File(out.single).readAsBytesSync())!;
    expect([im.width, im.height], [20, 10]);
  });

  test('sequence writes one numbered file per frame of the range', () async {
    final out = await writeExport(doc, const ExportOptions(kind: ExportKind.sequence, rangeStart: 1, rangeEnd: 4), dir.path);
    expect(out.map((e) => e.split(Platform.pathSeparator).last), ['clip_0000.png', 'clip_0001.png', 'clip_0002.png']);
  });

  test('GIF animation has one frame per frame of the range', () async {
    final out = await writeExport(doc, const ExportOptions(kind: ExportKind.animation, anim: AnimFormat.gif, rangeStart: 0, rangeEnd: 3), dir.path);
    final anim = img.decodeGif(File(out.single).readAsBytesSync())!;
    expect(anim.numFrames, 3);
  });

  test('sprite sheet writes PNG and TexturePacker JSON', () async {
    final out = await writeExport(doc, const ExportOptions(kind: ExportKind.spriteSheet, rangeStart: 0, rangeEnd: 4, columns: 2), dir.path);
    expect(out.map((e) => e.split('.').last), ['png', 'json']);
    final sheet = img.decodePng(File(out.first).readAsBytesSync())!;
    expect([sheet.width, sheet.height], [80, 40]);
    final meta = jsonDecode(File(out.last).readAsStringSync()) as Map<String, dynamic>;
    expect((meta['frames'] as Map).length, 4);
  });
}
