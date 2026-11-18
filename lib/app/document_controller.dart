import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../core/i18n.dart';
import '../core/ids.dart';
import '../engine/compositor.dart';
import '../engine/tiles.dart';
import '../model/document.dart';
import '../model/layer.dart';
import '../model/vector.dart';
import 'history.dart';
import 'view_state.dart';

/// A listenable that can be fired from the outside.
class Signal extends ChangeNotifier {
  void fire() => notifyListeners();
}

/// What happens when drawing on a frame that only holds a previous drawing.
enum AutoKeyMode { editHeld, newBlank, duplicate }

/// Where a raster edit lands.
class PaintTarget {
  /// Project to build the result on (may already contain a freshly created
  /// drawing / key for the current frame).
  final Project project;
  final PaintLayer? layer;
  final String layerId;
  final int drawing;

  /// Pixels being edited: the drawing, or the layer mask when [onMask].
  final TilePlane plane;
  final bool onMask;

  PaintTarget({required this.project, required this.layer, required this.layerId, required this.drawing, required this.plane, required this.onMask});
}

/// State and operations of one open document (one tab).
///
/// The document itself ([project]) is immutable; every edit produces a new
/// project that is pushed on the undo [history]. Listeners of the
/// controller are told about structural changes; [canvasSignal],
/// [viewSignal] and [frameSignal] are finer grained.
class DocumentController extends ChangeNotifier {
  DocumentController(Project project, {String? title, this.filePath})
      : _project = project,
        title = title ?? project.main.name,
        compStack = [project.mainId] {
    final top = project.main.layers.isEmpty ? null : project.main.layers.last;
    activeLayerId = top?.id;
    history = History(HistoryEntry(tr('Abrir', 'Open'), project, compId: project.mainId, activeLayerId: activeLayerId));
  }

  final String uid = newId('doc');
  Project _project;
  late final History history;

  /// Composition being edited (last) and the path of parents when editing
  /// a symbol in place.
  List<String> compStack;

  String? activeLayerId;
  Set<String> selectedLayers = {};
  int _frame = 0;

  ViewState view = const ViewState();
  Size viewportSize = Size.zero;
  bool viewInitialized = false;

  /// In-progress edit shown by the compositor.
  LiveEdit? live;

  /// Paint on the active layer's mask instead of its pixels.
  bool editMask = false;

  OnionSkin onion = const OnionSkin();
  double lightTable = 0;
  bool viewCamera = false;
  AutoKeyMode autoKey = AutoKeyMode.editHeld;

  /// Record transform changes as keyframes at the current frame.
  bool autoKeyTransforms = false;

  bool showGrid = false;
  bool showGuides = true;
  bool showRulers = true;
  bool snapToGrid = false;
  bool snapToGuides = true;
  double gridSize = 64;
  int gridSubdivisions = 4;
  bool showPixelGrid = true;

  String title;
  String? filePath;
  bool dirty = false;
  int _busy = 0;
  String? busyLabel;

  final Signal canvasSignal = Signal();
  final Signal viewSignal = Signal();
  final Signal frameSignal = Signal();
  final Signal busySignal = Signal();

  String? _mergeKey;
  DateTime _mergeTime = DateTime.fromMillisecondsSinceEpoch(0);
  static int _gestureCounter = 0;

  /// A merge key unique to one drag gesture.
  static String gestureKey(String name) => '!$name:${++_gestureCounter}';

  // ---- accessors ----------------------------------------------------------

  Project get project => _project;
  String get compId => _project.comps.containsKey(compStack.last) ? compStack.last : _project.mainId;
  Comp get comp => _project.comp(compId);
  Timeline get timeline => comp.timeline;
  Layer? get activeLayer => comp.layer(activeLayerId);
  bool get isBusy => _busy > 0;
  int get frame => _frame;
  bool get isEditingSymbol => compStack.length > 1;

  set frame(int f) {
    final nf = f < 0 ? 0 : f;
    if (nf == _frame) return;
    _frame = nf;
    frameSignal.fire();
    canvasSignal.fire();
  }

  void repaint() => canvasSignal.fire();

  void setView(ViewState v) {
    view = v;
    viewSignal.fire();
    canvasSignal.fire();
  }

  void setLive(LiveEdit? l) {
    live = l;
    canvasSignal.fire();
  }

  /// Notifies panels of a non-document change (active layer, toggles…).
  void touch() {
    notifyListeners();
    canvasSignal.fire();
  }

  void selectLayer(String? id, {bool additive = false}) {
    if (additive && id != null) {
      if (selectedLayers.contains(id) && selectedLayers.length > 1) {
        selectedLayers = {...selectedLayers}..remove(id);
        if (activeLayerId == id) activeLayerId = selectedLayers.last;
      } else {
        selectedLayers = {...selectedLayers, id};
        activeLayerId = id;
      }
    } else {
      activeLayerId = id;
      selectedLayers = id == null ? {} : {id};
    }
    final l = activeLayer;
    if (l == null || l.props.mask == null) editMask = false;
    touch();
  }

  // ---- history ------------------------------------------------------------

  /// Commits [next] as a new undo step. Calls sharing a [mergeKey] within a
  /// short time collapse into one step (slider drags, nudges…); a key that
  /// starts with '!' (see [gestureKey]) merges for as long as it repeats.
  void apply(String label, Project next, {String? mergeKey}) {
    if (identical(next, _project)) return;
    _project = next;
    final entry = HistoryEntry(label, next, compId: compId, activeLayerId: activeLayerId, frame: _frame);
    final now = DateTime.now();
    // keys starting with '!' identify one drag gesture and merge regardless of timing
    final recent = mergeKey != null && (mergeKey.startsWith('!') || now.difference(_mergeTime).inMilliseconds < 1200);
    if (mergeKey != null && mergeKey == _mergeKey && recent && history.canUndo) {
      history.replaceCurrent(entry);
    } else {
      history.push(entry);
    }
    _mergeKey = mergeKey;
    _mergeTime = now;
    dirty = true;
    _validateSelection();
    notifyListeners();
    canvasSignal.fire();
  }

  void applyComp(String label, Comp Function(Comp c) f, {String? mergeKey}) {
    final c = comp;
    final n = f(c);
    if (identical(n, c)) return;
    apply(label, _project.withComp(n), mergeKey: mergeKey);
  }

  void updateLayer(String label, String id, Layer Function(Layer l) f, {String? mergeKey}) =>
      applyComp(label, (c) => c.updateLayer(id, f), mergeKey: mergeKey);

  void updateProps(String label, String id, LayerProps Function(LayerProps p) f, {String? mergeKey}) =>
      updateLayer(label, id, (l) => l.withProps(f(l.props)), mergeKey: mergeKey);

  void _restore(HistoryEntry e) {
    _project = e.project;
    if (!_project.comps.containsKey(compStack.last)) compStack = [_project.mainId];
    if (comp.layer(activeLayerId) == null) {
      activeLayerId = comp.layer(e.activeLayerId)?.id ?? (comp.layers.isEmpty ? null : comp.layers.last.id);
    }
    _mergeKey = null;
    live = null;
    dirty = true;
    _validateSelection();
    notifyListeners();
    canvasSignal.fire();
  }

  void undo() {
    final e = history.undo();
    if (e != null) _restore(e);
  }

  void redo() {
    final e = history.redo();
    if (e != null) _restore(e);
  }

  void jumpToHistory(int index) => _restore(history.jumpTo(index));

  void _validateSelection() {
    final c = comp;
    selectedLayers = selectedLayers.where((id) => c.layer(id) != null).toSet();
    if (c.layer(activeLayerId) == null) {
      activeLayerId = c.layers.isEmpty ? null : c.layers.last.id;
    }
    if (activeLayerId != null && selectedLayers.isEmpty) selectedLayers = {activeLayerId!};
    final l = activeLayer;
    if (l == null || l.props.mask == null) editMask = false;
  }

  /// Replaces the whole project (open / revert), resetting history.
  void reset(Project p) {
    _project = p;
    compStack = [p.mainId];
    activeLayerId = p.main.layers.isEmpty ? null : p.main.layers.last.id;
    selectedLayers = activeLayerId == null ? {} : {activeLayerId!};
    history.clear(HistoryEntry(tr('Abrir', 'Open'), p, compId: p.mainId, activeLayerId: activeLayerId));
    _frame = 0;
    live = null;
    dirty = false;
    notifyListeners();
    frameSignal.fire();
    canvasSignal.fire();
  }

  // ---- busy ---------------------------------------------------------------

  /// Runs an async document operation while flagging the document busy so
  /// tools do not start overlapping edits.
  Future<T?> run<T>(String label, Future<T> Function() op) async {
    _busy++;
    busyLabel = label;
    busySignal.fire();
    try {
      return await op();
    } catch (e, st) {
      debugPrint('Drawly: "$label" failed: $e\n$st');
      lastError = '$label: $e';
      return null;
    } finally {
      _busy--;
      if (_busy == 0) busyLabel = null;
      busySignal.fire();
    }
  }

  String? lastError;

  // ---- symbol (nested comp) editing ----------------------------------------

  void enterComp(String id) {
    if (!_project.comps.containsKey(id) || compStack.contains(id)) return;
    compStack = [...compStack, id];
    activeLayerId = comp.layers.isEmpty ? null : comp.layers.last.id;
    selectedLayers = activeLayerId == null ? {} : {activeLayerId!};
    _frame = 0;
    live = null;
    viewInitialized = false;
    notifyListeners();
    frameSignal.fire();
    canvasSignal.fire();
  }

  void exitComp() {
    if (compStack.length <= 1) return;
    compStack = compStack.sublist(0, compStack.length - 1);
    activeLayerId = comp.layers.isEmpty ? null : comp.layers.last.id;
    selectedLayers = activeLayerId == null ? {} : {activeLayerId!};
    live = null;
    viewInitialized = false;
    notifyListeners();
    frameSignal.fire();
    canvasSignal.fire();
  }

  // ---- paint targets ------------------------------------------------------

  /// Why the active layer cannot be painted on, or null when it can.
  String? get paintBlocker {
    final l = activeLayer;
    if (l == null) return tr('No hay ninguna capa seleccionada', 'No layer selected');
    if (!l.props.visible) return tr('La capa está oculta', 'The layer is hidden');
    if (l.props.locked) return tr('La capa está bloqueada', 'The layer is locked');
    if (editMask && l.props.mask != null) return null;
    if (l is! PaintLayer) return tr('Esta herramienta necesita una capa de trama', 'This tool needs a raster layer');
    return null;
  }

  /// Resolves the raster target of the active layer at the current frame,
  /// creating a drawing / key when the frame is empty.
  PaintTarget? resolvePaintTarget() {
    final l = activeLayer;
    if (l == null || paintBlocker != null) return null;
    if (editMask && l.props.mask != null) {
      return PaintTarget(project: _project, layer: l is PaintLayer ? l : null, layerId: l.id, drawing: 0, plane: l.props.mask!, onMask: true);
    }
    if (l is! PaintLayer) return null;
    var layer = l;
    var proj = _project;
    var id = layer.cels.drawingIdAt(_frame);
    final hasKey = layer.cels.hasKeyAt(_frame);
    if (id == null) {
      id = layer.cels.newDrawingId;
      layer = layer.withCels(layer.cels.withDrawing(id, TilePlane.empty).withKey(_frame, id));
      proj = proj.withComp(comp.updateLayer(layer.id, (_) => layer));
    } else if (!hasKey && autoKey != AutoKeyMode.editHeld) {
      final nid = layer.cels.newDrawingId;
      final content = autoKey == AutoKeyMode.duplicate ? layer.cels.drawings[id]! : TilePlane.empty;
      layer = layer.withCels(layer.cels.withDrawing(nid, content).withKey(_frame, nid));
      proj = proj.withComp(comp.updateLayer(layer.id, (_) => layer));
      id = nid;
    }
    return PaintTarget(project: proj, layer: layer, layerId: layer.id, drawing: id, plane: layer.cels.drawings[id]!, onMask: false);
  }

  /// Writes [pixels] back to where [target] came from and commits.
  void commitPaint(String label, PaintTarget target, TilePlane pixels, {String? mergeKey}) {
    final c = target.project.comp(compId);
    Comp next;
    if (target.onMask) {
      next = c.updateLayer(target.layerId, (l) => l.withProps(l.props.copyWith(mask: pixels)));
    } else {
      next = c.updateLayer(target.layerId, (l) => (l as PaintLayer).withCels(l.cels.withDrawing(target.drawing, pixels)));
    }
    live = null;
    apply(label, target.project.withComp(next), mergeKey: mergeKey);
  }

  /// The vector art being edited at the current frame (creating it if needed).
  ({Project project, VectorLayer layer, int drawing, VectorArt art})? resolveVectorTarget() {
    final l = activeLayer;
    if (l is! VectorLayer || l.props.locked || !l.props.visible) return null;
    var layer = l;
    var proj = _project;
    var id = layer.cels.drawingIdAt(_frame);
    if (id == null) {
      id = layer.cels.newDrawingId;
      layer = layer.withCels(layer.cels.withDrawing(id, VectorArt.empty).withKey(_frame, id));
      proj = proj.withComp(comp.updateLayer(layer.id, (_) => layer));
    }
    return (project: proj, layer: layer, drawing: id, art: layer.cels.drawings[id]!);
  }

  void commitVector(String label, Project base, String layerId, int drawing, VectorArt art, {String? mergeKey}) {
    final c = base.comp(compId);
    final next = c.updateLayer(layerId, (l) => (l as VectorLayer).withCels(l.cels.withDrawing(drawing, art)));
    live = null;
    apply(label, base.withComp(next), mergeKey: mergeKey);
  }

  // ---- rendering helpers --------------------------------------------------

  /// Flattened image of the current frame (what the user sees, without
  /// editor overlays).
  Image renderCurrent({double scale = 1, bool background = true, Rect? region, bool forExport = false}) =>
      renderCompImage(_project, comp, _frame.toDouble(), scale: scale, background: background, region: region, forExport: forExport, useCamera: false);

  @override
  void dispose() {
    canvasSignal.dispose();
    viewSignal.dispose();
    frameSignal.dispose();
    busySignal.dispose();
    super.dispose();
  }
}
