import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../../model/document.dart';
import '../theme.dart';
import '../widgets.dart';

Future<bool> confirmDialog(BuildContext context, {required String title, String? message, String? ok, bool danger = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title, style: const TextStyle(fontSize: 17)),
      content: message == null ? null : Text(message, style: const TextStyle(fontSize: 13)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancelar', 'Cancel'))),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: ctx.cs.error, foregroundColor: ctx.cs.onError) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(ok ?? tr('Aceptar', 'OK')),
        ),
      ],
    ),
  );
  return r ?? false;
}

Future<String?> promptText(BuildContext context, {required String title, String initial = '', String? label, String? ok}) {
  final c = TextEditingController(text: initial)..selection = TextSelection(baseOffset: 0, extentOffset: initial.length);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title, style: const TextStyle(fontSize: 17)),
      content: SizedBox(
        width: 320,
        child: TextField(
          controller: c,
          autofocus: true,
          decoration: InputDecoration(labelText: label),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Cancelar', 'Cancel'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: Text(ok ?? tr('Aceptar', 'OK'))),
      ],
    ),
  );
}

Future<double?> promptNumber(
  BuildContext context, {
  required String title,
  required double initial,
  double min = 0,
  double max = 1000,
  String suffix = 'px',
  int decimals = 0,
  String? label,
}) {
  var value = initial;
  return showDialog<double>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(title, style: const TextStyle(fontSize: 17)),
        content: SizedBox(
          width: 340,
          child: MiniSlider(
            label: label ?? '',
            value: value,
            min: min,
            max: max,
            decimals: decimals,
            suffix: ' $suffix',
            width: 340,
            onChanged: (v) => setState(() => value = decimals == 0 ? v.roundToDouble() : v),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Cancelar', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, value), child: Text(tr('Aceptar', 'OK'))),
        ],
      ),
    ),
  );
}

/// Picks one entry from a list.
Future<T?> pickFromList<T>(BuildContext context, {required String title, required List<(T, String)> items}) {
  return showDialog<T>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text(title, style: const TextStyle(fontSize: 17)),
      children: [
        for (final e in items) SimpleDialogOption(onPressed: () => Navigator.pop(ctx, e.$1), child: Text(e.$2, style: const TextStyle(fontSize: 13))),
      ],
    ),
  );
}

/// New canvas size and the anchor that stays fixed.
Future<({int w, int h, double ax, double ay})?> showCanvasSizeDialog(BuildContext context, Comp comp) {
  var w = comp.width.toDouble(), h = comp.height.toDouble();
  var ax = 0.5, ay = 0.5;
  return showDialog<({int w, int h, double ax, double ay})>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(tr('Tamaño de lienzo', 'Canvas size'), style: const TextStyle(fontSize: 17)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            NumField(value: w, min: 1, max: 30000, width: 110, label: tr('Ancho', 'Width'), suffix: 'px', onSubmitted: (v) => setState(() => w = v)),
            const SizedBox(width: 12),
            NumField(value: h, min: 1, max: 30000, width: 110, label: tr('Alto', 'Height'), suffix: 'px', onSubmitted: (v) => setState(() => h = v)),
          ]),
          const SizedBox(height: 16),
          Text(tr('Anclaje', 'Anchor'), style: kSmall.copyWith(color: ctx.dim)),
          const SizedBox(height: 6),
          for (var y = 0; y < 3; y++)
            Row(mainAxisSize: MainAxisSize.min, children: [
              for (var x = 0; x < 3; x++)
                Padding(
                  padding: const EdgeInsets.all(2),
                  child: PanelButton(
                    icon: Icons.circle,
                    iconSize: 9,
                    tooltip: '',
                    selected: ax == x / 2 && ay == y / 2,
                    onTap: () => setState(() {
                      ax = x / 2;
                      ay = y / 2;
                    }),
                  ),
                ),
            ]),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Cancelar', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, (w: w.round(), h: h.round(), ax: ax, ay: ay)), child: Text(tr('Aplicar', 'Apply'))),
        ],
      ),
    ),
  );
}

/// New image size (resamples the artwork).
Future<({int w, int h})?> showImageSizeDialog(BuildContext context, Comp comp) {
  var w = comp.width.toDouble(), h = comp.height.toDouble();
  var keep = true;
  final ratio = comp.width / comp.height;
  return showDialog<({int w, int h})>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(tr('Tamaño de imagen', 'Image size'), style: const TextStyle(fontSize: 17)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            NumField(
              key: ValueKey('w$w'),
              value: w,
              min: 1,
              max: 30000,
              width: 110,
              label: tr('Ancho', 'Width'),
              suffix: 'px',
              onSubmitted: (v) => setState(() {
                w = v;
                if (keep) h = (v / ratio).roundToDouble().clamp(1, 30000);
              }),
            ),
            const SizedBox(width: 12),
            NumField(
              key: ValueKey('h$h'),
              value: h,
              min: 1,
              max: 30000,
              width: 110,
              label: tr('Alto', 'Height'),
              suffix: 'px',
              onSubmitted: (v) => setState(() {
                h = v;
                if (keep) w = (v * ratio).roundToDouble().clamp(1, 30000);
              }),
            ),
          ]),
          const SizedBox(height: 12),
          MiniToggle(label: tr('Mantener proporción', 'Keep aspect ratio'), icon: Icons.link, value: keep, onChanged: (v) => setState(() => keep = v)),
          const SizedBox(height: 10),
          Row(mainAxisSize: MainAxisSize.min, children: [
            for (final f in const [0.25, 0.5, 2.0, 4.0])
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ActionChip(
                  label: Text('${f < 1 ? (f * 100).round() : (f * 100).round()} %', style: kTiny),
                  onPressed: () => setState(() {
                    w = (comp.width * f).roundToDouble().clamp(1, 30000);
                    h = (comp.height * f).roundToDouble().clamp(1, 30000);
                  }),
                ),
              ),
          ]),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Cancelar', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, (w: w.round(), h: h.round())), child: Text(tr('Aplicar', 'Apply'))),
        ],
      ),
    ),
  );
}
