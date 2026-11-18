import 'dart:ui';

import '../core/i18n.dart';
import '../core/ids.dart';
import '../core/mat2d.dart';
import '../engine/compositor.dart';
import '../engine/text_render.dart';
import '../engine/tiles.dart';
import '../model/document.dart';
import '../model/filter_spec.dart';
import '../model/layer.dart';
import '../model/specs.dart';
import '../model/vector.dart';
import 'document_controller.dart';

/// Layer stack operations.
extension DocLayers on DocumentController {
  String uniqueLayerName(String base) {
    final names = {for (final l in walkLayers(comp.layers)) l.name};
    var i = 1;
    while (names.contains('$base $i')) {
      i++;
    }
    return '$base $i';
  }

  Xform get _centerAnchor => Xform(ax: comp.width / 2, ay: comp.height / 2);

  /// Inserts [layer] above the active layer (or inside the active group)
  /// and makes it active.
  void addLayer(Layer layer, {String? label}) {
    final active = activeLayer;
    final List<Layer> next;
    if (active is GroupLayer && !active.props.collapsed) {
      next = insertLayer(comp.layers, layer, intoGroup: active.id);
    } else {
      next = insertLayer(comp.layers, layer, aboveId: active?.id);
    }
    activeLayerId = layer.id;
    selectedLayers = {layer.id};
    editMask = false;
    applyComp(label ?? tr('Nueva capa', 'New layer'), (c) => c.copyWith(layers: next));
  }

  void addPaintLayer({String? name, TilePlane? pixels}) {
    final l = PaintLayer.create(name ?? uniqueLayerName(tr('Capa', 'Layer')), pixels: pixels);
    addLayer(l.withProps(l.props.copyWith(xf: _centerAnchor)));
  }

  void addVectorLayer() {
    final l = VectorLayer.create(uniqueLayerName(tr('Vector', 'Vector')));
    addLayer(l.withProps(l.props.copyWith(xf: _centerAnchor)), label: tr('Nueva capa vectorial', 'New vector layer'));
  }

  void addGroupLayer() {
    addLayer(GroupLayer(newId('L'), LayerProps(name: uniqueLayerName(tr('Grupo', 'Group')), xf: _centerAnchor), const []),
        label: tr('Nuevo grupo', 'New group'));
  }

  void addAdjustLayer(FilterSpec spec) {
    addLayer(AdjustLayer(newId('L'), LayerProps(name: spec.def.label), spec), label: tr('Nueva capa de ajuste', 'New adjustment layer'));
  }

  void addTextLayer(TextSpec spec) {
    final name = spec.text.trim().isEmpty ? tr('Texto', 'Text') : spec.text.trim().split('\n').first;
    final b = TextRender.bounds(spec);
    addLayer(
      TextLayer(newId('L'), LayerProps(name: name.length > 24 ? '${name.substring(0, 24)}…' : name, xf: Xform(ax: b.center.dx, ay: b.center.dy)), spec),
      label: tr('Nuevo texto', 'New text'),
    );
  }

  void addParticleLayer(ParticlePreset preset) {
    addLayer(
      ParticleLayer(newId('L'), LayerProps(name: preset.label, xf: _centerAnchor), ParticleSpec.preset(preset, comp.size)),
      label: tr('Nuevas partículas', 'New particles'),
    );
  }

  void addInstanceLayer(String compId) {
    final sub = project.comps[compId];
    if (sub == null || sub.id == this.compId || compStack.contains(compId)) return;
    addLayer(
      InstanceLayer(newId('L'), LayerProps(name: sub.name, xf: Xform(ax: sub.width / 2, ay: sub.height / 2)), compId),
      label: tr('Insertar símbolo', 'Insert symbol'),
    );
  }

  void deleteSelectedLayers() {
    final ids = selectedLayers.isEmpty ? {?activeLayerId} : selectedLayers;
    if (ids.isEmpty) return;
    var layers = comp.layers;
    for (final id in ids) {
      layers = removeLayer(layers, id);
    }
    // children of removed parents lose their parent link
    layers = mapAllLayers(layers, (l) => ids.contains(l.props.parentId) ? l.withProps(l.props.copyWith(parentId: null)) : l);
    applyComp(tr('Eliminar capa', 'Delete layer'), (c) => c.copyWith(layers: layers));
  }

  void duplicateActiveLayer() {
    final l = activeLayer;
    if (l == null) return;
    final copy = cloneLayer(l, name: '${l.name} ${tr('copia', 'copy')}');
    final next = insertLayer(comp.layers, copy, aboveId: l.id);
    activeLayerId = copy.id;
    selectedLayers = {copy.id};
    applyComp(tr('Duplicar capa', 'Duplicate layer'), (c) => c.copyWith(layers: next));
  }

  /// Moves a layer to sit directly above [aboveId], below [belowId], or
  /// into the group [intoGroup] (as its top child).
  void moveLayer(String id, {String? aboveId, String? belowId, String? intoGroup}) {
    final layer = comp.layer(id);
    if (layer == null) return;
    // never drop a group into itself
    if (layer is GroupLayer) {
      final inside = {for (final l in walkLayers(layer.children)) l.id, layer.id};
      if (inside.contains(aboveId) || inside.contains(belowId) || inside.contains(intoGroup)) return;
    }
    var layers = removeLayer(comp.layers, id);
    if (intoGroup != null) {
      layers = insertLayer(layers, layer, intoGroup: intoGroup);
    } else if (aboveId != null) {
      layers = insertLayer(layers, layer, aboveId: aboveId);
    } else if (belowId != null) {
      List<Layer> rec(List<Layer> list) {
        final i = list.indexWhere((l) => l.id == belowId);
        if (i >= 0) return [...list.sublist(0, i), layer, ...list.sublist(i)];
        return [
          for (final l in list)
            if (l is GroupLayer) l.withChildren(rec(l.children)) else l,
        ];
      }

      layers = rec(layers);
    } else {
      layers = [...layers, layer];
    }
    applyComp(tr('Reordenar capas', 'Reorder layers'), (c) => c.copyWith(layers: layers));
  }

  /// Raises (+1) or lowers (-1) the active layer among its siblings.
  void shiftActiveLayer(int delta) {
    final id = activeLayerId;
    if (id == null) return;
    List<Layer> rec(List<Layer> list) {
      final i = list.indexWhere((l) => l.id == id);
      if (i >= 0) {
        final j = (i + delta).clamp(0, list.length - 1);
        if (j == i) return list;
        final out = [...list];
        final l = out.removeAt(i);
        out.insert(j, l);
        return out;
      }
      var changed = false;
      final out = <Layer>[];
      for (final l in list) {
        if (l is GroupLayer) {
          final c = rec(l.children);
          changed = changed || !identical(c, l.children);
          out.add(identical(c, l.children) ? l : l.withChildren(c));
        } else {
          out.add(l);
        }
      }
      return changed ? out : list;
    }

    final next = rec(comp.layers);
    if (identical(next, comp.layers)) return;
    applyComp(tr('Reordenar capas', 'Reorder layers'), (c) => c.copyWith(layers: next));
  }

  void groupSelected() {
    final ids = selectedLayers.isEmpty ? {?activeLayerId} : selectedLayers;
    if (ids.isEmpty) return;
    final members = [
      for (final l in walkLayers(comp.layers))
        if (ids.contains(l.id) && !ids.contains(parentGroupOf(comp.layers, l.id)?.id)) l,
    ];
    if (members.isEmpty) return;
    final top = members.last;
    final group = GroupLayer(newId('L'), LayerProps(name: uniqueLayerName(tr('Grupo', 'Group')), xf: _centerAnchor), members);
    var layers = insertLayer(comp.layers, group, aboveId: top.id);
    for (final m in members) {
      // remove the originals (the group holds the same objects, so remove by position outside the group)
      layers = _removeOutside(layers, m.id, group.id);
    }
    activeLayerId = group.id;
    selectedLayers = {group.id};
    applyComp(tr('Agrupar capas', 'Group layers'), (c) => c.copyWith(layers: layers));
  }

  List<Layer> _removeOutside(List<Layer> layers, String id, String keepInsideGroup) {
    final out = <Layer>[];
    for (final l in layers) {
      if (l.id == keepInsideGroup) {
        out.add(l);
      } else if (l.id == id) {
        continue;
      } else if (l is GroupLayer) {
        out.add(l.withChildren(_removeOutside(l.children, id, keepInsideGroup)));
      } else {
        out.add(l);
      }
    }
    return out;
  }

  void ungroupActive() {
    final g = activeLayer;
    if (g is! GroupLayer) return;
    List<Layer> rec(List<Layer> list) {
      final i = list.indexWhere((l) => l.id == g.id);
      if (i >= 0) return [...list.sublist(0, i), ...g.children, ...list.sublist(i + 1)];
      return [
        for (final l in list)
          if (l is GroupLayer) l.withChildren(rec(l.children)) else l,
      ];
    }

    final next = rec(comp.layers);
    activeLayerId = g.children.isEmpty ? null : g.children.last.id;
    selectedLayers = {for (final c in g.children) c.id};
    applyComp(tr('Desagrupar', 'Ungroup'), (c) => c.copyWith(layers: next));
  }

  // ---- flatten / merge ----------------------------------------------------

  Rect _contentRegion(List<Layer> layers) {
    var r = comp.rect;
    for (final l in walkLayers(layers)) {
      if (l is PaintLayer) {
        for (final p in l.cels.drawings.values) {
          final b = p.bounds;
          if (b != null) r = r.expandToInclude(comp.worldMatrix(l, frame.toDouble()).mapRect(b));
        }
      }
    }
    return r.roundedOut;
  }

  Set<int> _keyFrames(List<Layer> layers) {
    final out = <int>{0};
    for (final l in walkLayers(layers)) {
      switch (l) {
        case PaintLayer():
          out.addAll(l.cels.xs.map((e) => e.frame));
        case VectorLayer():
          out.addAll(l.cels.xs.map((e) => e.frame));
        default:
          break;
      }
      for (final t in l.props.tracks.values) {
        if (t.keys.length > 1) {
          for (var f = t.keys.first.frame; f <= t.keys.last.frame; f++) {
            out.add(f);
          }
        }
      }
    }
    return out;
  }

  /// Flattens [layers] (in paint order) into one raster layer, frame by frame.
  PaintLayer flattenLayers(List<Layer> layers, String name, {LayerProps? props}) {
    final region = _contentRegion(layers);
    final frames = _keyFrames(layers).toList()..sort();
    final tmp = Comp(id: compId, name: comp.name, width: comp.width, height: comp.height, background: null, infinite: true, layers: layers, timeline: comp.timeline);
    final proj = project.withComp(tmp);
    final drawings = <int, TilePlane>{};
    final xs = <Exposure>[];
    var id = 1;
    for (final f in frames) {
      final img = renderCompImage(proj, tmp, f.toDouble(), region: region, background: false, forExport: false, useCamera: false, docMode: false);
      drawings[id] = TilePlane.fromImage(img, origin: region.topLeft);
      img.dispose();
      xs.add(Exposure(f, id));
      id++;
    }
    return PaintLayer(newId('L'), props ?? LayerProps(name: name, xf: _centerAnchor), CelTrack(drawings: drawings, xs: xs));
  }

  void mergeDown() {
    final l = activeLayer;
    if (l == null) return;
    final parent = parentGroupOf(comp.layers, l.id);
    final siblings = parent?.children ?? comp.layers;
    final i = siblings.indexWhere((s) => s.id == l.id);
    if (i <= 0) return;
    final below = siblings[i - 1];
    final merged = flattenLayers([below, l], below.name);
    final out = [...siblings.sublist(0, i - 1), merged, ...siblings.sublist(i + 1)];
    final layers = parent == null ? out : mapLayer(comp.layers, parent.id, (g) => (g as GroupLayer).withChildren(out));
    activeLayerId = merged.id;
    selectedLayers = {merged.id};
    applyComp(tr('Fusionar hacia abajo', 'Merge down'), (c) => c.copyWith(layers: layers));
  }

  void mergeVisible() {
    final visible = comp.layers.where((l) => l.visible).toList();
    if (visible.length < 2) return;
    final merged = flattenLayers(visible, visible.last.name);
    final hidden = comp.layers.where((l) => !l.visible).toList();
    activeLayerId = merged.id;
    selectedLayers = {merged.id};
    applyComp(tr('Fusionar visibles', 'Merge visible'), (c) => c.copyWith(layers: [...hidden, merged]));
  }

  void flattenImage() {
    if (comp.layers.isEmpty) return;
    final merged = flattenLayers(comp.layers.where((l) => l.visible).toList(), tr('Fondo', 'Background'));
    activeLayerId = merged.id;
    selectedLayers = {merged.id};
    applyComp(tr('Aplanar imagen', 'Flatten image'), (c) => c.copyWith(layers: [merged]));
  }

  void mergeSelected() {
    final ids = selectedLayers;
    if (ids.length < 2) return mergeDown();
    final members = comp.layers.where((l) => ids.contains(l.id)).toList();
    if (members.length < 2) return;
    final merged = flattenLayers(members, members.last.name);
    final top = members.last.id;
    final out = <Layer>[];
    for (final l in comp.layers) {
      if (l.id == top) {
        out.add(merged);
      } else if (!ids.contains(l.id)) {
        out.add(l);
      }
    }
    activeLayerId = merged.id;
    selectedLayers = {merged.id};
    applyComp(tr('Fusionar capas', 'Merge layers'), (c) => c.copyWith(layers: out));
  }

  /// Converts any layer into a raster layer, keeping its blend, opacity,
  /// mask and transform as layer properties.
  void rasterizeActive() {
    final l = activeLayer;
    if (l == null || l is PaintLayer || l is AdjustLayer) return;
    final plain = l.withProps(LayerProps(name: l.name));
    final flat = flattenLayers([plain], l.name, props: l.props);
    final r = flat.withId(l.id);
    updateLayer(tr('Rasterizar capa', 'Rasterize layer'), l.id, (_) => r);
  }

  // ---- masks --------------------------------------------------------------

  void addMask({bool fromSelection = true}) {
    final l = activeLayer;
    if (l == null) return;
    var hide = TilePlane.empty;
    final sel = comp.selection;
    if (fromSelection && sel != null) {
      // hide everything outside the selection
      final area = comp.rect.expandToInclude(sel.bounds).roundedOut;
      hide = TilePlane.empty.drawn((c) {
        c.drawRect(area, Paint()..color = const Color(0xFF000000));
        sel.mask.paint(c, paint: Paint()..blendMode = BlendMode.dstOut);
      }, area: area);
    }
    editMask = true;
    updateProps(tr('Añadir máscara', 'Add mask'), l.id, (p) => p.copyWith(mask: hide, maskEnabled: true));
  }

  void deleteMask() {
    final l = activeLayer;
    if (l == null || l.props.mask == null) return;
    editMask = false;
    updateProps(tr('Eliminar máscara', 'Delete mask'), l.id, (p) => p.copyWith(mask: null));
  }

  void toggleMaskEnabled() {
    final l = activeLayer;
    if (l == null || l.props.mask == null) return;
    updateProps(tr('Activar/desactivar máscara', 'Toggle mask'), l.id, (p) => p.copyWith(maskEnabled: !p.maskEnabled));
  }

  void invertMask() {
    final l = activeLayer;
    final m = l?.props.mask;
    if (l == null || m == null) return;
    final area = comp.rect.expandToInclude(m.bounds ?? comp.rect).roundedOut;
    final inv = TilePlane.empty.drawn((c) {
      c.drawRect(area, Paint()..color = const Color(0xFF000000));
      m.paint(c, paint: Paint()..blendMode = BlendMode.dstOut);
    }, area: area);
    updateProps(tr('Invertir máscara', 'Invert mask'), l.id, (p) => p.copyWith(mask: inv));
  }

  /// Bakes the mask into the pixels of a raster layer.
  void applyMask() {
    final l = activeLayer;
    final m = l?.props.mask;
    if (l is! PaintLayer || m == null) return;
    final cels = l.cels.mapDrawings((p) => p.maskedBy(m, invert: true));
    editMask = false;
    updateLayer(tr('Aplicar máscara', 'Apply mask'), l.id, (x) => (x as PaintLayer).withCels(cels).withProps(x.props.copyWith(mask: null)));
  }

  // ---- symbols / nested comps ---------------------------------------------

  /// Wraps the selected layers into a new composition and replaces them by
  /// an instance (symbol / smart object / precomp).
  void convertToSymbol({String? name}) {
    final ids = selectedLayers.isEmpty ? {?activeLayerId} : selectedLayers;
    final members = comp.layers.where((l) => ids.contains(l.id)).toList();
    if (members.isEmpty) return;
    final id = newId('C');
    final symName = name ?? '${tr('Símbolo', 'Symbol')} ${project.comps.length}';
    final sym = Comp(
      id: id,
      name: symName,
      width: comp.width,
      height: comp.height,
      background: null,
      layers: members,
      timeline: Timeline(fps: comp.timeline.fps, length: comp.timeline.length),
      symmetry: SymmetrySpec(center: Offset(comp.width / 2, comp.height / 2)),
    );
    final inst = InstanceLayer(newId('L'), LayerProps(name: symName, xf: _centerAnchor), id);
    final top = members.last.id;
    final out = <Layer>[];
    for (final l in comp.layers) {
      if (l.id == top) {
        out.add(inst);
      } else if (!ids.contains(l.id)) {
        out.add(l);
      }
    }
    activeLayerId = inst.id;
    selectedLayers = {inst.id};
    apply(tr('Convertir en símbolo', 'Convert to symbol'), project.withComp(sym).withComp(comp.copyWith(layers: out)));
  }

  /// Creates an empty symbol and returns its id.
  String createSymbol(String name, {int? width, int? height}) {
    final id = newId('C');
    final layer = PaintLayer.create(tr('Capa 1', 'Layer 1'));
    final w = width ?? comp.width, h = height ?? comp.height;
    final sym = Comp(
      id: id,
      name: name,
      width: w,
      height: h,
      background: null,
      layers: [layer.withProps(layer.props.copyWith(xf: Xform(ax: w / 2, ay: h / 2)))],
      timeline: Timeline(fps: comp.timeline.fps, length: comp.timeline.length),
      symmetry: SymmetrySpec(center: Offset(w / 2, h / 2)),
    );
    apply(tr('Nuevo símbolo', 'New symbol'), project.withComp(sym));
    return id;
  }

  void deleteSymbol(String id) {
    if (id == project.mainId) return;
    var p = project.withoutComp(id);
    // drop instances that pointed at it
    for (final c in p.comps.values) {
      final ids = [
        for (final l in walkLayers(c.layers))
          if (l is InstanceLayer && l.compId == id) l.id,
      ];
      if (ids.isEmpty) continue;
      var layers = c.layers;
      for (final lid in ids) {
        layers = removeLayer(layers, lid);
      }
      p = p.withComp(c.copyWith(layers: layers));
    }
    if (compStack.contains(id)) compStack = [p.mainId];
    apply(tr('Eliminar símbolo', 'Delete symbol'), p);
  }

  /// Converts the active vector layer's shapes / text into node-editable
  /// outlines is not possible for text (no glyph outlines); shapes are
  /// already paths. Returns false when nothing was converted.
  bool vectorizeActiveToShapes(VectorArt art, String name) {
    final l = VectorLayer(newId('L'), LayerProps(name: name, xf: _centerAnchor), CelTrack.single(art));
    addLayer(l, label: tr('Vectorizar', 'Vectorize'));
    return true;
  }

  /// World-space matrix helper used by tools.
  Mat2D layerMatrix(Layer l) => comp.worldMatrix(l, frame.toDouble());
}
