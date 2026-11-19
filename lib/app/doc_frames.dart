import '../core/i18n.dart';
import '../engine/tiles.dart';
import '../model/document.dart';
import '../model/layer.dart';
import '../model/vector.dart';
import 'document_controller.dart';

/// Copied frame columns: one map per frame, layer id -> drawing content
/// (TilePlane or VectorArt; null = blank).
class FrameColumnClipboard {
  static List<Map<String, Object?>> frames = const [];
}

CelTrack<Object>? _cels(Layer layer) => switch (layer) {
      PaintLayer() => layer.cels,
      VectorLayer() => layer.cels,
      _ => null,
    };

bool _animated(Layer layer) {
  final track = _cels(layer);
  return track != null && (track.xs.length > 1 || (track.xs.length == 1 && track.xs.single.frame > 0));
}

/// Mutable working copy; only compacted, immutable model data is published.
class _Columns<T> {
  _Columns(CelTrack<T> track, int length)
      : ids = List.generate(length, (f) => track.drawingIdAt(f) ?? 0),
        drawings = {...track.drawings},
        nextId = track.newDrawingId;

  final List<int> ids;
  final Map<int, T> drawings;
  int nextId;

  int add(T content) {
    final id = nextId++;
    drawings[id] = content;
    return id;
  }

  CelTrack<T> compact() => CelTrack<T>(
        drawings: drawings,
        xs: [
          for (var f = 0; f < ids.length; f++)
            if (f == 0 || ids[f] != ids[f - 1]) Exposure(f, ids[f]),
        ],
      ).pruned();
}

Layer _editColumns(Layer layer, int length, void Function<T>(_Columns<T> columns, T blank) edit) {
  CelTrack<T> update<T>(CelTrack<T> track, T blank) {
    final columns = _Columns(track, length);
    edit(columns, blank);
    return columns.compact();
  }

  return switch (layer) {
    PaintLayer() => layer.withCels(update(layer.cels, TilePlane.empty)),
    VectorLayer() => layer.withCels(update(layer.cels, VectorArt.empty)),
    _ => layer,
  };
}

Layer _shiftTracks(Layer layer, int from, int delta) {
  var out = layer;
  if (layer.props.tracks.isNotEmpty) {
    out = layer.withProps(layer.props.copyWith(tracks: {
      for (final e in layer.props.tracks.entries) e.key: e.value.shifted(from, delta),
    }));
  }
  if (out is PaintLayer && out.rig != null) out = out.withRig(out.rig!.shifted(from, delta));
  return out;
}

Timeline _shiftTimeline(Timeline timeline, int from, int delta, int length) {
  int? shifted(int? f) {
    if (f == null || f < from) return f;
    if (delta < 0 && f < from - delta) return null;
    return f + delta;
  }

  final start = shifted(timeline.loopStart)?.clamp(0, length - 1);
  final end = shifted(timeline.loopEnd)?.clamp((start ?? 0) + 1, length);
  return timeline.copyWith(
    length: length,
    loopStart: start,
    loopEnd: end,
    markers: [
      for (final m in timeline.markers)
        if (shifted(m.frame) case final int f) Marker(f, m.label, m.color),
    ],
    camera: timeline.camera.copyWith(tracks: {
      for (final e in timeline.camera.tracks.entries) e.key: e.value.shifted(from, delta),
    }),
  );
}

/// Scene-wide frame column editing, with a single undo step per operation.
extension DocFrames on DocumentController {
  /// Frames of the scene (= timeline.length).
  int get frameCount => timeline.length;

  /// Whether a paint/vector layer has multiple exposures or a delayed start.
  bool isAnimatedLayer(Layer l) => _animated(l);

  int _insertionIndex(int? after) => (after ?? frame).clamp(-1, frameCount - 1) + 1;

  void _insertColumns(String label, int at, int count, Layer Function(Layer) edit) {
    applyComp(label, (c) => c.copyWith(
          layers: mapAllLayers(c.layers, (l) => _shiftTracks(edit(l), at, count)),
          timeline: _shiftTimeline(c.timeline, at, count, c.timeline.length + count),
        ));
    frame = at;
  }

  /// Inserts independent blank drawings after [after] (default: current).
  /// Static layers hold their content, except for the active paint/vector layer.
  void insertFrames({int? after, int count = 1}) {
    if (count <= 0) return;
    final at = _insertionIndex(after);
    final length = frameCount;
    _insertColumns(tr('Insertar fotograma', 'Insert frame'), at, count, (layer) {
      if (!_animated(layer) && layer.id != activeLayerId) return layer;
      return _editColumns(layer, length, <T>(columns, blank) {
        final inserted = List.generate(count, (_) => columns.add(blank));
        columns.ids.insertAll(at, inserted);
      });
    });
  }

  /// Inserts a copy after [f] (default: current), with fresh drawing ids on
  /// animated layers. Immutable drawing contents remain shared safely.
  void duplicateFrame([int? f]) {
    final source = (f ?? frame).clamp(0, frameCount - 1);
    final length = frameCount;
    _insertColumns(tr('Duplicar fotograma', 'Duplicate frame'), source + 1, 1, (layer) {
      if (!_animated(layer)) return layer;
      return _editColumns(layer, length, <T>(columns, blank) {
        final content = columns.drawings[columns.ids[source]] ?? blank;
        columns.ids.insert(source + 1, columns.add(content));
      });
    });
  }

  /// Removes [start, end), pruning unused drawings and shifting timed keys.
  /// Deleting every column leaves one blank column and preserves static layers.
  void deleteFrames(int start, int end) {
    final length = frameCount;
    final first = start.clamp(0, length), last = end.clamp(0, length);
    if (first >= last) return;
    final count = last - first;
    final newLength = (length - count).clamp(1, length);
    applyComp(tr('Eliminar fotogramas', 'Delete frames'), (c) => c.copyWith(
          layers: mapAllLayers(c.layers, (layer) {
            final edited = !_animated(layer) ? layer : _editColumns(layer, length, <T>(columns, blank) {
              columns.ids.removeRange(first, last);
              if (columns.ids.isEmpty) columns.ids.add(columns.add(blank));
            });
            return _shiftTracks(edited, first, -count);
          }),
          timeline: _shiftTimeline(c.timeline, first, -count, newLength),
        ));
    frame = frame.clamp(0, newLength - 1);
  }

  /// Moves [start, end) to the insertion boundary [to] in the original timeline.
  /// Destinations inside the block (including either boundary) do nothing.
  /// Only drawings move; property keys, markers and camera remain in place.
  void moveFrames(int start, int end, int to) {
    final length = frameCount;
    final first = start.clamp(0, length), last = end.clamp(0, length);
    final target = to.clamp(0, length);
    if (first >= last || (target >= first && target <= last)) return;
    final destination = target > last ? target - (last - first) : target;
    applyComp(tr('Mover fotogramas', 'Move frames'), (c) => c.copyWith(
          layers: mapAllLayers(c.layers, (layer) => !_animated(layer) ? layer : _editColumns(layer, length, <T>(columns, blank) {
            final moved = columns.ids.sublist(first, last);
            columns.ids.removeRange(first, last);
            columns.ids.insertAll(destination, moved);
          })),
        ));
  }

  /// Copies visible drawing contents in [start, end), including held/blank cels.
  /// An empty clipped range leaves the clipboard unchanged.
  void copyFrames(int start, int end) {
    final first = start.clamp(0, frameCount), last = end.clamp(0, frameCount);
    if (first >= last) return;
    final layers = walkLayers(comp.layers).where((l) => _cels(l) != null).toList();
    FrameColumnClipboard.frames = [
      for (var f = first; f < last; f++) {for (final l in layers) l.id: _cels(l)!.at(f)},
    ];
  }

  /// Inserts copied columns after [after] (default: current) with fresh ids.
  /// Static layers hold their content; missing layers are ignored and animated
  /// layers absent from a copied column hold the preceding drawing.
  void pasteFrames({int? after}) {
    final copied = FrameColumnClipboard.frames;
    if (copied.isEmpty) return;
    final length = frameCount, at = _insertionIndex(after);
    _insertColumns(tr('Pegar fotogramas', 'Paste frames'), at, copied.length, (layer) {
      if (!_animated(layer)) return layer;
      return _editColumns(layer, length, <T>(columns, blank) {
        var held = at == 0 ? 0 : columns.ids[at - 1];
        final inserted = <int>[];
        for (final column in copied) {
          if (column.containsKey(layer.id)) {
            final content = column[layer.id];
            if (content == null || content is T) held = columns.add(content == null ? blank : content as T);
          }
          inserted.add(held);
        }
        columns.ids.insertAll(at, inserted);
      });
    });
  }

  /// Reverses drawing columns in [start, end), preserving held drawing ids.
  /// Property keys, markers and camera remain in place.
  void reverseFrameRange(int start, int end) {
    final length = frameCount;
    final first = start.clamp(0, length), last = end.clamp(0, length);
    if (last - first < 2) return;
    applyComp(tr('Invertir fotogramas', 'Reverse frames'), (c) => c.copyWith(
          layers: mapAllLayers(c.layers, (layer) => !_animated(layer) ? layer : _editColumns(layer, length, <T>(columns, blank) {
            final reversed = columns.ids.sublist(first, last).reversed.toList();
            columns.ids.replaceRange(first, last, reversed);
          })),
        ));
  }
}
