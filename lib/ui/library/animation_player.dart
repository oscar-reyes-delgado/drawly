import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../app/app_state.dart';
import '../../core/i18n.dart';
import '../../engine/compositor.dart';
import '../../io/project_codec.dart';
import '../../model/document.dart';
import '../../platform/io.dart';

/// Opens the full-screen player for [project] (its main composition).
Future<void> showAnimationPlayer(BuildContext context, Project project, {String title = '', int startFrame = 0}) =>
    Navigator.of(context).push(PageRouteBuilder<void>(
      opaque: true,
      pageBuilder: (_, _, _) => AnimationPlayerPage(project: project, title: title, startFrame: startFrame),
      transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
    ));

/// Reads a `.drawly` file and plays it. Returns an error message, or null.
Future<String?> playProjectFile(BuildContext context, String path, {String? title}) async {
  try {
    final bytes = await readFileBytes(path);
    if (bytes == null) return tr('No se pudo leer el archivo', 'Could not read the file');
    final project = await ProjectCodec.decode(bytes);
    if (!context.mounted) return null;
    await showAnimationPlayer(context, project, title: title ?? project.main.name);
    return null;
  } on FormatException {
    return tr('El archivo está dañado', 'The file is damaged');
  } catch (e) {
    return '$e';
  }
}

/// Plays an animation full screen, without the editor: play / pause, frame
/// slider, loop and sound. Rendered frames are cached so loops stay smooth.
class AnimationPlayerPage extends StatefulWidget {
  const AnimationPlayerPage({super.key, required this.project, this.title = '', this.startFrame = 0, this.autoPlay = true});
  final Project project;
  final String title;
  final int startFrame;
  final bool autoPlay;

  @override
  State<AnimationPlayerPage> createState() => _AnimationPlayerPageState();
}

class _AnimationPlayerPageState extends State<AnimationPlayerPage> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  late final _FrameCache _cache = _FrameCache(widget.project);
  Duration _last = Duration.zero;
  double _acc = 0;
  late int _frame;
  bool _playing = false;
  bool _loop = true;
  bool _controls = true;

  Comp get _comp => widget.project.main;
  Timeline get _t => _comp.timeline;
  int get _start => _t.rangeStart;
  int get _end => math.max(_t.rangeStart + 1, _t.rangeEnd);

  @override
  void initState() {
    super.initState();
    _frame = widget.startFrame.clamp(_start, _end - 1);
    if (widget.autoPlay && _end - _start > 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _play();
      });
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    AppState.I.audio?.stop();
    _cache.dispose();
    super.dispose();
  }

  void _play() {
    if (_playing) return;
    if (_frame >= _end - 1) _frame = _start;
    setState(() => _playing = true);
    _last = Duration.zero;
    _acc = 0;
    _ticker.start();
    AppState.I.audio?.start(widget.project, _t, _frame.toDouble());
  }

  void _pause() {
    if (!_playing) return;
    _ticker.stop();
    AppState.I.audio?.stop();
    setState(() => _playing = false);
  }

  void _toggle() => _playing ? _pause() : _play();

  void _seek(int f) {
    final wasPlaying = _playing;
    if (wasPlaying) _pause();
    setState(() => _frame = f.clamp(_start, _end - 1));
    if (wasPlaying) _play();
  }

  void _tick(Duration elapsed) {
    final dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    _acc += dt * _t.fps;
    final steps = _acc.floor();
    if (steps <= 0) return;
    _acc -= steps;
    var f = _frame + steps;
    if (f >= _end) {
      if (!_loop) {
        _ticker.stop();
        AppState.I.audio?.stop();
        setState(() {
          _frame = _end - 1;
          _playing = false;
        });
        return;
      }
      f = _start + (f - _start) % (_end - _start);
      AppState.I.audio?.start(widget.project, _t, f.toDouble());
    }
    setState(() => _frame = f);
  }

  KeyEventResult _key(FocusNode node, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.space || k == LogicalKeyboardKey.enter) {
      _toggle();
    } else if (k == LogicalKeyboardKey.escape) {
      Navigator.of(context).maybePop();
    } else if (k == LogicalKeyboardKey.arrowRight) {
      _seek(_frame + 1);
    } else if (k == LogicalKeyboardKey.arrowLeft) {
      _seek(_frame - 1);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final total = _end - _start;
    const fg = Colors.white;
    return Focus(
      autofocus: true,
      onKeyEvent: _key,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(children: [
            Positioned.fill(
              child: GestureDetector(
                key: const ValueKey('player.stage'),
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _controls = !_controls),
                onDoubleTap: _toggle,
                child: LayoutBuilder(
                  builder: (context, box) => CustomPaint(
                    size: box.biggest,
                    painter: _StagePainter(_cache, _comp, _frame, MediaQuery.devicePixelRatioOf(context)),
                  ),
                ),
              ),
            ),
            if (_controls) ...[
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  color: Colors.black54,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(children: [
                    IconButton(
                      key: const ValueKey('player.close'),
                      tooltip: tr('Cerrar', 'Close'),
                      icon: const Icon(Icons.close, color: fg),
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                    Expanded(
                      child: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: fg, fontSize: 16, fontWeight: FontWeight.w600)),
                    ),
                    Text('${_t.fps} fps', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                    const SizedBox(width: 12),
                  ]),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  color: Colors.black54,
                  padding: const EdgeInsets.fromLTRB(4, 0, 12, 4),
                  child: Row(children: [
                    IconButton(
                      key: const ValueKey('player.play'),
                      iconSize: 36,
                      tooltip: _playing ? tr('Pausar', 'Pause') : tr('Reproducir', 'Play'),
                      icon: Icon(_playing ? Icons.pause_circle_filled : Icons.play_circle_filled, color: fg),
                      onPressed: _toggle,
                    ),
                    Expanded(
                      child: total > 1
                          ? Slider(
                              key: const ValueKey('player.slider'),
                              value: (_frame - _start).toDouble(),
                              min: 0,
                              max: (total - 1).toDouble(),
                              divisions: total - 1,
                              onChanged: (v) => _seek(_start + v.round()),
                            )
                          : const SizedBox.shrink(),
                    ),
                    Text('${_frame - _start + 1} / $total', style: const TextStyle(color: fg, fontSize: 14, fontFeatures: [ui.FontFeature.tabularFigures()])),
                    IconButton(
                      key: const ValueKey('player.loop'),
                      tooltip: tr('Repetir', 'Loop'),
                      isSelected: _loop,
                      icon: Icon(Icons.repeat, color: _loop ? Theme.of(context).colorScheme.primary : Colors.white54),
                      onPressed: () => setState(() => _loop = !_loop),
                    ),
                  ]),
                ),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

/// Rendered frames of one project at one scale, kept within a memory budget.
class _FrameCache {
  _FrameCache(this.project);
  final Project project;
  final LinkedHashMap<int, ui.Image> _images = LinkedHashMap();
  double _scale = 0;
  int _bytes = 0;
  static const int budget = 160 * 1024 * 1024;

  ui.Image imageFor(Comp comp, int frame, double scale) {
    if ((scale - _scale).abs() > 1e-6) {
      clear();
      _scale = scale;
    }
    final hit = _images.remove(frame);
    if (hit != null) {
      _images[frame] = hit;
      return hit;
    }
    final img = renderCompImage(project, comp, frame.toDouble(), scale: scale, background: true, forExport: true, useCamera: true);
    _images[frame] = img;
    _bytes += img.width * img.height * 4;
    while (_bytes > budget && _images.length > 1) {
      final oldest = _images.keys.first;
      final o = _images.remove(oldest)!;
      _bytes -= o.width * o.height * 4;
      o.dispose();
    }
    return img;
  }

  void clear() {
    for (final i in _images.values) {
      i.dispose();
    }
    _images.clear();
    _bytes = 0;
  }

  void dispose() => clear();
}

class _StagePainter extends CustomPainter {
  _StagePainter(this.cache, this.comp, this.frame, this.dpr);
  final _FrameCache cache;
  final Comp comp;
  final int frame;
  final double dpr;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || comp.width <= 0 || comp.height <= 0) return;
    final fit = math.min(size.width / comp.width, size.height / comp.height);
    // render at screen resolution, never above the document's own size
    final scale = math.min(1.0, fit * dpr);
    final img = cache.imageFor(comp, frame, scale);
    final w = comp.width * fit, h = comp.height * fit;
    final dst = Rect.fromLTWH((size.width - w) / 2, (size.height - h) / 2, w, h);
    canvas.drawImageRect(img, Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()), dst, Paint()..filterQuality = FilterQuality.medium);
  }

  @override
  bool shouldRepaint(_StagePainter old) => old.frame != frame || old.comp != comp || old.dpr != dpr;
}
