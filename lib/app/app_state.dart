import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/i18n.dart';
import '../engine/brush/tips.dart';
import '../engine/filters.dart';
import '../model/document.dart';
import '../tools/registry.dart';
import '../tools/tool.dart';
import 'audio_backend.dart';
import 'audio_sync.dart';
import 'autosave.dart';
import 'easy_autosave.dart';
import 'voice_recorder.dart';
import '../platform/io.dart' as io;
import 'package:path/path.dart' as p;
import 'commands.dart';
import 'document_controller.dart';
import 'key_combo.dart';
import 'playback.dart';
import 'settings.dart';
import 'tool_state.dart';

/// Application-wide state: open documents, tools, settings, commands.
class AppState extends ChangeNotifier {
  AppState._();
  static final AppState I = AppState._();

  final Settings settings = Settings();
  final ToolState ts = ToolState();
  final List<DocumentController> docs = [];
  int _active = -1;

  final Map<String, Tool> toolMap = {};
  final CommandRegistry commands = CommandRegistry();
  late final Playback playback = Playback(this);

  /// Plays the timeline audio during playback (created by [init]; null in tests).
  AudioSync? audio;

  /// Voice recording over the animation.
  final VoiceRecorder voice = VoiceRecorder();

  /// Crash-recovery copies (native platforms; created by [init]).
  AutosaveService? autosave;

  /// Easy mode: saves documents with a file shortly after each edit.
  EasyFileSaver? easySaver;

  /// Repaints tool / selection overlays.
  final Signal overlaySignal = Signal();

  /// Transient status message.
  final ValueNotifier<String?> message = ValueNotifier<String?>(null);
  Timer? _messageTimer;

  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  bool _ready = false;
  bool get isReady => _ready;

  /// Temporary tool while a modifier is held (space = hand, alt = picker).
  String? _tempTool;

  Future<void> init() async {
    if (_ready) return;
    await settings.load();
    await ts.load();
    await Future.wait([BrushTips.instance.ensureLoaded(), Shaders.instance.ensureLoaded()]);
    registerTools(this);
    registerCommands(this);
    final sync = audio = AudioSync(PluginAudioBackend());
    playback.onStart = (frame) {
      final d = doc;
      if (d != null) sync.start(d.project, d.timeline, frame.toDouble(), speed: playback.speed);
    };
    playback.onStop = sync.stop;
    if (io.hasFileSystem) {
      autosave = AutosaveService(
        directory: () async => p.join((await io.appDataDir()) ?? (await io.tempDir()) ?? '.', 'recovery'),
        interval: Duration(minutes: settings.autosaveMinutes),
        busy: () => tool.active,
      );
      easySaver = EasyFileSaver(enabled: () => settings.isEasy && settings.autosaveMinutes > 0, busy: () => tool.active);
      settings.addListener(() => autosave?.interval = Duration(minutes: settings.autosaveMinutes));
    }
    ts.addListener(_onToolState);
    settings.addListener(notifyListeners);
    _ready = true;
    notifyListeners();
  }

  // ---- documents ----------------------------------------------------------

  DocumentController? get doc => _active >= 0 && _active < docs.length ? docs[_active] : null;
  int get activeIndex => _active;

  DocumentController addDocument(Project p, {String? title, String? path}) {
    final d = DocumentController(p, title: title, filePath: path);
    d.history.maxEntries = settings.historyLimit;
    d.history.nonLinear = settings.nonLinearHistory;
    docs.add(d);
    _active = docs.length - 1;
    d.addListener(_onDocChanged);
    if (settings.autosaveMinutes > 0) autosave?.attach(d);
    easySaver?.attach(d);
    notifyListeners();
    return d;
  }

  void closeDocument(DocumentController d) {
    final i = docs.indexOf(d);
    if (i < 0) return;
    playback.stop();
    d.removeListener(_onDocChanged);
    // closing on purpose (saved, or the user chose to discard): drop its recovery copy
    autosave?.detach(d);
    easySaver?.detach(d);
    docs.removeAt(i);
    d.dispose();
    if (_active >= docs.length) _active = docs.length - 1;
    notifyListeners();
  }

  void activate(int i) {
    if (i < 0 || i >= docs.length || i == _active) return;
    playback.stop();
    tool.onCancel();
    _active = i;
    notifyListeners();
  }

  void _onDocChanged() => overlaySignal.fire();

  // ---- tools --------------------------------------------------------------

  Tool get tool => toolMap[_tempTool ?? ts.toolId] ?? toolMap['brush']!;
  String get activeToolId => _tempTool ?? ts.toolId;
  String? _lastTool;

  void _onToolState() {
    if (_lastTool != ts.toolId) {
      final prev = toolMap[_lastTool];
      prev?.onCancel();
      prev?.onDeactivate();
      _lastTool = ts.toolId;
      toolMap[ts.toolId]?.onActivate();
    }
    overlaySignal.fire();
    notifyListeners();
  }

  void setTool(String id) {
    if (!toolMap.containsKey(id)) return;
    _tempTool = null;
    ts.toolId = id;
  }

  /// Switches tool only while a key is held.
  void setTempTool(String? id) {
    if (id != null && !toolMap.containsKey(id)) return;
    if (tool.active) {
      // never swap tools mid-stroke: apply once the stroke ends
      _wantTemp = id;
      _hasWant = true;
      return;
    }
    _hasWant = false;
    if (_tempTool == id) return;
    tool.onCancel();
    _tempTool = id;
    overlaySignal.fire();
    notifyListeners();
  }

  String? _wantTemp;
  bool _hasWant = false;

  /// Called by the canvas when a pointer interaction ends.
  void toolIdle() {
    if (!_hasWant) return;
    _hasWant = false;
    setTempTool(_wantTemp);
  }

  // ---- keyboard -----------------------------------------------------------

  /// Root focus of the workspace; the canvas grabs it on pointer down.
  final FocusNode focusNode = FocusNode(debugLabel: 'drawly');

  static bool get _typing => FocusManager.instance.primaryFocus?.context?.widget is EditableText;

  /// Commands that keep firing while their key is held.
  static const Set<String> _repeatable = {
    'edit.undo', 'edit.redo', 'brush.smaller', 'brush.larger', 'view.zoomIn', 'view.zoomOut',
    'anim.nextFrame', 'anim.prevFrame', 'layer.selectAbove', 'layer.selectBelow',
  };

  DateTime? _spaceDown;

  /// In easy mode, Space released before this plays / pauses instead of panning.
  static const Duration spaceTapTime = Duration(milliseconds: 220);

  KeyEventResult handleKey(FocusNode node, KeyEvent e) {
    if (_typing) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final hw = HardwareKeyboard.instance;
    if (k == LogicalKeyboardKey.space && !hw.isControlPressed) {
      if (e is KeyDownEvent) {
        _spaceDown = DateTime.now();
        setTempTool('hand');
      }
      if (e is KeyUpEvent) {
        setTempTool(null);
        // Easy mode: a quick tap plays / pauses; holding still pans.
        final down = _spaceDown;
        _spaceDown = null;
        if (settings.isEasy && down != null && DateTime.now().difference(down) < spaceTapTime && doc != null) playback.toggle();
      }
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.altLeft || k == LogicalKeyboardKey.altRight) {
      if (e is KeyDownEvent && kAltPicksColor.contains(ts.toolId) && _tempTool == null) setTempTool('eyedropper');
      if (e is KeyUpEvent && (_tempTool == 'eyedropper' || (_hasWant && _wantTemp == 'eyedropper'))) setTempTool(null);
      return KeyEventResult.ignored;
    }
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    if (tool.onKey(e)) return KeyEventResult.handled;
    final combo = KeyCombo.fromEvent(e);
    if (combo == null) return KeyEventResult.ignored;
    final cmd = commands.forCombo(combo);
    if (cmd == null) return KeyEventResult.ignored;
    if (e is KeyRepeatEvent && !_repeatable.contains(cmd.id)) return KeyEventResult.handled;
    commands.run(cmd.id);
    return KeyEventResult.handled;
  }

  // ---- messages -----------------------------------------------------------

  void toast(String text, {Duration duration = const Duration(seconds: 3)}) {
    message.value = text;
    _messageTimer?.cancel();
    _messageTimer = Timer(duration, () => message.value = null);
  }

  BuildContext? get context => navigatorKey.currentContext;

  String get docTitle => doc == null ? 'Drawly' : '${doc!.title}${doc!.dirty ? ' •' : ''} — Drawly';

  String untitledName() {
    final base = tr('Sin título', 'Untitled');
    var i = 1;
    while (docs.any((d) => d.title == '$base $i')) {
      i++;
    }
    return '$base $i';
  }
}
