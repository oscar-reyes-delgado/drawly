import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drawly/app/doc_timeline.dart';
import 'package:drawly/app/document_controller.dart';
import 'package:drawly/app/easy_defaults.dart';
import 'package:drawly/app/file_ops.dart';
import 'package:drawly/app/settings.dart';
import 'package:drawly/core/i18n.dart';
import 'package:drawly/io/image_export.dart';
import 'package:drawly/ui/dialogs/export_dialog.dart';
import 'package:drawly/ui/easy/easy_export_sheet.dart';
import 'package:drawly/ui/theme.dart';

DocumentController _makeDoc({int width = 320, int height = 200, int frames = 6}) {
  final doc = DocumentController(easyProject(width: width, height: height), title: 'clip');
  doc.setLength(frames);
  return doc;
}

Future<void> _openSheet(
  WidgetTester tester,
  DocumentController doc,
  EasyExportActions actions,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(Settings(), Brightness.dark),
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showEasyExport(context, doc, actions),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('hides Video when writeVideo is null; calls writeVideo with chosen scale when present', (tester) async {
    final doc = _makeDoc();

    await _openSheet(
      tester,
      doc,
      EasyExportActions(
        pickFolder: () async => '/out',
        write: (_, _, _, _) async => const [],
      ),
    );
    expect(find.text(tr('Vídeo (MP4)', 'Video (MP4)')), findsNothing);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    double? recordedScale;
    String? recordedDir;
    await _openSheet(
      tester,
      doc,
      EasyExportActions(
        pickFolder: () async => '/videos',
        write: (_, _, _, _) async => const [],
        writeVideo: (dir, scale, onProgress, cancel) async {
          recordedDir = dir;
          recordedScale = scale;
          onProgress(1);
          return ['/videos/clip.mp4'];
        },
      ),
    );
    expect(find.text(tr('Vídeo (MP4)', 'Video (MP4)')), findsOneWidget);

    await tester.tap(find.text(tr('Grande (200 %)', 'Large (200%)')));
    await tester.pump();
    expect(find.text('640 × 400 px'), findsOneWidget);

    await tester.tap(find.text(tr('Vídeo (MP4)', 'Video (MP4)')));
    await tester.pumpAndSettle();

    expect(recordedDir, '/videos');
    expect(recordedScale, 2.0);
    expect(find.text(tr('¡Listo!', 'Done!')), findsOneWidget);
  });

  testWidgets('Animated GIF with Small passes animation/gif/0.5/0..6 and shows reported progress', (tester) async {
    final doc = _makeDoc();
    ExportOptions? recordedOpts;
    final completer = Completer<List<String>>();
    void Function(double)? progressCb;

    await _openSheet(
      tester,
      doc,
      EasyExportActions(
        pickFolder: () async => '/gifs',
        write: (opts, dir, onProgress, cancel) {
          recordedOpts = opts;
          progressCb = onProgress;
          return completer.future;
        },
      ),
    );

    await tester.tap(find.text(tr('Pequeño (50 %)', 'Small (50%)')));
    await tester.pump();
    expect(find.text('160 × 100 px'), findsOneWidget);

    await tester.tap(find.text(tr('GIF animado', 'Animated GIF')));
    await tester.pump();
    await tester.pump();

    expect(recordedOpts, isNotNull);
    expect(recordedOpts!.kind, ExportKind.animation);
    expect(recordedOpts!.anim, AnimFormat.gif);
    expect(recordedOpts!.scale, 0.5);
    expect(recordedOpts!.rangeStart, 0);
    expect(recordedOpts!.rangeEnd, 6);

    progressCb!(0.42);
    await tester.pump();

    final indicator = tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
    expect(indicator.value, closeTo(0.42, 1e-6));
    expect(find.text('42%'), findsOneWidget);

    completer.complete(['/gifs/clip.gif']);
    await tester.pumpAndSettle();
    expect(find.text(tr('¡Listo!', 'Done!')), findsOneWidget);
  });

  testWidgets('cancelling during slow write marks CancelToken and shows Export cancelled', (tester) async {
    final doc = _makeDoc();
    final completer = Completer<List<String>>();
    CancelToken? token;

    await _openSheet(
      tester,
      doc,
      EasyExportActions(
        pickFolder: () async => '/out',
        write: (opts, dir, onProgress, cancel) {
          token = cancel;
          return completer.future;
        },
      ),
    );

    await tester.tap(find.text(tr('GIF animado', 'Animated GIF')));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text(tr('Cancelar', 'Cancel')));
    await tester.pump();

    expect(token, isNotNull);
    expect(token!.isCancelled, isTrue);

    completer.complete(const []);
    await tester.pumpAndSettle();

    expect(find.text(tr('Exportación cancelada', 'Export cancelled')), findsOneWidget);
  });

  testWidgets('Image (PNG) exports current frame and only PNG has transparency checkbox', (tester) async {
    final doc = _makeDoc();
    doc.frame = 3;
    ExportOptions? recordedOpts;

    await _openSheet(
      tester,
      doc,
      EasyExportActions(
        pickFolder: () async => '/pngs',
        write: (opts, dir, onProgress, cancel) async {
          recordedOpts = opts;
          return ['/pngs/clip.png'];
        },
      ),
    );

    // Only one transparency checkbox exists, attached to the PNG card.
    expect(find.byType(Checkbox), findsOneWidget);
    expect(find.text(tr('Fondo transparente', 'Transparent background')), findsOneWidget);

    await tester.tap(find.byType(Checkbox));
    await tester.pump();

    await tester.tap(find.text(tr('Imagen (PNG)', 'Image (PNG)')));
    await tester.pumpAndSettle();

    expect(recordedOpts, isNotNull);
    expect(recordedOpts!.kind, ExportKind.still);
    expect(recordedOpts!.still, StillFormat.png);
    expect(recordedOpts!.frame, 3);
    expect(recordedOpts!.scale, 1.0);
    expect(recordedOpts!.transparent, isFalse);
  });

  testWidgets('Show in folder calls reveal with the first exported path', (tester) async {
    final doc = _makeDoc();
    String? revealedPath;

    await _openSheet(
      tester,
      doc,
      EasyExportActions(
        pickFolder: () async => '/out',
        write: (_, _, _, _) async => ['/out/clip.png', '/out/extra.png'],
        reveal: (path) async {
          revealedPath = path;
          return true;
        },
      ),
    );

    await tester.tap(find.text(tr('Imagen (PNG)', 'Image (PNG)')));
    await tester.pumpAndSettle();

    await tester.tap(find.text(tr('Mostrar en la carpeta', 'Show in folder')));
    await tester.pump();

    expect(revealedPath, '/out/clip.png');
  });

  testWidgets('fits on 360x640 phone without overflow', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final doc = _makeDoc();
    await _openSheet(
      tester,
      doc,
      EasyExportActions(
        pickFolder: () async => null,
        write: (_, _, _, _) async => const [],
        writeVideo: (_, _, _, _) async => const [],
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text(tr('Vídeo (MP4)', 'Video (MP4)')), findsOneWidget);
    expect(find.text(tr('Más opciones…', 'More options…')), findsOneWidget);
  });
}
