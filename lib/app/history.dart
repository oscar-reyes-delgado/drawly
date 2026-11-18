import '../model/document.dart';

/// One undo state: a full (structurally shared) snapshot of the project.
class HistoryEntry {
  HistoryEntry(this.label, this.project, {required this.compId, this.activeLayerId, this.frame = 0}) : time = DateTime.now();

  final String label;
  final Project project;
  final String compId;
  final String? activeLayerId;
  final int frame;
  final DateTime time;
}

/// Snapshot based undo history.
///
/// Because [Project] is immutable and tile planes share untouched tiles,
/// keeping hundreds of states costs only the pixels that actually changed.
class History {
  History(HistoryEntry initial, {this.maxEntries = 300}) : _entries = [initial];

  final List<HistoryEntry> _entries;
  int _index = 0;

  /// 0 = unlimited.
  int maxEntries;

  /// When true, editing from an earlier state keeps the later states
  /// instead of discarding them (non-linear history).
  bool nonLinear = false;

  List<HistoryEntry> get entries => _entries;
  int get index => _index;
  HistoryEntry get current => _entries[_index];
  bool get canUndo => _index > 0;
  bool get canRedo => _index < _entries.length - 1;

  void push(HistoryEntry e) {
    if (!nonLinear && _index < _entries.length - 1) {
      _entries.removeRange(_index + 1, _entries.length);
    }
    _entries.add(e);
    _index = _entries.length - 1;
    if (maxEntries > 0 && _entries.length > maxEntries) {
      final drop = _entries.length - maxEntries;
      _entries.removeRange(0, drop);
      _index -= drop;
    }
  }

  /// Replaces the current state (used to merge rapid successive tweaks such
  /// as dragging a slider into a single undo step).
  void replaceCurrent(HistoryEntry e) {
    _entries[_index] = e;
  }

  HistoryEntry? undo() {
    if (!canUndo) return null;
    _index--;
    return current;
  }

  HistoryEntry? redo() {
    if (!canRedo) return null;
    _index++;
    return current;
  }

  HistoryEntry jumpTo(int i) {
    _index = i.clamp(0, _entries.length - 1);
    return current;
  }

  void clear(HistoryEntry initial) {
    _entries
      ..clear()
      ..add(initial);
    _index = 0;
  }
}
