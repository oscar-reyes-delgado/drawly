import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_state.dart';
import '../../app/doc_edit.dart';
import '../../app/document_controller.dart';
import '../../core/i18n.dart';
import '../../engine/compositor.dart';
import '../../model/filter_spec.dart';
import '../../model/gradient.dart';
import '../../model/layer.dart';
import '../theme.dart';
import '../widgets.dart';

/// Edits a filter with a live preview on the canvas.
///
/// With [adjustLayerId] the dialog edits that adjustment layer in place;
/// otherwise it previews on the active raster layer and returns the spec to
/// apply (null when cancelled).
Future<FilterSpec?> showFilterDialog(BuildContext context, DocumentController doc, FilterSpec initial, {String? adjustLayerId}) {
  return showDialog<FilterSpec>(
    context: context,
    barrierColor: Colors.transparent,
    builder: (_) => _FilterDialog(doc, initial, adjustLayerId),
  );
}

class _FilterDialog extends StatefulWidget {
  const _FilterDialog(this.doc, this.initial, this.adjustLayerId);
  final DocumentController doc;
  final FilterSpec initial;
  final String? adjustLayerId;

  @override
  State<_FilterDialog> createState() => _FilterDialogState();
}

class _FilterDialogState extends State<_FilterDialog> {
  late FilterSpec _spec = widget.initial;
  bool _preview = true;
  bool _done = false;
  bool _applied = false;
  Timer? _timer;
  String _channel = 'rgb';
  late final String _key = DocumentController.gestureKey('filter');

  DocumentController get d => widget.doc;

  @override
  void initState() {
    super.initState();
    if (widget.adjustLayerId == null) WidgetsBinding.instance.addPostFrameCallback((_) => _render());
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (!_done) _revert();
    super.dispose();
  }

  void _revert() {
    if (widget.adjustLayerId != null) {
      if (_applied) d.undo();
    } else {
      d.setLive(null);
    }
  }

  void _set(FilterSpec s) {
    setState(() => _spec = s);
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 40), _render);
  }

  void _render() {
    if (!mounted) return;
    final id = widget.adjustLayerId;
    if (id != null) {
      d.updateLayer(_spec.def.label, id, (l) => l is AdjustLayer ? l.withFilter(_spec) : l, mergeKey: _key);
      _applied = true;
      return;
    }
    if (!_preview) {
      d.setLive(null);
      return;
    }
    final t = d.resolvePaintTarget();
    if (t == null || t.onMask) return;
    final region = d.filterRegion(t.plane, _spec);
    if (region.width < 1 || region.height < 1) return;
    final img = d.filteredRegion(t.plane, _spec, region);
    final out = t.plane.cleared(region).withImage(img, region.topLeft, blend: BlendMode.src);
    img.dispose();
    d.setLive(LiveEdit(layerId: t.layerId, replace: out));
  }

  void _accept() {
    _done = true;
    if (widget.adjustLayerId == null) d.setLive(null);
    Navigator.pop(context, _spec);
  }

  void _cancel() {
    _done = true;
    _revert();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final def = _spec.def;
    final ts = AppState.I.ts;
    return Dialog(
      alignment: Alignment.centerRight,
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: 330,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(def.label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              for (final p in def.params)
                if (p.min != p.max)
                  if (p.max - p.min == 1 && p.decimals == 0)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: MiniToggle(label: p.label, value: _spec.v(p.key) >= 0.5, onChanged: (v) => _set(_spec.withParam(p.key, v ? 1 : 0))),
                    )
                  else
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(p.label, style: kTiny.copyWith(color: context.dim)),
                      MiniSlider(
                        label: '',
                        value: _spec.v(p.key),
                        min: p.min,
                        max: p.max,
                        decimals: p.decimals,
                        suffix: p.unit.isEmpty ? '' : ' ${p.unit}',
                        width: 294,
                        onChanged: (v) => _set(_spec.withParam(p.key, p.decimals == 0 ? v.roundToDouble() : v)),
                      ),
                    ]),
              if (def.hasColor)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(children: [
                    Swatch(color: _spec.color ?? const Color(0xFF00FF00), size: 26),
                    const SizedBox(width: 10),
                    Flexible(child: TextButton(onPressed: () => _set(_spec.copyWith(color: ts.fg)), child: Text(tr('Usar color frontal', 'Use foreground colour'), style: kSmall))),
                  ]),
                ),
              if (def.hasGradient) ...[
                const SizedBox(height: 4),
                _GradientBar(_spec.gradient ?? GradientSpec.blackWhite),
                const SizedBox(height: 6),
                Wrap(spacing: 4, runSpacing: 4, children: [
                  ActionChip(
                    label: Text(tr('Frontal → fondo', 'Foreground → background'), style: kTiny),
                    onPressed: () => _set(_spec.copyWith(gradient: GradientSpec.twoColor(ts.fg, ts.bg))),
                  ),
                  for (final g in gradientPresets()) ActionChip(label: Text(g.$1, style: kTiny), onPressed: () => _set(_spec.copyWith(gradient: GradientSpec(stops: g.$2)))),
                ]),
              ],
              if (def.hasCurve) ...[
                Row(children: [
                  for (final ch in const ['rgb', 'r', 'g', 'b'])
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: MiniToggle(label: ch.toUpperCase(), value: _channel == ch, onChanged: (_) => setState(() => _channel = ch)),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => _set(_spec.copyWith(curves: {..._spec.curves}..remove(_channel))),
                    child: Text(tr('Restablecer', 'Reset'), style: kTiny),
                  ),
                ]),
                const SizedBox(height: 6),
                CurveEditor(
                  points: _spec.curves[_channel] ?? const [Offset(0, 0), Offset(1, 1)],
                  color: switch (_channel) {
                    'r' => const Color(0xFFFF5252),
                    'g' => const Color(0xFF4CAF50),
                    'b' => const Color(0xFF448AFF),
                    _ => context.cs.onSurface,
                  },
                  onChanged: (pts) => _set(_spec.copyWith(curves: {..._spec.curves, _channel: pts})),
                ),
                Text(tr('Clic: añadir punto · Doble clic: quitarlo', 'Click: add a point · Double click: remove it'), style: kTiny.copyWith(color: context.dim)),
              ],
              const SizedBox(height: 10),
              // wraps to two lines when the text is large (phones)
              Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, runSpacing: 6, children: [
                if (widget.adjustLayerId == null)
                  MiniToggle(
                    label: tr('Vista previa', 'Preview'),
                    value: _preview,
                    onChanged: (v) {
                      setState(() => _preview = v);
                      _render();
                    },
                  ),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  TextButton(onPressed: _cancel, child: Text(tr('Cancelar', 'Cancel'))),
                  const SizedBox(width: 6),
                  FilledButton(onPressed: _accept, child: Text(tr('Aplicar', 'Apply'))),
                ]),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

class _GradientBar extends StatelessWidget {
  const _GradientBar(this.gradient);
  final GradientSpec gradient;

  @override
  Widget build(BuildContext context) {
    final s = gradient.sorted;
    return Container(
      height: 22,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: context.line),
        gradient: LinearGradient(colors: s.length < 2 ? [s.first.color, s.first.color] : [for (final e in s) e.color], stops: s.length < 2 ? null : [for (final e in s) e.t.clamp(0.0, 1.0)]),
      ),
    );
  }
}

/// Tone curve editor: points in 0..1 (x = input, y = output, origin bottom-left).
class CurveEditor extends StatefulWidget {
  const CurveEditor({super.key, required this.points, required this.onChanged, this.color, this.size = 294});
  final List<Offset> points;
  final ValueChanged<List<Offset>> onChanged;
  final Color? color;
  final double size;

  @override
  State<CurveEditor> createState() => _CurveEditorState();
}

class _CurveEditorState extends State<CurveEditor> {
  int? _drag;

  List<Offset> get _pts => [...widget.points]..sort((a, b) => a.dx.compareTo(b.dx));

  Offset _toUnit(Offset local) => Offset((local.dx / widget.size).clamp(0.0, 1.0), (1 - local.dy / widget.size).clamp(0.0, 1.0));

  int? _hit(Offset local) {
    final pts = _pts;
    for (var i = 0; i < pts.length; i++) {
      final p = Offset(pts[i].dx * widget.size, (1 - pts[i].dy) * widget.size);
      if ((p - local).distance < 12) return i;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanStart: (e) {
        var i = _hit(e.localPosition);
        if (i == null) {
          final pts = [..._pts, _toUnit(e.localPosition)]..sort((a, b) => a.dx.compareTo(b.dx));
          i = pts.indexOf(_toUnit(e.localPosition));
          widget.onChanged(pts);
        }
        _drag = i;
      },
      onPanUpdate: (e) {
        final i = _drag;
        final pts = _pts;
        if (i == null || i >= pts.length) return;
        var u = _toUnit(e.localPosition);
        // keep the point between its neighbours
        final lo = i > 0 ? pts[i - 1].dx + 0.01 : 0.0, hi = i < pts.length - 1 ? pts[i + 1].dx - 0.01 : 1.0;
        u = Offset(u.dx.clamp(lo, hi < lo ? lo : hi), u.dy);
        pts[i] = u;
        widget.onChanged(pts);
      },
      onPanEnd: (_) => _drag = null,
      onDoubleTapDown: (e) {
        final i = _hit(e.localPosition);
        final pts = _pts;
        if (i == null || pts.length <= 2) return;
        pts.removeAt(i);
        widget.onChanged(pts);
      },
      onDoubleTap: () {},
      child: CustomPaint(size: Size.square(widget.size), painter: _CurvePainter(_pts, widget.color ?? context.cs.onSurface, context.line, context.cs.surfaceContainerHigh)),
    );
  }
}

class _CurvePainter extends CustomPainter {
  _CurvePainter(this.pts, this.color, this.grid, this.bg);
  final List<Offset> pts;
  final Color color, grid, bg;

  /// Monotone cubic interpolation through the points (matches the engine's look closely enough for editing).
  double _eval(double x) {
    if (pts.isEmpty) return x;
    if (x <= pts.first.dx) return pts.first.dy;
    if (x >= pts.last.dx) return pts.last.dy;
    for (var i = 0; i < pts.length - 1; i++) {
      final a = pts[i], b = pts[i + 1];
      if (x >= a.dx && x <= b.dx) {
        final t = (x - a.dx) / (b.dx - a.dx == 0 ? 1 : b.dx - a.dx);
        final s = t * t * (3 - 2 * t);
        return a.dy + (b.dy - a.dy) * s;
      }
    }
    return x;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(6)), Paint()..color = bg);
    final g = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      canvas.drawLine(Offset(s * i / 4, 0), Offset(s * i / 4, s), g);
      canvas.drawLine(Offset(0, s * i / 4), Offset(s, s * i / 4), g);
    }
    canvas.drawLine(Offset(0, s), Offset(s, 0), g);
    final path = Path();
    for (var i = 0; i <= 96; i++) {
      final x = i / 96;
      final y = _eval(x).clamp(0.0, 1.0);
      if (i == 0) {
        path.moveTo(x * s, (1 - y) * s);
      } else {
        path.lineTo(x * s, (1 - y) * s);
      }
    }
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = color);
    for (final p in pts) {
      final c = Offset(p.dx * s, (1 - p.dy) * s);
      canvas.drawCircle(c, 5, Paint()..color = bg);
      canvas.drawCircle(
          c,
          5,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = color);
    }
  }

  @override
  bool shouldRepaint(_CurvePainter old) => true;
}
