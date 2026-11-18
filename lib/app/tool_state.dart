import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/i18n.dart';
import '../core/ids.dart';
import '../engine/brush/preset.dart';
import '../model/gradient.dart';
import '../model/layer.dart';
import '../model/vector.dart';
import 'doc_selection.dart';

enum ShapeKind { line, rect, roundRect, ellipse, polygon, star, arrow, heart, bubble, burst, cloud }

extension ShapeKindLabel on ShapeKind {
  String get label => switch (this) {
        ShapeKind.line => tr('Línea', 'Line'),
        ShapeKind.rect => tr('Rectángulo', 'Rectangle'),
        ShapeKind.roundRect => tr('Rectángulo redondeado', 'Rounded rectangle'),
        ShapeKind.ellipse => tr('Elipse', 'Ellipse'),
        ShapeKind.polygon => tr('Polígono', 'Polygon'),
        ShapeKind.star => tr('Estrella', 'Star'),
        ShapeKind.arrow => tr('Flecha', 'Arrow'),
        ShapeKind.heart => tr('Corazón', 'Heart'),
        ShapeKind.bubble => tr('Globo de diálogo', 'Speech balloon'),
        ShapeKind.burst => tr('Globo de grito', 'Shout balloon'),
        ShapeKind.cloud => tr('Globo de pensamiento', 'Thought balloon'),
      };
}

enum RetouchMode { blur, sharpen, dodge, burn, saturate, desaturate }

extension RetouchModeLabel on RetouchMode {
  String get label => switch (this) {
        RetouchMode.blur => tr('Desenfocar', 'Blur'),
        RetouchMode.sharpen => tr('Enfocar', 'Sharpen'),
        RetouchMode.dodge => tr('Aclarar', 'Dodge'),
        RetouchMode.burn => tr('Oscurecer', 'Burn'),
        RetouchMode.saturate => tr('Saturar', 'Saturate'),
        RetouchMode.desaturate => tr('Desaturar', 'Desaturate'),
      };
}

enum TransformMode { free, skew, distort, perspective, warp }

extension TransformModeLabel on TransformMode {
  String get label => switch (this) {
        TransformMode.free => tr('Escalar / rotar', 'Scale / rotate'),
        TransformMode.skew => tr('Sesgar', 'Skew'),
        TransformMode.distort => tr('Distorsionar', 'Distort'),
        TransformMode.perspective => tr('Perspectiva', 'Perspective'),
        TransformMode.warp => tr('Deformar (malla)', 'Warp (mesh)'),
      };
}

enum LiquifyMode { push, twirl, pinch, bloat, restore }

extension LiquifyModeLabel on LiquifyMode {
  String get label => switch (this) {
        LiquifyMode.push => tr('Empujar', 'Push'),
        LiquifyMode.twirl => tr('Remolino', 'Twirl'),
        LiquifyMode.pinch => tr('Contraer', 'Pinch'),
        LiquifyMode.bloat => tr('Inflar', 'Bloat'),
        LiquifyMode.restore => tr('Restaurar', 'Restore'),
      };
}

class Palette {
  Palette(this.id, this.name, this.colors, {this.builtin = false});
  final String id;
  String name;
  List<int> colors;
  final bool builtin;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'colors': colors};
  static Palette fromJson(dynamic j) =>
      Palette((j as Map)['id'] as String? ?? newId('pal'), j['name'] as String? ?? '', ((j['colors'] as List?) ?? const []).map((e) => e as int).toList());
}

List<Palette> builtinPalettes() => [
      Palette('basic', tr('Básica', 'Basic'), const [
        0xFF000000, 0xFF434343, 0xFF7F7F7F, 0xFFBFBFBF, 0xFFFFFFFF, 0xFFE53935, 0xFFFB8C00, 0xFFFDD835, 0xFF7CB342, 0xFF43A047,
        0xFF00ACC1, 0xFF1E88E5, 0xFF3949AB, 0xFF8E24AA, 0xFFD81B60, 0xFF6D4C41, 0xFFFFCDD2, 0xFFFFE0B2, 0xFFFFF9C4, 0xFFC8E6C9,
        0xFFB2EBF2, 0xFFBBDEFB, 0xFFD1C4E9, 0xFFF8BBD0,
      ], builtin: true),
      Palette('skin', tr('Tonos de piel', 'Skin tones'), const [
        0xFF3B2219, 0xFF5C3A21, 0xFF8D5524, 0xFFA1665E, 0xFFC68642, 0xFFD69A6E, 0xFFE0AC69, 0xFFF1C27D, 0xFFFFDBAC, 0xFFFFE5D0,
        0xFFF7C4B4, 0xFFE8A590, 0xFFB5651D, 0xFF6F4E37,
      ], builtin: true),
      Palette('pastel', tr('Pastel', 'Pastel'), const [
        0xFFFFB3BA, 0xFFFFDFBA, 0xFFFFFFBA, 0xFFBAFFC9, 0xFFBAE1FF, 0xFFD5BAFF, 0xFFFFBAF3, 0xFFE2F0CB, 0xFFB5EAD7, 0xFFC7CEEA,
        0xFFFFDAC1, 0xFFFF9AA2,
      ], builtin: true),
      Palette('retro16', tr('Retro 16', 'Retro 16'), const [
        0xFF1A1C2C, 0xFF5D275D, 0xFFB13E53, 0xFFEF7D57, 0xFFFFCD75, 0xFFA7F070, 0xFF38B764, 0xFF257179, 0xFF29366F, 0xFF3B5DC9,
        0xFF41A6F6, 0xFF73EFF7, 0xFFF4F4F4, 0xFF94B0C2, 0xFF566C86, 0xFF333C57,
      ], builtin: true),
      Palette('gameboy', tr('Verde 4 tonos', '4-tone green'), const [0xFF0F380F, 0xFF306230, 0xFF8BAC0F, 0xFF9BBC0F], builtin: true),
      Palette('grays', tr('Grises', 'Greys'), const [
        0xFF000000, 0xFF1A1A1A, 0xFF333333, 0xFF4D4D4D, 0xFF666666, 0xFF808080, 0xFF999999, 0xFFB3B3B3, 0xFFCCCCCC, 0xFFE6E6E6, 0xFFFFFFFF,
      ], builtin: true),
      Palette('comic', tr('Cómic', 'Comic'), const [
        0xFF111111, 0xFFFFFFFF, 0xFFED1C24, 0xFFFFF200, 0xFF00A2E8, 0xFF22B14C, 0xFFFF7F27, 0xFFA349A4, 0xFFFFAEC9, 0xFFB97A57,
      ], builtin: true),
    ];

/// Current tool, colours, brushes and per-tool options.
class ToolState extends ChangeNotifier {
  ToolState() {
    brushes = builtinBrushes();
    palettes = builtinPalettes();
  }

  // ---- tool ---------------------------------------------------------------
  String _toolId = 'brush';
  String get toolId => _toolId;
  set toolId(String v) {
    if (v == _toolId) return;
    _toolId = v;
    notifyListeners();
  }

  // ---- colours ------------------------------------------------------------
  Color _fg = const Color(0xFF1B1B1F), _bg = const Color(0xFFFFFFFF);
  Color get fg => _fg;
  Color get bg => _bg;
  List<Color> colorHistory = [];
  late List<Palette> palettes;
  String paletteId = 'basic';

  Palette get palette => palettes.firstWhere((p) => p.id == paletteId, orElse: () => palettes.first);

  set fg(Color c) {
    if (c == _fg) return;
    _fg = c;
    notifyListeners();
  }

  set bg(Color c) {
    if (c == _bg) return;
    _bg = c;
    notifyListeners();
  }

  void swapColors() {
    final t = _fg;
    _fg = _bg;
    _bg = t;
    notifyListeners();
  }

  void resetColors() {
    _fg = const Color(0xFF000000);
    _bg = const Color(0xFFFFFFFF);
    notifyListeners();
  }

  /// Remembers a colour that was actually used on the canvas.
  void pushColorHistory(Color c) {
    final opaque = c.withValues(alpha: 1);
    if (colorHistory.isNotEmpty && colorHistory.first == opaque) return;
    colorHistory = [opaque, ...colorHistory.where((e) => e != opaque)].take(28).toList();
    notifyListeners();
  }

  // ---- brushes ------------------------------------------------------------
  late List<BrushPreset> brushes;

  /// Brush used by each brush-like tool slot.
  final Map<String, String> slotBrush = {'brush': 'ink_pen', 'eraser': 'eraser_hard', 'blend': 'smudge'};

  String slotOf(String toolId) => switch (toolId) {
        'eraser' => 'eraser',
        'smudge' => 'blend',
        _ => 'brush',
      };

  BrushPreset brushFor(String slot) {
    final id = slotBrush[slot];
    return brushes.firstWhere((b) => b.id == id, orElse: () => brushes.first);
  }

  /// Brush of the active tool (falls back to the paint brush).
  BrushPreset get brush => brushFor(slotOf(_toolId));

  void selectBrush(BrushPreset b) {
    final slot = b.erase ? 'eraser' : (b.engine == BrushEngine.smudge ? 'blend' : 'brush');
    slotBrush[slot] = b.id;
    if (slot == 'eraser') {
      _toolId = 'eraser';
    } else if (slot == 'blend') {
      _toolId = 'smudge';
    } else if (_toolId == 'eraser' || _toolId == 'smudge' || !_brushTools.contains(_toolId)) {
      _toolId = 'brush';
    }
    notifyListeners();
  }

  static const _brushTools = {'brush', 'eraser', 'smudge'};

  /// Replaces the preset with the same id (live edits from the option bar
  /// and the brush editor).
  void updateBrush(BrushPreset b) {
    final i = brushes.indexWhere((e) => e.id == b.id);
    if (i < 0) return;
    brushes = [...brushes]..[i] = b;
    notifyListeners();
    if (!b.builtin) saveCustomBrushes();
  }

  BrushPreset duplicateBrush(BrushPreset b, {String? name}) {
    final copy = b.copyWith(id: newId('b'), name: name ?? '${b.name} ${tr('copia', 'copy')}', category: 'custom', builtin: false);
    brushes = [...brushes, copy];
    selectBrush(copy);
    saveCustomBrushes();
    return copy;
  }

  void deleteBrush(BrushPreset b) {
    if (b.builtin) return;
    brushes = brushes.where((e) => e.id != b.id).toList();
    for (final slot in slotBrush.keys.toList()) {
      if (slotBrush[slot] == b.id) {
        slotBrush[slot] = switch (slot) {
          'eraser' => 'eraser_hard',
          'blend' => 'smudge',
          _ => 'ink_pen',
        };
      }
    }
    notifyListeners();
    saveCustomBrushes();
  }

  void resetBuiltinBrush(String id) {
    final def = builtinBrushes().where((b) => b.id == id);
    if (def.isEmpty) return;
    updateBrush(def.first);
  }

  /// Imports presets from a `.drawlybrushes` JSON document.
  int importBrushes(String json) {
    final data = jsonDecode(json);
    final list = data is Map ? (data['brushes'] as List? ?? const []) : (data as List);
    var n = 0;
    for (final j in list) {
      final b = BrushPreset.fromJson(j).copyWith(id: newId('b'), builtin: false);
      brushes = [...brushes, b.category == 'custom' ? b : b.copyWith(category: b.category)];
      n++;
    }
    if (n > 0) {
      notifyListeners();
      saveCustomBrushes();
    }
    return n;
  }

  String exportBrushes(Iterable<BrushPreset> list) => const JsonEncoder.withIndent(' ').convert({
        'format': 'drawly-brushes',
        'version': 1,
        'brushes': list.map((b) => b.toJson()).toList(),
      });

  static const _brushKey = 'drawly.brushes.v1';
  static const _paletteKey = 'drawly.palettes.v1';

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_brushKey);
      if (raw != null) {
        final list = (jsonDecode(raw) as List).map((j) => BrushPreset.fromJson(j).copyWith(builtin: false)).toList();
        brushes = [...builtinBrushes(), ...list];
      }
      final pr = prefs.getString(_paletteKey);
      if (pr != null) {
        palettes = [...builtinPalettes(), ...(jsonDecode(pr) as List).map(Palette.fromJson)];
      }
    } catch (_) {}
  }

  Future<void> saveCustomBrushes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_brushKey, jsonEncode(brushes.where((b) => !b.builtin).map((b) => b.toJson()).toList()));
    } catch (_) {}
  }

  Future<void> savePalettes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_paletteKey, jsonEncode(palettes.where((p) => !p.builtin).map((p) => p.toJson()).toList()));
    } catch (_) {}
  }

  Palette addPalette(String name, List<int> colors) {
    final p = Palette(newId('pal'), name, colors);
    palettes = [...palettes, p];
    paletteId = p.id;
    notifyListeners();
    savePalettes();
    return p;
  }

  void addToPalette(Color c) {
    var p = palette;
    if (p.builtin) p = addPalette(tr('Mi paleta', 'My palette'), []);
    if (!p.colors.contains(c.toARGB32())) p.colors = [...p.colors, c.toARGB32()];
    notifyListeners();
    savePalettes();
  }

  void removeFromPalette(int argb) {
    final p = palette;
    if (p.builtin) return;
    p.colors = p.colors.where((c) => c != argb).toList();
    notifyListeners();
    savePalettes();
  }

  void deletePalette(Palette p) {
    if (p.builtin) return;
    palettes = palettes.where((e) => e.id != p.id).toList();
    paletteId = palettes.first.id;
    notifyListeners();
    savePalettes();
  }

  // ---- per-tool options ---------------------------------------------------

  void set(void Function() f) {
    f();
    notifyListeners();
  }

  // selection
  SelectMode selectMode = SelectMode.replace;
  double selectFeather = 0;
  bool selectAntiAlias = true;
  String marqueeShape = 'rect';

  // wand / bucket
  int tolerance = 32;
  bool contiguous = true;
  SampleSource sampleSource = SampleSource.layer;
  double fillExpand = 0;
  int fillGap = 0;
  double fillOpacity = 1;

  // gradient
  GradientKind gradientKind = GradientKind.linear;

  /// null = foreground -> background.
  List<GradStop>? gradientStops;
  bool gradientToTransparent = false;
  double gradientOpacity = 1;
  bool gradientRepeat = false;

  GradientSpec gradientFor(Offset from, Offset to) {
    final stops = gradientStops ??
        [
          GradStop(0, _fg),
          GradStop(1, gradientToTransparent ? _fg.withValues(alpha: 0) : _bg),
        ];
    return GradientSpec(kind: gradientKind, stops: stops, from: from, to: to, repeat: gradientRepeat);
  }

  // shapes
  ShapeKind shapeKind = ShapeKind.rect;
  bool shapeFill = true;
  bool shapeStroke = false;
  double shapeStrokeWidth = 4;
  double shapeRadius = 24;
  int shapeSides = 6;
  double starRatio = 0.5;
  StrokeCap strokeCap = StrokeCap.round;
  StrokeJoin strokeJoin = StrokeJoin.round;
  List<double> strokeDash = const [];
  WidthProfile strokeProfile = WidthProfile.uniform;
  bool shapeAntiAlias = true;

  // text
  String fontFamily = '';
  double fontSize = 72;
  bool fontBold = false;
  bool fontItalic = false;
  int textAlign = 0;

  // eyedropper
  bool pickAllLayers = true;
  int pickRadius = 0;

  // retouch / clone
  RetouchMode retouchMode = RetouchMode.blur;
  double retouchStrength = 0.6;
  double retouchSize = 60;
  Offset? cloneSource;
  bool cloneAligned = true;
  bool cloneAllLayers = false;

  // transform / liquify
  TransformMode transformMode = TransformMode.free;
  LiquifyMode liquifyMode = LiquifyMode.push;
  double liquifySize = 120;
  double liquifyStrength = 0.5;

  // pen
  bool penAutoClose = true;

  // move
  bool moveAutoSelect = false;

  // brush as vector strokes on vector layers
  LayerBlend strokeBlend = LayerBlend.normal;
}
