import 'dart:convert';
import 'dart:typed_data';

import '../core/color_utils.dart';

/// Supported palette interchange formats.
enum PaletteFormat { gpl, hex, jascPal, aco, ase }

/// A named palette of opaque ARGB colors.
class PaletteFile {
  const PaletteFile(this.name, this.colors);
  final String name;
  final List<int> colors;
}

/// Returns the conventional extension without a leading dot.
String paletteExtension(PaletteFormat f) => switch (f) {
  PaletteFormat.gpl => 'gpl', PaletteFormat.hex => 'hex', PaletteFormat.jascPal => 'pal',
  PaletteFormat.aco => 'aco', PaletteFormat.ase => 'ase',
};

/// Detects the format by extension first, then by content. Null when unknown
/// or malformed. Unsupported binary color models are skipped.
PaletteFile? decodePalette(Uint8List bytes, {String fileName = ''}) {
  final base = fileName.replaceAll('\\', '/').split('/').last;
  final dot = base.lastIndexOf('.');
  final name = dot > 0 ? base.substring(0, dot) : base;
  final ext = dot >= 0 ? base.substring(dot + 1).toLowerCase() : '';
  final candidates = <PaletteFormat>[
    for (final f in PaletteFormat.values) if (paletteExtension(f) == ext) f,
    if (bytes.length >= 4 && String.fromCharCodes(bytes.take(4)) == 'ASEF') PaletteFormat.ase,
    if (bytes.length >= 4 && bytes[0] == 0 && bytes[1] == 1) PaletteFormat.aco,
  ];
  String? text;
  try { text = utf8.decode(bytes).replaceFirst('\uFEFF', '').trim(); } on FormatException { /* Binary input. */ }
  if (text != null) {
    if (text.startsWith('GIMP Palette')) candidates.add(PaletteFormat.gpl);
    if (text.startsWith('JASC-PAL')) candidates.add(PaletteFormat.jascPal);
    if (text.isNotEmpty && const LineSplitter().convert(text).every((s) => s.trim().isEmpty || RegExp(r'^#?[0-9a-fA-F]{6}$').hasMatch(s.trim()))) {
      candidates.add(PaletteFormat.hex);
    }
  }
  for (final format in candidates.toSet()) {
    try {
      return switch (format) {
        PaletteFormat.gpl => _gpl(text, name),
        PaletteFormat.hex => _hex(text, name),
        PaletteFormat.jascPal => _jasc(text, name),
        PaletteFormat.aco => _aco(bytes, name),
        PaletteFormat.ase => _ase(bytes, name),
      };
    } on FormatException { /* Try content detection after an incorrect extension. */ }
  }
  return null;
}

List<String> _lines(String? text) {
  if (text == null) throw const FormatException('Expected text palette');
  return const LineSplitter().convert(text).map((s) => s.trim()).toList();
}

int _rgb(double r, double g, double b) => 0xff000000 | ch8(r) << 16 | ch8(g) << 8 | ch8(b);

int _rgbLine(String line) {
  final match = RegExp(r'^(\d+)\s+(\d+)\s+(\d+)(?:\s.*)?$').firstMatch(line);
  if (match == null) throw const FormatException('Invalid RGB palette entry');
  final channels = [for (var i = 1; i <= 3; i++) int.parse(match.group(i)!)];
  if (channels.any((v) => v > 255)) throw const FormatException('RGB channel exceeds 255');
  return 0xff000000 | channels[0] << 16 | channels[1] << 8 | channels[2];
}

PaletteFile _gpl(String? text, String name) {
  final lines = _lines(text);
  if (lines.isEmpty || lines.first != 'GIMP Palette') throw const FormatException('Expected GIMP Palette');
  final colors = <int>[];
  for (final line in lines.skip(1)) {
    if (line.isEmpty || line.startsWith('#') || line.startsWith('Columns:')) continue;
    if (line.startsWith('Name:')) { name = line.substring(5).trim(); continue; }
    colors.add(_rgbLine(line));
  }
  return PaletteFile(name, colors);
}

PaletteFile _hex(String? text, String name) {
  final colors = <int>[];
  for (final line in _lines(text)) {
    if (line.isEmpty) continue;
    if (!RegExp(r'^#?[0-9a-fA-F]{6}$').hasMatch(line)) throw const FormatException('Expected RRGGBB');
    colors.add(0xff000000 | int.parse(line.replaceFirst('#', ''), radix: 16));
  }
  return PaletteFile(name, colors);
}

PaletteFile _jasc(String? text, String name) {
  final lines = _lines(text).where((s) => s.isNotEmpty).toList();
  if (lines.length < 3 || lines[0] != 'JASC-PAL' || lines[1] != '0100') throw const FormatException('Expected JASC-PAL 0100');
  final count = int.tryParse(lines[2]);
  if (count == null || count < 0 || lines.length != count + 3) throw const FormatException('Invalid JASC color count');
  return PaletteFile(name, lines.skip(3).map(_rgbLine).toList());
}

class _Reader {
  _Reader(Uint8List bytes) : data = ByteData.sublistView(bytes);
  final ByteData data;
  int pos = 0;
  int get remaining => data.lengthInBytes - pos;
  void require(int n) { if (n < 0 || remaining < n) throw const FormatException('Truncated palette'); }
  int u16() { require(2); final v = data.getUint16(pos, Endian.big); pos += 2; return v; }
  int u32() { require(4); final v = data.getUint32(pos, Endian.big); pos += 4; return v; }
  double f32() {
    require(4); final v = data.getFloat32(pos, Endian.big); pos += 4;
    if (!v.isFinite) throw const FormatException('Non-finite palette color');
    return v;
  }
  String ascii(int n) { require(n); return String.fromCharCodes(List.generate(n, (_) => data.getUint8(pos++))); }
  String name() {
    final n = u16(); require(n * 2);
    final codes = List.generate(n, (_) => u16());
    if (codes.isNotEmpty && codes.last == 0) codes.removeLast();
    return String.fromCharCodes(codes);
  }
  _Reader block(int n) {
    require(n); final result = _Reader(Uint8List.sublistView(data, pos, pos + n)); pos += n; return result;
  }
}

PaletteFile _aco(Uint8List bytes, String name) {
  final r = _Reader(bytes);
  if (r.u16() != 1) throw const FormatException('Expected ACO version 1');
  final count = r.u16(); r.require(count * 10);
  final colors = <int>[];
  for (var i = 0; i < count; i++) {
    final space = r.u16(), x = r.u16(), y = r.u16(), z = r.u16(), w = r.u16();
    switch (space) {
      case 0: colors.add(_rgb(x / 65535, y / 65535, z / 65535));
      case 1: colors.add(Hsv(x / 182.04, y / 65535, z / 65535).toColor().toARGB32());
      case 2: colors.add(Cmyk(1 - x / 65535, 1 - y / 65535, 1 - z / 65535, 1 - w / 65535).toColor().toARGB32());
      case 8: colors.add(_rgb(x / 10000, x / 10000, x / 10000));
    }
  }
  return PaletteFile(name, colors);
}

PaletteFile _ase(Uint8List bytes, String name) {
  final r = _Reader(bytes);
  if (r.ascii(4) != 'ASEF' || r.u16() != 1 || r.u16() != 0) throw const FormatException('Expected ASE version 1.0');
  final count = r.u32();
  final colors = <int>[];
  for (var i = 0; i < count; i++) {
    final type = r.u16(), block = r.block(r.u32());
    if (type == 0xc001) { final group = block.name(); if (name.isEmpty) name = group; continue; }
    if (type != 1) continue;
    block.name();
    final model = block.ascii(4);
    int? color;
    switch (model) {
      case 'RGB ': color = _rgb(block.f32(), block.f32(), block.f32());
      case 'CMYK': color = Cmyk(block.f32(), block.f32(), block.f32(), block.f32()).toColor().toARGB32();
      case 'Gray': final gray = block.f32(); color = _rgb(gray, gray, gray);
      default: continue;
    }
    block.u16();
    colors.add(color);
  }
  return PaletteFile(name, colors);
}

class _Writer {
  final bytes = BytesBuilder();
  void ascii(String s) => bytes.add(s.codeUnits);
  void u16(int v) => bytes.add((ByteData(2)..setUint16(0, v, Endian.big)).buffer.asUint8List());
  void u32(int v) => bytes.add((ByteData(4)..setUint32(0, v, Endian.big)).buffer.asUint8List());
  void f32(double v) => bytes.add((ByteData(4)..setFloat32(0, v, Endian.big)).buffer.asUint8List());
  void name(String s) {
    if (s.length >= 65535) throw ArgumentError('ASE name exceeds 65534 UTF-16 units');
    u16(s.length + 1); for (final code in s.codeUnits) { u16(code); } u16(0);
  }
  void block(int type, _Writer body) { u16(type); u32(body.bytes.length); bytes.add(body.bytes.takeBytes()); }
}

/// Encodes a palette, discarding alpha as required by the interchange formats.
Uint8List encodePalette(PaletteFile palette, PaletteFormat format) {
  String hex(int color) => (color & 0xffffff).toRadixString(16).padLeft(6, '0').toUpperCase();
  String rgb(int color) => '${(color >> 16) & 255} ${(color >> 8) & 255} ${color & 255}';
  final cleanName = palette.name.replaceAll(RegExp(r'[\r\n]'), ' ');
  switch (format) {
    case PaletteFormat.gpl:
      return Uint8List.fromList(utf8.encode('GIMP Palette\nName: $cleanName\nColumns: 0\n#\n${palette.colors.map((c) => '${rgb(c)}\t${hex(c)}').join('\n')}\n'));
    case PaletteFormat.hex:
      return Uint8List.fromList(utf8.encode('${palette.colors.map(hex).join('\n')}\n'));
    case PaletteFormat.jascPal:
      return Uint8List.fromList(utf8.encode('JASC-PAL\n0100\n${palette.colors.length}\n${palette.colors.map(rgb).join('\n')}\n'));
    case PaletteFormat.aco:
      if (palette.colors.length > 65535) throw ArgumentError('ACO supports at most 65535 colors');
      final w = _Writer()..u16(1)..u16(palette.colors.length);
      for (final color in palette.colors) {
        w.u16(0); w.u16(((color >> 16) & 255) * 257); w.u16(((color >> 8) & 255) * 257); w.u16((color & 255) * 257); w.u16(0);
      }
      return w.bytes.takeBytes();
    case PaletteFormat.ase:
      final w = _Writer()..ascii('ASEF')..u16(1)..u16(0)..u32(palette.colors.length + 2);
      w.block(0xc001, _Writer()..name(palette.name));
      for (final color in palette.colors) {
        final body = _Writer()..name(hex(color))..ascii('RGB ')
            ..f32(((color >> 16) & 255) / 255)..f32(((color >> 8) & 255) / 255)..f32((color & 255) / 255)..u16(0);
        w.block(1, body);
      }
      w.block(0xc002, _Writer());
      return w.bytes.takeBytes();
  }
}
