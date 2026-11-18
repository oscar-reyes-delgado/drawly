import 'dart:typed_data';
import 'flat_layer.dart';

/// Encodes a row with PackBits packets of at most 128 bytes.
Uint8List packBits(Uint8List row) {
  final out = BytesBuilder();
  var p = 0;
  int run(int start) { var end = start + 1; while (end < row.length && end - start < 128 && row[end] == row[start]) { end++; } return end - start; }
  while (p < row.length) {
    final repeat = run(p);
    if (repeat >= 3) { out.add([257 - repeat, row[p]]); p += repeat; }
    else {
      final start = p++;
      while (p < row.length && p - start < 128 && run(p) < 3) { p++; }
      out.addByte(p - start - 1); out.add(Uint8List.sublistView(row, start, p));
    }
  }
  return out.takeBytes();
}

/// Decodes exactly [length] bytes, rejecting truncated or overflowing packets.
Uint8List unpackBits(Uint8List packed, int length) {
  if (length < 0) throw ArgumentError.value(length);
  final out = Uint8List(length);
  var p = 0, o = 0;
  while (p < packed.length) {
    final header = packed[p++];
    if (header == 128) continue;
    final n = header < 128 ? header + 1 : 257 - header;
    if (o + n > length || p + (header < 128 ? n : 1) > packed.length) throw const FormatException('Invalid PackBits packet');
    if (header < 128) { out.setRange(o, o + n, packed, p); p += n; } else { out.fillRange(o, o + n, packed[p++]); }
    o += n;
  }
  if (o != length) throw const FormatException('Truncated PackBits row');
  return out;
}

class _Writer {
  final data = BytesBuilder();
  void u8(int n) => data.addByte(n);
  void u16(int n) => data.add((ByteData(2)..setUint16(0, n, Endian.big)).buffer.asUint8List());
  void i16(int n) => data.add((ByteData(2)..setInt16(0, n, Endian.big)).buffer.asUint8List());
  void u32(int n) => data.add((ByteData(4)..setUint32(0, n, Endian.big)).buffer.asUint8List());
  void i32(int n) => data.add((ByteData(4)..setInt32(0, n, Endian.big)).buffer.asUint8List());
  void text(String s) => data.add(s.codeUnits);
  void sized(Uint8List bytes) { u32(bytes.length); data.add(bytes); }
  Uint8List take() => data.takeBytes();
}

List<Uint8List> _rows(Uint8List rgba, int width, int height, int channel) => [for (var y = 0; y < height; y++)
  packBits(Uint8List.fromList([for (var x = 0; x < width; x++) rgba[(y * width + x) * 4 + channel]]))];
Uint8List _channel(Uint8List rgba, int width, int height, int channel) {
  final rows = _rows(rgba, width, height, channel), w = _Writer()..u16(1);
  for (final row in rows) { if (row.length > 65535) throw ArgumentError('PSD row is too wide'); w.u16(row.length); }
  for (final row in rows) { w.data.add(row); }
  return w.take();
}
void _validate(Uint8List bytes, int w, int h) { if (w < 0 || h < 0 || w > 30000 || h > 30000 || bytes.length != w * h * 4) throw ArgumentError('Invalid PSD image dimensions'); }

/// Writes an 8-bit RGB PSD with bottom-to-top layers and a flattened RGBA image.
Uint8List encodePsd(List<FlatLayer> layers, {required int width, required int height, required Uint8List mergedRgba}) {
  _validate(mergedRgba, width, height);
  if (width == 0 || height == 0 || layers.length > 32767) throw ArgumentError('Invalid PSD document dimensions');
  const blends = ['norm', 'mul ', 'scrn', 'over', 'dark', 'lite', 'div ', 'idiv', 'hLit', 'sLit', 'diff', 'smud', 'lddg', 'hue ', 'sat ', 'colr', 'lum '];
  final w = _Writer()..text('8BPS')..u16(1);
  w.data.add(Uint8List(6)); w.u16(4); w.u32(height); w.u32(width); w.u16(8); w.u16(3); w.u32(0); w.u32(0);
  final info = _Writer()..i16(-layers.length), channelData = <Uint8List>[];
  for (final l in layers) {
    _validate(l.rgba, l.width, l.height);
    info.i32(l.top); info.i32(l.left); info.i32(l.top + l.height); info.i32(l.left + l.width); info.u16(4);
    for (var c = 0; c < 4; c++) {
      final data = _channel(l.rgba, l.width, l.height, c); channelData.add(data);
      info.i16(c == 3 ? -1 : c); info.u32(data.length);
    }
    info.text('8BIM'); info.text(blends[l.blend.index]); info.u8((l.opacity.clamp(0, 1) * 255).round()); info.u8(0); info.u8(l.visible ? 0 : 2); info.u8(0);
    final extra = _Writer()..u32(0)..u32(0);
    final legacy = l.name.codeUnits.take(255).map((v) => v <= 255 ? v : 63).toList();
    extra.u8(legacy.length); extra.data.add(legacy);
    while (extra.data.length % 4 != 0) { extra.u8(0); }
    final unicode = _Writer()..u32(l.name.length);
    for (final code in l.name.codeUnits) { unicode.u16(code); }
    extra.text('8BIM'); extra.text('luni'); extra.sized(unicode.take());
    info.sized(extra.take());
  }
  for (final data in channelData) { info.data.add(data); }
  if (info.data.length.isOdd) info.u8(0);
  final section = _Writer()..sized(info.take())..u32(0);
  w.sized(section.take()); w.u16(1);
  // PSD composites store RGB against a white matte; layer channels stay straight.
  final composite = Uint8List.fromList(mergedRgba);
  for (var i = 0; i < composite.length; i += 4) {
    final alpha = composite[i + 3];
    if (alpha == 0 || alpha == 255) continue;
    for (var c = 0; c < 3; c++) { composite[i + c] = (mergedRgba[i + c] * alpha / 255 + 255 - alpha).round(); }
  }
  final rows = [for (var c = 0; c < 4; c++) ..._rows(composite, width, height, c)];
  for (final row in rows) { w.u16(row.length); }
  for (final row in rows) { w.data.add(row); }
  return w.take();
}
