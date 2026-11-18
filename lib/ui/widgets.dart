import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

/// Compact icon button that never takes keyboard focus (so canvas shortcuts
/// keep working after it is clicked).
class PanelButton extends StatelessWidget {
  const PanelButton({super.key, required this.icon, required this.tooltip, this.onTap, this.selected = false, this.size = 28, this.iconSize = 17, this.child, this.color});

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool selected;
  final double size, iconSize;

  /// Replaces the icon.
  final Widget? child;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final fg = onTap == null ? cs.onSurface.withValues(alpha: 0.3) : (color ?? (selected ? cs.primary : cs.onSurface.withValues(alpha: 0.86)));
    return Tooltip(
      message: tooltip,
      child: Material(
        color: selected ? cs.primary.withValues(alpha: 0.16) : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          canRequestFocus: false,
          borderRadius: BorderRadius.circular(6),
          hoverColor: cs.onSurface.withValues(alpha: 0.08),
          onTap: onTap,
          child: SizedBox(width: size, height: size, child: Center(child: child ?? Icon(icon, size: iconSize, color: fg))),
        ),
      ),
    );
  }
}

/// Label + slider + editable value on one row.
class MiniSlider extends StatelessWidget {
  const MiniSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.onChangeEnd,
    this.decimals = 0,
    this.suffix = '',
    this.log = false,
    this.width = 190,
    this.display,
  });

  final String label, suffix;
  final double value, min, max;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;
  final int decimals;

  /// Logarithmic response (for sizes).
  final bool log;
  final double width;

  /// Multiplier applied to the shown number (e.g. 100 for percentages).
  final double? display;

  double _toT(double v) {
    final c = v.clamp(min, max);
    if (!log) return max == min ? 0 : (c - min) / (max - min);
    final lo = math.log(math.max(min, 1e-6)), hi = math.log(max);
    return (math.log(math.max(c, 1e-6)) - lo) / (hi - lo);
  }

  double _fromT(double t) {
    if (!log) return min + (max - min) * t;
    final lo = math.log(math.max(min, 1e-6)), hi = math.log(max);
    return math.exp(lo + (hi - lo) * t);
  }

  @override
  Widget build(BuildContext context) {
    final shown = value * (display ?? 1);
    final text = '${shown.toStringAsFixed(decimals)}$suffix';
    return SizedBox(
      width: width,
      height: 28,
      child: Row(children: [
        Flexible(flex: 0, child: Text(label, style: kTiny.copyWith(color: context.dim), overflow: TextOverflow.ellipsis)),
        Expanded(
          child: Slider(
            value: _toT(value).clamp(0.0, 1.0),
            onChanged: (t) => onChanged(_fromT(t)),
            onChangeEnd: onChangeEnd == null ? null : (t) => onChangeEnd!(_fromT(t)),
          ),
        ),
        SizedBox(width: 44, child: Text(text, style: kTiny, textAlign: TextAlign.right, maxLines: 1)),
      ]),
    );
  }
}

/// Small dropdown showing the current choice.
class MiniDropdown<T> extends StatelessWidget {
  const MiniDropdown({super.key, required this.value, required this.items, required this.onChanged, this.tooltip, this.width, this.icon});

  final T value;
  final List<(T, String)> items;
  final ValueChanged<T> onChanged;
  final String? tooltip;
  final double? width;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final current = items.where((e) => e.$1 == value).map((e) => e.$2).firstOrNull ?? '';
    return PopupMenuButton<T>(
      tooltip: tooltip ?? '',
      initialValue: value,
      onSelected: onChanged,
      position: PopupMenuPosition.under,
      constraints: const BoxConstraints(minWidth: 140),
      itemBuilder: (_) => [
        for (final e in items) PopupMenuItem<T>(value: e.$1, height: 32, child: Text(e.$2, style: kSmall)),
      ],
      child: Container(
        width: width,
        height: 26,
        padding: const EdgeInsets.only(left: 8, right: 2),
        decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(6)),
        child: Row(mainAxisSize: width == null ? MainAxisSize.min : MainAxisSize.max, children: [
          if (icon != null) ...[Icon(icon, size: 14, color: context.dim), const SizedBox(width: 5)],
          Flexible(fit: width == null ? FlexFit.loose : FlexFit.tight, child: Text(current, style: kSmall, overflow: TextOverflow.ellipsis)),
          Icon(Icons.arrow_drop_down, size: 18, color: context.dim),
        ]),
      ),
    );
  }
}

/// Toggle chip used in option bars.
class MiniToggle extends StatelessWidget {
  const MiniToggle({super.key, required this.label, required this.value, required this.onChanged, this.icon});
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Material(
      color: value ? cs.primary.withValues(alpha: 0.18) : cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        canRequestFocus: false,
        borderRadius: BorderRadius.circular(6),
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: 14, color: value ? cs.primary : context.dim), const SizedBox(width: 4)],
            Text(label, style: kSmall.copyWith(color: value ? cs.primary : cs.onSurface)),
          ]),
        ),
      ),
    );
  }
}

/// Colour swatch with a checkerboard under translucent colours.
class Swatch extends StatelessWidget {
  const Swatch({super.key, required this.color, this.size = 20, this.onTap, this.onLongPress, this.selected = false, this.tooltip, this.radius = 4});
  final Color color;
  final double size, radius;
  final VoidCallback? onTap, onLongPress;
  final bool selected;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final box = GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      onSecondaryTap: onLongPress,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: selected ? context.cs.primary : context.cs.outline.withValues(alpha: 0.6), width: selected ? 2 : 1),
        ),
      ),
    );
    return tooltip == null ? box : Tooltip(message: tooltip!, child: box);
  }
}

/// Numeric text field that commits on Enter or when it loses focus.
class NumField extends StatefulWidget {
  const NumField({super.key, required this.value, required this.onSubmitted, this.width = 64, this.decimals = 0, this.min, this.max, this.suffix, this.label});
  final double value;
  final ValueChanged<double> onSubmitted;
  final double width;
  final int decimals;
  final double? min, max;
  final String? suffix, label;

  @override
  State<NumField> createState() => _NumFieldState();
}

class _NumFieldState extends State<NumField> {
  late final TextEditingController _c = TextEditingController(text: _fmt(widget.value));
  late final FocusNode _f = FocusNode()..addListener(_onFocus);

  String _fmt(double v) => v.toStringAsFixed(widget.decimals);

  void _onFocus() {
    if (!_f.hasFocus) _commit();
  }

  void _commit() {
    final v = double.tryParse(_c.text.replaceAll(',', '.'));
    if (v == null) {
      _c.text = _fmt(widget.value);
      return;
    }
    var out = v;
    if (widget.min != null) out = math.max(widget.min!, out);
    if (widget.max != null) out = math.min(widget.max!, out);
    _c.text = _fmt(out);
    if (out != widget.value) widget.onSubmitted(out);
  }

  @override
  void didUpdateWidget(NumField old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value && !_f.hasFocus) _c.text = _fmt(widget.value);
  }

  @override
  void dispose() {
    _f.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      child: TextField(
        controller: _c,
        focusNode: _f,
        style: kSmall,
        textAlign: TextAlign.right,
        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\-]'))],
        decoration: InputDecoration(suffixText: widget.suffix, labelText: widget.label, contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7)),
        onSubmitted: (_) => _commit(),
      ),
    );
  }
}

/// Thin vertical separator for toolbars.
class VSep extends StatelessWidget {
  const VSep({super.key, this.height = 22});
  final double height;
  @override
  Widget build(BuildContext context) => Container(width: 1, height: height, margin: const EdgeInsets.symmetric(horizontal: 8), color: context.line);
}

/// Checkerboard used behind transparent content.
class CheckerPainter extends CustomPainter {
  const CheckerPainter({this.cell = 6});
  final double cell;

  @override
  void paint(Canvas canvas, Size size) {
    final a = Paint()..color = const Color(0xFFFFFFFF), b = Paint()..color = const Color(0xFFCFCFCF);
    canvas.drawRect(Offset.zero & size, a);
    for (var y = 0; y * cell < size.height; y++) {
      for (var x = y.isEven ? 1 : 0; x * cell < size.width; x += 2) {
        canvas.drawRect(Rect.fromLTWH(x * cell, y * cell, cell, cell).intersect(Offset.zero & size), b);
      }
    }
  }

  @override
  bool shouldRepaint(CheckerPainter old) => old.cell != cell;
}
