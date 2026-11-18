import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../engine/compositor.dart';
import '../model/document.dart';
import 'app_state.dart';

/// Pre-rendered frames for smooth playback. Keyed by frame number and
/// valid only for one (project, comp, scale) combination.
class FrameCache {
  Project? _project;
  String? _compId;
  double _scale = 1;
  bool _camera = true;
  final Map<int, ui.Image> _frames = {};
  int _bytes = 0;

  /// Memory budget in bytes.
  int budget = 512 * 1024 * 1024;

  int get length => _frames.length;
  Iterable<int> get cachedFrames => _frames.keys;

  void clear() {
    for (final img in _frames.values) {
      img.dispose();
    }
    _frames.clear();
    _bytes = 0;
  }

  void _validate(Project p, Comp c, double scale, bool camera) {
    if (!identical(p, _project) || c.id != _compId || scale != _scale || camera != _camera) {
      clear();
      _project = p;
      _compId = c.id;
      _scale = scale;
      _camera = camera;
    }
  }

  bool has(Project p, Comp c, int frame, double scale, {bool camera = true}) {
    _validate(p, c, scale, camera);
    return _frames.containsKey(frame);
  }

  /// Returns the cached frame, rendering it first when needed.
  ui.Image frame(Project p, Comp c, int frame, double scale, {bool camera = true}) {
    _validate(p, c, scale, camera);
    final hit = _frames[frame];
    if (hit != null) return hit;
    final img = renderCompImage(p, c, frame.toDouble(), scale: scale, background: true, forExport: true, useCamera: camera, quality: ui.FilterQuality.low);
    final size = img.width * img.height * 4;
    while (_bytes + size > budget && _frames.isNotEmpty) {
      final k = _frames.keys.first;
      final old = _frames.remove(k)!;
      _bytes -= old.width * old.height * 4;
      old.dispose();
    }
    _frames[frame] = img;
    _bytes += size;
    return img;
  }
}

/// Timeline playback: fps, speed, loop / ping-pong / range.
class Playback extends ChangeNotifier {
  Playback(this.app);

  final AppState app;
  final FrameCache cache = FrameCache();

  bool _playing = false;
  bool loop = true;
  bool pingPong = false;
  double speed = 1.0;

  /// Called when playback starts / stops / jumps so audio can follow.
  void Function(int frame)? onStart;
  VoidCallback? onStop;

  int _dir = 1;
  Ticker? _ticker;
  Duration _prev = Duration.zero;
  double _acc = 0;

  /// Frames actually shown per second during the last second of playback.
  double measuredFps = 0;
  int _shown = 0;
  Duration _fpsMark = Duration.zero;

  bool get playing => _playing;

  void setLoop(bool v) {
    loop = v;
    notifyListeners();
  }

  void setPingPong(bool v) {
    pingPong = v;
    notifyListeners();
  }

  void setSpeed(double v) {
    speed = v.clamp(0.1, 8.0);
    notifyListeners();
  }

  void toggle() => _playing ? stop() : play();

  void play() {
    final d = app.doc;
    if (d == null || _playing) return;
    app.tool.onCancel();
    cache.budget = app.settings.frameCacheMb * 1024 * 1024;
    final t = d.timeline;
    if (d.frame < t.rangeStart || d.frame >= t.rangeEnd - 1) d.frame = t.rangeStart;
    _playing = true;
    _dir = 1;
    _acc = 0;
    _prev = Duration.zero;
    _fpsMark = Duration.zero;
    _shown = 0;
    _ticker ??= Ticker(_tick);
    _ticker!.start();
    onStart?.call(d.frame);
    notifyListeners();
    d.repaint();
  }

  void stop() {
    if (!_playing) return;
    _playing = false;
    _ticker?.stop();
    onStop?.call();
    notifyListeners();
    app.doc?.repaint();
  }

  void _tick(Duration elapsed) {
    final d = app.doc;
    if (d == null) {
      stop();
      return;
    }
    final dt = (elapsed - _prev).inMicroseconds / 1e6;
    _prev = elapsed;
    final t = d.timeline;
    _acc += dt * t.fps * speed;
    final steps = _acc.floor();
    if (steps <= 0) return;
    _acc -= steps;
    final start = t.rangeStart, end = t.rangeEnd;
    final span = end - start;
    var f = d.frame;
    if (span <= 1) {
      f = start;
    } else if (pingPong) {
      for (var i = 0; i < steps; i++) {
        final n = f + _dir;
        if (n >= end || n < start) {
          _dir = -_dir;
          if (!loop && _dir == 1) {
            stop();
            return;
          }
          f += _dir;
        } else {
          f = n;
        }
      }
    } else {
      final n = f + steps;
      if (n >= end) {
        if (loop) {
          f = start + (n - start) % span;
          onStart?.call(f);
        } else {
          d.frame = end - 1;
          stop();
          return;
        }
      } else {
        f = n;
      }
    }
    d.frame = f.clamp(start, end - 1);
    _shown++;
    if ((elapsed - _fpsMark).inMilliseconds >= 1000) {
      measuredFps = _shown * 1000 / (elapsed - _fpsMark).inMilliseconds;
      _shown = 0;
      _fpsMark = elapsed;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    cache.clear();
    super.dispose();
  }
}
