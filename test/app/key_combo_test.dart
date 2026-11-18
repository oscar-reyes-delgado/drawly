import 'package:drawly/app/key_combo.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parse modifiers and key', () {
    final k = KeyCombo.parse('Ctrl+Shift+Z')!;
    expect(k.ctrl, isTrue);
    expect(k.shift, isTrue);
    expect(k.alt, isFalse);
    expect(k.key, LogicalKeyboardKey.keyZ);
  });

  test('parse empty text', () {
    expect(KeyCombo.parse(''), isNull);
    expect(KeyCombo.parse('   '), isNull);
  });

  test('modifiers are case-insensitive', () {
    final k = KeyCombo.parse('ctrl+s')!;
    expect(k.ctrl, isTrue);
    expect(k.key, LogicalKeyboardKey.keyS);
    expect(KeyCombo.parse('CTRL+SHIFT+s'), KeyCombo.parse('Ctrl+Shift+S'));
  });

  test('parse / toString round trip', () {
    for (final s in ['Ctrl+S', 'Ctrl+Shift+Z', 'Alt+Left', 'F5', 'Space', '[', 'Ctrl+=', 'Del']) {
      expect(KeyCombo.parse(s).toString(), s);
    }
  });

  test('Ctrl++ means Ctrl+=', () {
    expect(KeyCombo.parse('Ctrl++'), KeyCombo.parse('Ctrl+='));
    expect(KeyCombo.parse('Ctrl++').toString(), 'Ctrl+=');
  });

  test('equality and hashCode', () {
    final a = KeyCombo.parse('Ctrl+S')!;
    const b = KeyCombo(LogicalKeyboardKey.keyS, ctrl: true);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(const KeyCombo(LogicalKeyboardKey.keyS, ctrl: true, shift: true)));
    expect(a, isNot(const KeyCombo(LogicalKeyboardKey.keyD, ctrl: true)));
    expect({a, b}.length, 1);
  });
}
