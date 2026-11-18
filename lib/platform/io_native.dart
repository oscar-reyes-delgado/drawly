// dart:io implementation of the local file layer.
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

bool get hasFileSystem => true;
bool get isDesktopOS => Platform.isWindows || Platform.isMacOS || Platform.isLinux;
String get pathSeparator => Platform.pathSeparator;

Future<Uint8List?> readFileBytes(String path) async {
  try {
    final f = File(path);
    if (!await f.exists()) return null;
    return await f.readAsBytes();
  } catch (_) {
    return null;
  }
}

Future<bool> writeFileBytes(String path, Uint8List bytes) async {
  try {
    final f = File(path);
    await f.parent.create(recursive: true);
    // write to a sibling first so a crash never leaves a half written file
    final tmp = File('$path.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    if (await f.exists()) await f.delete();
    await tmp.rename(path);
    return true;
  } catch (_) {
    try {
      await File(path).writeAsBytes(bytes, flush: true);
      return true;
    } catch (_) {
      return false;
    }
  }
}

Future<bool> fileExists(String path) async => File(path).exists();

Future<void> deleteFile(String path) async {
  try {
    final f = File(path);
    if (await f.exists()) await f.delete();
  } catch (_) {}
}

Future<void> ensureDir(String path) async {
  try {
    await Directory(path).create(recursive: true);
  } catch (_) {}
}

Future<List<String>> listFiles(String dir, {String? extension}) async {
  try {
    final d = Directory(dir);
    if (!await d.exists()) return const [];
    final out = <String>[];
    await for (final e in d.list()) {
      if (e is File && (extension == null || e.path.toLowerCase().endsWith(extension.toLowerCase()))) out.add(e.path);
    }
    out.sort();
    return out;
  } catch (_) {
    return const [];
  }
}

Future<DateTime?> fileModified(String path) async {
  try {
    return await File(path).lastModified();
  } catch (_) {
    return null;
  }
}

Future<String?> appDataDir() async {
  try {
    final d = await getApplicationSupportDirectory();
    return d.path;
  } catch (_) {
    return null;
  }
}

Future<String?> tempDir() async {
  try {
    final d = await getTemporaryDirectory();
    return d.path;
  } catch (_) {
    return Directory.systemTemp.path;
  }
}

/// Installed font family names (best effort, desktop only).
Future<List<String>> systemFontFamilies() async {
  final dirs = <String>[];
  if (Platform.isWindows) {
    dirs.add('${Platform.environment['WINDIR'] ?? r'C:\Windows'}\\Fonts');
    final local = Platform.environment['LOCALAPPDATA'];
    if (local != null) dirs.add('$local\\Microsoft\\Windows\\Fonts');
  } else if (Platform.isMacOS) {
    dirs.addAll(['/System/Library/Fonts', '/Library/Fonts', '${Platform.environment['HOME']}/Library/Fonts']);
  } else if (Platform.isLinux) {
    dirs.addAll(['/usr/share/fonts', '/usr/local/share/fonts', '${Platform.environment['HOME']}/.fonts']);
  }
  final files = <String>[];
  for (final dir in dirs) {
    try {
      final d = Directory(dir);
      if (!await d.exists()) continue;
      await for (final e in d.list(recursive: true, followLinks: false)) {
        final p = e.path.toLowerCase();
        if (e is File && (p.endsWith('.ttf') || p.endsWith('.otf') || p.endsWith('.ttc'))) files.add(e.path);
      }
    } catch (_) {}
  }
  return files;
}

Future<({int exitCode, String stdout, String stderr})?> runProcess(String exe, List<String> args, {String? workingDirectory}) async {
  try {
    final r = await Process.run(exe, args, workingDirectory: workingDirectory);
    return (exitCode: r.exitCode, stdout: '${r.stdout}', stderr: '${r.stderr}');
  } catch (_) {
    return null;
  }
}

Future<String?> findExecutable(String name) async {
  if (!isDesktopOS) return null;
  try {
    final r = await Process.run(Platform.isWindows ? 'where' : 'which', [name]);
    if (r.exitCode != 0) return null;
    final line = '${r.stdout}'.split('\n').map((l) => l.trim()).firstWhere((l) => l.isNotEmpty, orElse: () => '');
    return line.isEmpty ? null : line;
  } catch (_) {
    return null;
  }
}
