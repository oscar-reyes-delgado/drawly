import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:drawly/app/project_library.dart';
import 'package:drawly/io/project_codec.dart';
import 'package:drawly/model/document.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late ProjectLibrary library;
  late Uint8List sampleDrawlyBytes;
  late Uint8List sampleDrawlyNoThumbBytes;

  setUpAll(() async {
    sampleDrawlyBytes = await ProjectCodec.encode(Project.blank(width: 32, height: 32));
    sampleDrawlyNoThumbBytes = await ProjectCodec.encode(Project.blank(width: 32, height: 32), thumbnail: false);
  });

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('drawly_project_library_test_');
    library = ProjectLibrary(tempDir.path);
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  File writeDrawly(String name, Uint8List bytes) {
    final file = File(p.join(tempDir.path, name));
    file.writeAsBytesSync(bytes);
    return file;
  }

  test('list ignores non-drawly files and subdirectories, and sorts by name and modified', () async {
    final fBeta = writeDrawly('beta.drawly', sampleDrawlyBytes);
    final fAlpha = writeDrawly('Alpha.drawly', sampleDrawlyBytes);
    final fGamma = writeDrawly('gamma.DRAWLY', sampleDrawlyBytes);
    File(p.join(tempDir.path, 'notes.txt')).writeAsStringSync('ignore');
    File(p.join(tempDir.path, 'temp.drawly.tmp')).writeAsBytesSync(sampleDrawlyBytes);
    Directory(p.join(tempDir.path, 'subdir.drawly')).createSync();

    final baseTime = DateTime(2026, 1, 1, 12, 0);
    await fAlpha.setLastModified(baseTime);
    await fBeta.setLastModified(baseTime.add(const Duration(minutes: 10)));
    await fGamma.setLastModified(baseTime.add(const Duration(minutes: 5)));

    final byNameAsc = await library.list(sort: ProjectSort.name, descending: false);
    expect(byNameAsc.map((e) => e.name).toList(), ['Alpha', 'beta', 'gamma']);
    expect(byNameAsc.every((e) => p.isAbsolute(e.path)), isTrue);
    expect(byNameAsc.every((e) => e.size == sampleDrawlyBytes.length), isTrue);

    final byModifiedDesc = await library.list(sort: ProjectSort.modified, descending: true);
    expect(byModifiedDesc.map((e) => e.name).toList(), ['beta', 'gamma', 'Alpha']);
  });

  test('thumbnail returns PNG bytes for valid project and null for garbage; isValid checks manifest', () async {
    final validFile = writeDrawly('valid.drawly', sampleDrawlyBytes);
    final noThumbFile = writeDrawly('nothumb.drawly', sampleDrawlyNoThumbBytes);
    final garbageFile = writeDrawly('garbage.drawly', Uint8List.fromList(utf8.encode('not a zip')));

    final wrongArchive = Archive()..addFile(ArchiveFile.string('manifest.json', jsonEncode({'format': 'other'})));
    final wrongZipFile = writeDrawly('wrong.drawly', Uint8List.fromList(ZipEncoder().encodeBytes(wrongArchive)));

    final thumb = await library.thumbnail(validFile.path);
    expect(thumb, isNotNull);
    expect(thumb!.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
    expect(await library.isValid(validFile.path), isTrue);

    expect(await library.thumbnail(noThumbFile.path), isNull);
    expect(await library.isValid(noThumbFile.path), isTrue);

    expect(await library.thumbnail(garbageFile.path), isNull);
    expect(await library.isValid(garbageFile.path), isFalse);

    expect(await library.isValid(wrongZipFile.path), isFalse);
    expect(await library.isValid(p.join(tempDir.path, 'missing.drawly')), isFalse);
  });

  test('rename sanitizes invalid filename characters and rejects empty or existing targets', () async {
    final original = writeDrawly('original.drawly', sampleDrawlyBytes);
    writeDrawly('existente.drawly', sampleDrawlyBytes);

    final renamedPath = await library.rename(original.path, 'Mi: dibujo?');
    expect(p.basename(renamedPath), 'Mi dibujo.drawly');
    expect(File(renamedPath).existsSync(), isTrue);
    expect(original.existsSync(), isFalse);

    await expectLater(library.rename(renamedPath, 'existente'), throwsArgumentError);
    await expectLater(library.rename(renamedPath, '::?'), throwsArgumentError);
  });

  test('duplicate creates distinct copies and delete removes files', () async {
    final original = writeDrawly('Proyecto.drawly', sampleDrawlyBytes);

    final copy1 = await library.duplicate(original.path);
    final copy2 = await library.duplicate(original.path);

    expect(copy1, isNot(equals(original.path)));
    expect(copy2, isNot(equals(original.path)));
    expect(copy1, isNot(equals(copy2)));
    expect(File(copy1).existsSync(), isTrue);
    expect(File(copy2).existsSync(), isTrue);
    expect(File(copy1).readAsBytesSync(), sampleDrawlyBytes);
    expect(File(copy2).readAsBytesSync(), sampleDrawlyBytes);

    await library.delete(copy1);
    expect(File(copy1).existsSync(), isFalse);
    expect(File(copy2).existsSync(), isTrue);
  });

  test('uniquePath appends incrementing counter when files already exist', () {
    expect(p.basename(library.uniquePath('A')), 'A.drawly');

    writeDrawly('A.drawly', sampleDrawlyBytes);
    expect(p.basename(library.uniquePath('A')), 'A (2).drawly');

    writeDrawly('A (2).drawly', sampleDrawlyBytes);
    expect(p.basename(library.uniquePath('A')), 'A (3).drawly');
  });
}
