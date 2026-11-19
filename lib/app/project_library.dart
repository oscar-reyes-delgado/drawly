import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/i18n.dart';

/// Sort criteria for [ProjectLibrary.list].
enum ProjectSort { name, modified }

/// Metadata for a `.drawly` project file in a library folder.
class ProjectEntry {
  const ProjectEntry({
    required this.path,
    required this.name,
    required this.modified,
    required this.size,
  });

  final String path;
  final String name;
  final DateTime modified;
  final int size;
}

/// Manages `.drawly` projects stored in a local directory (native platforms only).
class ProjectLibrary {
  ProjectLibrary(this.dir);

  final String dir;

  static final RegExp _invalidNameChars = RegExp(r'[\\/:*?"<>|]');

  /// `<documents>/Drawly` (created if missing), from `path_provider`.
  static Future<String> defaultDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final drawlyDir = Directory(p.join(docs.path, 'Drawly'));
    if (!await drawlyDir.exists()) {
      await drawlyDir.create(recursive: true);
    }
    return drawlyDir.absolute.path;
  }

  /// `.drawly` files directly inside [dir] (not recursive), sorted.
  Future<List<ProjectEntry>> list({
    ProjectSort sort = ProjectSort.modified,
    bool descending = true,
  }) async {
    final directory = Directory(dir);
    if (!await directory.exists()) return const [];

    final entries = <ProjectEntry>[];
    await for (final entity in directory.list(recursive: false, followLinks: false)) {
      if (entity is! File) continue;
      final base = p.basename(entity.path);
      final lower = base.toLowerCase();
      if (lower.endsWith('.tmp') || !lower.endsWith('.drawly')) continue;

      final stat = await entity.stat();
      final name = base.substring(0, base.length - '.drawly'.length);
      entries.add(ProjectEntry(
        path: entity.absolute.path,
        name: name,
        modified: stat.modified,
        size: stat.size,
      ));
    }

    entries.sort((a, b) {
      int cmp;
      switch (sort) {
        case ProjectSort.name:
          cmp = _compareNames(a.name, b.name);
        case ProjectSort.modified:
          cmp = a.modified.compareTo(b.modified);
          if (cmp == 0) cmp = _compareNames(a.name, b.name);
      }
      return descending ? -cmp : cmp;
    });

    return entries;
  }

  /// PNG bytes of `thumbnail.png` inside the file, or null when absent or the file is not a valid zip.
  Future<Uint8List?> thumbnail(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      for (final entry in archive.files) {
        if (!entry.isFile) continue;
        if (entry.name.replaceAll('\\', '/') == 'thumbnail.png') {
          final data = Uint8List.fromList(entry.content);
          return data.isEmpty ? null : data;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// True when the file is a zip with a manifest whose format is `"drawly"`.
  Future<bool> isValid(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return false;
      final bytes = await file.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      for (final entry in archive.files) {
        if (!entry.isFile) continue;
        if (entry.name.replaceAll('\\', '/') == 'manifest.json') {
          final decoded = jsonDecode(utf8.decode(entry.content));
          return decoded is Map && decoded['format'] == 'drawly';
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Free path in [dir] for [name]: `"Name.drawly"`, else `"Name (2).drawly"`, `"Name (3).drawly"`…
  String uniquePath(String name) {
    final cleaned = _sanitizeName(name);
    final base = cleaned.isEmpty ? tr('Sin título', 'Untitled') : cleaned;
    var candidate = p.join(dir, '$base.drawly');
    if (!File(candidate).existsSync()) return candidate;

    var index = 2;
    while (true) {
      candidate = p.join(dir, '$base ($index).drawly');
      if (!File(candidate).existsSync()) return candidate;
      index++;
    }
  }

  /// Renames keeping the extension; [newName] is cleaned of characters not allowed in file names
  /// (`\ / : * ? " < > |`) and trimmed. Throws [ArgumentError] when empty or when the target exists.
  /// Returns the new path.
  Future<String> rename(String path, String newName) async {
    final clean = _sanitizeName(newName);
    if (clean.isEmpty) {
      throw ArgumentError.value(newName, 'newName', tr('El nombre no puede estar vacío', 'Name cannot be empty'));
    }

    final ext = p.extension(path);
    final target = p.join(p.dirname(path), '$clean${ext.isEmpty ? '.drawly' : ext}');
    if (await File(target).exists()) {
      throw ArgumentError.value(newName, 'newName', tr('Ya existe un proyecto con ese nombre', 'A project with that name already exists'));
    }

    final renamed = await File(path).rename(target);
    return renamed.absolute.path;
  }

  /// Copies to `"Name (copia)"` / `"Name (copy)"` ([tr]) using [uniquePath]; returns the new path.
  Future<String> duplicate(String path) async {
    final base = p.basenameWithoutExtension(path);
    final copyName = '$base (${tr('copia', 'copy')})';
    final dest = uniquePath(copyName);
    await Directory(dir).create(recursive: true);
    final copied = await File(path).copy(dest);
    return copied.absolute.path;
  }

  /// Deletes the project file at [path] if it exists.
  Future<void> delete(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  static String _sanitizeName(String name) => name.replaceAll(_invalidNameChars, '').trim();

  static int _compareNames(String a, String b) {
    final lowerCmp = a.toLowerCase().compareTo(b.toLowerCase());
    return lowerCmp != 0 ? lowerCmp : a.compareTo(b);
  }
}
