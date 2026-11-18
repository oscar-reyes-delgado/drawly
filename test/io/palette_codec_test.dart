import 'dart:convert';
import 'dart:typed_data';

import 'package:drawly/io/palette_codec.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List text(String value) => Uint8List.fromList(utf8.encode(value));

class Binary {
  final bytes = BytesBuilder();
  void u16(int n) => bytes.add((ByteData(2)..setUint16(0, n, Endian.big)).buffer.asUint8List());
  void u32(int n) => bytes.add((ByteData(4)..setUint32(0, n, Endian.big)).buffer.asUint8List());
  void float(double n) => bytes.add((ByteData(4)..setFloat32(0, n, Endian.big)).buffer.asUint8List());
  void ascii(String value) => bytes.add(value.codeUnits);
  void name(String value) { u16(value.length + 1); for (final c in value.codeUnits) { u16(c); } u16(0); }
  void block(int type, Binary body) { u16(type); u32(body.bytes.length); bytes.add(body.bytes.takeBytes()); }
  Uint8List take() => bytes.takeBytes();
}

Uint8List aco(List<List<int>> entries) {
  final b = Binary()..u16(1)..u16(entries.length);
  for (final entry in entries) { for (final n in entry) { b.u16(n); } }
  return b.take();
}

Uint8List ase() {
  final b = Binary()..ascii('ASEF')..u16(1)..u16(0)..u32(7);
  b.block(0xc001, Binary()..name('Grupo 🎨'));
  b.block(1, Binary()..name('Cyan')..ascii('CMYK')..float(1)..float(0)..float(0)..float(0)..u16(0));
  b.block(1, Binary()..name('Gray')..ascii('Gray')..float(0.5)..u16(1));
  b.block(1, Binary()..name('Unsupported')..ascii('LAB ')..float(50)..float(0)..float(0)..u16(0));
  b.block(0x1234, Binary()..ascii('unknown'));
  b.block(1, Binary()..name('Red')..ascii('RGB ')..float(1)..float(0)..float(0)..u16(2));
  b.block(0xc002, Binary());
  return b.take();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const colors = [0xff000000, 0xffffffff, 0xff00ffff, 0xff12abef, 0xff804020];
  for (final format in PaletteFormat.values) {
    test('five opaque colors round trip through ${format.name}', () {
      const source = PaletteFile('Paleta ñ 🎨', colors);
      final bytes = encodePalette(source, format);
      final result = decodePalette(bytes, fileName: 'sample.${paletteExtension(format)}');
      expect(result, isNotNull); expect(result!.colors, colors);
      if (format == PaletteFormat.gpl) expect(result.name, source.name);
      final detected = decodePalette(bytes);
      expect(detected, isNotNull); expect(detected!.colors, colors);
      if (format == PaletteFormat.ase) expect(detected.name, source.name);
    });
  }
  test('GPL reads comments, columns, names, tabs and CRLF', () {
    final source = text('GIMP Palette\r\nName: Ejemplo\r\nColumns: 4\r\n# comentario\r\n255 0 0\tRojo\r\n 0 255 0 Green\r\n\r\n0 0 255\r\n');
    final result = decodePalette(source)!;
    expect(result.name, 'Ejemplo'); expect(result.colors, [0xffff0000, 0xff00ff00, 0xff0000ff]);
  });
  test('HEX accepts hash, lowercase, blanks, BOM and derives filename', () {
    final result = decodePalette(text('\uFEFF#12abef\n\nFFFFFF\n  #000000\n'), fileName: r'C:\palettes\test.HEX')!;
    expect(result.colors, [0xff12abef, 0xffffffff, 0xff000000]); expect(result.name, 'test');
  });
  test('ACO converts inverted CMYK, gray and HSB and ignores following v2', () {
    final bytes = aco([
      [2, 0, 65535, 65535, 65535],
      [8, 5000, 0, 0, 0],
      [1, 21845, 65535, 65535, 0],
      [7, 0, 0, 0, 0],
    ]);
    final result = decodePalette(Uint8List.fromList([...bytes, 0, 2, 0, 0]))!;
    expect(result.colors, [0xff00ffff, 0xff808080, 0xff00ff00]);
  });
  test('ASE reads grouped CMYK, gray and RGB, skipping LAB and unknown blocks', () {
    final result = decodePalette(ase())!;
    expect(result.name, 'Grupo 🎨'); expect(result.colors, [0xff00ffff, 0xff808080, 0xffff0000]);
  });
  test('extension has priority with content fallback for mislabeled files', () {
    expect(decodePalette(ase(), fileName: 'wrong.gpl')!.colors.first, 0xff00ffff);
    expect(decodePalette(text('abcdef'), fileName: 'wrong.aco')!.colors, [0xffabcdef]);
    expect(decodePalette(encodePalette(const PaletteFile('A', colors), PaletteFormat.gpl), fileName: 'wrong.hex')!.colors, colors);
  });
  test('unknown and malformed text returns null', () {
    for (final bytes in [Uint8List(0), Uint8List.fromList([255, 0, 12]), text('hello'), text('JASC-PAL\n0100\n2\n0 0 0'), text('GIMP Palette\n300 0 0'), text('JASC-PAL\n0100\n-1')]) {
      expect(decodePalette(bytes), isNull);
    }
    expect(decodePalette(text('12345'), fileName: 'bad.hex'), isNull);
  });
  test('binary truncations and oversized block lengths return null', () {
    final valid = ase();
    for (var i = 0; i < valid.length; i++) {
      expect(decodePalette(Uint8List.sublistView(valid, 0, i), fileName: 'truncated.ase'), isNull, reason: 'length $i');
    }
    final broken = Uint8List.fromList(valid); ByteData.sublistView(broken).setUint32(14, 0xffffffff, Endian.big);
    expect(decodePalette(broken), isNull);
    expect(decodePalette(Uint8List.fromList([0, 1, 255, 255])), isNull);
  });
  test('empty palettes encode and decode with explicit extension', () {
    for (final format in PaletteFormat.values) {
      final bytes = encodePalette(const PaletteFile('Empty', []), format);
      expect(decodePalette(bytes, fileName: 'empty.${paletteExtension(format)}')!.colors, isEmpty);
    }
  });
  test('export discards alpha and protects text names from newlines', () {
    for (final format in PaletteFormat.values) {
      final result = decodePalette(encodePalette(const PaletteFile('A\nB', [0x00123456]), format), fileName: 'x.${paletteExtension(format)}')!;
      expect(result.colors, [0xff123456]);
      if (format == PaletteFormat.gpl) expect(result.name, 'A B');
    }
  });
  test('extensions match the API contract', () {
    expect(PaletteFormat.values.map(paletteExtension), ['gpl', 'hex', 'pal', 'aco', 'ase']);
  });
}
