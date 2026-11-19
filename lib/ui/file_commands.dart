import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

import '../app/app_state.dart';
import '../app/commands.dart';
import '../app/document_controller.dart';
import '../app/file_ops.dart';
import '../engine/compositor.dart';
import '../engine/tiles.dart';
import '../core/i18n.dart';
import '../io/image_export.dart';
import '../io/project_codec.dart';
import '../platform/io.dart';
import '../platform/video_encoder.dart';
import 'dialogs/export_dialog.dart';

/// File menu commands: open, save, save as and exports, wired to [file_ops].
void registerFileCommands(CommandRegistry r, AppState app) {
  void add(String id, String Function() label, void Function() run, {String shortcut = '', bool needsDocument = true}) {
    r.add(Command(id: id, category: CommandCategory.file, label: label, run: run, shortcut: shortcut, needsDocument: needsDocument));
  }

  Future<void> guarded(String what, Future<void> Function() body) async {
    try {
      await body();
    } catch (e) {
      app.toast('$what: $e', duration: const Duration(seconds: 6));
    }
  }

  void markSaved(DocumentController d, String path) {
    d.filePath = path;
    d.title = p.basenameWithoutExtension(path);
    d.dirty = false;
    d.touch();
    if (!path.startsWith('content://')) app.settings.addRecent(path);
  }

  Future<void> saveAs() => guarded(tr('Error al guardar', 'Save failed'), () async {
        final d = app.doc;
        if (d == null) return;
        final bytes = await ProjectCodec.encode(d.project);
        final uri = await FilePicker.saveFile(
          dialogTitle: tr('Guardar proyecto', 'Save project'),
          fileName: '${d.title}.drawly',
          bytes: bytes,
        );
        if (uri == null) return;
        markSaved(d, uri.scheme == 'file' ? uri.toFilePath() : uri.toString());
        app.toast(tr('Guardado', 'Saved'));
      });

  Future<void> save() => guarded(tr('Error al guardar', 'Save failed'), () async {
        final d = app.doc;
        if (d == null) return;
        final path = d.filePath;
        if (path == null || !path.toLowerCase().endsWith('.drawly')) return saveAs();
        if (await saveProjectTo(d, path)) {
          markSaved(d, path);
          app.toast(tr('Guardado', 'Saved'));
        } else {
          app.toast(tr('No se pudo escribir el archivo', 'Could not write the file'));
        }
      });

  Future<void> open() => guarded(tr('Error al abrir', 'Open failed'), () async {
        final f = await FilePicker.pickFile(dialogTitle: tr('Abrir proyecto', 'Open project'), type: FileType.custom, allowedExtensions: const ['drawly']);
        final path = f?.path;
        if (path == null) return;
        final c = await openProjectFrom(path);
        app.addDocument(c.project, title: c.title, path: c.filePath);
        c.dispose();
        app.settings.addRecent(path);
      });

  /// Asks for a folder and returns `<folder>/<title>.<ext>`, or null.
  Future<String?> exportPath(String ext) async {
    final d = app.doc;
    if (d == null) return null;
    final dir = await _pickDir();
    if (dir == null) return null;
    return p.join(dir, '${d.title}.$ext');
  }

  void done(bool ok, String path) => app.toast(ok ? tr('Exportado: ', 'Exported: ') + path : tr('No se pudo exportar', 'Export failed'));

  String? watermark() => app.settings.watermarkEnabled && app.settings.watermark.isNotEmpty ? app.settings.watermark : null;

  Future<void> still(StillFormat f) => guarded(tr('Error al exportar', 'Export failed'), () async {
        final path = await exportPath(f.ext);
        if (path == null) return;
        final d = app.doc!;
        done(await exportStill(d, path, f, frame: d.frame, watermark: watermark()), path);
      });

  Future<void> anim(AnimFormat f) => guarded(tr('Error al exportar', 'Export failed'), () async {
        final path = await exportPath(f == AnimFormat.apng ? 'apng.png' : f.ext);
        if (path == null) return;
        done(await exportAnimationTo(app.doc!, path, f), path);
      });

  add('file.open', () => tr('Abrir…', 'Open…'), open, shortcut: 'Ctrl+O', needsDocument: false);
  add('file.save', () => tr('Guardar', 'Save'), save, shortcut: 'Ctrl+S');
  add('file.saveAs', () => tr('Guardar como…', 'Save as…'), saveAs, shortcut: 'Ctrl+Shift+S');
  add('file.exportPng', () => tr('Exportar PNG…', 'Export PNG…'), () => still(StillFormat.png));
  add('file.export', () => tr('Exportar…', 'Export…'), () => guarded(tr('Error al exportar', 'Export failed'), () => _exportWithDialog(app)), shortcut: 'Ctrl+Alt+E');
  add('file.exportJpg', () => tr('Exportar JPG…', 'Export JPG…'), () => still(StillFormat.jpg));
  add('file.exportWebp', () => tr('Exportar WebP…', 'Export WebP…'), () => still(StillFormat.webp));
  add('file.exportGif', () => tr('Exportar GIF animado…', 'Export animated GIF…'), () => anim(AnimFormat.gif));
  add('file.exportApng', () => tr('Exportar APNG…', 'Export APNG…'), () => anim(AnimFormat.apng));
  add('file.exportMp4', () => tr('Exportar vídeo MP4…', 'Export MP4 video…'), () => guarded(tr('Error al exportar', 'Export failed'), () async {
        if (!await VideoEncoder.isAvailable()) {
          app.toast(tr('Este dispositivo no puede crear vídeo MP4; exporta GIF o WebP', 'This device cannot create MP4 video; export GIF or WebP'));
          return;
        }
        final dir = await _pickDir();
        if (dir == null) return;
        app.toast(tr('Exportando vídeo…', 'Exporting video…'), duration: const Duration(minutes: 5));
        final out = await writeMp4(app.doc!, dir, watermark: watermark());
        done(out.isNotEmpty, out.isEmpty ? dir : out.first);
      }));
  add('file.exportSequence', () => tr('Exportar secuencia PNG…', 'Export PNG sequence…'), () {
    guarded(tr('Error al exportar', 'Export failed'), () async {
      final d = app.doc!;
      final dir = await _pickDir();
      if (dir == null) return;
      final files = await exportSequence(d, dir, d.title);
      app.toast(tr('Exportados ${files.length} fotogramas', 'Exported ${files.length} frames'));
    });
  });
  add('file.exportSvg', () => tr('Exportar SVG (capa vectorial)…', 'Export SVG (vector layer)…'), () {
    guarded(tr('Error al exportar', 'Export failed'), () async {
      final path = await exportPath('svg');
      if (path == null) return;
      done(await exportSvgTo(app.doc!, path), path);
    });
  });
}

/// Destination folder as a file-system path (null when cancelled or not a local folder).
/// Asks for a destination folder (null when cancelled or not a local folder).
Future<String?> pickExportFolder() => _pickDir();

Future<String?> _pickDir() async {
  final uri = await FilePicker.pickDirectory(dialogTitle: tr('Carpeta de destino', 'Destination folder'));
  if (uri == null) return null;
  return uri.scheme == 'file' ? uri.toFilePath() : null;
}

/// Opens the export dialog, asks for a folder and writes the result.
Future<void> _exportWithDialog(AppState app) async {
  final d = app.doc;
  final ctx = app.context;
  if (d == null || ctx == null) return;
  final o = await showExportDialog(ctx, d);
  if (o == null) return;
  if (o.kind == ExportKind.svg) {
    final dir = await _pickDir();
    if (dir == null) return;
    final path = p.join(dir, '${d.title}.svg');
    final ok = await exportSvgTo(d, path);
    app.toast(ok ? tr('Exportado: ', 'Exported: ') + path : tr('La capa activa no es vectorial', 'The active layer is not a vector layer'));
    return;
  }
  final dir = await _pickDir();
  if (dir == null) return;
  final written = await writeExport(d, o, dir, watermark: o.watermark && app.settings.watermark.isNotEmpty ? app.settings.watermark : null);
  app.toast(written.isEmpty ? tr('No se pudo exportar', 'Export failed') : tr('Exportado: ', 'Exported: ') + (written.length == 1 ? written.first : '${written.length} ${tr('archivos', 'files')}'));
}

/// Renders and writes [o] into [dir]; returns the paths written (empty on failure).
/// Raster kinds only ([ExportKind.svg] is handled by `exportSvgTo`).
/// [onProgress] goes from 0 to 1; when [cancel] is cancelled the files written
/// so far are deleted and an empty list is returned.
Future<List<String>> writeExport(DocumentController d, ExportOptions o, String dir, {String? watermark, void Function(double)? onProgress, CancelToken? cancel}) async {
  final out = <String>[];
  try {
    return await _writeExport(d, o, dir, out, watermark: watermark, onProgress: onProgress, cancel: cancel);
  } on ExportCancelled {
    for (final f in out) {
      await deleteFile(f);
    }
    return const [];
  }
}

Future<List<String>> _writeExport(DocumentController d, ExportOptions o, String dir, List<String> out, {String? watermark, void Function(double)? onProgress, CancelToken? cancel}) async {
  final frameTotal = o.kind == ExportKind.still ? 1 : (o.rangeEnd - o.rangeStart).clamp(1, 1 << 30);
  var done = 0;
  // Yields to the UI between frames so progress shows and Cancel can be pressed.
  Future<void> step([double share = 1]) async {
    done++;
    onProgress?.call((share * done / frameTotal).clamp(0.0, 1.0));
    await Future<void>.delayed(Duration.zero);
    cancel?.check();
  }

  final project = d.project, comp = d.comp;
  final alpha = switch (o.kind) {
    ExportKind.animation => o.anim != AnimFormat.gif || o.transparent,
    ExportKind.spriteSheet => o.transparent,
    _ => o.still.hasAlpha && o.transparent,
  };

  ui.Image render(int frame) {
    final img = renderCompImage(project, comp, frame.toDouble(), scale: o.scale, background: !alpha, forExport: true, useCamera: true);
    if (watermark == null) return img;
    final marked = applyWatermark(img, watermark);
    img.dispose();
    return marked;
  }

  Future<bool> write(String name, List<int> bytes) async => writeFileBytes(p.join(dir, name), Uint8List.fromList(bytes));

  await ensureDir(dir);
  cancel?.check();
  onProgress?.call(0);
  final base = d.title;
  switch (o.kind) {
    case ExportKind.still:
      final img = render(o.frame);
      try {
        final name = '$base.${o.still.ext}';
        if (await write(name, await encodeStill(img, o.still, quality: o.quality))) out.add(p.join(dir, name));
      } finally {
        img.dispose();
      }
    case ExportKind.sequence:
      final total = o.rangeEnd - o.rangeStart;
      for (var f = o.rangeStart; f < o.rangeEnd; f++) {
        final img = render(f);
        try {
          final name = sequenceName(base, f - o.rangeStart, total, o.still.ext);
          if (await write(name, await encodeStill(img, o.still, quality: o.quality))) out.add(p.join(dir, name));
        } finally {
          img.dispose();
        }
        await step();
      }
    case ExportKind.animation:
    case ExportKind.spriteSheet:
      final frames = <ui.Image>[];
      try {
        for (var f = o.rangeStart; f < o.rangeEnd; f++) {
          frames.add(render(f));
          await step(0.85);
        }
        if (o.kind == ExportKind.animation) {
          final name = '$base.${o.anim == AnimFormat.apng ? 'apng.png' : o.anim.ext}';
          if (await write(name, await encodeAnimation(frames, o.anim, fps: comp.timeline.fps))) out.add(p.join(dir, name));
        } else {
          final sheet = buildSpriteSheet(frames, columns: o.columns <= 0 ? null : o.columns, padding: o.padding);
          try {
            final png = '$base.png';
            if (await write(png, await encodeStill(sheet.image, StillFormat.png))) out.add(p.join(dir, png));
            final json = '$base.json';
            if (await write(json, utf8.encode(spriteSheetJson(sheet, imageName: png, fps: comp.timeline.fps, animName: base)))) out.add(p.join(dir, json));
          } finally {
            sheet.image.dispose();
          }
        }
      } finally {
        for (final f in frames) {
          f.dispose();
        }
      }
    case ExportKind.svg:
      break;
  }
  onProgress?.call(1);
  return out;
}

/// Renders the playback range of [d] and writes `<title>.mp4` into [dir] with the
/// platform encoder (opaque background, even size). Returns the path written, or
/// an empty list when cancelled or when the platform has no encoder.
Future<List<String>> writeMp4(DocumentController d, String dir, {double scale = 1, String? watermark, void Function(double)? onProgress, CancelToken? cancel}) async {
  if (!await VideoEncoder.isAvailable()) return const [];
  final project = d.project, comp = d.comp, t = comp.timeline;
  final (w, h) = VideoEncoder.evenSize((comp.width * scale).round(), (comp.height * scale).round());
  await ensureDir(dir);
  final path = p.join(dir, '${d.title}.mp4');
  final enc = await VideoEncoder.begin(path, width: w, height: h, fps: t.fps);
  final total = (t.rangeEnd - t.rangeStart).clamp(1, 1 << 30);
  try {
    onProgress?.call(0);
    for (var f = t.rangeStart; f < t.rangeEnd; f++) {
      cancel?.check();
      var img = renderCompImage(project, comp, f.toDouble(), scale: w / comp.width, background: true, forExport: true, useCamera: true);
      if (watermark != null) {
        final marked = applyWatermark(img, watermark);
        img.dispose();
        img = marked;
      }
      try {
        // the render may be a pixel larger than the even size: crop by reading only w x h
        final rgba = await imageToRgba(img, straight: true);
        await enc.addFrame(_cropRgba(rgba, img.width, img.height, w, h));
      } finally {
        img.dispose();
      }
      onProgress?.call((f - t.rangeStart + 1) / total * 0.98);
      await Future<void>.delayed(Duration.zero);
    }
    cancel?.check();
    final ok = await enc.finish();
    onProgress?.call(1);
    return ok ? [path] : const [];
  } on ExportCancelled {
    await enc.abort();
    return const [];
  } catch (_) {
    await enc.abort();
    rethrow;
  }
}

Uint8List _cropRgba(Uint8List src, int sw, int sh, int w, int h) {
  if (sw == w && sh == h) return src;
  final out = Uint8List(w * h * 4);
  for (var y = 0; y < h && y < sh; y++) {
    out.setRange(y * w * 4, y * w * 4 + (w < sw ? w : sw) * 4, src, y * sw * 4);
  }
  return out;
}
