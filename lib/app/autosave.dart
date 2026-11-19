import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/ids.dart';
import '../io/project_codec.dart';
import '../model/document.dart';
import 'document_controller.dart';

/// State of a document's recovery copy.
enum AutosaveStatus { idle, pending, saving, saved, error }

/// One recoverable copy, as listed in `recovery.json`.
class RecoveryEntry {
  const RecoveryEntry({required this.id, required this.title, required this.file, required this.savedAt, this.originalPath});

  final String id, title, file;
  final DateTime savedAt;
  final String? originalPath;

  /// Serializes the recovery metadata, with an ISO 8601 timestamp.
  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'file': file, 'savedAt': savedAt.toIso8601String(), 'originalPath': originalPath};

  /// Parses recovery metadata; malformed entries throw [FormatException].
  static RecoveryEntry fromJson(dynamic j) {
    try {
      return RecoveryEntry(id: j['id'] as String, title: j['title'] as String, file: j['file'] as String,
          savedAt: DateTime.parse(j['savedAt'] as String), originalPath: j['originalPath'] as String?);
    } catch (e) {
      throw FormatException('Invalid recovery entry: $e');
    }
  }
}

class _WatchedDocument {
  final status = ValueNotifier(AutosaveStatus.idle);
  VoidCallback? listener;
  Timer? timer;
  Project? saved;
  int generation = 0;
  bool attached = false;
}

/// Native-only recovery storage. Owns timers and listeners, but not documents.
/// All file operations are serialized within this service.
class AutosaveService {
  AutosaveService({required Future<String> Function() directory, this.idleDelay = const Duration(seconds: 15),
    Duration interval = const Duration(minutes: 3), bool Function()? busy})
      // Public parameter names are part of the API; the fields stay private.
      // ignore: prefer_initializing_formals
      : _directory = directory, _interval = interval, _busy = busy ?? (() => false);

  final Future<String> Function() _directory;
  final bool Function() _busy;
  final Duration idleDelay;
  Duration _interval;
  Timer? _periodic;
  final _ids = Expando<String>();
  final _states = <DocumentController, _WatchedDocument>{};
  Future<void> _queue = Future.value();
  String? _dir;
  bool _disposed = false;

  /// Periodic save interval; zero disables periodic saving.
  Duration get interval => _interval;
  set interval(Duration value) {
    _interval = value;
    _restartPeriodic();
  }

  String _id(DocumentController doc) => _ids[doc] ??= newId('rec');
  _WatchedDocument _state(DocumentController doc) => _states.putIfAbsent(doc, _WatchedDocument.new);

  void _status(_WatchedDocument state, AutosaveStatus value) {
    if (!_disposed) state.status.value = value;
  }

  Future<T> _serial<T>(Future<T> Function() operation) {
    final result = _queue.then((_) => operation());
    _queue = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<String> _root() async {
    final dir = _dir ??= p.normalize(p.absolute(await _directory()));
    await Directory(dir).create(recursive: true);
    return dir;
  }

  void _restartPeriodic() {
    _periodic?.cancel();
    if (_disposed || _interval <= Duration.zero || !_states.values.any((s) => s.attached)) return;
    _periodic = Timer.periodic(_interval, (_) {
      for (final entry in _states.entries.toList()) {
        if (entry.value.attached && entry.key.dirty) unawaited(saveNow(entry.key));
      }
    });
  }

  void _schedule(DocumentController doc, _WatchedDocument state, Duration delay) {
    state.timer?.cancel();
    if (_disposed || !state.attached) return;
    state.timer = Timer(delay, () => unawaited(saveNow(doc)));
  }

  /// Starts watching the document. Repeated attachment is harmless.
  void attach(DocumentController doc) {
    if (_disposed) return;
    final state = _state(doc);
    if (state.attached) return;
    _id(doc);
    state.attached = true;
    state.listener = () {
      if (doc.dirty) {
        _status(state, AutosaveStatus.pending);
        _schedule(doc, state, idleDelay);
      } else {
        state.generation++;
        state.timer?.cancel();
        unawaited(_clean(doc, state));
      }
    };
    doc.addListener(state.listener!);
    _restartPeriodic();
    if (doc.dirty) state.listener!();
  }

  Future<void> _clean(DocumentController doc, _WatchedDocument state) async {
    try {
      await _serial(() async {
        await _remove(_id(doc));
        state.saved = null;
        _status(state, doc.dirty ? AutosaveStatus.pending : AutosaveStatus.idle);
      });
    } catch (_) {
      _status(state, AutosaveStatus.error);
    }
  }

  /// Stops watching; [discard] removes its recovery copy on a clean close.
  Future<void> detach(DocumentController doc, {bool discard = true}) async {
    final state = _states[doc];
    if (state != null) {
      if (state.attached) doc.removeListener(state.listener!);
      state.attached = false;
      state.generation++;
      state.timer?.cancel();
    }
    _restartPeriodic();
    await _serial(() async {
      if (discard) {
        await _remove(_id(doc));
        state?.saved = null;
        if (state != null) _status(state, AutosaveStatus.idle);
      }
    });
  }

  /// Stable status listenable, valid until the service is disposed.
  ValueListenable<AutosaveStatus> statusOf(DocumentController doc) => _state(doc).status;

  /// Writes a dirty, changed project; returns false on no-op, deferral or error.
  /// Never changes the user's file or the document's dirty flag.
  Future<bool> saveNow(DocumentController doc) async {
    if (_disposed) return false;
    final state = _state(doc);
    final generation = state.generation;
    try {
      return await _serial(() async {
        if (_disposed || generation != state.generation || !doc.dirty) return false;
        if (identical(doc.project, state.saved)) {
          _status(state, AutosaveStatus.saved);
          return false;
        }
        if (_busy()) {
          _status(state, AutosaveStatus.pending);
          _schedule(doc, state, const Duration(seconds: 2));
          return false;
        }
        state.timer?.cancel();
        final snapshot = doc.project;
        final title = doc.title, originalPath = doc.filePath;
        _status(state, AutosaveStatus.saving);
        final bytes = await ProjectCodec.encode(snapshot, thumbnail: false);
        final dir = await _root();
        if (_disposed || generation != state.generation || !doc.dirty) return false;
        final file = p.join(dir, '${_id(doc)}.drawly');
        if (originalPath != null && p.equals(p.absolute(originalPath), file)) {
          throw StateError('Recovery file must differ from the original file.');
        }
        await _atomic(file, bytes);
        final entries = await _readEntries(dir);
        entries.removeWhere((e) => e.id == _id(doc));
        entries.add(RecoveryEntry(id: _id(doc), title: title, file: file, savedAt: DateTime.now(), originalPath: originalPath));
        await _writeEntries(dir, entries);
        state.saved = snapshot;
        if (generation == state.generation && doc.dirty && identical(snapshot, doc.project)) {
          _status(state, AutosaveStatus.saved);
        } else if (doc.dirty) {
          _status(state, AutosaveStatus.pending);
          _schedule(doc, state, idleDelay);
        }
        return true;
      });
    } catch (_) {
      _status(state, AutosaveStatus.error);
      return false;
    }
  }

  Future<void> _atomic(String path, List<int> bytes) async {
    final temp = File('$path.tmp');
    try {
      await temp.writeAsBytes(bytes, flush: true);
      await temp.rename(path);
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  }

  Future<void> _writeEntries(String dir, List<RecoveryEntry> entries) =>
      _atomic(p.join(dir, 'recovery.json'), utf8.encode(jsonEncode(entries.map((e) => e.toJson()).toList())));

  bool _owned(String dir, RecoveryEntry e) => RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(e.id) &&
      p.equals(p.normalize(e.file), p.join(dir, '${e.id}.drawly')) &&
      (e.originalPath == null || !p.equals(p.absolute(e.originalPath!), p.normalize(e.file)));

  Future<List<RecoveryEntry>> _readEntries(String dir) async {
    final index = File(p.join(dir, 'recovery.json'));
    if (!await index.exists()) return [];
    List<RecoveryEntry> entries;
    try {
      entries = (jsonDecode(await index.readAsString()) as List).map(RecoveryEntry.fromJson).toList();
    } on FormatException {
      await _writeEntries(dir, []);
      return [];
    } on TypeError {
      await _writeEntries(dir, []);
      return [];
    }
    final valid = <RecoveryEntry>[];
    for (final e in entries) {
      if (!_owned(dir, e)) continue;
      final stat = await File(e.file).stat();
      if (stat.type == FileSystemEntityType.file && stat.size > 0) valid.add(e);
    }
    if (valid.length != entries.length) await _writeEntries(dir, valid);
    return valid;
  }

  /// Lists nonempty recovery files, repairing malformed or stale metadata.
  Future<List<RecoveryEntry>> listRecoverable() => _serial(() async => _readEntries(await _root()));

  /// Opens a copy as a dirty controller with the original title and file path.
  Future<DocumentController> restore(RecoveryEntry e) async {
    final project = await ProjectCodec.decode(await File(e.file).readAsBytes());
    return DocumentController(project, title: e.title, filePath: e.originalPath)..dirty = true;
  }

  Future<void> _remove(String id) async {
    final dir = await _root();
    final entries = await _readEntries(dir);
    final file = File(p.join(dir, '$id.drawly'));
    if (await file.exists()) await file.delete();
    entries.removeWhere((e) => e.id == id);
    await _writeEntries(dir, entries);
  }

  /// Deletes a recovery copy and its index entry, never its original file.
  Future<void> discard(RecoveryEntry e) => _serial(() async {
    final dir = await _root();
    if (!_owned(dir, e)) return;
    await _remove(e.id);
    for (final entry in _states.entries) {
      if (_ids[entry.key] == e.id) {
        entry.value.saved = null;
        _status(entry.value, AutosaveStatus.idle);
      }
    }
  });

  /// Deletes all indexed recovery copies.
  Future<void> discardAll() => _serial(() async {
    final dir = await _root();
    for (final e in await _readEntries(dir)) {
      final file = File(e.file);
      if (await file.exists()) await file.delete();
    }
    await _writeEntries(dir, []);
    for (final state in _states.values) {
      state.saved = null;
      _status(state, AutosaveStatus.idle);
    }
  });

  /// Stops timers and listeners. Existing recovery files are retained.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _periodic?.cancel();
    for (final entry in _states.entries) {
      final state = entry.value;
      state.timer?.cancel();
      if (state.attached) entry.key.removeListener(state.listener!);
      state.attached = false;
      state.status.dispose();
    }
  }
}
