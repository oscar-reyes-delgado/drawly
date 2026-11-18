import 'dart:math' as math;
import 'dart:typed_data';

import '../core/i18n.dart';
import '../core/ids.dart';
import '../engine/tiles.dart';
import '../model/anim.dart';
import '../model/document.dart';
import '../model/layer.dart';
import '../model/vector.dart';
import 'document_controller.dart';

/// Copied cel contents (frame clipboard).
class FrameClipboard {
  static List<Object> contents = const [];
}

Layer? _mapCels(Layer l, CelTrack<T> Function<T>(CelTrack<T> t, T blank) f) => switch (l) {
      PaintLayer() => l.withCels(f<TilePlane>(l.cels, TilePlane.empty)),
      VectorLayer() => l.withCels(f<VectorArt>(l.cels, VectorArt.empty)),
      _ => null,
    };

/// Timeline / animation operations.
extension DocTimeline on DocumentController {
  void setTimeline(String label, Timeline Function(Timeline t) f, {String? mergeKey}) =>
      applyComp(label, (c) => c.copyWith(timeline: f(c.timeline)), mergeKey: mergeKey);

  void setFps(int fps) => setTimeline(tr('Fotogramas por segundo', 'Frame rate'), (t) => t.copyWith(fps: fps.clamp(1, 240)), mergeKey: 'fps');

  void setLength(int frames) {
    final n = math.max(1, frames);
    setTimeline(tr('Duración', 'Duration'), (t) => t.copyWith(length: n), mergeKey: 'length');
    if (frame >= n) frame = n - 1;
  }

  void setLoopRange(int? start, int? end) => setTimeline(tr('Rango de reproducción', 'Playback range'), (t) => t.copyWith(loopStart: start, loopEnd: end));

  /// Grows the timeline when keys are placed beyond its end.
  Timeline _fit(Timeline t, int lastFrame) => lastFrame >= t.length ? t.copyWith(length: lastFrame + 1) : t;

  bool get activeHasCels => activeLayer is PaintLayer || activeLayer is VectorLayer;

  CelTrack<Object>? celsOf(Layer? l) => switch (l) {
        PaintLayer() => l.cels,
        VectorLayer() => l.cels,
        _ => null,
      };

  /// Adds a key at the current frame of the active layer: a new blank
  /// drawing, or a copy of what is currently shown.
  void addKeyFrame({bool duplicate = false, String? layerId, int? at}) {
    final l = comp.layer(layerId ?? activeLayerId);
    if (l == null) return;
    final f = at ?? frame;
    final next = _mapCels(l, <T>(t, blank) {
      final cur = t.drawingIdAt(f);
      final id = t.newDrawingId;
      final T content = duplicate && cur != null ? t.drawings[cur] as T : blank;
      return t.withDrawing(id, content).withKey(f, id);
    });
    if (next == null) return;
    applyComp(duplicate ? tr('Duplicar fotograma', 'Duplicate frame') : tr('Nuevo fotograma', 'New frame'),
        (c) => c.updateLayer(l.id, (_) => next).copyWith(timeline: _fit(c.timeline, f)));
  }

  /// Inserts an explicit blank (empty exposure) at the current frame.
  void addBlankKey({String? layerId, int? at}) {
    final l = comp.layer(layerId ?? activeLayerId);
    if (l == null) return;
    final f = at ?? frame;
    final next = _mapCels(l, <T>(t, blank) => t.withKey(f, 0));
    if (next == null) return;
    applyComp(tr('Fotograma en blanco', 'Blank frame'), (c) => c.updateLayer(l.id, (_) => next));
  }

  void deleteKey({String? layerId, int? at}) {
    final l = comp.layer(layerId ?? activeLayerId);
    if (l == null) return;
    final f = at ?? frame;
    final next = _mapCels(l, <T>(t, blank) {
      final key = t.exposureAt(f);
      return key == null ? t : t.withoutKey(key.frame);
    });
    if (next == null) return;
    applyComp(tr('Eliminar fotograma clave', 'Delete keyframe'), (c) => c.updateLayer(l.id, (_) => next));
  }

  void moveKey(String layerId, int from, int to) {
    if (to < 0 || from == to) return;
    final l = comp.layer(layerId);
    if (l == null) return;
    final next = _mapCels(l, <T>(t, blank) => t.movedKey(from, to));
    if (next == null) return;
    applyComp(tr('Mover fotograma', 'Move frame'), (c) => c.updateLayer(l.id, (_) => next).copyWith(timeline: _fit(c.timeline, to)));
  }

  /// Inserts ([count] > 0) or removes ([count] < 0) frames after the current
  /// frame, on the active layer or on every layer (also shifting tweens,
  /// markers and the camera).
  void shiftFrames(int count, {bool allLayers = false}) {
    if (count == 0) return;
    final from = count > 0 ? frame + 1 : frame + 1;
    Layer shift(Layer l) {
      final cels = _mapCels(l, <T>(t, blank) => t.shifted(from, count)) ?? l;
      if (!allLayers) return cels;
      final tracks = {for (final e in cels.props.tracks.entries) e.key: e.value.shifted(from, count)};
      final moved = cels.withProps(cels.props.copyWith(tracks: tracks));
      return moved is PaintLayer && moved.rig != null ? moved.withRig(moved.rig!.shifted(from, count)) : moved;
    }

    applyComp(count > 0 ? tr('Insertar fotogramas', 'Insert frames') : tr('Quitar fotogramas', 'Remove frames'), (c) {
      var layers = c.layers;
      var t = c.timeline;
      if (allLayers) {
        layers = mapAllLayers(layers, shift);
        t = t.copyWith(
          length: math.max(1, t.length + count),
          markers: [
            for (final m in t.markers)
              if (m.frame < from)
                m
              else if (count > 0 || m.frame >= from - count)
                Marker(m.frame + count, m.label, m.color),
          ],
          camera: t.camera.copyWith(tracks: {for (final e in t.camera.tracks.entries) e.key: e.value.shifted(from, count)}),
        );
      } else {
        final id = activeLayerId;
        if (id == null) return c;
        layers = mapLayer(layers, id, shift);
        var last = 0;
        final cels = celsOf(findLayer(layers, id));
        if (cels != null) last = cels.lastKeyFrame;
        t = _fit(t, last);
      }
      return c.copyWith(layers: layers, timeline: t);
    });
  }

  /// X-sheet: expose an existing drawing at [f] (drawing substitution).
  void setExposure(String layerId, int f, int drawing) {
    final l = comp.layer(layerId);
    if (l == null) return;
    final next = _mapCels(l, <T>(t, blank) => (drawing == 0 || t.drawings.containsKey(drawing)) ? t.withKey(f, drawing) : t);
    if (next == null) return;
    applyComp(tr('Cambiar dibujo expuesto', 'Change exposed drawing'), (c) => c.updateLayer(l.id, (_) => next).copyWith(timeline: _fit(c.timeline, f)));
  }

  /// Gives the key at the current frame its own copy of a shared drawing.
  void makeDrawingUnique({String? layerId, int? at}) {
    final l = comp.layer(layerId ?? activeLayerId);
    if (l == null) return;
    final f = at ?? frame;
    final next = _mapCels(l, <T>(t, blank) {
      final key = t.exposureAt(f);
      if (key == null || key.drawing == 0 || !t.isShared(key.drawing)) return t;
      final id = t.newDrawingId;
      return t.withDrawing(id, t.drawings[key.drawing] as T).withKey(key.frame, id);
    });
    if (next == null) return;
    applyComp(tr('Hacer dibujo único', 'Make drawing unique'), (c) => c.updateLayer(l.id, (_) => next));
  }

  /// Repeats the keys in [start, end) [times] more times (cycle / loop).
  void repeatFrames(int start, int end, int times, {String? layerId}) {
    final l = comp.layer(layerId ?? activeLayerId);
    if (l == null || end <= start || times < 1) return;
    final span = end - start;
    var last = end;
    final next = _mapCels(l, <T>(t, blank) {
      var out = t;
      final keys = t.xs.where((e) => e.frame >= start && e.frame < end).toList();
      final head = t.exposureAt(start);
      for (var k = 1; k <= times; k++) {
        final base = start + span * k;
        if (head != null && !t.hasKeyAt(start)) out = out.withKey(base, head.drawing);
        for (final e in keys) {
          out = out.withKey(base + (e.frame - start), e.drawing);
        }
        last = base + span;
      }
      return out;
    });
    if (next == null) return;
    applyComp(tr('Repetir ciclo', 'Repeat cycle'), (c) => c.updateLayer(l.id, (_) => next).copyWith(timeline: _fit(c.timeline, last - 1)));
  }

  /// Reverses the order of the keys in [start, end).
  void reverseFrames(int start, int end, {String? layerId}) {
    final l = comp.layer(layerId ?? activeLayerId);
    if (l == null || end <= start) return;
    final next = _mapCels(l, <T>(t, blank) {
      final inside = t.xs.where((e) => e.frame >= start && e.frame < end).toList();
      if (inside.length < 2) return t;
      // durations of each key inside the range
      final durations = <int>[];
      for (var i = 0; i < inside.length; i++) {
        final nextFrame = i + 1 < inside.length ? inside[i + 1].frame : end;
        durations.add(nextFrame - inside[i].frame);
      }
      var out = CelTrack<T>(drawings: t.drawings, xs: t.xs.where((e) => e.frame < start || e.frame >= end).toList());
      var f = inside.first.frame;
      for (var i = inside.length - 1; i >= 0; i--) {
        out = out.withKey(f, inside[i].drawing);
        f += durations[i];
      }
      return out;
    });
    if (next == null) return;
    applyComp(tr('Invertir fotogramas', 'Reverse frames'), (c) => c.updateLayer(l.id, (_) => next));
  }

  void copyFrame() {
    final l = activeLayer;
    final Object? content = switch (l) {
      PaintLayer() => l.cels.at(frame),
      VectorLayer() => l.cels.at(frame),
      _ => null,
    };
    if (content != null) FrameClipboard.contents = [content];
  }

  void pasteFrame() {
    final l = activeLayer;
    if (l == null || FrameClipboard.contents.isEmpty) return;
    var f = frame;
    Layer cur = l;
    for (final content in FrameClipboard.contents) {
      if (cur is PaintLayer && content is TilePlane) {
        final id = cur.cels.newDrawingId;
        cur = cur.withCels(cur.cels.withDrawing(id, content).withKey(f, id));
      } else if (cur is VectorLayer && content is VectorArt) {
        final id = cur.cels.newDrawingId;
        cur = cur.withCels(cur.cels.withDrawing(id, content).withKey(f, id));
      } else {
        return;
      }
      f++;
    }
    final result = cur;
    applyComp(tr('Pegar fotograma', 'Paste frame'), (c) => c.updateLayer(l.id, (_) => result).copyWith(timeline: _fit(c.timeline, f - 1)));
  }

  int? prevKeyFrame() => celsOf(activeLayer)?.prevKeyFrame(celsOf(activeLayer)?.exposureAt(frame)?.frame ?? frame);
  int? nextKeyFrame() => celsOf(activeLayer)?.nextKeyFrame(frame);

  void goToPrevKey() {
    final f = prevKeyFrame();
    if (f != null) frame = f;
  }

  void goToNextKey() {
    final f = nextKeyFrame();
    if (f != null) frame = f;
  }

  void stepFrame(int delta) {
    final n = timeline.length;
    frame = ((frame + delta) % n + n) % n;
  }

  // ---- property (tween) keys ----------------------------------------------

  /// Sets an animatable layer property. Adds / updates a keyframe at the
  /// current frame when the property is already animated or auto-key is on;
  /// otherwise changes the static value.
  void setLayerProp(String layerId, Prop p, double v, {String? mergeKey, bool forceKey = false}) {
    updateProps(p.label, layerId, (props) => _withProp(props, p, v, forceKey), mergeKey: mergeKey ?? 'prop:$layerId:${p.name}');
  }

  LayerProps _withProp(LayerProps props, Prop p, double v, bool forceKey) {
    final track = props.tracks[p];
    final animated = track != null && track.isNotEmpty;
    if (animated || forceKey || autoKeyTransforms) {
      final existing = track?.keyAt(frame);
      final key = AnimKey(frame, v, existing?.ease ?? Ease.smooth);
      var t = (track ?? AnimTrack.none).withKey(key);
      // first key of a new track: also pin the previous static value at frame 0
      if (!animated && frame != 0) {
        t = t.withKey(AnimKey(0, p == Prop.opacity ? props.opacity : props.xf.get(p)));
      }
      return props.copyWith(tracks: {...props.tracks, p: t});
    }
    if (p == Prop.opacity) return props.copyWith(opacity: v.clamp(0.0, 1.0));
    return props.copyWith(xf: props.xf.set(p, v));
  }

  /// Sets several transform properties in one undo step (move / rotate tools).
  void setLayerProps(String layerId, Map<Prop, double> values, {String? mergeKey, String? label}) {
    updateProps(label ?? tr('Transformar capa', 'Transform layer'), layerId, (props) {
      var p = props;
      values.forEach((k, v) => p = _withProp(p, k, v, false));
      return p;
    }, mergeKey: mergeKey);
  }

  /// Same as [setLayerProps] for several layers in a single undo step.
  void setLayersProps(Map<String, Map<Prop, double>> values, {String? mergeKey, String? label}) {
    applyComp(label ?? tr('Transformar capas', 'Transform layers'), (c) {
      var out = c;
      values.forEach((id, props) {
        out = out.updateLayer(id, (l) {
          var p = l.props;
          props.forEach((k, v) => p = _withProp(p, k, v, false));
          return l.withProps(p);
        });
      });
      return out;
    }, mergeKey: mergeKey);
  }

  void addPropKey(String layerId, Prop p, {Ease ease = Ease.smooth}) {
    final l = comp.layer(layerId);
    if (l == null) return;
    final v = l.props.valueAt(p, frame.toDouble());
    updateProps(tr('Añadir fotograma clave', 'Add keyframe'), layerId, (props) {
      final t = (props.tracks[p] ?? AnimTrack.none).withKey(AnimKey(frame, v, ease));
      return props.copyWith(tracks: {...props.tracks, p: t});
    });
  }

  /// Keys position, scale, rotation and opacity at the current frame.
  void addTransformKeys(String layerId) {
    final l = comp.layer(layerId);
    if (l == null) return;
    updateProps(tr('Añadir fotogramas clave', 'Add keyframes'), layerId, (props) {
      final tracks = {...props.tracks};
      for (final p in const [Prop.x, Prop.y, Prop.scaleX, Prop.scaleY, Prop.rotation, Prop.opacity]) {
        final v = props.valueAt(p, frame.toDouble());
        final existing = tracks[p]?.keyAt(frame);
        tracks[p] = (tracks[p] ?? AnimTrack.none).withKey(AnimKey(frame, v, existing?.ease ?? Ease.smooth));
      }
      return props.copyWith(tracks: tracks);
    });
  }

  void removePropKey(String layerId, Prop p, int f) {
    updateProps(tr('Eliminar fotograma clave', 'Delete keyframe'), layerId, (props) {
      final t = props.tracks[p];
      if (t == null) return props;
      final nt = t.withoutKey(f);
      final tracks = {...props.tracks};
      if (nt.isEmpty) {
        tracks.remove(p);
      } else {
        tracks[p] = nt;
      }
      return props.copyWith(tracks: tracks);
    });
  }

  void movePropKey(String layerId, Prop p, int from, int to, {String? mergeKey}) {
    if (to < 0) return;
    updateProps(tr('Mover fotograma clave', 'Move keyframe'), layerId, (props) {
      final t = props.tracks[p];
      if (t == null) return props;
      return props.copyWith(tracks: {...props.tracks, p: t.movedKey(from, to)});
    }, mergeKey: mergeKey);
  }

  void setPropKey(String layerId, Prop p, int f, {double? value, Ease? ease, String? mergeKey}) {
    updateProps(tr('Editar fotograma clave', 'Edit keyframe'), layerId, (props) {
      final t = props.tracks[p];
      final k = t?.keyAt(f);
      if (t == null || k == null) return props;
      return props.copyWith(tracks: {...props.tracks, p: t.withKey(k.copyWith(value: value, ease: ease))});
    }, mergeKey: mergeKey);
  }

  void clearTracks(String layerId) => updateProps(tr('Quitar animación', 'Remove animation'), layerId, (p) => p.copyWith(tracks: const {}));

  void setParent(String layerId, String? parentId) {
    if (parentId == layerId) return;
    // refuse cycles
    var p = parentId;
    var guard = 0;
    while (p != null && guard++ < 64) {
      if (p == layerId) return;
      p = comp.layer(p)?.props.parentId;
    }
    updateProps(tr('Emparentar capa', 'Parent layer'), layerId, (props) => props.copyWith(parentId: parentId));
  }

  // ---- camera -------------------------------------------------------------

  void setCamera(Camera Function(Camera c) f, {String? mergeKey}) =>
      setTimeline(tr('Cámara', 'Camera'), (t) => t.copyWith(camera: f(t.camera)), mergeKey: mergeKey);

  void setCameraKey(Prop p, double v, {String? mergeKey}) {
    setCamera((c) {
      final existing = c.tracks[p]?.keyAt(frame);
      final t = (c.tracks[p] ?? AnimTrack.none).withKey(AnimKey(frame, v, existing?.ease ?? Ease.smooth));
      return c.copyWith(enabled: true, tracks: {...c.tracks, p: t});
    }, mergeKey: mergeKey ?? 'cam:${p.name}');
  }

  void removeCameraKey(Prop p, int f) {
    setCamera((c) {
      final t = c.tracks[p];
      if (t == null) return c;
      final tracks = {...c.tracks};
      final nt = t.withoutKey(f);
      if (nt.isEmpty) {
        tracks.remove(p);
      } else {
        tracks[p] = nt;
      }
      return c.copyWith(tracks: tracks);
    });
  }

  // ---- markers & scenes ---------------------------------------------------

  void toggleMarker({int? at, String label = ''}) {
    final f = at ?? frame;
    setTimeline(tr('Marcador', 'Marker'), (t) {
      final has = t.markers.any((m) => m.frame == f);
      final list = has ? t.markers.where((m) => m.frame != f).toList() : ([...t.markers, Marker(f, label)]..sort((a, b) => a.frame.compareTo(b.frame)));
      return t.copyWith(markers: list);
    });
  }

  void setMarker(int f, {String? label, int? color, int? moveTo}) {
    setTimeline(tr('Editar marcador', 'Edit marker'), (t) {
      final list = [
        for (final m in t.markers)
          if (m.frame == f) Marker(moveTo ?? m.frame, label ?? m.label, color ?? m.color) else m,
      ]..sort((a, b) => a.frame.compareTo(b.frame));
      return t.copyWith(markers: list);
    });
  }

  void addScene({String? name, int? start, int? length}) {
    setTimeline(tr('Nueva escena', 'New scene'), (t) {
      final s = start ?? (t.scenes.isEmpty ? 0 : t.scenes.last.end);
      final n = length ?? t.fps * 2;
      final scene = Scene(id: newId('sc'), name: name ?? '${tr('Escena', 'Scene')} ${t.scenes.length + 1}', start: s, length: n);
      return t.copyWith(scenes: [...t.scenes, scene]..sort((a, b) => a.start.compareTo(b.start)), length: math.max(t.length, s + n));
    });
  }

  void updateScene(String id, Scene Function(Scene s) f, {String? mergeKey}) {
    setTimeline(tr('Editar escena', 'Edit scene'), (t) {
      final list = [for (final s in t.scenes) s.id == id ? f(s) : s]..sort((a, b) => a.start.compareTo(b.start));
      return t.copyWith(scenes: list);
    }, mergeKey: mergeKey);
  }

  void removeScene(String id) =>
      setTimeline(tr('Eliminar escena', 'Delete scene'), (t) => t.copyWith(scenes: t.scenes.where((s) => s.id != id).toList()));

  Scene? sceneAt(int f) {
    for (final s in timeline.scenes) {
      if (f >= s.start && f < s.end) return s;
    }
    return null;
  }

  // ---- audio --------------------------------------------------------------

  void addAudioClip(String name, Uint8List bytes, double duration, {String kind = 'music', int? startFrame}) {
    final assetId = newId('au');
    final clip = AudioClip(id: newId('ac'), name: name, assetId: assetId, startFrame: startFrame ?? frame, duration: duration, kind: kind);
    final p = project.copyWith(assets: {...project.assets, assetId: bytes});
    final c = p.comp(compId);
    final end = clip.startFrame + (duration * c.timeline.fps).ceil();
    apply(
      tr('Añadir audio', 'Add audio'),
      p.withComp(c.copyWith(timeline: c.timeline.copyWith(audio: [...c.timeline.audio, clip], length: math.max(c.timeline.length, math.min(end, 100000))))),
    );
  }

  void updateAudioClip(String id, AudioClip Function(AudioClip c) f, {String? mergeKey}) {
    setTimeline(tr('Editar audio', 'Edit audio'), (t) => t.copyWith(audio: [for (final a in t.audio) a.id == id ? f(a) : a]), mergeKey: mergeKey);
  }

  void removeAudioClip(String id) {
    setTimeline(tr('Eliminar audio', 'Delete audio'), (t) => t.copyWith(audio: t.audio.where((a) => a.id != id).toList()));
  }
}
