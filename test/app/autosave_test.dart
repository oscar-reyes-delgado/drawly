import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:drawly/app/autosave.dart';
import 'package:drawly/app/doc_layers.dart';
import 'package:drawly/app/document_controller.dart';
import 'package:drawly/app/file_ops.dart';
import 'package:drawly/model/document.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

Future<void> _until(bool Function() predicate) async {
  final end = DateTime.now().add(const Duration(seconds: 5));
  while (!predicate()) {
    if (DateTime.now().isAfter(end)) fail('Timed out waiting for autosave');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late AutosaveService service;
  late DocumentController doc;
  late bool busy;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('drawly_autosave_');
    busy = false;
    service = AutosaveService(directory: () async => temp.path, idleDelay: const Duration(milliseconds: 20),
        interval: Duration.zero, busy: () => busy);
    doc = DocumentController(Project.blank(width: 32, height: 32), title: 'My drawing');
    service.attach(doc);
  });

  tearDown(() async {
    await service.detach(doc, discard: false);
    service.dispose();
    doc.dispose();
    await temp.delete(recursive: true);
  });

  test('idle edit saves a separate copy, metadata and all status transitions', () async {
    final status = service.statusOf(doc);
    final seen = <AutosaveStatus>[];
    status.addListener(() => seen.add(status.value));
    final original = File(p.join(temp.path, 'original.drawly'))..writeAsStringSync('untouched');
    doc.filePath = original.path;
    doc.addPaintLayer();
    expect(status.value, AutosaveStatus.pending);
    await _until(() => status.value == AutosaveStatus.saved);
    final entry = (await service.listRecoverable()).single;
    expect(entry.title, doc.title);
    expect(entry.originalPath, original.path);
    expect(entry.file, p.join(temp.path, '${entry.id}.drawly'));
    expect(entry.savedAt.difference(DateTime.now()).inSeconds.abs(), lessThan(5));
    expect(original.readAsStringSync(), 'untouched');
    expect(doc.dirty, isTrue);
    expect(seen, containsAllInOrder([AutosaveStatus.pending, AutosaveStatus.saving, AutosaveStatus.saved]));
    final archive = ZipDecoder().decodeBytes(await File(entry.file).readAsBytes());
    expect(archive.findFile('thumbnail.png'), isNull);
    expect(temp.listSync().where((f) => f.path.endsWith('.tmp')), isEmpty);
    expect(RecoveryEntry.fromJson(entry.toJson()).toJson(), entry.toJson());
  });

  test('restore preserves layers, title and original path and marks dirty', () async {
    doc.filePath = p.join(temp.path, 'user.drawly');
    doc.addPaintLayer(name: 'Second');
    expect(await service.saveNow(doc), isTrue);
    final entry = (await service.listRecoverable()).single;
    final restored = await service.restore(entry);
    addTearDown(restored.dispose);
    expect(restored.comp.layers.map((l) => l.props.name), doc.comp.layers.map((l) => l.props.name));
    expect(restored.comp.layers.map((l) => l.id), doc.comp.layers.map((l) => l.id));
    expect(restored.title, doc.title);
    expect(restored.filePath, doc.filePath);
    expect(restored.dirty, isTrue);
  });

  test('busy defers the idle save and retries after two seconds', () async {
    busy = true;
    doc.addPaintLayer();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(await service.listRecoverable(), isEmpty);
    expect(service.statusOf(doc).value, AutosaveStatus.pending);
    busy = false;
    await _until(() => service.statusOf(doc).value == AutosaveStatus.saved);
    expect(await service.listRecoverable(), hasLength(1));
  });

  test('manual save removes recovery copy and index entry', () async {
    doc.addPaintLayer();
    await service.saveNow(doc);
    final entry = (await service.listRecoverable()).single;
    expect(await saveProjectTo(doc, p.join(temp.path, 'user.drawly')), isTrue);
    expect(await service.listRecoverable(), isEmpty);
    expect(File(entry.file).existsSync(), isFalse);
    expect(service.statusOf(doc).value, AutosaveStatus.idle);
    doc.addPaintLayer();
    expect(await service.saveNow(doc), isTrue);
    expect((await service.listRecoverable()).single.id, entry.id);
  });

  test('detach preserves recovery for a new service and cancels listening', () async {
    doc.addPaintLayer();
    await service.saveNow(doc);
    final entry = (await service.listRecoverable()).single;
    await service.detach(doc, discard: false);
    doc.addPaintLayer();
    final next = AutosaveService(directory: () async => temp.path);
    addTearDown(next.dispose);
    expect((await next.listRecoverable()).single.toJson(), entry.toJson());
    await Future<void>.delayed(const Duration(milliseconds: 60));
    final restored = await next.restore(entry);
    addTearDown(restored.dispose);
    expect(restored.comp.layers.length, doc.comp.layers.length - 1);
  });

  test('malformed index is repaired and damaged copy throws FormatException', () async {
    final index = File(p.join(temp.path, 'recovery.json'));
    for (final invalid in ['garbage', '{}', '[{}]']) {
      await index.writeAsString(invalid);
      expect(await service.listRecoverable(), isEmpty);
      expect(jsonDecode(await index.readAsString()), isEmpty);
    }
    doc.addPaintLayer();
    await service.saveNow(doc);
    final entry = (await service.listRecoverable()).single;
    await File(entry.file).writeAsString('garbage');
    await expectLater(service.restore(entry), throwsFormatException);
  });

  test('unchanged and simultaneous save requests do not rewrite a copy', () async {
    doc.addPaintLayer();
    expect(await Future.wait([service.saveNow(doc), service.saveNow(doc)]), [true, false]);
    final entry = (await service.listRecoverable()).single;
    final file = File(entry.file);
    final fixed = DateTime(2000);
    await file.setLastModified(fixed);
    final stamp = await file.lastModified();
    doc.touch();
    expect(await service.saveNow(doc), isFalse);
    expect(await file.lastModified(), stamp);
    expect((await service.listRecoverable()).single.savedAt, entry.savedAt);
    doc.addPaintLayer();
    expect(await service.saveNow(doc), isTrue);
    expect(await file.lastModified(), isNot(stamp));
  });

  test('missing and empty copies are removed from the index', () async {
    doc.addPaintLayer();
    await service.saveNow(doc);
    final entry = (await service.listRecoverable()).single;
    await File(entry.file).writeAsBytes([]);
    expect(await service.listRecoverable(), isEmpty);
    await File(p.join(temp.path, 'recovery.json')).writeAsString(jsonEncode([entry.toJson()]));
    await File(entry.file).delete();
    expect(await service.listRecoverable(), isEmpty);
    expect(jsonDecode(await File(p.join(temp.path, 'recovery.json')).readAsString()), isEmpty);
  });

  test('two documents save concurrently without losing either index entry', () async {
    final other = DocumentController(Project.blank(width: 32, height: 32), title: 'Other');
    try {
      service.attach(other);
      doc.addPaintLayer();
      other.addPaintLayer();
      expect(await Future.wait([service.saveNow(doc), service.saveNow(other)]), [true, true]);
      final entries = await service.listRecoverable();
      expect(entries.map((e) => e.title), unorderedEquals(['My drawing', 'Other']));
      await service.discard(entries.first);
      expect(await service.listRecoverable(), hasLength(1));
      await service.discardAll();
      expect(await service.listRecoverable(), isEmpty);
      expect(entries.any((e) => File(e.file).existsSync()), isFalse);
    } finally {
      await service.detach(other);
      other.dispose();
    }
  });

  test('periodic saving works without idle time and interval can be disabled', () async {
    final periodic = AutosaveService(directory: () async => temp.path,
        idleDelay: const Duration(hours: 1), interval: const Duration(milliseconds: 20));
    await service.detach(doc);
    periodic.attach(doc);
    try {
      doc.addPaintLayer();
      await _until(() => periodic.statusOf(doc).value == AutosaveStatus.saved);
      periodic.interval = Duration.zero;
      // let a periodic save that had already started finish before editing again
      await periodic.saveNow(doc);
      doc.addPaintLayer();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(periodic.statusOf(doc).value, AutosaveStatus.pending);
    } finally {
      await periodic.detach(doc);
      periodic.dispose();
    }
  });

  test('write errors return false, expose error and permit retry', () async {
    final blocker = File(p.join(temp.path, 'blocker'))..writeAsStringSync('file');
    final failing = AutosaveService(directory: () async => blocker.path, interval: Duration.zero);
    addTearDown(failing.dispose);
    doc.addPaintLayer();
    expect(await failing.saveNow(doc), isFalse);
    expect(failing.statusOf(doc).value, AutosaveStatus.error);
    await blocker.delete();
    expect(await failing.saveNow(doc), isTrue);
    expect(failing.statusOf(doc).value, AutosaveStatus.saved);
  });

  test('edits during a save leave the newer project pending', () async {
    final entered = Completer<void>(), release = Completer<void>();
    final slow = AutosaveService(directory: () async {
      entered.complete();
      await release.future;
      return temp.path;
    }, idleDelay: const Duration(hours: 1), interval: Duration.zero);
    await service.detach(doc);
    slow.attach(doc);
    try {
      doc.addPaintLayer();
      final saving = slow.saveNow(doc);
      await entered.future;
      doc.addPaintLayer();
      release.complete();
      expect(await saving, isTrue);
      expect(slow.statusOf(doc).value, AutosaveStatus.pending);
      expect(await slow.saveNow(doc), isTrue);
      final restored = await slow.restore((await slow.listRecoverable()).single);
      addTearDown(restored.dispose);
      expect(restored.comp.layers.length, doc.comp.layers.length);
    } finally {
      await slow.detach(doc);
      slow.dispose();
    }
  });

  test('cleaning during a save prevents publication of stale recovery', () async {
    final entered = Completer<void>(), release = Completer<void>();
    final slow = AutosaveService(directory: () async {
      entered.complete();
      await release.future;
      return temp.path;
    }, interval: Duration.zero);
    await service.detach(doc);
    slow.attach(doc);
    try {
      doc.addPaintLayer();
      final saving = slow.saveNow(doc);
      await entered.future;
      doc.dirty = false;
      doc.touch();
      release.complete();
      expect(await saving, isFalse);
      expect(await slow.listRecoverable(), isEmpty);
      expect(slow.statusOf(doc).value, AutosaveStatus.idle);
    } finally {
      await slow.detach(doc);
      slow.dispose();
    }
  });

  test('detach discard and dispose cancel timers and preserve originals', () async {
    doc.addPaintLayer();
    await service.saveNow(doc);
    final entry = (await service.listRecoverable()).single;
    await service.detach(doc);
    expect(File(entry.file).existsSync(), isFalse);
    service.attach(doc);
    service.attach(doc);
    service.dispose();
    doc.addPaintLayer();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(await service.saveNow(doc), isFalse);
    expect(File(entry.file).existsSync(), isFalse);
  });
}
