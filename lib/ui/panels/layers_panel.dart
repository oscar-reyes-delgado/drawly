import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/doc_layers.dart';
import '../../app/document_controller.dart';
import '../../core/i18n.dart';
import '../../model/layer.dart';
import '../theme.dart';
import '../widgets.dart';

/// Layer list of the active composition (top layer first) with a toolbar.
class LayersPanel extends StatelessWidget {
  const LayersPanel({super.key, required this.doc, required this.onCommand});

  final DocumentController doc;

  /// Runs a command by id (the app passes `AppState.I.commands.run`).
  final void Function(String commandId) onCommand;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: doc,
        builder: (context, _) {
          final rows = _visibleLayers(doc.comp.layers).toList();
          final indices = {for (var i = 0; i < rows.length; i++) ValueKey('${doc.uid}:${doc.compId}:${rows[i].layer.id}'): i};
          final active = doc.activeLayer;
          return ColoredBox(
            color: context.panel,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: const EdgeInsets.all(4),
                child: Wrap(spacing: 2, children: [
                  _command('layer.newPaint', Icons.add, tr('Nueva capa', 'New layer')),
                  _command('layer.newVector', Icons.polyline_outlined, tr('Nueva capa vectorial', 'New vector layer')),
                  _command('layer.newGroup', Icons.create_new_folder_outlined, tr('Nuevo grupo', 'New group')),
                  _command('layer.duplicate', Icons.copy_outlined, tr('Duplicar capa', 'Duplicate layer')),
                  _command('layer.delete', Icons.delete_outline, tr('Eliminar capa', 'Delete layer')),
                  _command('layer.mergeDown', Icons.merge_type, tr('Fusionar hacia abajo', 'Merge down')),
                ]),
              ),
              const Divider(height: 1),
              Expanded(
                child: rows.isEmpty
                    ? Center(child: Text(tr('Sin capas', 'No layers'), style: kSmall.copyWith(color: context.dim)))
                    : ListView.builder(
                        key: PageStorageKey('layers:${doc.uid}:${doc.compId}'),
                        padding: EdgeInsets.zero,
                        itemExtent: 36,
                        itemCount: rows.length,
                        findChildIndexCallback: (key) => indices[key],
                        itemBuilder: (_, index) {
                          final row = rows[index];
                          return _LayerRow(
                            key: ValueKey('${doc.uid}:${doc.compId}:${row.layer.id}'),
                            doc: doc,
                            layer: row.layer,
                            depth: row.depth,
                          );
                        },
                      ),
              ),
              if (active != null) ...[
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    MiniDropdown<LayerBlend>(
                      key: const ValueKey('layer-blend'),
                      value: active.props.blend,
                      items: [for (final blend in LayerBlend.values) (blend, blend.label)],
                      width: double.infinity,
                      tooltip: tr('Modo de fusión', 'Blend mode'),
                      onChanged: (blend) => doc.updateProps(tr('Modo de fusión', 'Blend mode'), active.id, (p) => p.copyWith(blend: blend)),
                    ),
                    const SizedBox(height: 4),
                    MiniSlider(
                      key: const ValueKey('layer-opacity'),
                      label: tr('Opacidad', 'Opacity'),
                      value: active.props.opacity * 100,
                      min: 0,
                      max: 100,
                      suffix: '%',
                      width: double.infinity,
                      onChanged: (value) => doc.updateProps(
                        tr('Opacidad', 'Opacity'), active.id, (p) => p.copyWith(opacity: value / 100), mergeKey: 'opacity:${active.id}',
                      ),
                    ),
                  ]),
                ),
              ],
            ]),
          );
        },
      );

  Widget _command(String id, IconData icon, String label) => PanelButton(key: ValueKey(id), icon: icon, tooltip: label, onTap: () => onCommand(id));
}

// Reverse siblings independently so each group remains above its children.
Iterable<({Layer layer, int depth})> _visibleLayers(List<Layer> layers, [int depth = 0]) sync* {
  for (final layer in layers.reversed) {
    yield (layer: layer, depth: depth);
    if (layer is GroupLayer && !layer.props.collapsed) yield* _visibleLayers(layer.children, depth + 1);
  }
}

IconData _layerIcon(Layer layer) => switch (layer) {
      PaintLayer() => Icons.brush_outlined,
      VectorLayer() => Icons.polyline_outlined,
      TextLayer() => Icons.text_fields,
      GroupLayer() => Icons.folder_outlined,
      AdjustLayer() => Icons.tune,
      InstanceLayer() => Icons.widgets_outlined,
      ParticleLayer() => Icons.auto_awesome,
    };

enum _DropZone { above, below, into }

class _LayerDrag {
  const _LayerDrag(this.doc, this.compId, this.id);
  final DocumentController doc;
  final String compId, id;
}

class _LayerRow extends StatefulWidget {
  const _LayerRow({super.key, required this.doc, required this.layer, required this.depth});
  final DocumentController doc;
  final Layer layer;
  final int depth;

  @override
  State<_LayerRow> createState() => _LayerRowState();
}

class _LayerRowState extends State<_LayerRow> {
  final TextEditingController _name = TextEditingController();
  late final FocusNode _nameFocus = FocusNode()..addListener(_onFocusChanged);
  bool _editing = false;
  bool _additive = false;
  _DropZone? _dropZone;

  void _onFocusChanged() {
    if (!_nameFocus.hasFocus && _editing) _finishRename();
  }

  void _beginRename() {
    widget.doc.selectLayer(widget.layer.id);
    _name.value = TextEditingValue(text: widget.layer.name, selection: TextSelection(baseOffset: 0, extentOffset: widget.layer.name.length));
    setState(() => _editing = true);
  }

  void _finishRename({bool cancel = false}) {
    if (!_editing) return;
    final name = _name.text.trim();
    setState(() => _editing = false);
    _nameFocus.unfocus();
    if (!cancel && name.isNotEmpty && name != widget.layer.name) {
      widget.doc.updateProps(tr('Renombrar capa', 'Rename layer'), widget.layer.id, (p) => p.copyWith(name: name));
    }
  }

  void _select() => widget.doc.selectLayer(widget.layer.id, additive: _additive);

  bool _canDrop(_LayerDrag data) {
    if (_editing || !identical(data.doc, widget.doc) || data.compId != widget.doc.compId || data.id == widget.layer.id) return false;
    final source = widget.doc.comp.layer(data.id);
    return source != null && !(source is GroupLayer && walkLayers(source.children).any((child) => child.id == widget.layer.id));
  }

  _DropZone _zoneAt(Offset offset) {
    final box = context.findRenderObject()! as RenderBox;
    final y = box.globalToLocal(offset).dy;
    if (widget.layer is GroupLayer && y >= 9 && y < 27) return _DropZone.into;
    return y < 18 ? _DropZone.above : _DropZone.below;
  }

  void _hover(DragTargetDetails<_LayerDrag> details) {
    if (!_canDrop(details.data)) return;
    final zone = _zoneAt(details.offset);
    if (_dropZone != zone) setState(() => _dropZone = zone);
  }

  void _drop(DragTargetDetails<_LayerDrag> details) {
    if (!_canDrop(details.data)) return;
    final zone = _zoneAt(details.offset);
    setState(() => _dropZone = null);
    widget.doc.moveLayer(
      details.data.id,
      aboveId: zone == _DropZone.above ? widget.layer.id : null,
      belowId: zone == _DropZone.below ? widget.layer.id : null,
      intoGroup: zone == _DropZone.into ? widget.layer.id : null,
    );
  }

  @override
  void dispose() {
    _nameFocus.removeListener(_onFocusChanged);
    _nameFocus.dispose();
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final layer = widget.layer;
    final props = layer.props;
    final active = widget.doc.activeLayerId == layer.id;
    final selected = widget.doc.selectedLayers.contains(layer.id);
    final cs = context.cs;
    final child = Semantics(
      key: ValueKey('layer-selection:${layer.id}'),
      selected: active || selected,
      child: Container(
        key: ValueKey('layer-row:${layer.id}'),
        height: 36,
        decoration: BoxDecoration(
          color: _dropZone == _DropZone.into ? cs.primary.withValues(alpha: 0.28) : (active ? cs.primary.withValues(alpha: 0.2) : (selected ? cs.primary.withValues(alpha: 0.1) : Colors.transparent)),
          border: Border(
            left: BorderSide(color: active ? cs.primary : Colors.transparent, width: 2),
            top: BorderSide(color: _dropZone == _DropZone.above ? cs.primary : Colors.transparent, width: 2),
            bottom: BorderSide(color: _dropZone == _DropZone.below ? cs.primary : context.line, width: 1),
          ),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            canRequestFocus: false,
            onTap: _select,
            child: Row(children: [
              PanelButton(
                key: ValueKey('layer-visibility:${layer.id}'),
                icon: props.visible ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                color: props.visible ? null : context.dim,
                tooltip: props.visible ? tr('Ocultar capa', 'Hide layer') : tr('Mostrar capa', 'Show layer'),
                onTap: () => widget.doc.updateProps(tr('Visibilidad de capa', 'Layer visibility'), layer.id, (p) => p.copyWith(visible: !p.visible)),
              ),
              PanelButton(
                key: ValueKey('layer-lock:${layer.id}'),
                icon: props.locked ? Icons.lock_outline : Icons.lock_open,
                color: props.locked ? cs.primary : context.dim,
                tooltip: props.locked ? tr('Desbloquear capa', 'Unlock layer') : tr('Bloquear capa', 'Lock layer'),
                onTap: () => widget.doc.updateProps(tr('Bloqueo de capa', 'Layer lock'), layer.id, (p) => p.copyWith(locked: !p.locked)),
              ),
              SizedBox(width: widget.depth * 16),
              if (layer is GroupLayer)
                PanelButton(
                  key: ValueKey('layer-collapse:${layer.id}'),
                  icon: props.collapsed ? Icons.chevron_right : Icons.expand_more,
                  tooltip: props.collapsed ? tr('Expandir grupo', 'Expand group') : tr('Contraer grupo', 'Collapse group'),
                  size: 20,
                  iconSize: 16,
                  onTap: () => widget.doc.updateProps(tr('Desplegar grupo', 'Toggle group'), layer.id, (p) => p.copyWith(collapsed: !p.collapsed)),
                )
              else
                const SizedBox(width: 20),
              Tooltip(message: layer.typeLabel, child: Icon(_layerIcon(layer), key: ValueKey('layer-type:${layer.id}'), size: 16, color: context.dim)),
              const SizedBox(width: 6),
              Expanded(
                child: _editing
                    ? Focus(
                        onKeyEvent: (_, event) {
                          if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
                            _finishRename(cancel: true);
                            return KeyEventResult.handled;
                          }
                          return KeyEventResult.ignored;
                        },
                        child: TextField(
                          key: ValueKey('layer-name-editor:${layer.id}'),
                          controller: _name,
                          focusNode: _nameFocus,
                          autofocus: true,
                          style: kSmall,
                          textInputAction: TextInputAction.done,
                          decoration: InputDecoration(contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5), hintText: tr('Nombre de capa', 'Layer name')),
                          onSubmitted: (_) => _finishRename(),
                          onTapOutside: (_) => _finishRename(),
                        ),
                      )
                    : GestureDetector(
                        onDoubleTap: _beginRename,
                        child: Text(layer.name, key: ValueKey('layer-name:${layer.id}'), style: kSmall, overflow: TextOverflow.ellipsis, maxLines: 1),
                      ),
              ),
              if (props.mask != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Tooltip(
                    message: props.maskEnabled ? tr('Máscara de capa', 'Layer mask') : tr('Máscara desactivada', 'Mask disabled'),
                    child: Icon(Icons.circle_outlined, key: ValueKey('layer-mask:${layer.id}'), size: 15, color: props.maskEnabled ? cs.onSurface : context.dim),
                  ),
                ),
              if (props.colorTag != 0)
                Padding(
                  padding: const EdgeInsets.only(left: 2, right: 6),
                  child: Swatch(key: ValueKey('layer-color:${layer.id}'), color: Color(props.colorTag), size: 10, radius: 2, tooltip: tr('Etiqueta de color', 'Colour tag')),
                )
              else
                const SizedBox(width: 6),
            ]),
          ),
        ),
      ),
    );
    final data = _LayerDrag(widget.doc, widget.doc.compId, layer.id);
    final feedback = Material(
      color: context.panel,
      elevation: 6,
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: 220,
        height: 36,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(children: [Icon(_layerIcon(layer), size: 16), const SizedBox(width: 6), Expanded(child: Text(layer.name, style: kSmall, maxLines: 1, overflow: TextOverflow.ellipsis))]),
        ),
      ),
    );
    final touch = switch (Theme.of(context).platform) {
      TargetPlatform.android || TargetPlatform.iOS || TargetPlatform.fuchsia => true,
      _ => false,
    };
    return Listener(
      onPointerDown: (_) => _additive = HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isShiftPressed,
      child: DragTarget<_LayerDrag>(
        onWillAcceptWithDetails: (details) => _canDrop(details.data),
        onMove: _hover,
        onLeave: (_) { if (mounted && _dropZone != null) setState(() => _dropZone = null); },
        onAcceptWithDetails: _drop,
        builder: (_, _, _) {
          if (_editing) return child;
          // Keep vertical scrolling available on touch screens until a long press.
          if (touch) {
            return LongPressDraggable<_LayerDrag>(data: data, dragAnchorStrategy: pointerDragAnchorStrategy, feedback: feedback, maxSimultaneousDrags: 1, child: child);
          }
          return Draggable<_LayerDrag>(data: data, dragAnchorStrategy: pointerDragAnchorStrategy, feedback: feedback, maxSimultaneousDrags: 1, child: child);
        },
      ),
    );
  }
}
