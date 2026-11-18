import 'package:flutter/widgets.dart';

import '../app/app_state.dart';
import '../app/commands.dart';
import '../app/doc_edit.dart';
import '../app/doc_image.dart';
import '../app/doc_layers.dart';
import '../app/doc_motion.dart';
import '../app/doc_selection.dart';
import '../app/doc_vector_ops.dart';
import '../app/document_controller.dart';
import '../core/i18n.dart';
import '../engine/compositor.dart';
import '../engine/path_ops.dart';
import '../engine/vectorize.dart';
import '../model/filter_spec.dart';
import '../model/layer.dart';
import 'dialogs/filter_dialog.dart';
import 'dialogs/prompts.dart';

/// Commands that open a dialog before editing: filters, adjustment layers,
/// canvas / image size and named selections.
void registerDialogCommands(CommandRegistry r, AppState app) {
  BuildContext? ctx() => app.context;
  DocumentController d() => app.doc!;

  void add(String id, CommandCategory cat, String Function() label, Future<void> Function() run, {String shortcut = '', bool Function(DocumentController d)? enabled}) {
    r.add(Command(id: id, category: cat, label: label, run: () => run(), shortcut: shortcut, enabled: enabled));
  }

  // ---- filters (destructive, on the active layer) and adjustment layers ----
  for (final def in kFilters) {
    add('filter.${def.id}', CommandCategory.filter, () => '${filterCategoryLabel(def.category)} › ${def.label}…', () async {
      final c = ctx();
      if (c == null) return;
      final spec = await showFilterDialog(c, d(), def.defaults);
      if (spec != null) d().applyFilterToActive(spec);
    }, enabled: (x) => x.activeLayer != null);
    if (def.adjustment) {
      add('layer.adjust.${def.id}', CommandCategory.layer, () => '${tr('Capa de ajuste', 'Adjustment layer')} › ${def.label}…', () async {
        final c = ctx();
        if (c == null) return;
        final doc = d();
        doc.addAdjustLayer(def.defaults);
        final id = doc.activeLayerId;
        if (id != null) await showFilterDialog(c, doc, def.defaults, adjustLayerId: id);
      });
    }
  }

  // ---- image size ----------------------------------------------------------
  add('image.canvasSize', CommandCategory.image, () => tr('Tamaño del lienzo…', 'Canvas size…'), () async {
    final c = ctx();
    if (c == null) return;
    final s = await showCanvasSizeDialog(c, d().comp);
    if (s != null) d().resizeCanvas(s.w, s.h, ax: s.ax, ay: s.ay);
  }, shortcut: 'Ctrl+Alt+C');
  add('image.imageSize', CommandCategory.image, () => tr('Tamaño de la imagen…', 'Image size…'), () async {
    final c = ctx();
    if (c == null) return;
    final s = await showImageSizeDialog(c, d().comp);
    if (s != null) d().resizeImage(s.w, s.h);
  }, shortcut: 'Ctrl+Alt+I');

  // ---- named selections ----------------------------------------------------
  add('select.save', CommandCategory.select, () => tr('Guardar selección…', 'Save selection…'), () async {
    final c = ctx();
    if (c == null) return;
    final n = d().comp.savedSelections.length + 1;
    final name = await promptText(c, title: tr('Guardar selección', 'Save selection'), initial: '${tr('Selección', 'Selection')} $n', label: tr('Nombre', 'Name'));
    if (name != null && name.trim().isNotEmpty) d().saveSelection(name.trim());
  }, enabled: (x) => x.comp.selection != null);
  add('select.load', CommandCategory.select, () => tr('Cargar selección…', 'Load selection…'), () async {
    final c = ctx();
    if (c == null) return;
    final names = d().comp.savedSelections.keys.toList();
    final name = await pickFromList<String>(c, title: tr('Cargar selección', 'Load selection'), items: [for (final n in names) (n, n)]);
    if (name != null) d().loadSelection(name);
  }, enabled: (x) => x.comp.savedSelections.isNotEmpty);

  // ---- document ------------------------------------------------------------
  add('file.rename', CommandCategory.file, () => tr('Renombrar documento…', 'Rename document…'), () async {
    final c = ctx();
    if (c == null) return;
    final doc = d();
    final name = await promptText(c, title: tr('Renombrar documento', 'Rename document'), initial: doc.title, label: tr('Nombre', 'Name'));
    if (name != null && name.trim().isNotEmpty) {
      doc.title = name.trim();
      doc.touch();
    }
  });

  // ---- vector layers: in-betweens and path booleans --------------------------
  bool isVector(DocumentController x) => x.activeLayer is VectorLayer;
  add('anim.inbetweens', CommandCategory.animation, () => tr('Generar intermedios vectoriales', 'Generate vector in-betweens'), () async {
    final n = d().generateInbetweens();
    app.toast(n == 0
        ? tr('Hace falta una clave siguiente con hueco en esta capa vectorial', 'Needs a later key with a gap on this vector layer')
        : '${tr('Intermedios creados', 'In-betweens created')}: $n');
  }, enabled: isVector);
  for (final (op, es, en) in [
    (BoolOp.union, 'Unir formas', 'Unite shapes'),
    (BoolOp.subtract, 'Restar formas (la de abajo menos el resto)', 'Subtract shapes (bottom minus the rest)'),
    (BoolOp.intersect, 'Intersecar formas', 'Intersect shapes'),
    (BoolOp.exclude, 'Excluir formas', 'Exclude shapes'),
  ]) {
    add('layer.shapes.${op.name}', CommandCategory.layer, () => tr(es, en), () async {
      if (!d().combineShapes(op)) app.toast(tr('Hacen falta al menos dos formas que den un resultado', 'Needs at least two shapes with a non-empty result'));
    }, enabled: isVector);
  }

  // ---- procedural motion -----------------------------------------------------
  add('anim.bounce', CommandCategory.animation, () => tr('Animar caída con rebote', 'Animate bouncing drop'), () async {
    final n = await d().bakeBounce();
    app.toast(n == 0
        ? tr('Hace falta una capa con contenido y fotogramas por delante', 'Needs a layer with content and frames ahead')
        : '${tr('Fotogramas animados', 'Frames animated')}: $n');
  }, enabled: (x) => x.activeLayer != null);

  // ---- vectorize -----------------------------------------------------------
  for (final lineArt in [false, true]) {
    add(lineArt ? 'layer.vectorizeLineArt' : 'layer.vectorize', CommandCategory.layer,
        () => lineArt ? tr('Vectorizar líneas de la capa', 'Vectorize layer line art') : tr('Vectorizar capa a color', 'Vectorize layer in colour'), () async {
      final doc = d();
      final layer = doc.activeLayer;
      if (layer == null) return;
      await vectorizeLayer(doc, VectorizeOptions(lineArt: lineArt));
    }, enabled: (x) => x.activeLayer != null);
  }
}

/// Traces the active layer (as rendered at the current frame) into a new
/// vector layer above it. Returns false when the layer has no pixels.
Future<bool> vectorizeLayer(DocumentController doc, VectorizeOptions options) async {
  final layer = doc.activeLayer;
  if (layer == null) return false;
  final plane = rasterizeLayer(doc.project, doc.comp, layer, doc.frame.toDouble());
  final b = plane.bounds;
  if (b == null || b.isEmpty) {
    AppState.I.toast(tr('La capa está vacía', 'The layer is empty'));
    return false;
  }
  final img = plane.toImage(b);
  try {
    final art = await vectorizeImage(img, options: options, origin: b.topLeft);
    if (art.shapes.isEmpty) return false;
    return doc.vectorizeActiveToShapes(art, '${layer.props.name} (${tr('vector', 'vector')})');
  } finally {
    img.dispose();
  }
}
