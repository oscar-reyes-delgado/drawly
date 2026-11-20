import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:drawly/app/autosave.dart';
import 'package:drawly/app/document_controller.dart';
import 'package:drawly/app/project_library.dart';
import 'package:drawly/app/settings.dart';
import 'package:drawly/core/i18n.dart';
import 'package:drawly/io/project_codec.dart';
import 'package:drawly/model/document.dart';
import 'package:drawly/ui/home/home_screen.dart';
import 'package:drawly/ui/theme.dart';

Future<void> _writeBlankProject(String path) async {
  final bytes = await ProjectCodec.encode(Project.blank(width: 32, height: 32));
  await File(path).writeAsBytes(bytes, flush: true);
}

Future<void> _settleIo(WidgetTester tester) async {
  for (var i = 0; i < 25; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

Future<void> _pumpHome(
  WidgetTester tester, {
  Key? homeKey,
  required Settings settings,
  required ProjectLibrary? library,
  void Function(Project project, String name, String? path)? onCreate,
  Future<void> Function(String path)? onOpen,
  VoidCallback? onOpenFile,
  VoidCallback? onSwitchMode,
  AutosaveService? autosave,
  void Function(DocumentController restored)? onRestore,
  VoidCallback? onSettings,
  Future<void> Function(String path)? onPreview,
  VoidCallback? onBack,
  bool switchToEasy = false,
  Size size = const Size(1280, 800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(settings, Brightness.dark),
      home: HomeScreen(
        key: homeKey,
        settings: settings,
        library: library,
        onCreate: onCreate ?? (_, _, _) {},
        onOpen: onOpen ?? (_) async {},
        onOpenFile: onOpenFile ?? () {},
        onSwitchMode: onSwitchMode ?? () {},
        autosave: autosave,
        onRestore: onRestore,
        onSettings: onSettings,
        onPreview: onPreview,
        onBack: onBack,
        switchToEasy: switchToEasy,
      ),
    ),
  );
  await _settleIo(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Settings settings;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    I18n.instance.lang = 'es';
    tempDir = Directory.systemTemp.createTempSync('drawly_home_test_');
    settings = Settings();
  });

  tearDown(() {
    settings.dispose();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  testWidgets('lists 2 projects in folder and tapping one calls onOpen with its path', (tester) async {
    final p1 = p.join(tempDir.path, 'Alpha.drawly');
    final p2 = p.join(tempDir.path, 'Beta.drawly');
    await tester.runAsync(() async {
      await _writeBlankProject(p1);
      await _writeBlankProject(p2);
    });

    String? openedPath;
    await _pumpHome(
      tester,
      settings: settings,
      library: ProjectLibrary(tempDir.path),
      onOpen: (path) async => openedPath = path,
    );

    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);

    await tester.tap(find.text('Alpha'));
    await tester.pumpAndSettle();
    expect(openedPath, p.normalize(File(p1).absolute.path));
  });

  testWidgets('the play button on a card previews that project without opening it', (tester) async {
    final p1 = p.join(tempDir.path, 'Alpha.drawly');
    await tester.runAsync(() => _writeBlankProject(p1));
    String? previewed, opened;
    await _pumpHome(
      tester,
      settings: settings,
      library: ProjectLibrary(tempDir.path),
      onOpen: (path) async => opened = path,
      onPreview: (path) async => previewed = path,
    );
    final abs = p.normalize(File(p1).absolute.path);
    await tester.tap(find.byKey(ValueKey('easy.home.play.$abs')));
    await tester.pumpAndSettle();
    expect(previewed, abs);
    expect(opened, isNull);
  });

  testWidgets('as a page it has a back arrow and offers the easy mode', (tester) async {
    var back = 0, mode = 0;
    await _pumpHome(tester, settings: settings, library: null, onBack: () => back++, switchToEasy: true, onSwitchMode: () => mode++);
    await tester.tap(find.byKey(const ValueKey('easy.home.back')));
    await tester.tap(find.byKey(const ValueKey('easy.home.switchMode')));
    await tester.pump();
    expect([back, mode], [1, 1]);
    expect(find.text(tr('Modo Fácil', 'Easy mode')), findsOneWidget);
  });

  testWidgets('+ New calls onCreate with 1-frame project having Fondo and Dibujo layers and path inside library', (tester) async {
    final p1 = p.join(tempDir.path, '${tr('Animación', 'Animation')} 1.drawly');
    await tester.runAsync(() => _writeBlankProject(p1));

    Project? createdProject;
    String? createdName;
    String? createdPath;

    await _pumpHome(
      tester,
      settings: settings,
      library: ProjectLibrary(tempDir.path),
      onCreate: (proj, name, path) {
        createdProject = proj;
        createdName = name;
        createdPath = path;
      },
    );

    await tester.tap(find.byKey(const ValueKey('easy.home.new')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pumpAndSettle();

    expect(createdProject, isNotNull);
    expect(createdProject!.main.timeline.length, 1);
    expect(createdProject!.main.layers.map((l) => l.props.name).toList(), [
      tr('Fondo', 'Background'),
      tr('Dibujo', 'Drawing'),
    ]);
    expect(createdName, '${tr('Animación', 'Animation')} 2');
    expect(createdPath, isNotNull);
    expect(p.dirname(createdPath!), tempDir.path);
  });

  testWidgets('rename and delete from card menu update disk and UI', (tester) async {
    final p1 = p.join(tempDir.path, 'Original.drawly');
    await tester.runAsync(() => _writeBlankProject(p1));

    await _pumpHome(
      tester,
      settings: settings,
      library: ProjectLibrary(tempDir.path),
    );

    expect(find.text('Original'), findsOneWidget);

    // Rename
    await tester.tap(find.byKey(const ValueKey('easy.home.menu.Original')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(tr('Renombrar', 'Rename')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Renombrado');
    await tester.tap(find.widgetWithText(FilledButton, tr('Renombrar', 'Rename')));
    await _settleIo(tester);

    expect(File(p1).existsSync(), isFalse);
    final renamedPath = p.join(tempDir.path, 'Renombrado.drawly');
    expect(File(renamedPath).existsSync(), isTrue);
    expect(find.text('Renombrado'), findsOneWidget);

    // Delete with confirmation
    await tester.tap(find.byKey(const ValueKey('easy.home.menu.Renombrado')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(tr('Eliminar', 'Delete')));
    await tester.pumpAndSettle();

    expect(find.text(tr('Se eliminará «Renombrado». No se puede deshacer.', '"Renombrado" will be deleted. This cannot be undone.')), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, tr('Eliminar', 'Delete')));
    await _settleIo(tester);

    expect(File(renamedPath).existsSync(), isFalse);
    expect(find.text('Renombrado'), findsNothing);
    expect(find.text(tr('Aún no tienes proyectos. Toca + Nuevo para empezar.', 'You have no projects yet. Tap + New to start.')), findsOneWidget);
  });

  testWidgets('recovery banner appears for dirty autosave, Recover calls onRestore and Discard removes it', (tester) async {
    final recDir = Directory(p.join(tempDir.path, 'recovery'))..createSync();
    final libDir = Directory(p.join(tempDir.path, 'lib'))..createSync();
    final autosave = AutosaveService(directory: () async => recDir.path);
    addTearDown(autosave.dispose);

    final doc = DocumentController(Project.blank(width: 32, height: 32, name: 'MiDibujo'), title: 'MiDibujo');
    addTearDown(doc.dispose);
    doc.apply('edit', doc.project.copyWith(palette: const [0xFFFF0000]));

    await tester.runAsync(() async {
      final saved = await autosave.saveNow(doc);
      expect(saved, isTrue);
    });

    DocumentController? restored;
    await _pumpHome(
      tester,
      settings: settings,
      library: ProjectLibrary(libDir.path),
      autosave: autosave,
      onRestore: (c) => restored = c,
    );

    expect(
      find.text(tr(
        'Drawly se cerró sin guardar. ¿Recuperar «MiDibujo»?',
        'Drawly closed without saving. Recover "MiDibujo"?',
      )),
      findsOneWidget,
    );

    // Recover
    await tester.tap(find.widgetWithText(FilledButton, tr('Recuperar', 'Recover')));
    await _settleIo(tester);

    expect(restored, isNotNull);
    expect(restored!.title, 'MiDibujo');
    restored!.dispose();
    final afterRestore = await tester.runAsync(() => autosave.listRecoverable());
    expect(afterRestore, isEmpty, reason: 'the recovered copy is dropped once reopened');

    // Make a new copy and test Discard on a fresh HomeScreen
    doc.apply('edit 2', doc.project.copyWith(palette: const [0xFF00FF00]));
    await tester.runAsync(() => autosave.saveNow(doc));
    await _pumpHome(
      tester,
      homeKey: UniqueKey(),
      settings: settings,
      library: ProjectLibrary(libDir.path),
      autosave: autosave,
    );
    expect(find.widgetWithText(OutlinedButton, tr('Descartar', 'Discard')), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, tr('Descartar', 'Discard')));
    await _settleIo(tester);

    expect(find.widgetWithText(OutlinedButton, tr('Descartar', 'Discard')), findsNothing);
    final remaining = await tester.runAsync(() => autosave.listRecoverable());
    expect(remaining, isEmpty);
  });

  testWidgets('damaged recovery copy shows error message and allows discarding', (tester) async {
    final recDir = Directory(p.join(tempDir.path, 'rec_bad'))..createSync();
    final libDir = Directory(p.join(tempDir.path, 'lib_bad'))..createSync();
    final autosave = AutosaveService(directory: () async => recDir.path);
    addTearDown(autosave.dispose);

    final doc = DocumentController(Project.blank(width: 32, height: 32, name: 'Roto'), title: 'Roto');
    addTearDown(doc.dispose);
    doc.apply('edit', doc.project.copyWith(palette: const [0xFFFF0000]));

    await tester.runAsync(() async {
      await autosave.saveNow(doc);
      final entries = await autosave.listRecoverable();
      await File(entries.first.file).writeAsBytes([1, 2, 3, 4], flush: true);
    });

    await _pumpHome(
      tester,
      settings: settings,
      library: ProjectLibrary(libDir.path),
      autosave: autosave,
    );

    await tester.tap(find.widgetWithText(FilledButton, tr('Recuperar', 'Recover')));
    await _settleIo(tester);

    expect(find.text(tr('La copia está dañada', 'The recovery copy is damaged')), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, tr('Descartar', 'Discard')), findsOneWidget);
  });

  testWidgets('with library: null only + New and Open… are shown', (tester) async {
    var openTapped = false;
    await _pumpHome(
      tester,
      settings: settings,
      library: null,
      onOpenFile: () => openTapped = true,
    );

    expect(find.byKey(const ValueKey('easy.home.new')), findsOneWidget);
    expect(find.byKey(const ValueKey('easy.home.openFile')), findsOneWidget);
    expect(find.text(tr('Mis proyectos', 'My projects')), findsNothing);
    expect(find.text(tr('Recientes fuera de la carpeta', 'Recent outside folder')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('easy.home.openFile')));
    await tester.pumpAndSettle();
    expect(openTapped, isTrue);
  });

  testWidgets('customize dialog creates project with chosen dimensions, fps and transparent background', (tester) async {
    Project? created;
    String? createdName;
    await _pumpHome(
      tester,
      settings: settings,
      library: ProjectLibrary(tempDir.path),
      onCreate: (proj, name, _) {
        created = proj;
        createdName = name;
      },
    );

    await tester.tap(find.byKey(const ValueKey('easy.home.customize')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'MiClip');
    await tester.tap(find.text('1080×1080'));
    await tester.tap(find.text('24 fps'));
    await tester.tap(find.text(tr('Transparente', 'Transparent')));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, tr('Crear', 'Create')));
    await tester.pumpAndSettle();

    expect(created, isNotNull);
    expect(createdName, 'MiClip');
    expect(created!.main.width, 1080);
    expect(created!.main.height, 1080);
    expect(created!.main.timeline.fps, 24);
  });

  testWidgets('recent files outside library folder are listed and missing ones are removed', (tester) async {
    final libDir = Directory(p.join(tempDir.path, 'library'))..createSync();
    final outsideDir = Directory(p.join(tempDir.path, 'outside'))..createSync();
    final existing = p.join(outsideDir.path, 'External.drawly');
    final missing = p.join(outsideDir.path, 'Missing.drawly');
    await tester.runAsync(() => _writeBlankProject(existing));

    settings.recentFiles = [existing, missing];

    String? opened;
    await _pumpHome(
      tester,
      settings: settings,
      library: ProjectLibrary(libDir.path),
      onOpen: (path) async => opened = path,
    );

    expect(find.text(tr('Recientes fuera de la carpeta', 'Recent outside folder')), findsOneWidget);
    expect(find.text('External'), findsOneWidget);
    expect(find.text('Missing'), findsNothing);
    expect(settings.recentFiles, [existing]);

    await tester.tap(find.widgetWithText(TextButton, tr('Abrir', 'Open')));
    await tester.pumpAndSettle();
    expect(opened, existing);
  });

  testWidgets('renders at 360x640 and 1280x800 without overflows', (tester) async {
    final p1 = p.join(tempDir.path, 'Uno.drawly');
    final p2 = p.join(tempDir.path, 'Dos.drawly');
    await tester.runAsync(() async {
      await _writeBlankProject(p1);
      await _writeBlankProject(p2);
    });

    for (final size in const [Size(360, 640), Size(1280, 800)]) {
      await _pumpHome(
        tester,
        settings: settings,
        library: ProjectLibrary(tempDir.path),
        onSettings: () {},
        size: size,
      );
      expect(tester.takeException(), isNull);
    }
  });
}
