import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../core/i18n.dart';
import 'app_state.dart';
import 'doc_edit.dart';
import 'doc_image.dart';
import 'doc_layers.dart';
import 'doc_selection.dart';
import 'doc_timeline.dart';
import 'document_controller.dart';
import 'key_combo.dart';
import 'view_state.dart';

/// Groups commands in the palette and in the shortcut list.
enum CommandCategory { file, edit, select, image, filter, layer, animation, view, tool, brush, color, help }

String commandCategoryLabel(CommandCategory c) => switch (c) {
      CommandCategory.file => tr('Archivo', 'File'),
      CommandCategory.edit => tr('Edición', 'Edit'),
      CommandCategory.select => tr('Selección', 'Select'),
      CommandCategory.image => tr('Imagen', 'Image'),
      CommandCategory.filter => tr('Filtro', 'Filter'),
      CommandCategory.layer => tr('Capa', 'Layer'),
      CommandCategory.animation => tr('Animación', 'Animation'),
      CommandCategory.view => tr('Vista', 'View'),
      CommandCategory.tool => tr('Herramienta', 'Tool'),
      CommandCategory.brush => tr('Pincel', 'Brush'),
      CommandCategory.color => tr('Color', 'Colour'),
      CommandCategory.help => tr('Ayuda', 'Help'),
    };

/// One user-invocable action: menu entry, palette entry and shortcut target.
class Command {
  Command({
    required this.id,
    required this.category,
    required this.label,
    required this.run,
    this.shortcut = '',
    this.enabled,
    this.needsDocument = true,
  });

  /// Stable id such as `edit.undo` (also the key of user shortcut overrides).
  final String id;
  final CommandCategory category;

  /// Localised label, evaluated on demand so a language switch applies at once.
  final String Function() label;
  final void Function() run;

  /// Default shortcut(s), alternatives separated by `|` (e.g. `Ctrl+Y|Ctrl+Shift+Z`).
  final String shortcut;

  /// Extra enablement condition (evaluated with an open document).
  final bool Function(DocumentController d)? enabled;

  /// When true the command is disabled while no document is open.
  final bool needsDocument;

  bool get isEnabled {
    final d = AppState.I.doc;
    if (d == null) return !needsDocument;
    if (d.isBusy && needsDocument) return false;
    return enabled?.call(d) ?? true;
  }
}

/// Every command of the app, with shortcut resolution and search.
class CommandRegistry {
  final Map<String, Command> _byId = {};
  Map<KeyCombo, Command>? _combos;

  Iterable<Command> get all => _byId.values;

  Command? byId(String id) => _byId[id];

  void add(Command c) {
    assert(!_byId.containsKey(c.id), 'duplicate command ${c.id}');
    _byId[c.id] = c;
    _combos = null;
  }

  /// Runs the command when it exists and is enabled; returns whether it ran.
  bool run(String id) {
    final c = _byId[id];
    if (c == null || !c.isEnabled) return false;
    c.run();
    return true;
  }

  /// Forget the cached shortcut table (call after changing `Settings.shortcuts`).
  void invalidateShortcuts() => _combos = null;

  /// Effective shortcut text of [id] (`''` when unbound). Alternatives use `|`.
  String shortcutOf(String id) {
    final c = _byId[id];
    if (c == null) return '';
    final custom = AppState.I.settings.shortcuts[id];
    return custom ?? c.shortcut;
  }

  Map<KeyCombo, Command> _table() {
    final t = <KeyCombo, Command>{};
    // defaults first so user overrides win when two commands share a combo
    for (final c in _byId.values) {
      if (AppState.I.settings.shortcuts.containsKey(c.id)) continue;
      for (final s in c.shortcut.split('|')) {
        final k = KeyCombo.parse(s.trim());
        if (k != null) t[k] = c;
      }
    }
    for (final e in AppState.I.settings.shortcuts.entries) {
      final c = _byId[e.key];
      if (c == null) continue;
      for (final s in e.value.split('|')) {
        final k = KeyCombo.parse(s.trim());
        if (k != null) t[k] = c;
      }
    }
    return t;
  }

  Command? forCombo(KeyCombo combo) => (_combos ??= _table())[combo];

  /// Case-insensitive search by label, id or category; best matches first.
  List<Command> search(String query) {
    final q = query.trim().toLowerCase();
    final list = _byId.values.toList();
    if (q.isEmpty) {
      list.sort((a, b) => a.category.index != b.category.index ? a.category.index - b.category.index : a.label().compareTo(b.label()));
      return list;
    }
    final scored = <(int, Command)>[];
    for (final c in list) {
      final l = c.label().toLowerCase();
      var s = -1;
      if (l.startsWith(q)) {
        s = 0;
      } else if (l.contains(q)) {
        s = 1;
      } else if (c.id.toLowerCase().contains(q)) {
        s = 2;
      } else if (commandCategoryLabel(c.category).toLowerCase().contains(q)) {
        s = 3;
      }
      if (s >= 0) scored.add((s, c));
    }
    scored.sort((a, b) => a.$1 != b.$1 ? a.$1 - b.$1 : a.$2.label().compareTo(b.$2.label()));
    return [for (final e in scored) e.$2];
  }
}

/// Hooks other modules (file dialogs, export…) use to add their commands
/// after [registerCommands] has run.
typedef CommandContributor = void Function(CommandRegistry r, AppState app);
final List<CommandContributor> kCommandContributors = [];

/// Registers the document-level commands. Commands that open dialogs or touch
/// files are contributed through [kCommandContributors] by the UI layer.
void registerCommands(AppState app) {
  final r = app.commands;
  DocumentController d() => app.doc!;

  void add(String id, CommandCategory cat, String Function() label, void Function() run, {String shortcut = '', bool Function(DocumentController d)? enabled, bool needsDocument = true}) {
    r.add(Command(id: id, category: cat, label: label, run: run, shortcut: shortcut, enabled: enabled, needsDocument: needsDocument));
  }

  const edit = CommandCategory.edit, sel = CommandCategory.select, img = CommandCategory.image, lay = CommandCategory.layer;
  const anim = CommandCategory.animation, view = CommandCategory.view, tool = CommandCategory.tool, brush = CommandCategory.brush, color = CommandCategory.color;

  // ---- edit ---------------------------------------------------------------
  add('edit.undo', edit, () => tr('Deshacer', 'Undo'), () => d().undo(), shortcut: 'Ctrl+Z', enabled: (x) => x.history.canUndo);
  add('edit.redo', edit, () => tr('Rehacer', 'Redo'), () => d().redo(), shortcut: 'Ctrl+Y|Ctrl+Shift+Z', enabled: (x) => x.history.canRedo);
  add('edit.cut', edit, () => tr('Cortar', 'Cut'), () => d().cutPixels(), shortcut: 'Ctrl+X');
  add('edit.copy', edit, () => tr('Copiar', 'Copy'), () => d().copyPixels(), shortcut: 'Ctrl+C');
  add('edit.copyMerged', edit, () => tr('Copiar fusionado', 'Copy merged'), () => d().copyPixels(merged: true), shortcut: 'Ctrl+Shift+C');
  add('edit.paste', edit, () => tr('Pegar', 'Paste'), () => d().paste(), shortcut: 'Ctrl+V');
  add('edit.clear', edit, () => tr('Borrar contenido', 'Clear'), () => d().clearPixels(), shortcut: 'Del');
  add('edit.fillFg', edit, () => tr('Rellenar con color frontal', 'Fill with foreground'), () => d().fillColor(app.ts.fg), shortcut: 'Alt+Backspace');
  add('edit.fillBg', edit, () => tr('Rellenar con color de fondo', 'Fill with background'), () => d().fillColor(app.ts.bg), shortcut: 'Ctrl+Backspace');
  add('edit.strokeSelection', edit, () => tr('Contornear selección', 'Stroke selection'), () => d().strokeSelection(app.ts.fg, 2), enabled: (x) => x.comp.selection != null);

  // ---- select -------------------------------------------------------------
  add('select.all', sel, () => tr('Seleccionar todo', 'Select all'), () => d().selectAll(), shortcut: 'Ctrl+A');
  add('select.none', sel, () => tr('Deseleccionar', 'Deselect'), () => d().deselect(), shortcut: 'Ctrl+D', enabled: (x) => x.comp.selection != null);
  add('select.invert', sel, () => tr('Invertir selección', 'Invert selection'), () => d().invertSelection(), shortcut: 'Ctrl+Shift+I', enabled: (x) => x.comp.selection != null);
  add('select.layerAlpha', sel, () => tr('Seleccionar opacidad de capa', 'Select layer opacity'), () => d().selectLayerAlpha());
  add('select.grow', sel, () => tr('Expandir selección 2 px', 'Grow selection 2 px'), () => d().growSelection(2), enabled: (x) => x.comp.selection != null);
  add('select.shrink', sel, () => tr('Contraer selección 2 px', 'Shrink selection 2 px'), () => d().growSelection(-2), enabled: (x) => x.comp.selection != null);
  add('select.feather', sel, () => tr('Suavizar selección 4 px', 'Feather selection 4 px'), () => d().featherSelection(4), enabled: (x) => x.comp.selection != null);
  add('select.smooth', sel, () => tr('Redondear selección', 'Smooth selection'), () => d().smoothSelection(4), enabled: (x) => x.comp.selection != null);

  // ---- image --------------------------------------------------------------
  add('image.cropSelection', img, () => tr('Recortar a la selección', 'Crop to selection'), () => d().cropToSelection(), enabled: (x) => x.comp.selection != null);
  add('image.trim', img, () => tr('Recortar a contenido', 'Trim to content'), () => d().trimCanvas());
  add('image.rotate90cw', img, () => tr('Girar lienzo 90° a la derecha', 'Rotate canvas 90° clockwise'), () => d().rotateCanvas90());
  add('image.rotate90ccw', img, () => tr('Girar lienzo 90° a la izquierda', 'Rotate canvas 90° counter-clockwise'), () => d().rotateCanvas90(clockwise: false));
  add('image.rotate180', img, () => tr('Girar lienzo 180°', 'Rotate canvas 180°'), () => d().rotateCanvas180());
  add('image.flipH', img, () => tr('Voltear lienzo horizontalmente', 'Flip canvas horizontally'), () => d().flipCanvas());
  add('image.flipV', img, () => tr('Voltear lienzo verticalmente', 'Flip canvas vertically'), () => d().flipCanvas(horizontal: false));
  add('image.flatten', img, () => tr('Aplanar imagen', 'Flatten image'), () => d().flattenImage());

  // ---- layers -------------------------------------------------------------
  add('layer.newPaint', lay, () => tr('Nueva capa de dibujo', 'New paint layer'), () => d().addPaintLayer(), shortcut: 'Ctrl+Shift+N');
  add('layer.newVector', lay, () => tr('Nueva capa vectorial', 'New vector layer'), () => d().addVectorLayer());
  add('layer.newGroup', lay, () => tr('Nuevo grupo', 'New group'), () => d().addGroupLayer());
  add('layer.delete', lay, () => tr('Eliminar capa', 'Delete layer'), () => d().deleteSelectedLayers(), enabled: (x) => x.activeLayer != null);
  add('layer.duplicate', lay, () => tr('Duplicar capa', 'Duplicate layer'), () => d().duplicateActiveLayer(), shortcut: 'Ctrl+J', enabled: (x) => x.activeLayer != null);
  add('layer.group', lay, () => tr('Agrupar capas', 'Group layers'), () => d().groupSelected(), shortcut: 'Ctrl+G', enabled: (x) => x.activeLayer != null);
  add('layer.ungroup', lay, () => tr('Desagrupar', 'Ungroup'), () => d().ungroupActive(), shortcut: 'Ctrl+Shift+G', enabled: (x) => x.activeLayer != null);
  add('layer.mergeDown', lay, () => tr('Fusionar hacia abajo', 'Merge down'), () => d().mergeDown(), shortcut: 'Ctrl+E', enabled: (x) => x.activeLayer != null);
  add('layer.mergeVisible', lay, () => tr('Fusionar visibles', 'Merge visible'), () => d().mergeVisible(), shortcut: 'Ctrl+Shift+E');
  add('layer.rasterize', lay, () => tr('Rasterizar capa', 'Rasterize layer'), () => d().rasterizeActive(), enabled: (x) => x.activeLayer != null);
  add('layer.raise', lay, () => tr('Subir capa', 'Raise layer'), () => d().shiftActiveLayer(1), shortcut: 'Ctrl+]', enabled: (x) => x.activeLayer != null);
  add('layer.lower', lay, () => tr('Bajar capa', 'Lower layer'), () => d().shiftActiveLayer(-1), shortcut: 'Ctrl+[', enabled: (x) => x.activeLayer != null);
  add('layer.selectAbove', lay, () => tr('Seleccionar capa superior', 'Select layer above'), () => _selectNeighbour(d(), 1), shortcut: 'Alt+]');
  add('layer.selectBelow', lay, () => tr('Seleccionar capa inferior', 'Select layer below'), () => _selectNeighbour(d(), -1), shortcut: 'Alt+[');
  add('layer.flipH', lay, () => tr('Voltear capa horizontalmente', 'Flip layer horizontally'), () => d().flipActiveLayer(), enabled: (x) => x.activeLayer != null);
  add('layer.flipV', lay, () => tr('Voltear capa verticalmente', 'Flip layer vertically'), () => d().flipActiveLayer(horizontal: false), enabled: (x) => x.activeLayer != null);
  add('layer.addMask', lay, () => tr('Añadir máscara', 'Add mask'), () => d().addMask(), enabled: (x) => x.activeLayer != null);
  add('layer.deleteMask', lay, () => tr('Eliminar máscara', 'Delete mask'), () => d().deleteMask(), enabled: (x) => x.activeLayer?.props.mask != null);
  add('layer.applyMask', lay, () => tr('Aplicar máscara', 'Apply mask'), () => d().applyMask(), enabled: (x) => x.activeLayer?.props.mask != null);
  add('layer.invertMask', lay, () => tr('Invertir máscara', 'Invert mask'), () => d().invertMask(), enabled: (x) => x.activeLayer?.props.mask != null);
  add('layer.toggleMask', lay, () => tr('Activar/desactivar máscara', 'Toggle mask'), () => d().toggleMaskEnabled(), enabled: (x) => x.activeLayer?.props.mask != null);
  add('layer.toSymbol', lay, () => tr('Convertir en símbolo', 'Convert to symbol'), () => d().convertToSymbol(), enabled: (x) => x.activeLayer != null);

  // ---- animation ----------------------------------------------------------
  add('anim.play', anim, () => tr('Reproducir / pausar', 'Play / pause'), () => app.playback.toggle(), shortcut: 'Enter');
  add('anim.nextFrame', anim, () => tr('Fotograma siguiente', 'Next frame'), () => d().stepFrame(1), shortcut: '.|Right');
  add('anim.prevFrame', anim, () => tr('Fotograma anterior', 'Previous frame'), () => d().stepFrame(-1), shortcut: ',|Left');
  add('anim.firstFrame', anim, () => tr('Ir al primer fotograma', 'Go to first frame'), () => d().frame = 0, shortcut: 'Home');
  add('anim.lastFrame', anim, () => tr('Ir al último fotograma', 'Go to last frame'), () => d().frame = d().timeline.length - 1, shortcut: 'End');
  add('anim.nextKey', anim, () => tr('Siguiente fotograma clave', 'Next keyframe'), () => d().goToNextKey(), shortcut: 'Alt+Right');
  add('anim.prevKey', anim, () => tr('Fotograma clave anterior', 'Previous keyframe'), () => d().goToPrevKey(), shortcut: 'Alt+Left');
  add('anim.newKey', anim, () => tr('Nuevo fotograma clave', 'New keyframe'), () => d().addKeyFrame(), shortcut: 'F6');
  add('anim.dupKey', anim, () => tr('Duplicar fotograma clave', 'Duplicate keyframe'), () => d().addKeyFrame(duplicate: true), shortcut: 'F7');
  add('anim.blankKey', anim, () => tr('Fotograma en blanco', 'Blank keyframe'), () => d().addBlankKey(), shortcut: 'F8');
  add('anim.deleteKey', anim, () => tr('Eliminar fotograma clave', 'Delete keyframe'), () => d().deleteKey(), shortcut: 'Shift+F6');
  add('anim.insertFrame', anim, () => tr('Insertar fotograma', 'Insert frame'), () => d().shiftFrames(1), shortcut: 'F5');
  add('anim.removeFrame', anim, () => tr('Quitar fotograma', 'Remove frame'), () => d().shiftFrames(-1), shortcut: 'Shift+F5');
  add('anim.copyFrame', anim, () => tr('Copiar fotograma', 'Copy frame'), () => d().copyFrame());
  add('anim.pasteFrame', anim, () => tr('Pegar fotograma', 'Paste frame'), () => d().pasteFrame());
  add('anim.loop', anim, () => tr('Alternar bucle', 'Toggle loop'), () => app.playback.setLoop(!app.playback.loop), needsDocument: false);
  add('anim.pingPong', anim, () => tr('Alternar ida y vuelta', 'Toggle ping-pong'), () => app.playback.setPingPong(!app.playback.pingPong), needsDocument: false);

  // ---- view ---------------------------------------------------------------
  void zoom(double f) {
    final x = d();
    final c = Offset(x.viewportSize.width / 2, x.viewportSize.height / 2);
    x.setView(x.view.zoomedAt(c, f));
  }

  void fit() {
    final x = d();
    final c = x.comp;
    x.setView(ViewState.fit(x.viewportSize, Rect.fromLTWH(0, 0, c.width.toDouble(), c.height.toDouble()), rotation: x.view.rotation, flip: x.view.flip));
  }

  void actual() {
    final x = d();
    final c = Offset(x.viewportSize.width / 2, x.viewportSize.height / 2);
    x.setView(x.view.withZoomAt(c, 1));
  }

  void toggle(void Function(DocumentController x) f) {
    final x = d();
    f(x);
    x.touch();
    x.repaint();
  }

  add('view.zoomIn', view, () => tr('Acercar', 'Zoom in'), () => zoom(1.25), shortcut: 'Ctrl+=|Ctrl+Num+');
  add('view.zoomOut', view, () => tr('Alejar', 'Zoom out'), () => zoom(1 / 1.25), shortcut: 'Ctrl+-');
  add('view.fit', view, () => tr('Ajustar a la ventana', 'Fit to window'), fit, shortcut: 'Ctrl+0');
  add('view.actual', view, () => tr('Tamaño real (100 %)', 'Actual size (100%)'), actual, shortcut: 'Ctrl+1');
  add('view.rotateReset', view, () => tr('Restablecer rotación', 'Reset rotation'), () {
    final x = d();
    final c = Offset(x.viewportSize.width / 2, x.viewportSize.height / 2);
    x.setView(x.view.withRotationAt(c, 0));
  }, shortcut: 'Ctrl+Shift+0');
  add('view.rotateCw', view, () => tr('Girar vista a la derecha', 'Rotate view clockwise'), () {
    final x = d();
    final c = Offset(x.viewportSize.width / 2, x.viewportSize.height / 2);
    x.setView(x.view.rotatedAt(c, math.pi / 12));
  });
  add('view.rotateCcw', view, () => tr('Girar vista a la izquierda', 'Rotate view counter-clockwise'), () {
    final x = d();
    final c = Offset(x.viewportSize.width / 2, x.viewportSize.height / 2);
    x.setView(x.view.rotatedAt(c, -math.pi / 12));
  });
  add('view.flip', view, () => tr('Voltear vista', 'Flip view'), () {
    final x = d();
    final c = Offset(x.viewportSize.width / 2, x.viewportSize.height / 2);
    x.setView(x.view.flippedAt(c));
  }, shortcut: 'Shift+F');
  add('view.grid', view, () => tr('Mostrar cuadrícula', 'Show grid'), () => toggle((x) => x.showGrid = !x.showGrid), shortcut: "Ctrl+'");
  add('view.guides', view, () => tr('Mostrar guías', 'Show guides'), () => toggle((x) => x.showGuides = !x.showGuides), shortcut: 'Ctrl+;');
  add('view.rulers', view, () => tr('Mostrar reglas', 'Show rulers'), () => toggle((x) => x.showRulers = !x.showRulers), shortcut: 'Ctrl+R');
  add('view.snapGrid', view, () => tr('Ajustar a la cuadrícula', 'Snap to grid'), () => toggle((x) => x.snapToGrid = !x.snapToGrid));
  add('view.snapGuides', view, () => tr('Ajustar a las guías', 'Snap to guides'), () => toggle((x) => x.snapToGuides = !x.snapToGuides));
  add('view.pixelGrid', view, () => tr('Cuadrícula de píxeles', 'Pixel grid'), () => toggle((x) => x.showPixelGrid = !x.showPixelGrid));
  add('view.onion', view, () => tr('Papel cebolla', 'Onion skin'), () => toggle((x) => x.onion = x.onion.copyWith(enabled: !x.onion.enabled)), shortcut: 'Alt+O');
  add('view.camera', view, () => tr('Ver a través de la cámara', 'View through camera'), () => toggle((x) => x.viewCamera = !x.viewCamera));

  // ---- tools --------------------------------------------------------------
  const toolKeys = <String, (String, String, String)>{
    'move': ('V', 'Mover', 'Move'),
    'marquee': ('M', 'Marco', 'Marquee'),
    'lasso': ('L', 'Lazo', 'Lasso'),
    'polylasso': ('Shift+L', 'Lazo poligonal', 'Polygonal lasso'),
    'wand': ('W', 'Varita mágica', 'Magic wand'),
    'eyedropper': ('I', 'Cuentagotas', 'Eyedropper'),
    'brush': ('B', 'Pincel', 'Brush'),
    'eraser': ('E', 'Borrador', 'Eraser'),
    'smudge': ('S', 'Difuminar', 'Smudge'),
    'bucket': ('G', 'Cubo de pintura', 'Paint bucket'),
    'gradient': ('Shift+G', 'Degradado', 'Gradient'),
    'shape': ('U', 'Formas', 'Shapes'),
    'text': ('T', 'Texto', 'Text'),
    'hand': ('H', 'Mano', 'Hand'),
    'zoom': ('Z', 'Zoom', 'Zoom'),
    'rotateView': ('R', 'Girar vista', 'Rotate view'),
    'liquify': ('Shift+W', 'Licuar', 'Liquify'),
    'ik': ('Shift+K', 'Cinemática inversa', 'Inverse kinematics'),
    'bones': ('Shift+B', 'Huesos', 'Bones'),
    'track': ('', 'Seguimiento', 'Track motion'),
    'transform': ('Ctrl+T', 'Transformar', 'Transform'),
  };
  for (final e in toolKeys.entries) {
    final (key, es, en) = e.value;
    add('tool.${e.key}', tool, () => tr(es, en), () => app.setTool(e.key), shortcut: key, needsDocument: false);
  }

  // ---- brush & colour -----------------------------------------------------
  void resize(double f) {
    final b = app.ts.brush;
    app.ts.updateBrush(b.copyWith(size: (b.size * f).clamp(0.5, 2000).toDouble()));
  }

  add('brush.smaller', brush, () => tr('Pincel más pequeño', 'Smaller brush'), () => resize(1 / 1.15), shortcut: '[', needsDocument: false);
  add('brush.larger', brush, () => tr('Pincel más grande', 'Larger brush'), () => resize(1.15), shortcut: ']', needsDocument: false);
  add('color.swap', color, () => tr('Intercambiar colores', 'Swap colours'), app.ts.swapColors, shortcut: 'X', needsDocument: false);
  add('color.reset', color, () => tr('Colores predeterminados', 'Default colours'), app.ts.resetColors, shortcut: 'D', needsDocument: false);

  for (final c in kCommandContributors) {
    c(r, app);
  }
}

void _selectNeighbour(DocumentController d, int delta) {
  final flat = d.comp.layers.reversed.toList();
  if (flat.isEmpty) return;
  final i = flat.indexWhere((l) => l.id == d.activeLayerId);
  final n = (i < 0 ? 0 : i - delta).clamp(0, flat.length - 1);
  d.selectLayer(flat[n].id);
}
