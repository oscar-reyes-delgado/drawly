import 'dart:ui';

import 'package:drawly/core/color_utils.dart';
import 'package:flutter_test/flutter_test.dart';

const double _tol = 1 / 255 + 1e-9;

void expectColor(Color actual, Color expected) {
  expect(actual.r, closeTo(expected.r, _tol), reason: 'red of ${actual.hex} vs ${expected.hex}');
  expect(actual.g, closeTo(expected.g, _tol), reason: 'green of ${actual.hex} vs ${expected.hex}');
  expect(actual.b, closeTo(expected.b, _tol), reason: 'blue of ${actual.hex} vs ${expected.hex}');
}

const samples = [
  Color(0xFFFF0000),
  Color(0xFF00FF00),
  Color(0xFF0000FF),
  Color(0xFFFFFFFF),
  Color(0xFF000000),
  Color(0xFF808080),
  Color(0xFF12ABEF),
  Color(0xFFC86432),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('colour spaces round trip', () {
    test('Hsv', () {
      for (final c in samples) {
        expectColor(Hsv.fromColor(c).toColor(), c);
      }
    });

    test('Hsl', () {
      for (final c in samples) {
        expectColor(Hsl.fromColor(c).toColor(), c);
      }
    });

    test('Cmyk', () {
      for (final c in samples) {
        expectColor(Cmyk.fromColor(c).toColor(), c);
      }
    });
  });

  group('hex', () {
    test('parseHex', () {
      expect(parseHex('#abc')!.toARGB32(), 0xFFAABBCC);
      expect(parseHex('AABBCC')!.toARGB32(), 0xFFAABBCC);
      final withAlpha = parseHex('AABBCC80')!;
      expect(withAlpha.toARGB32(), 0x80AABBCC);
      expect(withAlpha.a8, 0x80);
      expect(parseHex('zzz'), isNull);
      expect(parseHex('not a colour'), isNull);
      expect(parseHex('abcd'), isNull);
    });

    test('ColorX.hex', () {
      expect(const Color(0xFF12ABEF).hex, '12ABEF');
    });
  });

  test('harmonyColors sizes', () {
    const base = Color(0xFF3366CC);
    const expected = {
      Harmony.complementary: 2,
      Harmony.analogous: 3,
      Harmony.triadic: 3,
      Harmony.splitComplementary: 3,
      Harmony.tetradic: 4,
      Harmony.square: 4,
      Harmony.monochromatic: 5,
    };
    for (final e in expected.entries) {
      expect(harmonyColors(base, e.key).length, e.value, reason: e.key.name);
    }
  });

  test('mixPigment cyan + yellow drifts to green', () {
    final mix = mixPigment(const Color(0xFF00FFFF), const Color(0xFFFFFF00), 0.5);
    expect(mix.g, greaterThan(mix.r));
    expect(mix.g, greaterThan(mix.b));
  });

  test('colorBlindMatrix', () {
    for (final k in ColorBlindness.values) {
      expect(colorBlindMatrix(k).length, 20, reason: k.name);
    }
    expect(colorBlindMatrix(ColorBlindness.none), const <double>[1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0]);
  });
}
