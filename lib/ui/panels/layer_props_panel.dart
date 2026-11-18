import 'package:flutter/material.dart';

import '../../app/doc_rig.dart';
import '../../app/doc_timeline.dart';
import '../../app/document_controller.dart';
import '../../core/i18n.dart';
import '../../model/anim.dart';
import '../../model/layer.dart';
import '../../model/layer_fx.dart';
import '../theme.dart';
import '../widgets.dart';

/// Colours offered by the small effect colour picker.
const List<Color> kFxColors = [
  Color(0xFF000000), Color(0xFFFFFFFF), Color(0xFF808080), Color(0xFFE53935),
  Color(0xFFFF9800), Color(0xFFFFEB3B), Color(0xFF43A047), Color(0xFF00ACC1),
  Color(0xFF1E88E5), Color(0xFF8E24AA), Color(0xFFFFE680), Color(0xFF6D4C41),
];

/// Layer colour tags. `LayerProps.colorTag` stores the ARGB value (0 = none), as the layer list and timeline read it.
const List<Color> kTagColors = [
  Color(0x00000000), Color(0xFFE53935), Color(0xFFFF9800), Color(0xFFFDD835),
  Color(0xFF43A047), Color(0xFF1E88E5), Color(0xFF8E24AA), Color(0xFF9E9E9E),
];

/// Properties of the active layer: transform, opacity, locks and layer effects.
class LayerPropsPanel extends StatelessWidget {
  const LayerPropsPanel({super.key, required this.doc});
  final DocumentController doc;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([doc, doc.frameSignal]),
      builder: (context, _) {
        final l = doc.activeLayer;
        if (l == null) {
          return Center(child: Text(tr('Ninguna capa seleccionada', 'No layer selected'), style: kSmall.copyWith(color: context.dim)));
        }
        return ListView(padding: const EdgeInsets.fromLTRB(10, 6, 10, 12), children: [
          _Section(title: tr('Transformación', 'Transform'), child: _TransformSection(doc: doc, layer: l)),
          _Section(title: tr('Capa', 'Layer'), child: _LayerSection(doc: doc, layer: l)),
          _Section(title: tr('Efectos', 'Effects'), initiallyOpen: l.props.fx.shadow || l.props.fx.glow || l.props.fx.innerGlow || l.props.fx.stroke, child: _FxSection(doc: doc, layer: l)),
        ]);
      },
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.initiallyOpen = true});
  final String title;
  final Widget child;
  final bool initiallyOpen;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        title: Text(title, style: kSmall.copyWith(fontWeight: FontWeight.w600)),
        initiallyExpanded: initiallyOpen,
        dense: true,
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 8),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [child],
      ),
    );
  }
}

/// Keyframe state of [p] on [l] at the current frame.
enum KeyState { none, animated, keyed }

KeyState keyStateOf(Layer l, Prop p, int frame) {
  final t = l.props.tracks[p];
  if (t == null || t.isEmpty) return KeyState.none;
  return t.keyAt(frame) != null ? KeyState.keyed : KeyState.animated;
}

/// Adds a key at the current frame, or removes it when one is already there.
void toggleKey(DocumentController doc, Layer l, Prop p) {
  final f = doc.frame;
  final t = l.props.tracks[p];
  if (t != null && t.keyAt(f) != null) {
    final next = t.withoutKey(f);
    final tracks = {...l.props.tracks};
    if (next.isEmpty) {
      tracks.remove(p);
    } else {
      tracks[p] = next;
    }
    doc.updateProps(tr('Quitar clave', 'Remove key'), l.id, (props) => props.copyWith(tracks: tracks));
  } else {
    doc.setLayerProp(l.id, p, l.props.valueAt(p, f.toDouble()), forceKey: true);
  }
}

class _KeyDiamond extends StatelessWidget {
  const _KeyDiamond({required this.state, required this.onTap, required this.prop});
  final KeyState state;
  final VoidCallback onTap;
  final Prop prop;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final icon = switch (state) {
      KeyState.keyed => Icons.diamond,
      KeyState.animated => Icons.diamond_outlined,
      KeyState.none => Icons.diamond_outlined,
    };
    final color = state == KeyState.none ? context.dim.withValues(alpha: 0.5) : cs.primary;
    return PanelButton(
      key: ValueKey('key-${prop.name}'),
      icon: icon,
      size: 22,
      iconSize: 13,
      color: color,
      tooltip: state == KeyState.keyed ? tr('Quitar clave', 'Remove key') : tr('Añadir clave', 'Add key'),
      onTap: onTap,
    );
  }
}

class _TransformSection extends StatelessWidget {
  const _TransformSection({required this.doc, required this.layer});
  final DocumentController doc;
  final Layer layer;

  Widget _row(BuildContext context, Prop p, String label, {double scale = 1, String? suffix, int decimals = 1, double? min, double? max}) {
    final f = doc.frame;
    final v = layer.props.valueAt(p, f.toDouble());
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        _KeyDiamond(prop: p, state: keyStateOf(layer, p, f), onTap: () => toggleKey(doc, layer, p)),
        const SizedBox(width: 4),
        Expanded(child: Text(label, style: kTiny.copyWith(color: context.dim))),
        NumField(
          key: ValueKey('field-${p.name}-${layer.id}'),
          value: v * scale,
          decimals: decimals,
          suffix: suffix,
          min: min,
          max: max,
          width: 90,
          onSubmitted: (x) => doc.setLayerProp(layer.id, p, x / scale),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      _row(context, Prop.x, tr('Posición X', 'Position X'), suffix: 'px'),
      _row(context, Prop.y, tr('Posición Y', 'Position Y'), suffix: 'px'),
      _row(context, Prop.scaleX, tr('Escala X', 'Scale X'), scale: 100, suffix: '%'),
      _row(context, Prop.scaleY, tr('Escala Y', 'Scale Y'), scale: 100, suffix: '%'),
      _row(context, Prop.rotation, tr('Rotación', 'Rotation'), suffix: '°'),
      _row(context, Prop.anchorX, tr('Ancla X', 'Anchor X'), suffix: 'px'),
      _row(context, Prop.anchorY, tr('Ancla Y', 'Anchor Y'), suffix: 'px'),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          key: const ValueKey('reset-transform'),
          onPressed: () => doc.setLayerProps(
            layer.id,
            {Prop.x: 0, Prop.y: 0, Prop.scaleX: 1, Prop.scaleY: 1, Prop.rotation: 0},
            label: tr('Restablecer transformación', 'Reset transform'),
          ),
          icon: const Icon(Icons.restart_alt, size: 16),
          label: Text(tr('Restablecer', 'Reset'), style: kSmall),
        ),
      ),
    ]);
  }
}

class _LayerSection extends StatelessWidget {
  const _LayerSection({required this.doc, required this.layer});
  final DocumentController doc;
  final Layer layer;

  void _props(String label, LayerProps Function(LayerProps p) f, {String? merge}) => doc.updateProps(label, layer.id, f, mergeKey: merge);

  Widget _toggle(String label, String hint, IconData icon, bool value, LayerProps Function(LayerProps p, bool v) set) => Tooltip(
        message: hint,
        child: MiniToggle(label: label, icon: icon, value: value, onChanged: (v) => _props(hint, (x) => set(x, v))),
      );

  @override
  Widget build(BuildContext context) {
    final p = layer.props;
    final f = doc.frame;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        _KeyDiamond(prop: Prop.opacity, state: keyStateOf(layer, Prop.opacity, f), onTap: () => toggleKey(doc, layer, Prop.opacity)),
        Expanded(
          child: MiniSlider(
            label: tr('Opacidad', 'Opacity'),
            value: p.valueAt(Prop.opacity, f.toDouble()),
            min: 0,
            max: 1,
            display: 100,
            suffix: '%',
            width: double.infinity,
            onChanged: (v) => doc.setLayerProp(layer.id, Prop.opacity, v, mergeKey: 'opacity:${layer.id}'),
          ),
        ),
      ]),
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 6, children: [
        _toggle(tr('Alfa', 'Alpha'), tr('Bloquear transparencia', 'Lock alpha'), Icons.grid_on, p.lockAlpha, (x, v) => x.copyWith(lockAlpha: v)),
        _toggle(tr('Posición', 'Position'), tr('Bloquear posición', 'Lock position'), Icons.open_with, p.lockPosition, (x, v) => x.copyWith(lockPosition: v)),
        _toggle(tr('Recorte', 'Clip'), tr('Recortar a la capa inferior', 'Clip to layer below'), Icons.subdirectory_arrow_right, p.clip, (x, v) => x.copyWith(clip: v)),
        _toggle(tr('Referencia', 'Reference'), tr('Capa de referencia', 'Reference layer'), Icons.push_pin_outlined, p.reference, (x, v) => x.copyWith(reference: v)),
        _toggle(tr('Borrador', 'Draft'), tr('Capa borrador: no se exporta', 'Draft layer: not exported'), Icons.edit_note, p.draft, (x, v) => x.copyWith(draft: v)),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        Tooltip(
          message: tr('La capa sigue la transformación de su padre (esqueleto de recortables)', 'The layer follows its parent transform (cut-out rig)'),
          child: Text(tr('Padre', 'Parent'), style: kTiny.copyWith(color: context.dim)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: MiniDropdown<String>(
            key: const ValueKey('parent'),
            value: p.parentId ?? '',
            width: double.infinity,
            items: [
              ('', tr('Ninguno', 'None')),
              for (final o in walkLayers(doc.comp.layers))
                if (o.id != layer.id) (o.id, o.props.name),
            ],
            onChanged: (id) => doc.parentKeepingPlace(layer.id, id.isEmpty ? null : id),
          ),
        ),
      ]),
      const SizedBox(height: 8),
      Text(tr('Etiqueta de color', 'Colour tag'), style: kTiny.copyWith(color: context.dim)),
      const SizedBox(height: 4),
      Wrap(spacing: 5, children: [
        for (var i = 0; i < kTagColors.length; i++)
          Swatch(
            key: ValueKey('tag-$i'),
            color: kTagColors[i],
            selected: p.colorTag == kTagColors[i].toARGB32(),
            tooltip: i == 0 ? tr('Sin etiqueta', 'No tag') : null,
            onTap: () => _props(tr('Etiqueta de color', 'Colour tag'), (x) => x.copyWith(colorTag: kTagColors[i].toARGB32())),
          ),
      ]),
    ]);
  }
}

class _FxSection extends StatelessWidget {
  const _FxSection({required this.doc, required this.layer});
  final DocumentController doc;
  final Layer layer;

  void _fx(LayerFx Function(LayerFx f) f, {bool merge = true}) =>
      doc.updateProps(tr('Efectos de capa', 'Layer effects'), layer.id, (p) => p.copyWith(fx: f(p.fx)), mergeKey: merge ? 'fx:${layer.id}' : null);

  Widget _slider(String label, double v, double min, double max, void Function(double) set, {String suffix = '', double? display, int decimals = 0}) =>
      MiniSlider(label: label, value: v, min: min, max: max, suffix: suffix, display: display, decimals: decimals, width: double.infinity, onChanged: set);

  Widget _color(BuildContext context, String id, Color c, void Function(Color) set) {
    return Builder(
      builder: (context) => Swatch(
        key: ValueKey('fxcolor-$id'),
        color: c,
        tooltip: tr('Color', 'Colour'),
        onTap: () async {
          final box = context.findRenderObject() as RenderBox?;
          final pos = box?.localToGlobal(Offset.zero) ?? Offset.zero;
          final picked = await showMenu<Color>(
            context: context,
            position: RelativeRect.fromLTRB(pos.dx, pos.dy + 22, pos.dx + 1, pos.dy + 23),
            items: [
              PopupMenuItem<Color>(
                enabled: false,
                child: Wrap(spacing: 4, runSpacing: 4, children: [
                  for (final k in kFxColors) Swatch(color: k, size: 22, onTap: () => Navigator.pop(context, k)),
                ]),
              ),
            ],
          );
          if (picked != null) set(picked);
        },
      ),
    );
  }

  Widget _header(BuildContext context, String id, String label, bool on, void Function(bool) set, {Color? color, void Function(Color)? setColor}) {
    return Row(children: [
      SizedBox(
        height: 28,
        child: Checkbox(key: ValueKey('fx-$id'), value: on, onChanged: (v) => set(v ?? false), visualDensity: VisualDensity.compact),
      ),
      Expanded(child: Text(label, style: kSmall)),
      if (color != null && setColor != null) _color(context, id, color, setColor),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final fx = layer.props.fx;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _header(context, 'shadow', tr('Sombra', 'Drop shadow'), fx.shadow, (v) => _fx((f) => f.copyWith(shadow: v), merge: false),
          color: fx.shadowColor, setColor: (c) => _fx((f) => f.copyWith(shadowColor: c), merge: false)),
      if (fx.shadow) ...[
        _slider(tr('Desplaz. X', 'Offset X'), fx.shadowDx, -100, 100, (v) => _fx((f) => f.copyWith(shadowDx: v)), suffix: 'px'),
        _slider(tr('Desplaz. Y', 'Offset Y'), fx.shadowDy, -100, 100, (v) => _fx((f) => f.copyWith(shadowDy: v)), suffix: 'px'),
        _slider(tr('Desenfoque', 'Blur'), fx.shadowBlur, 0, 100, (v) => _fx((f) => f.copyWith(shadowBlur: v)), suffix: 'px'),
        _slider(tr('Opacidad', 'Opacity'), fx.shadowOpacity, 0, 1, (v) => _fx((f) => f.copyWith(shadowOpacity: v)), display: 100, suffix: '%'),
      ],
      _header(context, 'glow', tr('Resplandor exterior', 'Outer glow'), fx.glow, (v) => _fx((f) => f.copyWith(glow: v), merge: false),
          color: fx.glowColor, setColor: (c) => _fx((f) => f.copyWith(glowColor: c), merge: false)),
      if (fx.glow) ...[
        _slider(tr('Desenfoque', 'Blur'), fx.glowBlur, 0, 100, (v) => _fx((f) => f.copyWith(glowBlur: v)), suffix: 'px'),
        _slider(tr('Opacidad', 'Opacity'), fx.glowOpacity, 0, 1, (v) => _fx((f) => f.copyWith(glowOpacity: v)), display: 100, suffix: '%'),
      ],
      _header(context, 'innerGlow', tr('Resplandor interior', 'Inner glow'), fx.innerGlow, (v) => _fx((f) => f.copyWith(innerGlow: v), merge: false)),
      _header(context, 'stroke', tr('Trazo', 'Stroke'), fx.stroke, (v) => _fx((f) => f.copyWith(stroke: v), merge: false),
          color: fx.strokeColor, setColor: (c) => _fx((f) => f.copyWith(strokeColor: c), merge: false)),
      if (fx.stroke) ...[
        _slider(tr('Ancho', 'Width'), fx.strokeWidth, 0.5, 50, (v) => _fx((f) => f.copyWith(strokeWidth: v)), suffix: 'px', decimals: 1),
        _slider(tr('Opacidad', 'Opacity'), fx.strokeOpacity, 0, 1, (v) => _fx((f) => f.copyWith(strokeOpacity: v)), display: 100, suffix: '%'),
      ],
    ]);
  }
}
