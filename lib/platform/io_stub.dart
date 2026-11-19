// Web / unsupported platform implementation of the local file layer.
import 'dart:typed_data';

bool get hasFileSystem => false;
bool get isDesktopOS => false;
String get pathSeparator => '/';

Future<Uint8List?> readFileBytes(String path) async => null;
Future<bool> writeFileBytes(String path, Uint8List bytes) async => false;
Future<bool> fileExists(String path) async => false;
Future<void> deleteFile(String path) async {}
Future<void> ensureDir(String path) async {}
Future<List<String>> listFiles(String dir, {String? extension}) async => const [];
Future<DateTime?> fileModified(String path) async => null;
Future<String?> appDataDir() async => null;
Future<String?> tempDir() async => null;
Future<List<String>> systemFontFamilies() async => const [];

/// Runs an external program; returns null when processes are unavailable.
Future<({int exitCode, String stdout, String stderr})?> runProcess(String exe, List<String> args, {String? workingDirectory}) async => null;

/// Locates an executable on PATH.
Future<String?> findExecutable(String name) async => null;

/// Shows [path] selected in the system file manager; false when unsupported.
Future<bool> revealInFileManager(String path) async => false;
