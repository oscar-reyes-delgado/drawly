import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/doc_layers.dart';
import '../../app/document_controller.dart';
import '../../core/i18n.dart';
import '../../engine/tiles.dart';
import '../../model/layer.dart';
import '../dialogs/prompts.dart';
import '../theme.dart';

/// True for layers fully editable in the easy mode: top-level PaintLayer without
/// mask, effects, rig or parent, normal blend.
bool isEasyEditable(Layer l) =>
    l is PaintLayer &&
    l.props.mask == null &&
    !l.props.fx.any &&
    (l.rig == null || l.rig!.isEmpty) &&
    l.props.parentId == null &&
    l.props.blend == LayerBlend.normal;

/// Simple layer list for beginners: big rows, thumbnail, eye, lock, opacity.
/// Layers the easy mode cannot edit (text, vector, groups, effects…) are listed
/// with a badge and only their visibility can be changed here.
class EasyLayers extends StatelessWidget {
  const EasyLayers({super.key, required this.doc});

  final DocumentController doc;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([doc, doc.frameSignal]),
      builder: (context, _) {
        final topLayers = doc.comp.layers;
        final rows = topLayers.reversed.toList();
        final active = doc.activeLayer;
        final activeTopIdx = active == null ? -1 : topLayers.indexWhere((l) => l.id == active.id);
        final activeEditable = active != null && activeTopIdx >= 0 && isEasyEditable(active);
        final canMergeDown = activeEditable && activeTopIdx > 0 && isEasyEditable(topLayers[activeTopIdx - 1]);
        final canDelete = active != null && topLayers.length > 1;

        return ColoredBox(
          color: context.panel,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: rows.isEmpty
                    ? Center(
                        child: Text(
                          tr('Sin capas', 'No layers'),
                          style: TextStyle(fontSize: 13, color: context.dim),
                        ),
                      )
                    : ReorderableListView.builder(
                        buildDefaultDragHandles: false,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemExtent: 56,
                        itemCount: rows.length,
                        onReorderItem: (oldIndex, newIndex) {
                          if (newIndex == oldIndex) return;
                          final moved = rows[oldIndex];
                          final without = [...rows]..removeAt(oldIndex);
                          if (newIndex == 0) {
                            doc.moveLayer(moved.id, aboveId: without.first.id);
                          } else {
                            doc.moveLayer(moved.id, belowId: without[newIndex - 1].id);
                          }
                        },
                        itemBuilder: (context, index) {
                          final layer = rows[index];
                          return _EasyLayerRow(
                            key: ValueKey('easy.layer.${layer.id}'),
                            doc: doc,
                            layer: layer,
                            index: index,
                            active: doc.activeLayerId == layer.id,
                          );
                        },
                      ),
              ),
              Divider(color: context.line, height: 1),
              if (active != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Text(
                            tr('Opacidad', 'Opacity'),
                            style: TextStyle(fontSize: 13, color: activeEditable ? context.cs.onSurface : context.dim),
                          ),
                          const Spacer(),
                          Text(
                            '${(active.props.opacity * 100).round()}%',
                            style: TextStyle(fontSize: 13, color: activeEditable ? context.cs.onSurface : context.dim),
                          ),
                        ],
                      ),
                      SizedBox(
                        height: 44,
                        child: Slider(
                          key: const Key('easy.layers.opacity'),
                          value: (active.props.opacity * 100).clamp(0.0, 100.0),
                          min: 0,
                          max: 100,
                          onChanged: activeEditable
                              ? (v) => doc.updateProps(
                                    tr('Opacidad', 'Opacity'),
                                    active.id,
                                    (p) => p.copyWith(opacity: v / 100),
                                    mergeKey: 'opacity:${active.id}',
                                  )
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _BarButton(
                      key: const Key('easy.layers.add'),
                      icon: Icons.add,
                      tooltip: tr('Nueva capa. Añade una capa de dibujo encima.', 'New layer. Adds a drawing layer on top.'),
                      onTap: () => doc.addPaintLayer(name: doc.uniqueLayerName(tr('Capa', 'Layer'))),
                    ),
                    _BarButton(
                      key: const Key('easy.layers.duplicate'),
                      icon: Icons.copy_outlined,
                      tooltip: tr('Duplicar capa. Crea una copia de la capa activa.', 'Duplicate layer. Creates a copy of the active layer.'),
                      onTap: active != null ? () => doc.duplicateActiveLayer() : null,
                    ),
                    _BarButton(
                      key: const Key('easy.layers.mergeDown'),
                      icon: Icons.merge_type,
                      tooltip: tr('Fusionar abajo. Une esta capa con la inferior.', 'Merge down. Combines this layer with the one below.'),
                      onTap: canMergeDown ? () => doc.mergeDown() : null,
                    ),
                    _BarButton(
                      key: const Key('easy.layers.delete'),
                      icon: Icons.delete_outline,
                      tooltip: tr('Eliminar capa. Borra la capa seleccionada.', 'Delete layer. Removes the selected layer.'),
                      onTap: canDelete ? () => _confirmDelete(context, active) : null,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmDelete(BuildContext context, Layer layer) async {
    final ok = await confirmDialog(
      context,
      title: tr('Eliminar capa', 'Delete layer'),
      message: tr('¿Eliminar la capa "${layer.name}"?', 'Delete layer "${layer.name}"?'),
      ok: tr('Eliminar', 'Delete'),
      danger: true,
    );
    if (ok) {
      doc.selectLayer(layer.id);
      doc.deleteSelectedLayers();
    }
  }
}

class _EasyLayerRow extends StatelessWidget {
  const _EasyLayerRow({
    super.key,
    required this.doc,
    required this.layer,
    required this.index,
    required this.active,
  });

  final DocumentController doc;
  final Layer layer;
  final int index;
  final bool active;

  Future<void> _rename(BuildContext context) async {
    final name = await promptText(
      context,
      title: tr('Renombrar capa', 'Rename layer'),
      initial: layer.name,
      label: tr('Nombre', 'Name'),
    );
    if (name == null) return;
    final trimmed = name.trim();
    if (trimmed.isNotEmpty && trimmed != layer.name) {
      doc.updateProps(tr('Renombrar capa', 'Rename layer'), layer.id, (p) => p.copyWith(name: trimmed));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final editable = isEasyEditable(layer);
    final props = layer.props;
    final plane = layer is PaintLayer ? (layer as PaintLayer).cels.at(doc.frame) : null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Material(
        color: active ? cs.primary.withValues(alpha: 0.18) : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: active ? cs.primary : context.line),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => doc.selectLayer(layer.id),
          child: SizedBox(
            height: 52,
            child: Row(
              children: [
                const SizedBox(width: 6),
                Container(
                  width: 48,
                  height: 36,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: context.line),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: layer is PaintLayer
                      ? CustomPaint(
                          key: Key('easy.layer.thumb.${layer.id}'),
                          size: const Size(48, 36),
                          painter: _LayerThumbPainter(plane, doc.comp.size),
                        )
                      : Center(
                          child: Icon(
                            _layerIcon(layer),
                            key: Key('easy.layer.thumb.${layer.id}'),
                            size: 24,
                            color: context.dim,
                          ),
                        ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onDoubleTap: editable ? () => _rename(context) : null,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        layer.name,
                        key: Key('easy.layer.name.${layer.id}'),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                          color: props.visible ? cs.onSurface : context.dim,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ),
                ),
                if (!editable)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Tooltip(
                      message: tr('Capa avanzada: edítala en el Modo Avanzado', 'Advanced layer: edit it in Advanced mode'),
                      child: Icon(
                        Icons.auto_awesome,
                        key: Key('easy.layer.badge.${layer.id}'),
                        size: 18,
                        color: context.dim,
                      ),
                    ),
                  ),
                _RowIconButton(
                  key: Key('easy.layer.visibility.${layer.id}'),
                  icon: props.visible ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  color: props.visible ? cs.onSurface : context.dim,
                  tooltip: props.visible ? tr('Ocultar capa', 'Hide layer') : tr('Mostrar capa', 'Show layer'),
                  onTap: () => doc.updateProps(
                    tr('Visibilidad de capa', 'Layer visibility'),
                    layer.id,
                    (p) => p.copyWith(visible: !p.visible),
                  ),
                ),
                _RowIconButton(
                  key: Key('easy.layer.lock.${layer.id}'),
                  icon: props.locked ? Icons.lock_outline : Icons.lock_open,
                  color: !editable ? context.dim.withValues(alpha: 0.4) : (props.locked ? cs.primary : context.dim),
                  tooltip: props.locked ? tr('Desbloquear capa', 'Unlock layer') : tr('Bloquear capa', 'Lock layer'),
                  onTap: editable
                      ? () => doc.updateProps(
                            tr('Bloqueo de capa', 'Layer lock'),
                            layer.id,
                            (p) => p.copyWith(locked: !p.locked),
                          )
                      : null,
                ),
                ReorderableDragStartListener(
                  index: index,
                  child: Tooltip(
                    message: tr('Arrastrar para reordenar', 'Drag to reorder'),
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: Center(
                        child: Icon(
                          Icons.drag_handle,
                          key: Key('easy.layer.drag.${layer.id}'),
                          size: 24,
                          color: context.dim,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RowIconButton extends StatelessWidget {
  const _RowIconButton({
    super.key,
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(child: Icon(icon, size: 24, color: color)),
        ),
      ),
    );
  }
}

class _BarButton extends StatelessWidget {
  const _BarButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final cs = context.cs;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: enabled ? context.line : context.line.withValues(alpha: 0.4)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(
              child: Icon(
                icon,
                size: 24,
                color: enabled ? cs.onSurface : context.dim.withValues(alpha: 0.4),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LayerThumbPainter extends CustomPainter {
  const _LayerThumbPainter(this.plane, this.compSize);

  final TilePlane? plane;
  final Size compSize;

  @override
  void paint(Canvas canvas, Size size) {
    const cell = 6.0;
    final light = Paint()..color = const Color(0xFFE8E8E8);
    final dark = Paint()..color = const Color(0xFFCFCFCF);
    canvas.drawRect(Offset.zero & size, light);
    for (var y = 0; y * cell < size.height; y++) {
      for (var x = y.isEven ? 1 : 0; x * cell < size.width; x += 2) {
        canvas.drawRect(Rect.fromLTWH(x * cell, y * cell, cell, cell).intersect(Offset.zero & size), dark);
      }
    }

    final p = plane;
    if (p == null || p.isEmpty) return;

    final cw = compSize.width <= 0 ? 1.0 : compSize.width;
    final ch = compSize.height <= 0 ? 1.0 : compSize.height;
    final scale = math.min(size.width / cw, size.height / ch);
    final dx = (size.width - cw * scale) / 2;
    final dy = (size.height - ch * scale) / 2;

    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate(dx, dy);
    canvas.scale(scale, scale);
    p.paint(canvas, cull: Rect.fromLTWH(0, 0, cw, ch), paint: TilePlane.paintFor(FilterQuality.low));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LayerThumbPainter old) => !identical(old.plane, plane) || old.compSize != compSize;
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
