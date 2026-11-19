import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

import '../app/app_state.dart';
import '../app/commands.dart';
import '../app/doc_edit.dart';
import '../app/doc_timeline.dart';
import '../app/document_controller.dart';
import '../app/interchange.dart';
import '../core/i18n.dart';
import '../app/audio_sync.dart';
import '../app/doc_import.dart';
import '../engine/audio/wav.dart';
import '../engine/tiles.dart';
import '../io/edit_lists.dart';
import '../io/lottie_export.dart';
import '../platform/io.dart';

/// Import / export of other formats: images, SVG, ORA, PSD, Lottie and palettes.
void registerInterchangeCommands(CommandRegistry r, AppState app) {
  void add(String id, CommandCategory cat, String Function() label, Future<void> Function() run, {bool needsDocument = true, String shortcut = ''}) {
    r.add(Command(
      id: id,
      category: cat,
      label: label,
      shortcut: shortcut,
      needsDocument: needsDocument,
      run: () async {
        try {
          await run();
        } catch (e) {
          app.toast('${label().replaceAll('…', '')}: $e', duration: const Duration(seconds: 6));
        }
      },
    ));
  }

  /// Picks one file and returns (name, bytes), or null when cancelled.
  Future<(String, Uint8List)?> pick(String title, List<String> exts) async {
    final f = await FilePicker.pickFile(dialogTitle: title, type: FileType.custom, allowedExtensions: exts);
    if (f == null) return null;
    final bytes = f.path == null ? null : await readFileBytes(f.path!);
    if (bytes == null) return null;
    return (f.name, bytes);
  }

  /// Lets the user save [bytes] as [fileName]; toasts the result.
  Future<void> save(String fileName, Uint8List bytes) async {
    final uri = await FilePicker.saveFile(dialogTitle: tr('Guardar como', 'Save as'), fileName: fileName, bytes: bytes);
    if (uri != null) app.toast(tr('Exportado: ', 'Exported: ') + (uri.scheme == 'file' ? uri.toFilePath() : fileName));
  }

  String base() => app.doc!.title;

  // ---- import ---------------------------------------------------------------
  add('file.importImage', CommandCategory.file, () => tr('Importar imagen como capa…', 'Import image as layer…'), () async {
    final f = await pick(tr('Importar imagen', 'Import image'), const ['png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp']);
    if (f == null) return;
    final img = await decodeImageBytes(f.$2);
    try {
      app.doc!.addImageLayer(img, p.basenameWithoutExtension(f.$1));
    } finally {
      img.dispose();
    }
  });
  add('file.importSvg', CommandCategory.file, () => tr('Importar SVG como capa vectorial…', 'Import SVG as vector layer…'), () async {
    final f = await pick(tr('Importar SVG', 'Import SVG'), const ['svg']);
    if (f == null) return;
    importSvgLayer(app.doc!, utf8.decode(f.$2, allowMalformed: true), name: p.basenameWithoutExtension(f.$1));
  });
  add('file.openOra', CommandCategory.file, () => tr('Abrir OpenRaster (.ora)…', 'Open OpenRaster (.ora)…'), () async {
    final f = await pick(tr('Abrir OpenRaster', 'Open OpenRaster'), const ['ora']);
    if (f == null) return;
    final name = p.basenameWithoutExtension(f.$1);
    app.addDocument(await projectFromOra(f.$2, name: name), title: name);
  }, needsDocument: false);

  add('file.importAudio', CommandCategory.animation, () => tr('Importar audio (WAV, MP3, OGG)…', 'Import audio (WAV, MP3, OGG)…'), () async {
    final f = await pick(tr('Importar audio', 'Import audio'), const ['wav', 'mp3', 'ogg']);
    if (f == null) return;
    final seconds = await importAudioClip(app.doc!, f.$1, f.$2, app.audio?.backend);
    app.toast('${tr('Audio añadido', 'Audio added')}: ${seconds.toStringAsFixed(1)} s');
  });

  add('file.importSequence', CommandCategory.animation, () => tr('Importar secuencia de imágenes…', 'Import image sequence…'), () async {
    final files = await FilePicker.pickFiles(dialogTitle: tr('Elige las imágenes (se ordenan por nombre)', 'Pick the images (sorted by name)'), type: FileType.custom, allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp']);
    if (files.isEmpty) return;
    final byName = {for (final f in files) f.name: f};
    final images = <ui.Image>[];
    try {
      for (final name in naturalSort(byName.keys)) {
        final f = byName[name]!;
        final bytes = f.path == null ? null : await readFileBytes(f.path!);
        if (bytes == null) continue;
        images.add(await decodeImageBytes(bytes));
      }
      if (images.isEmpty) return;
      final d = app.doc!;
      d.importImageSequence(images, p.basenameWithoutExtension(naturalSort(byName.keys).first), start: d.frame);
      app.toast('${tr('Fotogramas importados', 'Frames imported')}: ${images.length}');
    } finally {
      for (final i in images) {
        i.dispose();
      }
    }
  });
  add('anim.recordVoice', CommandCategory.animation, () => tr('Grabar voz / detener', 'Record voice / stop'), () async {
    final v = app.voice;
    if (v.recording) {
      final secs = await v.stop();
      app.toast(secs == null ? tr('No se grabó nada', 'Nothing was recorded') : '${tr('Voz añadida', 'Voice added')}: ${secs.toStringAsFixed(1)} s');
    } else {
      final error = await v.start(app.doc!, app.playback);
      app.toast(error ?? tr('Grabando… vuelve a pulsar para detener', 'Recording… press again to stop'));
    }
  });

  // ---- export ---------------------------------------------------------------
  add('file.exportOra', CommandCategory.file, () => tr('Exportar OpenRaster (.ora)…', 'Export OpenRaster (.ora)…'), () async {
    await save('${base()}.ora', await documentToOra(app.doc!));
  });
  add('file.exportPsd', CommandCategory.file, () => tr('Exportar Photoshop (.psd)…', 'Export Photoshop (.psd)…'), () async {
    await save('${base()}.psd', await documentToPsd(app.doc!));
  });
  add('file.exportLottie', CommandCategory.file, () => tr('Exportar Lottie (.json)…', 'Export Lottie (.json)…'), () async {
    final d = app.doc!;
    final res = await exportLottie(d.project, compId: d.compId);
    await save('${base()}.json', Uint8List.fromList(utf8.encode(res.json)));
    if (res.warnings.isNotEmpty) {
      app.toast('${tr('Omitido', 'Skipped')}: ${res.warnings.take(3).join(' · ')}${res.warnings.length > 3 ? ' …' : ''}', duration: const Duration(seconds: 8));
    }
  });

  add('file.exportEdl', CommandCategory.file, () => tr('Exportar lista de edición EDL…', 'Export EDL edit list…'), () async {
    final d = app.doc!;
    await save('${base()}.edl', Uint8List.fromList(utf8.encode(timelineToEdl(d.timeline, title: base()))));
  });
  add('file.exportFcpXml', CommandCategory.file, () => tr('Exportar XML de Final Cut Pro 7…', 'Export Final Cut Pro 7 XML…'), () async {
    final d = app.doc!;
    final xml = timelineToFcpXml(d.timeline, title: base(), width: d.comp.width, height: d.comp.height, mediaName: '${base()}.mov');
    await save('${base()}.xml', Uint8List.fromList(utf8.encode(xml)));
  });

  // ---- palettes -------------------------------------------------------------
  add('color.importPalette', CommandCategory.color, () => tr('Importar paleta…', 'Import palette…'), () async {
    final f = await pick(tr('Importar paleta', 'Import palette'), const ['gpl', 'hex', 'pal', 'aco', 'ase', 'txt']);
    if (f == null) return;
    final pal = readPalette(f.$2, f.$1);
    if (pal == null || pal.colors.isEmpty) {
      app.toast(tr('Formato de paleta no reconocido', 'Unrecognised palette format'));
      return;
    }
    app.ts.addPalette(pal.name.isEmpty ? p.basenameWithoutExtension(f.$1) : pal.name, pal.colors);
    app.toast('${tr('Paleta importada', 'Palette imported')}: ${pal.colors.length}');
  }, needsDocument: false);
  for (final fmt in PaletteFormat.values) {
    final ext = paletteExtension(fmt);
    add('color.exportPalette.$ext', CommandCategory.color, () => '${tr('Exportar paleta', 'Export palette')} (.$ext)…', () async {
      final pal = app.ts.palette;
      await save('${pal.name}.$ext', writePalette(pal.name, pal.colors, fmt));
    }, needsDocument: false);
  }
}

/// Decodes [bytes] as WAV and adds it as an audio clip at the current frame.
/// Returns its duration in seconds. Throws [FormatException] when it is not a WAV file.
/// Adds a WAV, MP3 or OGG file as an audio clip at the current frame and returns
/// its length in seconds. WAV is measured here; other formats ask [backend]
/// (the platform player). Throws FormatException when the length is unknown.
Future<double> importAudioClip(DocumentController doc, String fileName, Uint8List bytes, AudioBackend? backend) async {
  final format = sniffAudio(bytes);
  if (format == AudioFormat.wav) return importWavClip(doc, fileName, bytes);
  if (format == AudioFormat.unknown) throw FormatException(tr('Formato de audio no reconocido', 'Unrecognised audio format'));
  final seconds = await backend?.durationOf(bytes, format);
  if (seconds == null || seconds <= 0) {
    throw FormatException(tr('No se pudo leer la duración del audio en este dispositivo', 'Could not read the audio length on this device'));
  }
  doc.addAudioClip(p.basenameWithoutExtension(fileName), bytes, seconds);
  return seconds;
}

double importWavClip(DocumentController doc, String fileName, Uint8List bytes) {
  if (!isWav(bytes)) throw FormatException(tr('No es un archivo WAV', 'Not a WAV file'));
  final buffer = decodeWav(bytes);
  doc.addAudioClip(p.basenameWithoutExtension(fileName), bytes, buffer.duration);
  return buffer.duration;
}
