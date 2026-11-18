import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/tool_state.dart';
import '../../core/color_utils.dart';
import '../../core/i18n.dart';
import '../theme.dart';
import '../widgets.dart';

/// Foreground/background swatches, HSV picker (square + hue bar), RGB/HEX fields, history and palette.
class ColorPanel extends StatelessWidget {
  const ColorPanel({super.key, required this.ts});

  final ToolState ts;

  @override
  Widget build(BuildContext context) => _ColorPanelBody(ts: ts);
}

class _ColorPanelBody extends StatefulWidget {
  const _ColorPanelBody({required this.ts});

  final ToolState ts;

  @override
  State<_ColorPanelBody> createState() => _ColorPanelBodyState();
}

class _ColorPanelBodyState extends State<_ColorPanelBody> {
  bool _editingBg = false;
  late double _hue;
  late double _sat;
  late double _val;
  Color? _lastSyncedColor;

  late final TextEditingController _hexController;
  late final FocusNode _hexFocus;

  Color get _activeColor => _editingBg ? widget.ts.bg : widget.ts.fg;

  @override
  void initState() {
    super.initState();
    final c = _activeColor;
    final hsv = Hsv.fromColor(c);
    _hue = hsv.h;
    _sat = hsv.s;
    _val = hsv.v;
    _lastSyncedColor = c;
    _hexController = TextEditingController(text: c.hex);
    _hexFocus = FocusNode()..addListener(_onHexFocusChange);
    widget.ts.addListener(_onToolStateChanged);
  }

  @override
  void didUpdateWidget(_ColorPanelBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ts != widget.ts) {
      oldWidget.ts.removeListener(_onToolStateChanged);
      widget.ts.addListener(_onToolStateChanged);
      _syncFromModel(forceHex: true);
    }
  }

  @override
  void dispose() {
    widget.ts.removeListener(_onToolStateChanged);
    _hexFocus.removeListener(_onHexFocusChange);
    _hexFocus.dispose();
    _hexController.dispose();
    super.dispose();
  }

  void _onToolStateChanged() {
    _syncFromModel();
  }

  void _syncFromModel({bool forceHex = false}) {
    final c = _activeColor;
    if (c != _lastSyncedColor || forceHex) {
      final hsv = Hsv.fromColor(c);
      // Keep the current hue when the colour becomes achromatic (s == 0 or v == 0)
      // so dragging into white/black/grey does not snap the hue slider back to red.
      if (hsv.s > 1e-4 && hsv.v > 1e-4) {
        _hue = hsv.h;
      }
      _sat = hsv.s;
      _val = hsv.v;
      _lastSyncedColor = c;
      if (!_hexFocus.hasFocus || forceHex) {
        _hexController.text = c.hex;
      }
    }
    if (mounted) setState(() {});
  }

  void _setEditingBg(bool bg) {
    if (_editingBg == bg) return;
    setState(() => _editingBg = bg);
    FocusScope.of(context).unfocus();
    _syncFromModel(forceHex: true);
  }

  void _setActiveColor(Color c, {bool updateHsv = true}) {
    if (updateHsv) {
      final hsv = Hsv.fromColor(c);
      if (hsv.s > 1e-4 && hsv.v > 1e-4) _hue = hsv.h;
      _sat = hsv.s;
      _val = hsv.v;
    }
    _lastSyncedColor = c;
    if (!_hexFocus.hasFocus) {
      _hexController.text = c.hex;
    }
    if (_editingBg) {
      widget.ts.bg = c;
    } else {
      widget.ts.fg = c;
    }
  }

  void _applyHsv(double h, double s, double v) {
    _hue = h.clamp(0.0, 360.0);
    _sat = s.clamp(0.0, 1.0);
    _val = v.clamp(0.0, 1.0);
    final c = Hsv(_hue, _sat, _val, _activeColor.a).toColor();
    _setActiveColor(c, updateHsv: false);
  }

  void _onHexFocusChange() {
    if (!_hexFocus.hasFocus) {
      _commitHex(restoreOnInvalid: true);
    }
  }

  void _onHexChanged(String text) {
    final clean = text.trim().replaceAll('#', '');
    if (clean.length == 6 || clean.length == 8) {
      final parsed = parseHex(clean);
      if (parsed != null) {
        final next = clean.length == 6 ? parsed.withValues(alpha: _activeColor.a) : parsed;
        _setActiveColor(next);
      }
    }
  }

  void _commitHex({bool restoreOnInvalid = false}) {
    final parsed = parseHex(_hexController.text);
    if (parsed == null) {
      if (restoreOnInvalid) _hexController.text = _activeColor.hex;
      return;
    }
    final clean = _hexController.text.trim().replaceAll('#', '');
    final next = clean.length <= 6 ? parsed.withValues(alpha: _activeColor.a) : parsed;
    _setActiveColor(next);
    _hexController.text = next.hex;
  }

  @override
  Widget build(BuildContext context) {
    final ts = widget.ts;
    final active = _activeColor;
    final pal = ts.palette;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _FgBgSwatches(
                fg: ts.fg,
                bg: ts.bg,
                editingBg: _editingBg,
                onSelectFg: () => _setEditingBg(false),
                onSelectBg: () => _setEditingBg(true),
              ),
              const SizedBox(width: 6),
              PanelButton(
                key: const ValueKey('color_swap_btn'),
                icon: Icons.swap_horiz,
                tooltip: tr('Intercambiar colores', 'Swap colors'),
                onTap: () {
                  FocusScope.of(context).unfocus();
                  ts.swapColors();
                },
              ),
              PanelButton(
                key: const ValueKey('color_reset_btn'),
                icon: Icons.restart_alt,
                tooltip: tr('Restablecer colores', 'Reset colors'),
                onTap: () {
                  FocusScope.of(context).unfocus();
                  ts.resetColors();
                },
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  key: const ValueKey('color_hex_field'),
                  controller: _hexController,
                  focusNode: _hexFocus,
                  style: kSmall,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F#]')),
                    LengthLimitingTextInputFormatter(9),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'HEX',
                    prefixText: '#',
                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                  ),
                  onChanged: _onHexChanged,
                  onSubmitted: (_) => _commitHex(restoreOnInvalid: true),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 152,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _SvSquare(
                    hue: _hue,
                    sat: _sat,
                    val: _val,
                    onChange: (s, v) {
                      FocusScope.of(context).unfocus();
                      _applyHsv(_hue, s, v);
                    },
                    onEnd: () => ts.pushColorHistory(_activeColor),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 20,
                  child: _HueBar(
                    hue: _hue,
                    onChange: (h) {
                      FocusScope.of(context).unfocus();
                      _applyHsv(h, _sat, _val);
                    },
                    onEnd: () => ts.pushColorHistory(_activeColor),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: NumField(
                  key: const ValueKey('color_r_field'),
                  label: 'R',
                  value: active.r8.toDouble(),
                  min: 0,
                  max: 255,
                  decimals: 0,
                  onSubmitted: (v) => _setActiveColor(Color.fromARGB(active.a8, v.round(), active.g8, active.b8)),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: NumField(
                  key: const ValueKey('color_g_field'),
                  label: 'G',
                  value: active.g8.toDouble(),
                  min: 0,
                  max: 255,
                  decimals: 0,
                  onSubmitted: (v) => _setActiveColor(Color.fromARGB(active.a8, active.r8, v.round(), active.b8)),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: NumField(
                  key: const ValueKey('color_b_field'),
                  label: 'B',
                  value: active.b8.toDouble(),
                  min: 0,
                  max: 255,
                  decimals: 0,
                  onSubmitted: (v) => _setActiveColor(Color.fromARGB(active.a8, active.r8, active.g8, v.round())),
                ),
              ),
            ],
          ),
          if (ts.colorHistory.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(tr('Recientes', 'Recent'), style: kTiny.copyWith(color: context.dim)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final c in ts.colorHistory)
                  Swatch(
                    color: c,
                    size: 18,
                    selected: ts.fg.toARGB32() == c.toARGB32(),
                    tooltip: '#${c.hex}',
                    onTap: () {
                      FocusScope.of(context).unfocus();
                      ts.fg = c;
                    },
                  ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: MiniDropdown<String>(
                  value: pal.id,
                  items: [for (final p in ts.palettes) (p.id, p.name)],
                  tooltip: tr('Paleta', 'Palette'),
                  onChanged: (id) => ts.set(() => ts.paletteId = id),
                ),
              ),
              const SizedBox(width: 4),
              PanelButton(
                key: const ValueKey('color_palette_add_btn'),
                icon: Icons.add,
                size: 26,
                iconSize: 16,
                tooltip: tr('Añadir a la paleta', 'Add to palette'),
                onTap: () => ts.addToPalette(_activeColor),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final argb in pal.colors)
                Swatch(
                  color: Color(argb),
                  size: 20,
                  selected: ts.fg.toARGB32() == argb,
                  tooltip: pal.builtin
                      ? '#${Color(argb).hex}'
                      : '#${Color(argb).hex} · ${tr('clic derecho o mantener para quitar', 'right-click or hold to remove')}',
                  onTap: () {
                    FocusScope.of(context).unfocus();
                    ts.fg = Color(argb);
                  },
                  onLongPress: pal.builtin ? null : () => ts.removeFromPalette(argb),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FgBgSwatches extends StatelessWidget {
  const _FgBgSwatches({
    required this.fg,
    required this.bg,
    required this.editingBg,
    required this.onSelectFg,
    required this.onSelectBg,
  });

  final Color fg, bg;
  final bool editingBg;
  final VoidCallback onSelectFg, onSelectBg;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 42,
      height: 38,
      child: Stack(
        children: [
          Positioned(
            left: 16,
            top: 12,
            child: Swatch(
              key: const ValueKey('color_bg_swatch'),
              color: bg,
              size: 24,
              selected: editingBg,
              tooltip: tr('Color de fondo', 'Background color'),
              onTap: onSelectBg,
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            child: Swatch(
              key: const ValueKey('color_fg_swatch'),
              color: fg,
              size: 24,
              selected: !editingBg,
              tooltip: tr('Color frontal', 'Foreground color'),
              onTap: onSelectFg,
            ),
          ),
        ],
      ),
    );
  }
}

class _SvSquare extends StatelessWidget {
  const _SvSquare({
    required this.hue,
    required this.sat,
    required this.val,
    required this.onChange,
    required this.onEnd,
  });

  final double hue, sat, val;
  final void Function(double s, double v) onChange;
  final VoidCallback onEnd;

  void _handle(Offset local, Size size) {
    final w = size.width <= 0 ? 1.0 : size.width;
    final h = size.height <= 0 ? 1.0 : size.height;
    onChange((local.dx / w).clamp(0.0, 1.0), (1.0 - local.dy / h).clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return GestureDetector(
          key: const ValueKey('color_sv_square'),
          behavior: HitTestBehavior.opaque,
          onPanDown: (d) => _handle(d.localPosition, size),
          onPanStart: (d) => _handle(d.localPosition, size),
          onPanUpdate: (d) => _handle(d.localPosition, size),
          onPanEnd: (_) => onEnd(),
          onTapUp: (_) => onEnd(),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: CustomPaint(
              painter: _SvPainter(hue: hue, sat: sat, val: val, borderColor: context.line),
              size: size,
            ),
          ),
        );
      },
    );
  }
}

class _SvPainter extends CustomPainter {
  const _SvPainter({required this.hue, required this.sat, required this.val, required this.borderColor});

  final double hue, sat, val;
  final Color borderColor;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final pure = Hsv(hue, 1, 1).toColor();
    canvas.drawRect(rect, Paint()..color = pure);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFFFFFFFF), Color(0x00FFFFFF)],
        ).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00000000), Color(0xFF000000)],
        ).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = borderColor,
    );

    final pos = Offset(sat.clamp(0.0, 1.0) * size.width, (1.0 - val.clamp(0.0, 1.0)) * size.height);
    canvas.drawCircle(
      pos,
      6,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFF000000),
    );
    canvas.drawCircle(
      pos,
      5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = const Color(0xFFFFFFFF),
    );
  }

  @override
  bool shouldRepaint(_SvPainter old) =>
      old.hue != hue || old.sat != sat || old.val != val || old.borderColor != borderColor;
}

class _HueBar extends StatelessWidget {
  const _HueBar({required this.hue, required this.onChange, required this.onEnd});

  final double hue;
  final ValueChanged<double> onChange;
  final VoidCallback onEnd;

  void _handle(Offset local, Size size) {
    final h = size.height <= 0 ? 1.0 : size.height;
    onChange((local.dy / h).clamp(0.0, 1.0) * 360.0);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return GestureDetector(
          key: const ValueKey('color_hue_bar'),
          behavior: HitTestBehavior.opaque,
          onPanDown: (d) => _handle(d.localPosition, size),
          onPanStart: (d) => _handle(d.localPosition, size),
          onPanUpdate: (d) => _handle(d.localPosition, size),
          onPanEnd: (_) => onEnd(),
          onTapUp: (_) => onEnd(),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: CustomPaint(
              painter: _HuePainter(hue: hue, borderColor: context.line),
              size: size,
            ),
          ),
        );
      },
    );
  }
}

class _HuePainter extends CustomPainter {
  const _HuePainter({required this.hue, required this.borderColor});

  final double hue;
  final Color borderColor;

  static const _stops = [0.0, 1 / 6, 2 / 6, 3 / 6, 4 / 6, 5 / 6, 1.0];
  static const _colors = [
    Color(0xFFFF0000),
    Color(0xFFFFFF00),
    Color(0xFF00FF00),
    Color(0xFF00FFFF),
    Color(0xFF0000FF),
    Color(0xFFFF00FF),
    Color(0xFFFF0000),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: _stops,
          colors: _colors,
        ).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = borderColor,
    );
    final y = (hue.clamp(0.0, 360.0) / 360.0) * size.height;
    canvas.drawLine(
      Offset(0, y),
      Offset(size.width, y),
      Paint()
        ..strokeWidth = 3
        ..color = const Color(0xFF000000),
    );
    canvas.drawLine(
      Offset(0, y),
      Offset(size.width, y),
      Paint()
        ..strokeWidth = 1.5
        ..color = const Color(0xFFFFFFFF),
    );
  }

  @override
  bool shouldRepaint(_HuePainter old) => old.hue != hue || old.borderColor != borderColor;
}
