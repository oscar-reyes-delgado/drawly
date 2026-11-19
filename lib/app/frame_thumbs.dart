import 'dart:async';
import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../engine/compositor.dart';
import '../model/document.dart';
import '../model/layer.dart';
import 'document_controller.dart';

/// Small renders of timeline frames, re-rendered only when what the frame
/// shows changes. Listeners are notified when new thumbnails are ready.
class FrameThumbnailCache extends ChangeNotifier {
  FrameThumbnailCache({
    this.height = 72,
    this.budgetBytes = 48 * 1024 * 1024,
    this.perTick = 3,
  });

  /// Thumbnail height in px; width keeps the aspect ratio.
  final double height;

  /// LRU budget (width * height * 4 per image).
  final int budgetBytes;

  /// Renders per scheduling tick.
  final int perTick;

  /// While true no rendering happens (set during playback and strokes).
  bool paused = false;

  final LinkedHashMap<_ThumbKey, _ThumbEntry> _cache = LinkedHashMap();
  final List<_PendingItem> _queue = [];
  final Set<_ThumbKey> _pendingKeys = {};

  int _totalBytes = 0;
  int _renderCount = 0;
  bool _scheduled = false;
  bool _disposed = false;

  /// Number of renders done since creation (for tests).
  int get renderCount => _renderCount;

  /// Thumbnail of [frame] if it matches the current document; otherwise
  /// schedules a render and returns the previous (stale) image for that frame, or null.
  ui.Image? thumbnailFor(DocumentController doc, int frame) {
    if (_disposed || frame < 0 || frame >= doc.timeline.length) return null;
    final key = _ThumbKey(doc.uid, doc.compId, frame);
    final entry = _cache[key];
    final sig = signatureOf(doc.comp, frame);
    if (entry != null && _sigEquals(entry.sig, sig)) {
      _cache.remove(key);
      _cache[key] = entry;
      return entry.image;
    }
    _enqueue(doc, [frame]);
    return entry?.image;
  }

  /// Schedules renders for [frames] (e.g. the visible ones), nearest to the playhead first.
  void request(DocumentController doc, Iterable<int> frames) {
    if (_disposed) return;
    _enqueue(doc, frames);
  }

  /// What frame [frame] shows, as a list compared element by element with `identical`.
  /// Public for tests.
  List<Object?> signatureOf(Comp comp, int frame) {
    final sig = <Object?>[comp.width, comp.height, comp.background];
    for (final l in walkLayers(comp.layers)) {
      sig.add(l.props);
      if (l is PaintLayer) {
        sig.add(l.cels.at(frame));
      } else if (l is VectorLayer) {
        sig.add(l.cels.at(frame));
      } else {
        sig.add(l);
      }
    }
    return sig;
  }

  /// Clears all cached thumbnails and pending render requests.
  void clear() {
    for (final entry in _cache.values) {
      entry.image.dispose();
    }
    _cache.clear();
    _totalBytes = 0;
    _queue.clear();
    _pendingKeys.clear();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    clear();
    super.dispose();
  }

  void _enqueue(DocumentController doc, Iterable<int> frames) {
    final len = doc.timeline.length;
    var added = false;
    for (final f in frames) {
      if (f < 0 || f >= len) continue;
      final key = _ThumbKey(doc.uid, doc.compId, f);
      if (_pendingKeys.add(key)) {
        _queue.add(_PendingItem(key, WeakReference(doc), f));
        added = true;
      }
    }
    if (added) {
      _queue.sort((a, b) {
        final fa = (a.frame - (a.docRef.target?.frame ?? 0)).abs();
        final fb = (b.frame - (b.docRef.target?.frame ?? 0)).abs();
        return fa != fb ? fa.compareTo(fb) : a.frame.compareTo(b.frame);
      });
    }
    if (!paused && !_scheduled && _queue.isNotEmpty) {
      _scheduled = true;
      Future.delayed(Duration.zero, _pump);
    }
  }

  void _pump() {
    _scheduled = false;
    if (_disposed || paused || _queue.isEmpty) return;

    var rendered = 0;
    var renderedAny = false;
    while (_queue.isNotEmpty && rendered < perTick) {
      final item = _queue.removeAt(0);
      _pendingKeys.remove(item.key);

      final doc = item.docRef.target;
      if (doc == null) continue;
      if (item.frame < 0 || item.frame >= doc.timeline.length) continue;
      if (doc.compId != item.key.compId) continue;

      final comp = doc.comp;
      final sig = signatureOf(comp, item.frame);
      final existing = _cache[item.key];
      if (existing != null && _sigEquals(existing.sig, sig)) {
        continue;
      }

      final scale = comp.height > 0 ? height / comp.height : 1.0;
      final img = renderCompImage(
        doc.project,
        comp,
        item.frame.toDouble(),
        scale: scale,
        background: true,
        forExport: true,
        useCamera: false,
      );
      _renderCount++;
      rendered++;
      renderedAny = true;

      _put(item.key, sig, img);
    }

    if (renderedAny && !_disposed) {
      notifyListeners();
    }
    if (_queue.isNotEmpty && !paused && !_disposed) {
      _scheduled = true;
      Future.delayed(Duration.zero, _pump);
    }
  }

  void _put(_ThumbKey key, List<Object?> sig, ui.Image image) {
    final old = _cache.remove(key);
    if (old != null) {
      _totalBytes -= old.bytes;
      old.image.dispose();
    }
    final bytes = image.width * image.height * 4;
    _cache[key] = _ThumbEntry(sig, image, bytes);
    _totalBytes += bytes;
    while (_totalBytes > budgetBytes && _cache.isNotEmpty) {
      final oldestKey = _cache.keys.first;
      final oldest = _cache.remove(oldestKey)!;
      _totalBytes -= oldest.bytes;
      oldest.image.dispose();
    }
  }

  static bool _sigEquals(List<Object?> a, List<Object?> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i])) return false;
    }
    return true;
  }
}

class _ThumbKey {
  const _ThumbKey(this.docId, this.compId, this.frame);

  final String docId;
  final String compId;
  final int frame;

  @override
  bool operator ==(Object other) =>
      other is _ThumbKey && other.docId == docId && other.compId == compId && other.frame == frame;

  @override
  int get hashCode => Object.hash(docId, compId, frame);
}

class _ThumbEntry {
  const _ThumbEntry(this.sig, this.image, this.bytes);

  final List<Object?> sig;
  final ui.Image image;
  final int bytes;
}

class _PendingItem {
  const _PendingItem(this.key, this.docRef, this.frame);

  final _ThumbKey key;
  final WeakReference<DocumentController> docRef;
  final int frame;
}
