import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/doc_frames.dart';
import '../../app/doc_timeline.dart';
import '../../app/document_controller.dart';
import '../../app/frame_thumbs.dart';
import '../../app/playback.dart';
import '../../core/i18n.dart';
import '../../engine/compositor.dart';
import '../dialogs/prompts.dart';
import '../theme.dart';

/// FlipaClip-like frame strip: one thumbnail per frame, a big «+» button,
/// playback controls, fps and onion-skin toggle.
class EasyTimeline extends StatefulWidget {
  const EasyTimeline({super.key, required this.doc, required this.playback, required this.thumbs, this.height = 116});
  final DocumentController doc;
  final Playback playback;
  final FrameThumbnailCache thumbs; // owned by the shell
  final double height;

  @override
  State<EasyTimeline> createState() => _EasyTimelineState();
}

class _EasyTimelineState extends State<EasyTimeline> {
  final ScrollController _scroll = ScrollController();
  final Set<int> _selected = {};
  int? _anchor;
  bool _multiMode = false;
  int? _dropTarget;

  DocumentController get doc => widget.doc;

  static const double _controlsHeight = 44;
  static const double _gap = 6;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  double get _thumbHeight => math.max(24.0, widget.height - _controlsHeight - 32);
  double get _cardWidth {
    final c = doc.comp;
    final aspect = c.height <= 0 ? 1.0 : c.width / c.height;
    return (_thumbHeight * aspect).clamp(40.0, 180.0) + 8;
  }

  /// The selected frames as one contiguous block (min..max), or the frame itself.
  (int, int) _block(int i) {
    if (_selected.length > 1 && _selected.contains(i)) {
      final lo = _selected.reduce(math.min), hi = _selected.reduce(math.max);
      return (lo, hi + 1);
    }
    return (i, i + 1);
  }

  void _clearSelection() {
    _selected.clear();
    _anchor = null;
    _multiMode = false;
  }

  void _tap(int i) {
    final hw = HardwareKeyboard.instance;
    setState(() {
      if (hw.isShiftPressed) {
        final a = _anchor ?? doc.frame;
        _selected
          ..clear()
          ..addAll([for (var k = math.min(a, i); k <= math.max(a, i); k++) k]);
        _anchor = a;
      } else if (hw.isControlPressed || hw.isMetaPressed || _multiMode) {
        if (!_selected.remove(i)) _selected.add(i);
        _anchor ??= i;
      } else {
        _clearSelection();
        _anchor = i;
      }
    });
    doc.frame = i;
  }

  void _scrollTo(int frame) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final w = _cardWidth + _gap;
      final left = frame * w, right = left + w;
      final pos = _scroll.position;
      if (left < pos.pixels) {
        _scroll.jumpTo(left.clamp(0.0, pos.maxScrollExtent));
      } else if (right > pos.pixels + pos.viewportDimension) {
        _scroll.jumpTo((right - pos.viewportDimension + w).clamp(0.0, pos.maxScrollExtent));
      }
    });
  }

  void _addFrame() {
    _clearSelection();
    doc.insertFrames();
    _scrollTo(doc.frame);
  }

  Future<void> _menu(int i, Offset globalPos) async {
    if (!_selected.contains(i)) {
      setState(_clearSelection);
      doc.frame = i;
    }
    final (lo, hi) = _block(i);
    final many = hi - lo > 1;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final pos = RelativeRect.fromRect(globalPos & const Size(1, 1), Offset.zero & overlay.size);
    final count = doc.frameCount;
    final choice = await showMenu<String>(
      context: context,
      position: pos,
      items: [
        PopupMenuItem(value: 'dup', child: Text(tr('Duplicar', 'Duplicate'))),
        PopupMenuItem(value: 'insert', child: Text(tr('Insertar en blanco después', 'Insert blank after'))),
        PopupMenuItem(value: 'copy', child: Text(many ? tr('Copiar fotogramas', 'Copy frames') : tr('Copiar', 'Copy'))),
        PopupMenuItem(value: 'paste', enabled: FrameColumnClipboard.frames.isNotEmpty, child: Text(tr('Pegar después', 'Paste after'))),
        PopupMenuItem(value: 'reverse', enabled: many, child: Text(tr('Invertir', 'Reverse'))),
        PopupMenuItem(value: 'multi', child: Text(_multiMode ? tr('Terminar selección', 'Finish selecting') : tr('Seleccionar varios', 'Select several'))),
        const PopupMenuDivider(),
        PopupMenuItem(
          key: const ValueKey('easy.menu.delete'),
          value: 'delete',
          enabled: count > 1 && hi - lo < count,
          child: Text(tr('Eliminar', 'Delete'), style: const TextStyle(color: Color(0xFFE53935))),
        ),
      ],
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'dup':
        if (many) {
          doc.copyFrames(lo, hi);
          doc.pasteFrames(after: hi - 1);
        } else {
          doc.duplicateFrame(i);
        }
      case 'insert':
        doc.insertFrames(after: hi - 1);
      case 'copy':
        doc.copyFrames(lo, hi);
      case 'paste':
        doc.pasteFrames(after: hi - 1);
      case 'reverse':
        doc.reverseFrameRange(lo, hi);
      case 'multi':
        setState(() {
          _multiMode = !_multiMode;
          if (_multiMode) _selected.add(i);
        });
        return;
      case 'delete':
        if (many) {
          final ok = await confirmDialog(
            context,
            title: tr('¿Eliminar fotogramas?', 'Delete frames?'),
            message: tr('Se eliminarán ${hi - lo} fotogramas.', '${hi - lo} frames will be deleted.'),
            ok: tr('Eliminar', 'Delete'),
            danger: true,
          );
          if (!ok) return;
        }
        doc.deleteFrames(lo, hi);
    }
    if (mounted) setState(_clearSelection);
  }

  void _drop(int from, int target) {
    final (lo, hi) = _block(from);
    if (target >= lo && target < hi) return;
    final to = target > lo ? target + 1 : target;
    doc.moveFrames(lo, hi, to);
    final moved = hi - lo;
    final newStart = to > hi ? to - moved : to;
    setState(_clearSelection);
    doc.frame = newStart.clamp(0, doc.frameCount - 1);
  }

  Future<void> _onionSettings() async {
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(builder: (context, setLocal) {
        final o = doc.onion;
        void set(OnionSkin Function(OnionSkin o) f) {
          doc.onion = f(doc.onion);
          doc.touch();
          doc.repaint();
          setLocal(() {});
        }

        Widget stepper(String label, int value, ValueChanged<int> onChanged) => Row(children: [
              Expanded(child: Text(label)),
              IconButton(onPressed: value > 0 ? () => onChanged(value - 1) : null, icon: const Icon(Icons.remove)),
              Text('$value'),
              IconButton(onPressed: value < 3 ? () => onChanged(value + 1) : null, icon: const Icon(Icons.add)),
            ]);
        return AlertDialog(
          title: Text(tr('Papel cebolla', 'Onion skin')),
          content: SizedBox(
            width: 280,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              stepper(tr('Anteriores', 'Before'), o.before, (v) => set((x) => x.copyWith(before: v))),
              stepper(tr('Siguientes', 'After'), o.after, (v) => set((x) => x.copyWith(after: v))),
              Row(children: [
                Text(tr('Opacidad', 'Opacity')),
                Expanded(
                  child: Slider(value: o.opacity.clamp(0.1, 0.9), min: 0.1, max: 0.9, onChanged: (v) => set((x) => x.copyWith(opacity: v))),
                ),
                SizedBox(width: 40, child: Text('${(o.opacity * 100).round()} %')),
              ]),
            ]),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Cerrar', 'Close')))],
        );
      }),
    );
  }

  Widget _controls(BuildContext context) {
    final pb = widget.playback;
    final count = doc.frameCount;
    Widget btn(IconData icon, String tip, VoidCallback? onTap, {Key? key, bool selected = false}) => SizedBox(
          width: 44,
          height: 44,
          child: IconButton(
            key: key,
            tooltip: tip,
            isSelected: selected,
            onPressed: onTap,
            icon: Icon(icon, size: 24, color: selected ? context.cs.primary : null),
          ),
        );
    return SizedBox(
      height: _controlsHeight,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          btn(Icons.first_page, tr('Primer fotograma', 'First frame'), () => doc.frame = 0),
          btn(Icons.chevron_left, tr('Fotograma anterior', 'Previous frame'), () => doc.stepFrame(-1)),
          btn(pb.playing ? Icons.pause : Icons.play_arrow, pb.playing ? tr('Pausar', 'Pause') : tr('Reproducir', 'Play'), pb.toggle,
              key: const ValueKey('easy.play'), selected: pb.playing),
          btn(Icons.chevron_right, tr('Fotograma siguiente', 'Next frame'), () => doc.stepFrame(1)),
          btn(Icons.last_page, tr('Último fotograma', 'Last frame'), () => doc.frame = count - 1),
          const SizedBox(width: 6),
          Text('${doc.frame + 1} / $count', style: const TextStyle(fontSize: 14, fontFeatures: [FontFeature.tabularFigures()])),
          const SizedBox(width: 12),
          PopupMenuButton<int>(
            key: const ValueKey('easy.fps'),
            tooltip: tr('Velocidad (fotogramas por segundo)', 'Speed (frames per second)'),
            onSelected: doc.setFps,
            itemBuilder: (_) => [for (final f in const [6, 8, 12, 15, 24, 30]) PopupMenuItem(value: f, child: Text('$f fps'))],
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              alignment: Alignment.center,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: context.line)),
              child: Text('${doc.timeline.fps} fps', style: const TextStyle(fontSize: 14)),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onLongPress: _onionSettings,
            onSecondaryTap: _onionSettings,
            child: btn(Icons.layers_outlined, tr('Papel cebolla (mantén pulsado para ajustar)', 'Onion skin (long-press to adjust)'), () {
              doc.onion = doc.onion.copyWith(enabled: !doc.onion.enabled);
              doc.touch();
              doc.repaint();
            }, key: const ValueKey('easy.onion'), selected: doc.onion.enabled),
          ),
          if (_multiMode)
            TextButton(onPressed: () => setState(_clearSelection), child: Text(tr('Listo', 'Done'))),
        ]),
      ),
    );
  }

  Widget _card(BuildContext context, int i) {
    final cs = context.cs;
    final current = i == doc.frame;
    final selected = _selected.contains(i);
    final drop = _dropTarget == i;
    final card = Container(
      width: _cardWidth,
      decoration: BoxDecoration(
        color: selected ? cs.primary.withValues(alpha: 0.18) : null,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(2),
      child: Column(children: [
        Expanded(
          child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: current ? cs.primary : (drop ? cs.secondary : context.line), width: current || drop ? 3 : 1),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: CustomPaint(painter: _ThumbPainter(widget.thumbs, doc, i), size: Size.infinite),
          ),
        ),
        ),
        const SizedBox(height: 2),
        Text('${i + 1}', style: TextStyle(fontSize: 13, height: 1.2, fontWeight: current ? FontWeight.w700 : FontWeight.w400, color: current ? cs.primary : context.dim)),
      ]),
    );
    final interactive = GestureDetector(
      key: ValueKey('easy.frame.$i'),
      behavior: HitTestBehavior.opaque,
      onTap: () => _tap(i),
      onSecondaryTapUp: (d) => _menu(i, d.globalPosition),
      child: card,
    );
    return DragTarget<int>(
      onWillAcceptWithDetails: (d) {
        if (d.data == i) return false;
        setState(() => _dropTarget = i);
        return true;
      },
      onLeave: (_) => setState(() => _dropTarget = null),
      onAcceptWithDetails: (d) {
        setState(() => _dropTarget = null);
        _drop(d.data, i);
      },
      builder: (context, _, _) => LongPressDraggable<int>(
        data: i,
        axis: Axis.horizontal,
        delay: const Duration(milliseconds: 300),
        feedback: Material(color: Colors.transparent, child: Opacity(opacity: 0.8, child: SizedBox(height: widget.height - _controlsHeight - 6, child: card))),
        childWhenDragging: Opacity(opacity: 0.35, child: card),
        onDragEnd: (d) {
          // a long press released in place opens the menu (touch screens)
          if (!d.wasAccepted && mounted) {
            final box = context.findRenderObject() as RenderBox?;
            if (box != null && (d.offset - box.localToGlobal(Offset.zero)).distance < 12) _menu(i, box.localToGlobal(box.size.center(Offset.zero)));
          }
        },
        child: interactive,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([doc, doc.frameSignal, widget.playback, widget.thumbs]),
      builder: (context, _) {
        widget.thumbs.paused = widget.playback.playing;
        final count = doc.frameCount;
        _selected.removeWhere((f) => f >= count);
        if (widget.playback.playing) _scrollTo(doc.frame);
        return SizedBox(
          height: widget.height,
          child: Column(children: [
            _controls(context),
            Expanded(
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.stylus, PointerDeviceKind.trackpad}),
                child: ListView.separated(
                  controller: _scroll,
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  itemCount: count + 1,
                  separatorBuilder: (_, _) => const SizedBox(width: _gap),
                  itemBuilder: (context, i) => i < count
                      ? _card(context, i)
                      : Center(
                          child: Tooltip(
                            message: tr('Añadir un fotograma', 'Add a frame'),
                            child: SizedBox(
                              width: 56,
                              height: 56,
                              child: FilledButton(
                                key: const ValueKey('easy.addFrame'),
                                style: FilledButton.styleFrom(padding: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                                onPressed: _addFrame,
                                child: const Icon(Icons.add, size: 32),
                              ),
                            ),
                          ),
                        ),
                ),
              ),
            ),
          ]),
        );
      },
    );
  }
}

class _ThumbPainter extends CustomPainter {
  _ThumbPainter(this.thumbs, this.doc, this.frame) : super(repaint: thumbs);
  final FrameThumbnailCache thumbs;
  final DocumentController doc;
  final int frame;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    canvas.drawRect(r, Paint()..color = const Color(0xFFE6E6EA));
    // ask inside paint: the cache may dispose images it gave out earlier
    final img = thumbs.thumbnailFor(doc, frame);
    if (img == null) return;
    final src = Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());
    final fitted = applyBoxFit(BoxFit.contain, src.size, size);
    final dst = Alignment.center.inscribe(fitted.destination, r);
    canvas.drawImageRect(img, src, dst, Paint()..filterQuality = FilterQuality.medium);
  }

  @override
  bool shouldRepaint(_ThumbPainter old) => old.frame != frame || old.doc != doc || old.thumbs != thumbs;
}
