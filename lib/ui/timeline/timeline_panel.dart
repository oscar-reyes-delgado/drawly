import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../app/doc_timeline.dart';
import '../../app/document_controller.dart';
import '../../app/playback.dart';
import '../../core/i18n.dart';
import '../../engine/audio/wav.dart';
import '../../model/document.dart';
import '../../model/layer.dart';
import '../theme.dart';
import '../widgets.dart';

/// Dope-sheet style timeline: frame ruler, one row per layer, playhead and transport bar.
class TimelinePanel extends StatelessWidget {
  const TimelinePanel({super.key, required this.doc, required this.playback, this.frameWidth = 14, this.rowHeight = 28});

  final DocumentController doc;
  final Playback playback;
  final double frameWidth, rowHeight;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([doc, doc.frameSignal, playback]),
      builder: (context, _) => _TimelineBody(doc: doc, playback: playback, frameWidth: frameWidth, rowHeight: rowHeight),
    );
  }
}

class _TimelineBody extends StatefulWidget {
  const _TimelineBody({required this.doc, required this.playback, required this.frameWidth, required this.rowHeight});

  final DocumentController doc;
  final Playback playback;
  final double frameWidth, rowHeight;

  @override
  State<_TimelineBody> createState() => _TimelineBodyState();
}

class _TimelineBodyState extends State<_TimelineBody> {
  static const double _layerColWidth = 168;
  static const double _rulerHeight = 26;
  static const double _transportHeight = 38;

  final ScrollController _rulerH = ScrollController();
  final ScrollController _gridH = ScrollController();
  final ScrollController _namesV = ScrollController();
  final ScrollController _gridV = ScrollController();
  final GlobalKey _tracksKey = GlobalKey();

  bool _syncingH = false;
  bool _syncingV = false;

  String? _dragLayerId;
  int? _dragFromFrame;
  int? _dragToFrame;
  double? _doubleTapDx;

  @override
  void initState() {
    super.initState();
    _rulerH.addListener(_onRulerHScroll);
    _gridH.addListener(_onGridHScroll);
    _namesV.addListener(_onNamesVScroll);
    _gridV.addListener(_onGridVScroll);
    widget.doc.frameSignal.addListener(_onFrameChanged);
  }

  @override
  void didUpdateWidget(covariant _TimelineBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.doc != widget.doc) {
      oldWidget.doc.frameSignal.removeListener(_onFrameChanged);
      widget.doc.frameSignal.addListener(_onFrameChanged);
    }
    if (widget.playback.playing) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _ensurePlayheadVisible());
    }
  }

  @override
  void dispose() {
    widget.doc.frameSignal.removeListener(_onFrameChanged);
    _rulerH.dispose();
    _gridH.dispose();
    _namesV.dispose();
    _gridV.dispose();
    super.dispose();
  }

  void _onRulerHScroll() {
    if (_syncingH || !_rulerH.hasClients || !_gridH.hasClients) return;
    _syncingH = true;
    final target = _rulerH.offset.clamp(0.0, _gridH.position.maxScrollExtent);
    if ((_gridH.offset - target).abs() > 0.5) _gridH.jumpTo(target);
    _syncingH = false;
  }

  void _onGridHScroll() {
    if (_syncingH || !_rulerH.hasClients || !_gridH.hasClients) return;
    _syncingH = true;
    final target = _gridH.offset.clamp(0.0, _rulerH.position.maxScrollExtent);
    if ((_rulerH.offset - target).abs() > 0.5) _rulerH.jumpTo(target);
    _syncingH = false;
  }

  void _onNamesVScroll() {
    if (_syncingV || !_namesV.hasClients || !_gridV.hasClients) return;
    _syncingV = true;
    final target = _namesV.offset.clamp(0.0, _gridV.position.maxScrollExtent);
    if ((_gridV.offset - target).abs() > 0.5) _gridV.jumpTo(target);
    _syncingV = false;
  }

  void _onGridVScroll() {
    if (_syncingV || !_namesV.hasClients || !_gridV.hasClients) return;
    _syncingV = true;
    final target = _gridV.offset.clamp(0.0, _namesV.position.maxScrollExtent);
    if ((_namesV.offset - target).abs() > 0.5) _namesV.jumpTo(target);
    _syncingV = false;
  }

  void _onFrameChanged() {
    if (widget.playback.playing) _ensurePlayheadVisible();
  }

  void _ensurePlayheadVisible() {
    if (!mounted || !_gridH.hasClients) return;
    final pos = _gridH.position;
    if (!pos.hasViewportDimension) return;
    final viewportW = pos.viewportDimension;
    final headLeft = widget.doc.frame * widget.frameWidth;
    final headRight = headLeft + widget.frameWidth;
    if (headLeft < pos.pixels) {
      _gridH.jumpTo(headLeft.clamp(0.0, pos.maxScrollExtent));
    } else if (headRight > pos.pixels + viewportW) {
      _gridH.jumpTo((headRight - viewportW).clamp(0.0, pos.maxScrollExtent));
    }
  }

  void _scrubTo(double localDx) {
    final len = math.max(1, widget.doc.timeline.length);
    final f = (localDx / widget.frameWidth).floor().clamp(0, len - 1);
    widget.doc.frame = f;
  }

  List<(Layer layer, int depth)> _flattenTopDown(List<Layer> layers, [int depth = 0]) {
    final out = <(Layer, int)>[];
    for (var i = layers.length - 1; i >= 0; i--) {
      final l = layers[i];
      out.add((l, depth));
      if (l is GroupLayer) out.addAll(_flattenTopDown(l.children, depth + 1));
    }
    return out;
  }

  int _frameFromGlobalX(double globalX) {
    final box = _tracksKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return 0;
    final local = box.globalToLocal(Offset(globalX, 0));
    return math.max(0, (local.dx / widget.frameWidth).floor());
  }

  IconData _layerIcon(Layer l) => switch (l) {
        PaintLayer() => Icons.brush_outlined,
        VectorLayer() => Icons.polyline_outlined,
        TextLayer() => Icons.title,
        GroupLayer() => Icons.folder_outlined,
        AdjustLayer() => Icons.tune,
        InstanceLayer() => Icons.layers_outlined,
        ParticleLayer() => Icons.auto_awesome_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final doc = widget.doc;
    final playback = widget.playback;
    final tl = doc.timeline;
    final rows = _flattenTopDown(doc.comp.layers);
    final audio = tl.audio;
    final totalFrames = math.max(1, tl.length);
    final framesWidth = totalFrames * widget.frameWidth;
    final cs = context.cs;

    return Material(
      color: context.panel,
      child: Column(
        children: [
          _buildTransportBar(context, doc, playback, tl),
          const Divider(height: 1),
          _buildHeaderRow(context, doc, tl, framesWidth),
          const Divider(height: 1),
          Expanded(
            child: rows.isEmpty && audio.isEmpty
                ? Center(child: Text(tr('Sin capas', 'No layers'), style: kSmall.copyWith(color: context.dim)))
                : Row(
                    children: [
                      SizedBox(
                        width: _layerColWidth,
                        child: ListView.builder(
                          controller: _namesV,
                          itemCount: rows.length + audio.length,
                          itemExtent: widget.rowHeight,
                          itemBuilder: (context, i) => i < rows.length ? _buildLayerNameCell(context, doc, rows[i].$1, rows[i].$2) : _buildAudioNameCell(context, doc, audio[i - rows.length]),
                        ),
                      ),
                      Container(width: 1, color: context.line),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final gridW = math.max(framesWidth, constraints.maxWidth);
                            final gridH = (rows.length + audio.length) * widget.rowHeight;
                            return Scrollbar(
                              controller: _gridH,
                              thumbVisibility: framesWidth > constraints.maxWidth,
                              child: SingleChildScrollView(
                                controller: _gridH,
                                scrollDirection: Axis.horizontal,
                                child: SizedBox(
                                  width: gridW,
                                  height: constraints.maxHeight,
                                  child: SingleChildScrollView(
                                    controller: _gridV,
                                    child: SizedBox(
                                      key: _tracksKey,
                                      width: gridW,
                                      height: gridH,
                                      child: Stack(
                                        children: [
                                          Column(
                                            children: [
                                              for (final row in rows) _buildTrackRow(context, doc, tl, row.$1, gridW, cs),
                                              for (final clip in audio) _buildAudioRow(context, doc, tl, clip, gridW, cs),
                                            ],
                                          ),
                                          Positioned.fill(
                                            child: IgnorePointer(
                                              child: CustomPaint(
                                                painter: _PlayheadOverlayPainter(
                                                  frame: doc.frame,
                                                  frameWidth: widget.frameWidth,
                                                  color: cs.primary,
                                                  dragFrame: _dragToFrame,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransportBar(BuildContext context, DocumentController doc, Playback playback, Timeline tl) {
    final lastFrame = math.max(0, tl.length - 1);
    return Container(
      height: _transportHeight,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            PanelButton(
              icon: Icons.first_page,
              tooltip: tr('Primer fotograma', 'First frame'),
              onTap: () => doc.frame = 0,
            ),
            PanelButton(
              icon: Icons.chevron_left,
              tooltip: tr('Fotograma anterior', 'Previous frame'),
              onTap: () => doc.stepFrame(-1),
            ),
            PanelButton(
              icon: playback.playing ? Icons.pause : Icons.play_arrow,
              tooltip: playback.playing ? tr('Pausar', 'Pause') : tr('Reproducir', 'Play'),
              selected: playback.playing,
              onTap: playback.toggle,
            ),
            PanelButton(
              icon: Icons.chevron_right,
              tooltip: tr('Fotograma siguiente', 'Next frame'),
              onTap: () => doc.stepFrame(1),
            ),
            PanelButton(
              icon: Icons.last_page,
              tooltip: tr('Último fotograma', 'Last frame'),
              onTap: () => doc.frame = lastFrame,
            ),
            const VSep(),
            MiniToggle(
              label: tr('Bucle', 'Loop'),
              icon: Icons.repeat,
              value: playback.loop,
              onChanged: playback.setLoop,
            ),
            const SizedBox(width: 4),
            MiniToggle(
              key: const ValueKey('timeline.onion'),
              label: tr('Cebolla', 'Onion'),
              icon: Icons.layers_outlined,
              value: doc.onion.enabled,
              onChanged: (v) {
                doc.onion = doc.onion.copyWith(enabled: v);
                doc.touch();
                doc.repaint();
              },
            ),
            const VSep(),
            Text('FPS', style: kTiny.copyWith(color: context.dim)),
            const SizedBox(width: 4),
            NumField(
              key: const ValueKey('timeline.fps'),
              value: tl.fps.toDouble(),
              min: 1,
              max: 240,
              decimals: 0,
              width: 48,
              onSubmitted: (v) => doc.setFps(v.round()),
            ),
            const SizedBox(width: 8),
            Text(tr('Duración', 'Length'), style: kTiny.copyWith(color: context.dim)),
            const SizedBox(width: 4),
            NumField(
              key: const ValueKey('timeline.length'),
              value: tl.length.toDouble(),
              min: 1,
              max: 100000,
              decimals: 0,
              width: 56,
              onSubmitted: (v) => doc.setLength(v.round()),
            ),
            const VSep(),
            Text(
              '${doc.frame} / ${tl.length}',
              style: kSmall.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderRow(BuildContext context, DocumentController doc, Timeline tl, double framesWidth) {
    final cs = context.cs;
    final hasCels = doc.activeHasCels;
    return SizedBox(
      height: _rulerHeight,
      child: Row(
        children: [
          Container(
            width: _layerColWidth,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            color: cs.surfaceContainerLow,
            child: Row(
              children: [
                Expanded(child: Text(tr('Capas', 'Layers'), style: kTiny.copyWith(color: context.dim), overflow: TextOverflow.ellipsis)),
                PanelButton(
                  icon: Icons.fiber_manual_record,
                  tooltip: tr('Nuevo fotograma clave', 'New keyframe'),
                  size: 22,
                  iconSize: 13,
                  onTap: hasCels ? () => doc.addKeyFrame() : null,
                ),
                PanelButton(
                  icon: Icons.crop_square,
                  tooltip: tr('Fotograma en blanco', 'Blank keyframe'),
                  size: 22,
                  iconSize: 13,
                  onTap: hasCels ? () => doc.addBlankKey() : null,
                ),
                PanelButton(
                  icon: Icons.backspace_outlined,
                  tooltip: tr('Eliminar fotograma clave', 'Delete keyframe'),
                  size: 22,
                  iconSize: 13,
                  onTap: hasCels ? () => doc.deleteKey() : null,
                ),
              ],
            ),
          ),
          Container(width: 1, color: context.line),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final rulerW = math.max(framesWidth, constraints.maxWidth);
                return SingleChildScrollView(
                  controller: _rulerH,
                  scrollDirection: Axis.horizontal,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (d) => _scrubTo(d.localPosition.dx),
                    onHorizontalDragStart: (d) => _scrubTo(d.localPosition.dx),
                    onHorizontalDragUpdate: (d) => _scrubTo(d.localPosition.dx),
                    child: SizedBox(
                      key: const ValueKey('timeline.ruler'),
                      width: rulerW,
                      height: _rulerHeight,
                      child: CustomPaint(
                        painter: _RulerPainter(
                          length: tl.length,
                          frame: doc.frame,
                          rangeStart: tl.rangeStart,
                          rangeEnd: tl.rangeEnd,
                          markers: tl.markers,
                          frameWidth: widget.frameWidth,
                          cs: cs,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLayerNameCell(BuildContext context, DocumentController doc, Layer layer, int depth) {
    final cs = context.cs;
    final active = doc.activeLayerId == layer.id;
    final selected = doc.selectedLayers.contains(layer.id);
    return InkWell(
      canRequestFocus: false,
      onTap: () => doc.selectLayer(layer.id),
      child: Container(
        height: widget.rowHeight,
        decoration: BoxDecoration(
          color: active
              ? cs.primary.withValues(alpha: 0.16)
              : (selected ? cs.primary.withValues(alpha: 0.08) : Colors.transparent),
          border: Border(
            left: BorderSide(color: active ? cs.primary : Colors.transparent, width: 2),
            bottom: BorderSide(color: context.line.withValues(alpha: 0.5), width: 1),
          ),
        ),
        padding: EdgeInsets.only(left: 6 + depth * 12.0, right: 6),
        child: Row(
          children: [
            Icon(_layerIcon(layer), size: 14, color: active ? cs.primary : context.dim),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                layer.name,
                style: kSmall.copyWith(color: layer.visible ? cs.onSurface : context.dim),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            if (layer.props.colorTag != 0)
              Container(
                width: 7,
                height: 7,
                margin: const EdgeInsets.only(left: 4),
                decoration: BoxDecoration(color: Color(layer.props.colorTag), shape: BoxShape.circle),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrackRow(BuildContext context, DocumentController doc, Timeline tl, Layer layer, double gridW, ColorScheme cs) {
    final cels = doc.celsOf(layer);
    final active = doc.activeLayerId == layer.id;
    return SizedBox(
      key: ValueKey('timeline.row.${layer.id}'),
      width: gridW,
      height: widget.rowHeight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) {
          final n = (d.localPosition.dx / widget.frameWidth).floor();
          if (n >= 0 && n < tl.length) {
            doc.selectLayer(layer.id);
            doc.frame = n;
          }
        },
        onDoubleTapDown: (d) => _doubleTapDx = d.localPosition.dx,
        onDoubleTap: cels == null
            ? null
            : () {
                final dx = _doubleTapDx;
                if (dx == null) return;
                final n = (dx / widget.frameWidth).floor();
                if (n >= 0 && n < tl.length && !cels.hasKeyAt(n)) {
                  doc.selectLayer(layer.id);
                  doc.frame = n;
                  doc.addKeyFrame(layerId: layer.id, at: n);
                }
              },
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _TrackBgPainter(
                  length: tl.length,
                  frameWidth: widget.frameWidth,
                  isActive: active,
                  cs: cs,
                ),
              ),
            ),
            if (cels != null) ..._buildExposureBlocks(context, doc, tl, layer, cels, cs),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildExposureBlocks(BuildContext context, DocumentController doc, Timeline tl, Layer layer, CelTrack<Object> cels, ColorScheme cs) {
    final blocks = <Widget>[];
    final xs = cels.xs;
    for (var i = 0; i < xs.length; i++) {
      final e = xs[i];
      final start = e.frame;
      if (start < 0 || start >= tl.length) continue;
      final next = i + 1 < xs.length ? xs[i + 1].frame : tl.length;
      final end = math.min(next, tl.length);
      final span = end - start;
      if (span <= 0) continue;

      final isBlank = e.drawing == 0;
      final isActive = doc.activeLayerId == layer.id;
      final isDraggingThis = _dragLayerId == layer.id && _dragFromFrame == e.frame;
      final blockW = span * widget.frameWidth;

      final Color fill = isBlank
          ? cs.onSurface.withValues(alpha: 0.14)
          : (isActive ? cs.primary.withValues(alpha: 0.28) : cs.primary.withValues(alpha: 0.16));
      final Color borderColor = isBlank ? cs.onSurface.withValues(alpha: 0.35) : cs.primary.withValues(alpha: 0.65);

      blocks.add(
        Positioned(
          key: ValueKey('cel:${layer.id}:${e.frame}'),
          left: start * widget.frameWidth,
          top: 2,
          width: blockW,
          height: widget.rowHeight - 4,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 0.5),
            decoration: BoxDecoration(
              color: isDraggingThis ? fill.withValues(alpha: 0.5) : fill,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: borderColor, width: 1),
            ),
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                if (!isBlank)
                  Positioned(
                    left: 2,
                    top: 1,
                    child: Text(
                      '${e.drawing}',
                      style: TextStyle(fontSize: 9, height: 1.0, fontWeight: FontWeight.w600, color: cs.onSurface),
                    ),
                  ),
                Positioned(
                  left: 0,
                  bottom: 3,
                  width: math.max(1.0, widget.frameWidth - 2),
                  child: Center(
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isBlank ? Colors.transparent : cs.primary,
                        border: isBlank ? Border.all(color: cs.onSurface.withValues(alpha: 0.7), width: 1.3) : null,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      blocks.add(
        Positioned(
          key: ValueKey('celKey:${layer.id}:${e.frame}'),
          left: start * widget.frameWidth,
          top: 0,
          width: widget.frameWidth,
          height: widget.rowHeight,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragStart: (d) {
              setState(() {
                _dragLayerId = layer.id;
                _dragFromFrame = e.frame;
                _dragToFrame = _frameFromGlobalX(d.globalPosition.dx);
              });
            },
            onHorizontalDragUpdate: (d) {
              final nextFrame = _frameFromGlobalX(d.globalPosition.dx);
              if (nextFrame != _dragToFrame) {
                setState(() => _dragToFrame = nextFrame);
              }
            },
            onHorizontalDragEnd: (_) {
              final lid = _dragLayerId;
              final from = _dragFromFrame;
              final to = _dragToFrame;
              setState(() {
                _dragLayerId = null;
                _dragFromFrame = null;
                _dragToFrame = null;
              });
              if (lid != null && from != null && to != null && to != from) {
                doc.moveKey(lid, from, to);
              }
            },
            onHorizontalDragCancel: () {
              setState(() {
                _dragLayerId = null;
                _dragFromFrame = null;
                _dragToFrame = null;
              });
            },
          ),
        ),
      );
    }
    return blocks;
  }

  // ---- audio ----------------------------------------------------------------

  /// Waveform peaks per clip asset (decoded once; buckets = 2 per frame at the fps used).
  final Map<String, Float32List?> _peaks = {};

  Float32List? _peaksFor(DocumentController doc, AudioClip clip, int fps) {
    final key = '${clip.assetId}@$fps';
    if (_peaks.containsKey(key)) return _peaks[key];
    Float32List? out;
    final bytes = doc.project.assets[clip.assetId];
    if (bytes != null && isWav(bytes)) {
      try {
        final buf = decodeWav(bytes);
        final buckets = math.max(2, (buf.duration * fps * 2).round());
        out = waveformPeaks(buf, buckets);
      } on FormatException {
        out = null;
      }
    }
    return _peaks[key] = out;
  }

  Widget _buildAudioNameCell(BuildContext context, DocumentController doc, AudioClip clip) {
    final cs = context.cs;
    return Container(
      key: ValueKey('timeline.audioName.${clip.id}'),
      height: widget.rowHeight,
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: context.line.withValues(alpha: 0.5), width: 1))),
      padding: const EdgeInsets.only(left: 6, right: 2),
      child: Row(children: [
        Icon(Icons.music_note, size: 14, color: context.dim),
        const SizedBox(width: 6),
        Expanded(child: Text(clip.name, style: kSmall.copyWith(color: clip.muted ? context.dim : cs.onSurface), overflow: TextOverflow.ellipsis, maxLines: 1)),
        PanelButton(
          key: ValueKey('timeline.audioMute.${clip.id}'),
          icon: clip.muted ? Icons.volume_off : Icons.volume_up,
          size: 22,
          iconSize: 13,
          tooltip: clip.muted ? tr('Activar sonido', 'Unmute') : tr('Silenciar', 'Mute'),
          onTap: () => doc.updateAudioClip(clip.id, (c) => c.copyWith(muted: !c.muted)),
        ),
        PanelButton(
          icon: Icons.close,
          size: 22,
          iconSize: 13,
          tooltip: tr('Quitar audio', 'Remove audio'),
          onTap: () => doc.removeAudioClip(clip.id),
        ),
      ]),
    );
  }

  Widget _buildAudioRow(BuildContext context, DocumentController doc, Timeline tl, AudioClip clip, double gridW, ColorScheme cs) {
    final fps = math.max(1, tl.fps);
    final frames = math.max(1, ((clip.duration - clip.trimStart - clip.trimEnd) * fps).ceil());
    final left = clip.startFrame * widget.frameWidth;
    final width = frames * widget.frameWidth;
    final peaks = _peaksFor(doc, clip, fps);
    final color = clip.muted ? context.dim : cs.tertiary;
    return SizedBox(
      key: ValueKey('timeline.audioRow.${clip.id}'),
      width: gridW,
      height: widget.rowHeight,
      child: Stack(children: [
        Positioned(
          left: left,
          top: 3,
          width: width,
          height: widget.rowHeight - 6,
          child: GestureDetector(
            key: ValueKey('timeline.audioClip.${clip.id}'),
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (_) => _audioDrag = 0,
            onHorizontalDragUpdate: (d) {
              _audioDrag += d.delta.dx;
              final delta = (_audioDrag / widget.frameWidth).round();
              if (delta == 0) return;
              _audioDrag -= delta * widget.frameWidth;
              doc.updateAudioClip(clip.id, (c) => c.copyWith(startFrame: math.max(0, c.startFrame + delta)), mergeKey: 'audioMove:${clip.id}');
            },
            child: Container(
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.18),
                border: Border.all(color: color.withValues(alpha: 0.7)),
                borderRadius: BorderRadius.circular(4),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: CustomPaint(painter: _WaveformPainter(peaks: peaks, color: color, trimStart: clip.trimStart, duration: clip.duration)),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  double _audioDrag = 0;
}

/// Min/max waveform of one audio clip, filling its box.
class _WaveformPainter extends CustomPainter {
  _WaveformPainter({required this.peaks, required this.color, required this.trimStart, required this.duration});
  final Float32List? peaks;
  final Color color;
  final double trimStart, duration;

  @override
  void paint(Canvas canvas, Size size) {
    final p = peaks;
    if (p == null || p.length < 2 || duration <= 0) return;
    final buckets = p.length ~/ 2;
    final first = (trimStart / duration * buckets).floor().clamp(0, buckets - 1);
    final mid = size.height / 2;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    final shown = buckets - first;
    for (var x = 0.0; x < size.width; x += 1) {
      final b = first + (x / size.width * shown).floor();
      if (b >= buckets) break;
      final lo = p[b * 2], hi = p[b * 2 + 1];
      canvas.drawLine(Offset(x, mid - hi * mid), Offset(x, mid - lo * mid), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter old) => old.peaks != peaks || old.color != color || old.trimStart != trimStart;
}

class _RulerPainter extends CustomPainter {
  const _RulerPainter({
    required this.length,
    required this.frame,
    required this.rangeStart,
    required this.rangeEnd,
    required this.markers,
    required this.frameWidth,
    required this.cs,
  });

  final int length, frame, rangeStart, rangeEnd;
  final List<Marker> markers;
  final double frameWidth;
  final ColorScheme cs;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = cs.surfaceContainerLow);

    // Playback range highlight
    final rx0 = rangeStart * frameWidth;
    final rx1 = rangeEnd * frameWidth;
    if (rx1 > rx0) {
      canvas.drawRect(
        Rect.fromLTWH(rx0, 0, rx1 - rx0, size.height),
        Paint()..color = cs.primary.withValues(alpha: 0.10),
      );
      canvas.drawRect(
        Rect.fromLTWH(rx0, 0, rx1 - rx0, 2),
        Paint()..color = cs.primary.withValues(alpha: 0.5),
      );
    }

    // Current frame highlight
    final px = frame * frameWidth;
    canvas.drawRect(
      Rect.fromLTWH(px, 0, frameWidth, size.height),
      Paint()..color = cs.primary.withValues(alpha: 0.22),
    );

    final tickPaint = Paint()
      ..color = cs.onSurfaceVariant.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    final majorTickPaint = Paint()
      ..color = cs.onSurfaceVariant.withValues(alpha: 0.85)
      ..strokeWidth = 1;

    final step = frameWidth < 10 ? 10 : 5;
    for (var i = 0; i < length; i++) {
      final x = i * frameWidth;
      final major = i % step == 0;
      canvas.drawLine(
        Offset(x, size.height - (major ? 10 : 5)),
        Offset(x, size.height),
        major ? majorTickPaint : tickPaint,
      );
      if (major) {
        final tp = TextPainter(
          text: TextSpan(text: '$i', style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x + 2, 3));
      }
    }

    // Markers
    for (final m in markers) {
      final mx = m.frame * frameWidth + frameWidth / 2;
      final path = Path()
        ..moveTo(mx - 4, 2)
        ..lineTo(mx + 4, 2)
        ..lineTo(mx, 9)
        ..close();
      canvas.drawPath(path, Paint()..color = Color(m.color));
    }

    // Playhead cap
    final headX = px + frameWidth / 2;
    final head = Path()
      ..moveTo(headX - 5, 0)
      ..lineTo(headX + 5, 0)
      ..lineTo(headX + 5, 7)
      ..lineTo(headX, 12)
      ..lineTo(headX - 5, 7)
      ..close();
    canvas.drawPath(head, Paint()..color = cs.primary);

    canvas.drawLine(
      Offset(0, size.height - 0.5),
      Offset(size.width, size.height - 0.5),
      Paint()
        ..color = cs.outlineVariant
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _RulerPainter old) =>
      old.length != length ||
      old.frame != frame ||
      old.rangeStart != rangeStart ||
      old.rangeEnd != rangeEnd ||
      old.markers != markers ||
      old.frameWidth != frameWidth ||
      old.cs != cs;
}

class _TrackBgPainter extends CustomPainter {
  const _TrackBgPainter({required this.length, required this.frameWidth, required this.isActive, required this.cs});

  final int length;
  final double frameWidth;
  final bool isActive;
  final ColorScheme cs;

  @override
  void paint(Canvas canvas, Size size) {
    if (isActive) {
      canvas.drawRect(Offset.zero & size, Paint()..color = cs.primary.withValues(alpha: 0.06));
    }
    final minor = Paint()
      ..color = cs.outlineVariant.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    final major = Paint()
      ..color = cs.outlineVariant.withValues(alpha: 0.7)
      ..strokeWidth = 1;

    for (var i = 0; i <= length; i++) {
      final x = i * frameWidth;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), i % 5 == 0 ? major : minor);
    }

    canvas.drawLine(
      Offset(0, size.height - 0.5),
      Offset(size.width, size.height - 0.5),
      Paint()
        ..color = cs.outlineVariant.withValues(alpha: 0.5)
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _TrackBgPainter old) =>
      old.length != length || old.frameWidth != frameWidth || old.isActive != isActive || old.cs != cs;
}

class _PlayheadOverlayPainter extends CustomPainter {
  const _PlayheadOverlayPainter({required this.frame, required this.frameWidth, required this.color, this.dragFrame});

  final int frame;
  final int? dragFrame;
  final double frameWidth;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final x = frame * frameWidth;
    canvas.drawRect(Rect.fromLTWH(x, 0, frameWidth, size.height), Paint()..color = color.withValues(alpha: 0.08));
    final cx = x + frameWidth / 2;
    canvas.drawLine(
      Offset(cx, 0),
      Offset(cx, size.height),
      Paint()
        ..color = color
        ..strokeWidth = 1.5,
    );
    if (dragFrame != null) {
      final dx = dragFrame! * frameWidth;
      canvas.drawRect(
        Rect.fromLTWH(dx, 0, frameWidth, size.height),
        Paint()
          ..color = color.withValues(alpha: 0.45)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PlayheadOverlayPainter old) =>
      old.frame != frame || old.frameWidth != frameWidth || old.color != color || old.dragFrame != dragFrame;
}
