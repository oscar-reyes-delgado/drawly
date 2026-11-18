import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../app/app_state.dart';
import '../app/document_controller.dart';
import '../app/tool_state.dart';
import '../app/view_state.dart';
import '../engine/assist.dart';

/// A pointer sample handed to tools, in both document and viewport space.
class ToolEvent {
  const ToolEvent({
    required this.doc,
    required this.view,
    this.pressure = 1,
    this.tilt = 0,
    this.azimuth = 0,
    this.timeMs = 0,
    this.hasPressure = false,
    this.kind = PointerDeviceKind.mouse,
    this.buttons = kPrimaryButton,
    this.shift = false,
    this.ctrl = false,
    this.alt = false,
    this.eraserEnd = false,
  });

  final Offset doc, view;
  final double pressure, tilt, azimuth, timeMs;
  final bool hasPressure;
  final PointerDeviceKind kind;
  final int buttons;
  final bool shift, ctrl, alt;

  /// The pen is flipped to its eraser end.
  final bool eraserEnd;

  ToolEvent withDoc(Offset d) => ToolEvent(
        doc: d,
        view: view,
        pressure: pressure,
        tilt: tilt,
        azimuth: azimuth,
        timeMs: timeMs,
        hasPressure: hasPressure,
        kind: kind,
        buttons: buttons,
        shift: shift,
        ctrl: ctrl,
        alt: alt,
        eraserEnd: eraserEnd,
      );
}

/// Base class of every canvas tool.
abstract class Tool {
  String get id;
  String get label;
  IconData get icon;

  /// Default shortcut shown in tooltips ('' = none).
  String get shortcut => '';

  /// Toolbar icon (tools without a fitting Material icon paint their own).
  Widget buildIcon(double size, Color color) => Icon(icon, size: size, color: color);

  /// Longer hint shown in the status bar.
  String get hint => '';

  AppState get app => AppState.I;
  ToolState get ts => app.ts;
  DocumentController? get doc => app.doc;

  MouseCursor get cursor => SystemMouseCursors.precise;

  /// Draw the round brush-size cursor (diameter in document pixels), or null.
  double? get brushCursorSize => null;

  /// Whether dragging outside the canvas should keep feeding this tool.
  bool get active => false;

  void onActivate() {}
  void onDeactivate() {}

  void onDown(ToolEvent e) {}
  void onMove(ToolEvent e) {}
  void onUp(ToolEvent e) {}
  void onCancel() {}
  void onHover(ToolEvent e) {}
  void onDoubleTap(ToolEvent e) {}

  /// Return true when the key was consumed.
  bool onKey(KeyEvent e) => false;

  /// Paints tool feedback above the document, in viewport coordinates.
  void paintOverlay(Canvas canvas, Size size, ViewState view) {}

  void requestOverlay() => app.overlaySignal.fire();

  void toast(String message) => app.toast(message);

  /// Snaps a document point to the grid / guides when those are enabled.
  Offset snapDoc(Offset p) {
    final d = doc;
    if (d == null || !(d.snapToGrid || (d.snapToGuides && d.showGuides))) return p;
    return snapPoint(
      p,
      guides: d.comp.guides,
      toGuides: d.snapToGuides && d.showGuides,
      toGrid: d.snapToGrid,
      gridSize: d.gridSize / (d.gridSubdivisions < 1 ? 1 : d.gridSubdivisions),
      threshold: 8 / d.view.zoom,
    );
  }

  /// A document-space path mapped into viewport space.
  static Path viewPath(Path docPath, ViewState view) => docPath.transform(view.matrix.storage);

  // ---- shared drawing helpers for overlays --------------------------------

  static final Paint _dark = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3
    ..color = const Color(0xB0000000);
  static final Paint _light = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.2
    ..color = const Color(0xFFFFFFFF);

  /// Outline readable over any artwork (dark halo + light line).
  static void drawContrastPath(Canvas canvas, Path path) {
    canvas.drawPath(path, _dark);
    canvas.drawPath(path, _light);
  }

  static void drawHandle(Canvas canvas, Offset p, {bool selected = false, double size = 9, bool round = false}) {
    final r = Rect.fromCenter(center: p, width: size, height: size);
    final fill = Paint()..color = selected ? const Color(0xFF4F8CFF) : const Color(0xFFFFFFFF);
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = selected ? const Color(0xFFFFFFFF) : const Color(0xFF1B1B1F);
    if (round) {
      canvas.drawCircle(p, size / 2, fill);
      canvas.drawCircle(p, size / 2, border);
    } else {
      canvas.drawRect(r, fill);
      canvas.drawRect(r, border);
    }
  }
}
