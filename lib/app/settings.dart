import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/color_utils.dart';
import '../core/i18n.dart';

/// User preferences, persisted as one JSON blob.
class Settings extends ChangeNotifier {
  ThemeMode themeMode = ThemeMode.dark;
  double uiScale = 1.0;
  String lang = 'es';
  bool leftHanded = false;
  bool highContrast = false;
  ColorBlindness colorBlind = ColorBlindness.none;
  Color accent = const Color(0xFF4F8CFF);

  /// Derive pressure from stroke speed for mice / fingers.
  bool simulatePressure = true;

  /// One finger draws (true) or pans (false, stylus-only drawing).
  bool fingerDraws = true;

  /// Exponent applied to pen pressure (1 = linear, <1 softer, >1 firmer).
  double pressureGamma = 1.0;
  bool wheelZooms = true;
  bool twoFingerUndo = true;

  /// 0 = unlimited.
  int historyLimit = 300;
  bool nonLinearHistory = false;
  int autosaveMinutes = 3;

  /// Render the canvas at reduced resolution while playing back.
  bool lowResPlayback = true;
  int frameCacheMb = 512;

  /// Accessibility: modifier keys latch until the next key press.
  bool stickyKeys = false;
  bool reduceMotion = false;
  bool showTips = true;

  /// Command id -> shortcut string overrides ('' = unbound).
  Map<String, String> shortcuts = {};
  List<String> recentFiles = [];
  String workspace = 'paint';
  Map<String, bool> panelVisible = {};
  double dockWidth = 300;
  double timelineHeight = 230;
  bool timelineVisible = true;

  /// Watermark text applied on export when enabled.
  String watermark = '';
  bool watermarkEnabled = false;

  /// Optional AI service endpoint (OpenAI-compatible images API) and key.
  String aiEndpoint = '';
  String aiKey = '';

  static const _key = 'drawly.settings.v1';
  SharedPreferences? _prefs;

  Future<void> load() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      final raw = _prefs!.getString(_key);
      if (raw != null) _fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // first run or unreadable prefs: keep defaults
    }
    I18n.instance.lang = lang;
  }

  Future<void> save() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs!.setString(_key, jsonEncode(_toJson()));
    } catch (_) {}
  }

  /// Applies [f], notifies listeners and persists.
  void update(void Function(Settings s) f) {
    f(this);
    I18n.instance.lang = lang;
    notifyListeners();
    save();
  }

  void addRecent(String path) {
    recentFiles = [path, ...recentFiles.where((p) => p != path)].take(12).toList();
    notifyListeners();
    save();
  }

  Map<String, dynamic> _toJson() => {
        'theme': themeMode.name,
        'uiScale': uiScale,
        'lang': lang,
        'leftHanded': leftHanded,
        'highContrast': highContrast,
        'colorBlind': colorBlind.name,
        'accent': accent.toARGB32(),
        'simulatePressure': simulatePressure,
        'fingerDraws': fingerDraws,
        'pressureGamma': pressureGamma,
        'wheelZooms': wheelZooms,
        'twoFingerUndo': twoFingerUndo,
        'historyLimit': historyLimit,
        'nonLinearHistory': nonLinearHistory,
        'autosaveMinutes': autosaveMinutes,
        'lowResPlayback': lowResPlayback,
        'frameCacheMb': frameCacheMb,
        'stickyKeys': stickyKeys,
        'reduceMotion': reduceMotion,
        'showTips': showTips,
        'shortcuts': shortcuts,
        'recent': recentFiles,
        'workspace': workspace,
        'panels': panelVisible,
        'dockWidth': dockWidth,
        'timelineHeight': timelineHeight,
        'timelineVisible': timelineVisible,
        'watermark': watermark,
        'watermarkEnabled': watermarkEnabled,
        'aiEndpoint': aiEndpoint,
        'aiKey': aiKey,
      };

  void _fromJson(Map<String, dynamic> m) {
    T pick<T>(String k, T def) => m[k] is T ? m[k] as T : def;
    double num_(String k, double def) => (m[k] as num?)?.toDouble() ?? def;
    themeMode = ThemeMode.values.firstWhere((t) => t.name == m['theme'], orElse: () => ThemeMode.dark);
    uiScale = num_('uiScale', 1).clamp(0.75, 2.0);
    lang = pick('lang', 'es');
    leftHanded = pick('leftHanded', false);
    highContrast = pick('highContrast', false);
    colorBlind = ColorBlindness.values.firstWhere((c) => c.name == m['colorBlind'], orElse: () => ColorBlindness.none);
    accent = Color(pick('accent', 0xFF4F8CFF));
    simulatePressure = pick('simulatePressure', true);
    fingerDraws = pick('fingerDraws', true);
    pressureGamma = num_('pressureGamma', 1).clamp(0.2, 4.0);
    wheelZooms = pick('wheelZooms', true);
    twoFingerUndo = pick('twoFingerUndo', true);
    historyLimit = pick('historyLimit', 300);
    nonLinearHistory = pick('nonLinearHistory', false);
    autosaveMinutes = pick('autosaveMinutes', 3);
    lowResPlayback = pick('lowResPlayback', true);
    frameCacheMb = pick('frameCacheMb', 512);
    stickyKeys = pick('stickyKeys', false);
    reduceMotion = pick('reduceMotion', false);
    showTips = pick('showTips', true);
    shortcuts = ((m['shortcuts'] as Map?) ?? const {}).map((k, v) => MapEntry('$k', '$v'));
    recentFiles = ((m['recent'] as List?) ?? const []).map((e) => '$e').toList();
    workspace = pick('workspace', 'paint');
    panelVisible = ((m['panels'] as Map?) ?? const {}).map((k, v) => MapEntry('$k', v == true));
    dockWidth = num_('dockWidth', 300).clamp(220.0, 600.0);
    timelineHeight = num_('timelineHeight', 230).clamp(120.0, 700.0);
    timelineVisible = pick('timelineVisible', true);
    watermark = pick('watermark', '');
    watermarkEnabled = pick('watermarkEnabled', false);
    aiEndpoint = pick('aiEndpoint', '');
    aiKey = pick('aiKey', '');
  }
}
