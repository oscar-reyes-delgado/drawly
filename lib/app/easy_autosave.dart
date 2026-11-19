import 'dart:async';

import 'document_controller.dart';
import 'file_ops.dart';

/// Easy mode: saves documents that already have a `.drawly` file a few seconds
/// after the last edit, like a phone app (no «Save» needed). Never while a
/// stroke is in progress. Crash copies are the job of AutosaveService.
class EasyFileSaver {
  EasyFileSaver({this.idle = const Duration(seconds: 4), required this.enabled, required this.busy});
  final Duration idle;

  /// Checked on every change (easy mode on and autosave not switched off).
  final bool Function() enabled;
  final bool Function() busy;

  final Map<DocumentController, (VoidCallback, Timer?)> _docs = {};

  void attach(DocumentController d) {
    if (_docs.containsKey(d)) return;
    void listener() => _schedule(d);
    _docs[d] = (listener, null);
    d.addListener(listener);
  }

  void detach(DocumentController d) {
    final e = _docs.remove(d);
    if (e == null) return;
    d.removeListener(e.$1);
    e.$2?.cancel();
  }

  void _schedule(DocumentController d) {
    final e = _docs[d];
    if (e == null) return;
    e.$2?.cancel();
    if (!d.dirty || !enabled() || !_hasFile(d)) return;
    _docs[d] = (e.$1, Timer(idle, () => saveNow(d)));
  }

  static bool _hasFile(DocumentController d) => d.filePath?.toLowerCase().endsWith('.drawly') ?? false;

  /// Saves [d] to its file now if it is dirty; retries later while busy.
  Future<bool> saveNow(DocumentController d) async {
    if (!_docs.containsKey(d) || !d.dirty || !_hasFile(d)) return false;
    if (busy() || d.isBusy) {
      _schedule(d);
      return false;
    }
    try {
      return await saveProjectTo(d, d.filePath!);
    } catch (_) {
      return false;
    }
  }

  void dispose() {
    for (final d in [..._docs.keys]) {
      detach(d);
    }
  }
}

typedef VoidCallback = void Function();
