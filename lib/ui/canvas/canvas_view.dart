import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_state.dart';
import '../../app/document_controller.dart';
import '../../app/view_state.dart';
import '../../engine/compositor.dart';
import '../../tools/tool.dart';
import '../theme.dart';

/// The drawing surface of one document: renders the composition, feeds
/// pointer input to the active tool and paints the tool overlays.
class CanvasView extends StatefulWidget {
  const CanvasView({super.key, required this.doc});
  final DocumentController doc;

  @override
  State<CanvasView> createState() => _CanvasViewState();
}

class _CanvasViewState extends State<CanvasView> {
  AppState get app => AppState.I;
  DocumentController get doc => widget.doc;

  int? _toolPointer;
  int? _panPointer;
  Offset _panLast = Offset.zero;
  Offset _hover = Offset.zero;
  bool _hasHover = false;

  // two-finger touch navigation
  final Map<int, Offset> _touches = {};
  double _pinchDist = 0, _pinchAngle = 0;
  Offset _pinchCenter = Offset.zero;
  bool _navigating = false;
  DateTime _touchStart = DateTime.now();

  late final Listenable _repaint = Listenable.merge([doc.canvasSignal, app.overlaySignal]);

  ToolEvent _event(PointerEvent e) {
    final kb = HardwareKeyboard.instance;
    final hasPressure = e.kind == PointerDeviceKind.stylus || e.kind == PointerDeviceKind.invertedStylus || (e.pressureMax > e.pressureMin && e.kind == PointerDeviceKind.touch && e.pressure != 1);
    var pressure = 1.0;
    if (hasPressure && e.pressureMax > e.pressureMin) {
      pressure = ((e.pressure - e.pressureMin) / (e.pressureMax - e.pressureMin)).clamp(0.0, 1.0);
    }
    return ToolEvent(
      doc: doc.view.toDoc(e.localPosition),
      view: e.localPosition,
      pressure: pressure,
      tilt: e.tilt,
      azimuth: e.orientation,
      timeMs: e.timeStamp.inMicroseconds / 1000.0,
      hasPressure: hasPressure,
      kind: e.kind,
      buttons: e.buttons,
      shift: kb.isShiftPressed,
      ctrl: kb.isControlPressed || kb.isMetaPressed,
      alt: kb.isAltPressed,
      eraserEnd: e.kind == PointerDeviceKind.invertedStylus,
    );
  }

  void _fitIfNeeded(Size size) {
    if (size.isEmpty) return;
    doc.viewportSize = size;
    if (!doc.viewInitialized) {
      doc.viewInitialized = true;
      final c = doc.comp;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        doc.setView(ViewState.fit(size, Rect.fromLTWH(0, 0, c.width.toDouble(), c.height.toDouble())));
      });
    }
  }

  // ---- pointer ------------------------------------------------------------

  void _down(PointerDownEvent e) {
    app.focusNode.requestFocus();
    if (e.kind == PointerDeviceKind.touch) {
      _touches[e.pointer] = e.localPosition;
      if (_touches.length == 1) _touchStart = DateTime.now();
      if (_touches.length == 2) {
        // second finger: cancel the stroke and start navigating
        if (_toolPointer != null) {
          app.tool.onCancel();
          _toolPointer = null;
        }
        _beginPinch();
        return;
      }
      if (_touches.length > 2) return;
      if (!app.settings.fingerDraws) {
        _panPointer = e.pointer;
        _panLast = e.localPosition;
        return;
      }
    }
    final middle = (e.buttons & kMiddleMouseButton) != 0;
    if (middle) {
      _panPointer = e.pointer;
      _panLast = e.localPosition;
      return;
    }
    if (_toolPointer != null) return;
    if ((e.buttons & kSecondaryMouseButton) != 0 && e.kind == PointerDeviceKind.mouse) return;
    _toolPointer = e.pointer;
    app.tool.onDown(_event(e));
  }

  void _move(PointerMoveEvent e) {
    if (e.kind == PointerDeviceKind.touch) {
      _touches[e.pointer] = e.localPosition;
      if (_navigating) {
        _updatePinch();
        return;
      }
    }
    if (_panPointer == e.pointer) {
      doc.setView(doc.view.panned(e.localPosition - _panLast));
      _panLast = e.localPosition;
      return;
    }
    if (_toolPointer == e.pointer) {
      app.tool.onMove(_event(e));
      _hover = e.localPosition;
      app.overlaySignal.fire();
    }
  }

  void _up(PointerUpEvent e) => _end(e, cancelled: false);
  void _cancel(PointerCancelEvent e) => _end(e, cancelled: true);

  void _end(PointerEvent e, {required bool cancelled}) {
    if (e.kind == PointerDeviceKind.touch) {
      final wasNavigating = _navigating;
      _touches.remove(e.pointer);
      if (wasNavigating) {
        if (_touches.length < 2) _navigating = false;
        // quick two-finger tap = undo
        if (!cancelled && _touches.isEmpty && app.settings.twoFingerUndo && DateTime.now().difference(_touchStart).inMilliseconds < 300 && _pinchMoved < 12) {
          doc.undo();
        }
        return;
      }
    }
    if (_panPointer == e.pointer) {
      _panPointer = null;
      return;
    }
    if (_toolPointer == e.pointer) {
      _toolPointer = null;
      if (cancelled) {
        app.tool.onCancel();
      } else {
        app.tool.onUp(_event(e));
      }
      app.toolIdle();
    }
  }

  double _pinchMoved = 0;

  void _beginPinch() {
    final pts = _touches.values.toList();
    _navigating = true;
    _pinchMoved = 0;
    _pinchDist = (pts[0] - pts[1]).distance;
    _pinchAngle = (pts[1] - pts[0]).direction;
    _pinchCenter = (pts[0] + pts[1]) / 2;
  }

  void _updatePinch() {
    final pts = _touches.values.toList();
    if (pts.length < 2) return;
    final dist = (pts[0] - pts[1]).distance;
    final angle = (pts[1] - pts[0]).direction;
    final center = (pts[0] + pts[1]) / 2;
    var v = doc.view.panned(center - _pinchCenter);
    if (_pinchDist > 0 && dist > 0) v = v.zoomedAt(center, dist / _pinchDist);
    var da = angle - _pinchAngle;
    while (da > math.pi) {
      da -= 2 * math.pi;
    }
    while (da < -math.pi) {
      da += 2 * math.pi;
    }
    v = v.rotatedAt(center, da);
    _pinchMoved += (center - _pinchCenter).distance + (dist - _pinchDist).abs();
    _pinchDist = dist;
    _pinchAngle = angle;
    _pinchCenter = center;
    doc.setView(v);
  }

  void _hoverEvent(PointerHoverEvent e) {
    _hover = e.localPosition;
    _hasHover = true;
    app.tool.onHover(_event(e));
    app.overlaySignal.fire();
  }

  void _signal(PointerSignalEvent e) {
    if (e is PointerScrollEvent) {
      final kb = HardwareKeyboard.instance;
      final dy = e.scrollDelta.dy;
      if (kb.isControlPressed || kb.isMetaPressed || app.settings.wheelZooms) {
        doc.setView(doc.view.zoomedAt(e.localPosition, math.exp(-dy / 300)));
      } else if (kb.isShiftPressed) {
        doc.setView(doc.view.panned(Offset(-dy, 0)));
      } else {
        doc.setView(doc.view.panned(Offset(-e.scrollDelta.dx, -dy)));
      }
    }
  }

  void _trackpad(PointerPanZoomUpdateEvent e) {
    var v = doc.view.panned(e.panDelta);
    if (e.scale != 1) v = v.zoomedAt(e.localPosition, e.scale / _lastTrackpadScale);
    _lastTrackpadScale = e.scale;
    doc.setView(v);
  }

  double _lastTrackpadScale = 1;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final size = Size(box.maxWidth, box.maxHeight);
      _fitIfNeeded(size);
      return ListenableBuilder(
        listenable: app,
        builder: (context, _) => MouseRegion(
          cursor: app.tool.cursor,
          onExit: (_) {
            _hasHover = false;
            app.overlaySignal.fire();
          },
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _down,
            onPointerMove: _move,
            onPointerUp: _up,
            onPointerCancel: _cancel,
            onPointerHover: _hoverEvent,
            onPointerSignal: _signal,
            onPointerPanZoomStart: (_) => _lastTrackpadScale = 1,
            onPointerPanZoomUpdate: _trackpad,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onDoubleTapDown: (d) => app.tool.onDoubleTap(ToolEvent(doc: doc.view.toDoc(d.localPosition), view: d.localPosition)),
              onDoubleTap: () {},
              child: ClipRect(
                child: Stack(fit: StackFit.expand, children: [
                  RepaintBoundary(child: CustomPaint(painter: _ArtPainter(doc, _repaint), size: Size.infinite)),
                  RepaintBoundary(child: CustomPaint(painter: _OverlayPainter(doc, app, _repaint, () => _hasHover ? _hover : null), size: Size.infinite)),
                ]),
              ),
            ),
          ),
        ),
      );
    });
  }
}

/// Paints the composition: checkerboard, the rendered frame and the page border.
class _ArtPainter extends CustomPainter {
  _ArtPainter(this.doc, Listenable repaint) : super(repaint: repaint);
  final DocumentController doc;

  @override
  void paint(Canvas canvas, Size size) {
    final comp = doc.comp;
    final view = doc.view;
    final docRect = Rect.fromLTWH(0, 0, comp.width.toDouble(), comp.height.toDouble());
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF141516));

    final visible = view.visibleDoc(size);
    final region = comp.infinite ? visible.inflate(2) : visible.intersect(docRect);
    if (region.isEmpty || region.width <= 0 || region.height <= 0) return;

    // Render at screen resolution, capped so huge zooms stay affordable.
    var scale = view.zoom;
    final maxSide = 4096.0;
    scale = math.min(scale, math.min(maxSide / region.width, maxSide / region.height));
    final r = region.roundedOutRect();

    canvas.save();
    canvas.transform(view.matrix.storage);
    ui.Image? img;
    try {
      img = renderCompImage(
        doc.project,
        comp,
        doc.frame.toDouble(),
        region: r,
        scale: scale,
        background: true,
        forExport: false,
        useCamera: doc.viewCamera,
        live: doc.live,
        quality: scale >= 2 ? FilterQuality.none : FilterQuality.medium,
        onion: AppState.I.playback.playing ? null : doc.onion,
        onionLayerId: doc.activeLayerId,
        lightTable: doc.lightTable,
        activeLayerId: doc.activeLayerId,
      );
      if (comp.background == null && !comp.infinite) {
        canvas.save();
        canvas.clipRect(docRect);
        _checker(canvas, r, 8 / view.zoom.clamp(0.0001, 1000));
        canvas.restore();
      }
      final paint = Paint()..filterQuality = view.zoom >= 2 ? FilterQuality.none : FilterQuality.medium;
      canvas.drawImageRect(img, Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()), r, paint);
    } finally {
      img?.dispose();
    }
    canvas.restore();

    // page border
    if (!comp.infinite) {
      final border = view.matrix.mapRect(docRect);
      canvas.drawRect(border.inflate(0.5), Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0x55FFFFFF));
    }
  }

  void _checker(Canvas canvas, Rect r, double cell) {
    final a = Paint()..color = const Color(0xFFFFFFFF), b = Paint()..color = const Color(0xFFD9D9DE);
    canvas.drawRect(r, a);
    final x0 = (r.left / cell).floor(), x1 = (r.right / cell).ceil();
    final y0 = (r.top / cell).floor(), y1 = (r.bottom / cell).ceil();
    if ((x1 - x0) * (y1 - y0) > 40000) return;
    for (var y = y0; y < y1; y++) {
      for (var x = x0; x < x1; x++) {
        if ((x + y).isOdd) canvas.drawRect(Rect.fromLTWH(x * cell, y * cell, cell, cell).intersect(r), b);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ArtPainter old) => !identical(old.doc, doc);
}

extension on Rect {
  Rect roundedOutRect() => Rect.fromLTRB(left.floorToDouble(), top.floorToDouble(), right.ceilToDouble(), bottom.ceilToDouble());
}

/// Grid, guides, rulers-less overlays and tool feedback, in viewport space.
class _OverlayPainter extends CustomPainter {
  _OverlayPainter(this.doc, this.app, Listenable repaint, this.hover) : super(repaint: repaint);
  final DocumentController doc;
  final AppState app;
  final Offset? Function() hover;

  @override
  void paint(Canvas canvas, Size size) {
    final view = doc.view;
    final comp = doc.comp;
    final docRect = Rect.fromLTWH(0, 0, comp.width.toDouble(), comp.height.toDouble());

    if (doc.showGrid) _grid(canvas, size, view, docRect);
    if (doc.showPixelGrid && view.zoom >= 8) _pixelGrid(canvas, size, view, docRect);
    if (doc.showGuides) {
      final p = Paint()
        ..color = const Color(0xAA2BD4E0)
        ..strokeWidth = 1;
      for (final g in comp.guides) {
        if (g.vertical) {
          final a = view.toView(Offset(g.pos, 0)), b = view.toView(Offset(g.pos, comp.height.toDouble()));
          canvas.drawLine(a, b, p);
        } else {
          final a = view.toView(Offset(0, g.pos)), b = view.toView(Offset(comp.width.toDouble(), g.pos));
          canvas.drawLine(a, b, p);
        }
      }
    }
    app.tool.paintOverlay(canvas, size, view);

    final h = hover();
    final cs = app.tool.brushCursorSize;
    if (h != null && cs != null && cs > 0) {
      final r = math.max(1.5, cs * view.zoom / 2);
      canvas.drawCircle(h, r, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..color = const Color(0x99000000));
      canvas.drawCircle(h, r, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xFFFFFFFF));
    }
  }

  void _grid(Canvas canvas, Size size, ViewState view, Rect docRect) {
    final step = doc.gridSize;
    if (step * view.zoom < 6) return;
    final p = Paint()
      ..color = const Color(0x33888888)
      ..strokeWidth = 1;
    for (var x = 0.0; x <= docRect.width; x += step) {
      canvas.drawLine(view.toView(Offset(x, 0)), view.toView(Offset(x, docRect.height)), p);
    }
    for (var y = 0.0; y <= docRect.height; y += step) {
      canvas.drawLine(view.toView(Offset(0, y)), view.toView(Offset(docRect.width, y)), p);
    }
  }

  void _pixelGrid(Canvas canvas, Size size, ViewState view, Rect docRect) {
    final vis = view.visibleDoc(size).intersect(docRect);
    if (vis.isEmpty) return;
    final p = Paint()
      ..color = const Color(0x22808080)
      ..strokeWidth = 1;
    final x0 = vis.left.floor(), x1 = vis.right.ceil(), y0 = vis.top.floor(), y1 = vis.bottom.ceil();
    if ((x1 - x0) + (y1 - y0) > 600) return;
    for (var x = x0; x <= x1; x++) {
      canvas.drawLine(view.toView(Offset(x.toDouble(), y0.toDouble())), view.toView(Offset(x.toDouble(), y1.toDouble())), p);
    }
    for (var y = y0; y <= y1; y++) {
      canvas.drawLine(view.toView(Offset(x0.toDouble(), y.toDouble())), view.toView(Offset(x1.toDouble(), y.toDouble())), p);
    }
  }

  @override
  bool shouldRepaint(covariant _OverlayPainter old) => !identical(old.doc, doc);
}

/// Placeholder shown when no document is open.
class EmptyWorkspace extends StatelessWidget {
  const EmptyWorkspace({super.key, required this.onNew, required this.onOpen});
  final VoidCallback onNew, onOpen;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.draw_outlined, size: 56, color: context.dim),
        const SizedBox(height: 12),
        Text('Drawly', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),
        Row(mainAxisSize: MainAxisSize.min, children: [
          FilledButton.icon(onPressed: onNew, icon: const Icon(Icons.add, size: 18), label: const Text('Nuevo / New')),
          const SizedBox(width: 8),
          OutlinedButton.icon(onPressed: onOpen, icon: const Icon(Icons.folder_open, size: 18), label: const Text('Abrir / Open')),
        ]),
      ]),
    );
  }
}
