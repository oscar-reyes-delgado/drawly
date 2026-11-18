import 'package:flutter/services.dart';

/// A keyboard shortcut such as `Ctrl+Shift+Z`, parsed from / formatted to
/// text so users can rebind commands.
class KeyCombo {
  const KeyCombo(this.key, {this.ctrl = false, this.shift = false, this.alt = false});

  final LogicalKeyboardKey key;
  final bool ctrl, shift, alt;

  static final Map<String, LogicalKeyboardKey> _named = {
    'Space': LogicalKeyboardKey.space,
    'Enter': LogicalKeyboardKey.enter,
    'Esc': LogicalKeyboardKey.escape,
    'Tab': LogicalKeyboardKey.tab,
    'Del': LogicalKeyboardKey.delete,
    'Backspace': LogicalKeyboardKey.backspace,
    'Left': LogicalKeyboardKey.arrowLeft,
    'Right': LogicalKeyboardKey.arrowRight,
    'Up': LogicalKeyboardKey.arrowUp,
    'Down': LogicalKeyboardKey.arrowDown,
    'Home': LogicalKeyboardKey.home,
    'End': LogicalKeyboardKey.end,
    'PgUp': LogicalKeyboardKey.pageUp,
    'PgDn': LogicalKeyboardKey.pageDown,
    'F1': LogicalKeyboardKey.f1,
    'F2': LogicalKeyboardKey.f2,
    'F3': LogicalKeyboardKey.f3,
    'F4': LogicalKeyboardKey.f4,
    'F5': LogicalKeyboardKey.f5,
    'F6': LogicalKeyboardKey.f6,
    'F7': LogicalKeyboardKey.f7,
    'F8': LogicalKeyboardKey.f8,
    'F9': LogicalKeyboardKey.f9,
    'F10': LogicalKeyboardKey.f10,
    'F11': LogicalKeyboardKey.f11,
    'F12': LogicalKeyboardKey.f12,
    ',': LogicalKeyboardKey.comma,
    '.': LogicalKeyboardKey.period,
    '/': LogicalKeyboardKey.slash,
    ';': LogicalKeyboardKey.semicolon,
    "'": LogicalKeyboardKey.quote,
    '[': LogicalKeyboardKey.bracketLeft,
    ']': LogicalKeyboardKey.bracketRight,
    '-': LogicalKeyboardKey.minus,
    '=': LogicalKeyboardKey.equal,
    '0': LogicalKeyboardKey.digit0,
    '1': LogicalKeyboardKey.digit1,
    '2': LogicalKeyboardKey.digit2,
    '3': LogicalKeyboardKey.digit3,
    '4': LogicalKeyboardKey.digit4,
    '5': LogicalKeyboardKey.digit5,
    '6': LogicalKeyboardKey.digit6,
    '7': LogicalKeyboardKey.digit7,
    '8': LogicalKeyboardKey.digit8,
    '9': LogicalKeyboardKey.digit9,
  };

  static final Map<LogicalKeyboardKey, String> _names = {for (final e in _named.entries) e.value: e.key};

  static LogicalKeyboardKey? _letter(String s) {
    if (s.length != 1) return null;
    final c = s.toLowerCase().codeUnitAt(0);
    if (c < 0x61 || c > 0x7A) return null;
    return LogicalKeyboardKey(c);
  }

  static KeyCombo? parse(String text) {
    final t = text.trim();
    if (t.isEmpty) return null;
    var ctrl = false, shift = false, alt = false;
    final parts = t == '+' ? ['+'] : t.split('+');
    // a trailing '+' key ("Ctrl++")
    if (t.endsWith('++')) {
      parts
        ..removeWhere((p) => p.isEmpty)
        ..add('=');
    }
    LogicalKeyboardKey? key;
    for (final raw in parts) {
      final p = raw.trim();
      switch (p.toLowerCase()) {
        case 'ctrl' || 'cmd' || 'control' || 'meta':
          ctrl = true;
        case 'shift':
          shift = true;
        case 'alt' || 'option':
          alt = true;
        default:
          key = _named[p] ?? _named[_cap(p)] ?? _letter(p);
      }
    }
    return key == null ? null : KeyCombo(key, ctrl: ctrl, shift: shift, alt: alt);
  }

  static String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1).toLowerCase();

  /// Combo for a key event, or null for pure modifier presses.
  static KeyCombo? fromEvent(KeyEvent e) {
    final k = e.logicalKey;
    if (_isModifier(k)) return null;
    final hw = HardwareKeyboard.instance;
    return KeyCombo(_normalize(k), ctrl: hw.isControlPressed || hw.isMetaPressed, shift: hw.isShiftPressed, alt: hw.isAltPressed);
  }

  static bool _isModifier(LogicalKeyboardKey k) =>
      k == LogicalKeyboardKey.controlLeft ||
      k == LogicalKeyboardKey.controlRight ||
      k == LogicalKeyboardKey.shiftLeft ||
      k == LogicalKeyboardKey.shiftRight ||
      k == LogicalKeyboardKey.altLeft ||
      k == LogicalKeyboardKey.altRight ||
      k == LogicalKeyboardKey.metaLeft ||
      k == LogicalKeyboardKey.metaRight ||
      k == LogicalKeyboardKey.control ||
      k == LogicalKeyboardKey.shift ||
      k == LogicalKeyboardKey.alt ||
      k == LogicalKeyboardKey.meta;

  /// Upper-case letters and numpad keys map onto their plain counterparts.
  static LogicalKeyboardKey _normalize(LogicalKeyboardKey k) {
    final id = k.keyId;
    if (id >= 0x41 && id <= 0x5A) return LogicalKeyboardKey(id + 0x20);
    if (k == LogicalKeyboardKey.numpadEnter) return LogicalKeyboardKey.enter;
    if (k == LogicalKeyboardKey.numpadAdd) return LogicalKeyboardKey.equal;
    if (k == LogicalKeyboardKey.numpadSubtract) return LogicalKeyboardKey.minus;
    if (k == LogicalKeyboardKey.add) return LogicalKeyboardKey.equal;
    return k;
  }

  @override
  String toString() {
    final id = key.keyId;
    final name = _names[key] ?? ((id >= 0x61 && id <= 0x7A) ? String.fromCharCode(id).toUpperCase() : key.keyLabel);
    return [if (ctrl) 'Ctrl', if (shift) 'Shift', if (alt) 'Alt', name].join('+');
  }

  @override
  bool operator ==(Object other) => other is KeyCombo && other.key == key && other.ctrl == ctrl && other.shift == shift && other.alt == alt;

  @override
  int get hashCode => Object.hash(key, ctrl, shift, alt);
}
