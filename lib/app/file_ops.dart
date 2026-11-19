import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:path/path.dart' as p;

import '../core/i18n.dart';
import '../engine/compositor.dart';
import '../io/image_export.dart';
import '../io/project_codec.dart';
import '../io/svg_codec.dart';
import '../model/layer.dart';
import '../model/vector.dart';
import '../platform/io.dart';
import 'document_controller.dart';

/// Lets the user stop a long export. Long operations call [check] between
/// frames; it throws [ExportCancelled] once [cancel] was called.
class CancelToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
  void check() {
    if (_cancelled) throw const ExportCancelled();
  }
}

class ExportCancelled implements Exception {
  const ExportCancelled();
  @override
  String toString() => 'Export cancelled';
}

/// Writes the project as .drawly to [path] and marks the document clean.
/// Returns false when the write failed. Edits made while saving stay dirty;
/// encoding errors propagate without changing the document's file metadata.
Future<bool> saveProjectTo(DocumentController doc, String path, {void Function(double)? onProgress}) async {
  final project = doc.project;
  final bytes = await ProjectCodec.encode(project, onProgress: onProgress);
  if (!await _writeBytes(path, bytes)) return false;
  doc.filePath = path;
  doc.title = p.basenameWithoutExtension(path);
  doc.dirty = !identical(doc.project, project);
  doc.touch();
  return true;
}

/// Opens a .drawly file and returns a new controller (not yet added to AppState).
/// Throws [FormatException] on bad data and [Exception] when reading fails.
Future<DocumentController> openProjectFrom(String path, {void Function(double)? onProgress}) async {
  final bytes = await readFileBytes(path);
  if (bytes == null) {
    throw Exception('${tr('No se pudo leer el archivo', 'Could not read the file')}: $path');
  }
  final project = await ProjectCodec.decode(bytes, onProgress: onProgress);
  return DocumentController(project, title: p.basenameWithoutExtension(path), filePath: path);
}

/// Renders [frame] of the current composition and writes it with [format].
/// Returns false when writing fails; rendering and encoding errors propagate.
Future<bool> exportStill(
  DocumentController doc,
  String path,
  StillFormat format, {
  int frame = 0,
  double scale = 1,
  int quality = 90,
  Color matte = const Color(0xFFFFFFFF),
  String? watermark,
}) async {
  final image = renderCompImage(doc.project, doc.comp, frame.toDouble(), scale: scale, background: true, forExport: true, useCamera: false);
  Image? marked;
  try {
    if (watermark != null && watermark.isNotEmpty) marked = applyWatermark(image, watermark);
    final bytes = await encodeStill(marked ?? image, format, quality: quality, matte: matte);
    return await _writeBytes(path, bytes);
  } finally {
    marked?.dispose();
    image.dispose();
  }
}

/// Renders the playback range into [dir] and returns the written file paths.
/// Names start at `baseName_0000` relative to the range, using [format]'s extension.
/// Throws [Exception] on a failed write; previously written files remain on disk.
Future<List<String>> exportSequence(
  DocumentController doc,
  String dir,
  String baseName, {
  StillFormat format = StillFormat.png,
  double scale = 1,
  void Function(double)? onProgress,
}) async {
  final project = doc.project;
  final comp = doc.comp;
  final start = comp.timeline.rangeStart, end = comp.timeline.rangeEnd;
  final total = end - start;
  final paths = <String>[];
  await ensureDir(dir);
  onProgress?.call(0);
  for (var frame = start; frame < end; frame++) {
    final path = p.join(dir, sequenceName(baseName, frame - start, total, format.ext));
    final image = renderCompImage(project, comp, frame.toDouble(), scale: scale, background: true, forExport: true, useCamera: false);
    try {
      final bytes = await encodeStill(image, format);
      if (!await _writeBytes(path, bytes)) {
        throw Exception('${tr('No se pudo escribir el archivo', 'Could not write the file')}: $path');
      }
      paths.add(path);
    } finally {
      image.dispose();
    }
    onProgress?.call(paths.length / total);
  }
  return paths;
}

/// Renders the playback range and writes one animated file at the timeline fps.
/// Returns false when writing fails; rendering and encoding errors propagate.
Future<bool> exportAnimationTo(
  DocumentController doc,
  String path,
  AnimFormat format, {
  double scale = 1,
  void Function(double)? onProgress,
}) async {
  final project = doc.project;
  final comp = doc.comp;
  final timeline = comp.timeline;
  final start = timeline.rangeStart, end = timeline.rangeEnd;
  final images = <Image>[];
  try {
    onProgress?.call(0);
    for (var frame = start; frame < end; frame++) {
      images.add(renderCompImage(project, comp, frame.toDouble(), scale: scale, background: true, forExport: true, useCamera: false));
      // Leave the last part of progress for encoding and the completed write.
      onProgress?.call(0.8 * images.length / (end - start));
    }
    final bytes = await encodeAnimation(images, format, fps: timeline.fps);
    if (!await _writeBytes(path, bytes)) return false;
    onProgress?.call(1);
    return true;
  } finally {
    for (final image in images) {
      image.dispose();
    }
  }
}

/// Exports the active vector layer drawing at the current frame as SVG.
/// Returns false for a non-vector layer or a failed write; blank cels yield an empty SVG.
Future<bool> exportSvgTo(DocumentController doc, String path) async {
  final layer = doc.activeLayer;
  if (layer is! VectorLayer) return false;
  final art = layer.cels.at(doc.frame) ?? VectorArt.empty;
  final svg = vectorArtToSvg(art, size: doc.comp.size, title: layer.props.name);
  return _writeBytes(path, Uint8List.fromList(utf8.encode(svg)));
}

Future<bool> _writeBytes(String path, Uint8List bytes) async {
  await ensureDir(p.dirname(path));
  return writeFileBytes(path, bytes);
}
