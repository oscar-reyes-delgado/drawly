import 'package:flutter/material.dart';

import '../../app/app_state.dart';
import '../../app/file_ops.dart';
import '../../app/project_library.dart';
import '../../core/i18n.dart';
import '../../model/document.dart';
import '../../platform/io.dart' as io;
import '../dialogs/prefs_dialog.dart';
import '../easy/easy_shell.dart';
import '../home/home_screen.dart';
import 'animation_player.dart';

/// The Drawly projects folder (null on the web, where there is no file system).
final Future<ProjectLibrary?> projectLibrary = () async {
  if (!io.hasFileSystem) return null;
  try {
    return ProjectLibrary(await ProjectLibrary.defaultDir());
  } catch (_) {
    return null;
  }
}();

/// Opens the library as a page (advanced mode): the same projects, with ▶ to
/// watch each animation; opening or creating a project closes the page.
Future<void> showLibraryPage(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ProjectLibraryView(asPage: true)));

/// Project library wired to the app: new projects are saved in the folder at
/// once, the ▶ on each card plays the animation without opening it.
class ProjectLibraryView extends StatelessWidget {
  const ProjectLibraryView({super.key, this.asPage = false});

  /// Shown as a pushed page (advanced mode): back arrow, closes after opening.
  final bool asPage;

  @override
  Widget build(BuildContext context) {
    final app = AppState.I;
    void close() {
      if (asPage && Navigator.of(context).canPop()) Navigator.of(context).pop();
    }

    return FutureBuilder<ProjectLibrary?>(
      future: projectLibrary,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        return HomeScreen(
          title: asPage ? tr('Biblioteca', 'Library') : 'Drawly',
          settings: app.settings,
          library: snap.data,
          autosave: app.autosave,
          onBack: asPage ? close : null,
          switchToEasy: asPage,
          onCreate: (Project project, String name, String? path) async {
            final d = app.addDocument(project, title: name, path: path);
            close();
            if (path != null && await saveProjectTo(d, path)) app.settings.addRecent(path);
          },
          onOpen: (path) async {
            try {
              final c = await openProjectFrom(path);
              app.addDocument(c.project, title: c.title, path: c.filePath);
              c.dispose();
              app.settings.addRecent(path);
              close();
            } catch (e) {
              app.toast('${tr('No se pudo abrir', 'Could not open')}: $e');
            }
          },
          onOpenFile: () {
            close();
            app.commands.run('file.open');
          },
          onRestore: (restored) {
            final d = app.addDocument(restored.project, title: restored.title, path: restored.filePath);
            d.dirty = true;
            d.touch();
            restored.dispose();
            close();
          },
          onPreview: (path) async {
            final error = await playProjectFile(context, path);
            if (error != null) app.toast(error);
          },
          onSwitchMode: () {
            close();
            setUiMode(app, asPage ? 'easy' : 'advanced');
          },
          onSettings: () => asPage ? showPrefsDialog(context) : openEasyPrefs(context),
        );
      },
    );
  }
}
