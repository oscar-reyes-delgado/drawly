import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:image/image.dart' as img;
import '../model/layer.dart';
import 'flat_layer.dart';

const _blends = ['src-over', 'multiply', 'screen', 'overlay', 'darken', 'lighten', 'color-dodge', 'color-burn', 'hard-light', 'soft-light', 'difference', 'exclusion', 'plus', 'hue', 'saturation', 'color', 'luminosity'];
String _escape(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;').replaceAll("'", '&apos;');
String _unescape(String s) => s.replaceAllMapped(RegExp(r'&(#x[\da-fA-F]+|#\d+|amp|lt|gt|quot|apos);'), (m) {
  final v = m[1]!;
  if (v.startsWith('#')) return String.fromCharCode(int.parse(v.substring(v.startsWith('#x') ? 2 : 1), radix: v.startsWith('#x') ? 16 : 10));
  return const {'amp': '&', 'lt': '<', 'gt': '>', 'quot': '"', 'apos': "'"}[v]!;
});
img.Image _image(Uint8List bytes, int w, int h) {
  if (w <= 0 || h <= 0 || bytes.length != w * h * 4) throw ArgumentError('Invalid RGBA image');
  return img.Image.fromBytes(width: w, height: h, bytes: bytes.buffer, bytesOffset: bytes.offsetInBytes, numChannels: 4, order: img.ChannelOrder.rgba);
}

/// Writes an OpenRaster file from layers ordered bottom to top.
Future<Uint8List> encodeOra(List<FlatLayer> layers, {required int width, required int height, required Uint8List mergedRgba, double dpi = 72}) async {
  final merged = _image(mergedRgba, width, height), zip = Archive();
  zip.addFile(ArchiveFile.noCompress('mimetype', 16, utf8.encode('image/openraster')));
  final xml = StringBuffer('<?xml version="1.0" encoding="UTF-8"?><image version="0.0.3" w="$width" h="$height" xres="$dpi" yres="$dpi"><stack>');
  for (var i = layers.length - 1; i >= 0; i--) {
    final l = layers[i], src = 'data/layer$i.png';
    zip.addFile(ArchiveFile.bytes(src, img.encodePng(_image(l.rgba, l.width, l.height))));
    xml.write('<layer name="${_escape(l.name)}" src="$src" x="${l.left}" y="${l.top}" opacity="${l.opacity}" visibility="${l.visible ? 'visible' : 'hidden'}" composite-op="svg:${_blends[l.blend.index]}"/>');
  }
  xml.write('</stack></image>'); zip.addFile(ArchiveFile.string('stack.xml', xml.toString()));
  zip.addFile(ArchiveFile.bytes('mergedimage.png', img.encodePng(merged)));
  final scale = 256 / math.max(width, height);
  zip.addFile(ArchiveFile.bytes('Thumbnails/thumbnail.png', img.encodePng(img.copyResize(merged, width: math.max(1, (width * scale).round()), height: math.max(1, (height * scale).round())))));
  return Uint8List.fromList(ZipEncoder().encodeBytes(zip));
}

/// Reads and flattens nested OpenRaster stacks into bottom-to-top layers.
Future<({int width, int height, List<FlatLayer> layers})> decodeOra(Uint8List bytes) async {
  try {
    final zip = ZipDecoder().decodeBytes(bytes);
    Uint8List file(String name) { final entry = zip.findFile(name); if (entry == null) throw FormatException('Missing $name'); return entry.content; }
    if (utf8.decode(file('mimetype')) != 'image/openraster') throw const FormatException('Expected OpenRaster mimetype');
    final xml = utf8.decode(file('stack.xml')), layers = <FlatLayer>[];
    var width = 0, height = 0, imageClosed = false;
    final stack = <({int x, int y, double opacity, bool visible})>[];
    final tags = RegExp(r'''<!--[^]*?-->|<(?:[^>"']|"[^"]*"|'[^']*')*>''');
    for (final match in tags.allMatches(xml)) {
      final tag = match[0]!;
      if (tag.startsWith('<!--') || tag.startsWith('<?')) continue;
      final name = RegExp(r'^</?([\w:-]+)').firstMatch(tag)?[1];
      final closing = tag.startsWith('</'), selfClosing = tag.endsWith('/>');
      final attrs = <String, String>{for (final a in RegExp(r'''([\w:.-]+)\s*=\s*(["'])(.*?)\2''', dotAll: true).allMatches(tag)) a[1]!: _unescape(a[3]!)};
      int number(String key, [int fallback = 0]) => attrs[key] == null ? fallback : int.parse(attrs[key]!);
      final parent = stack.isEmpty ? (x: 0, y: 0, opacity: 1.0, visible: true) : stack.last;
      if (name == 'image') {
        if (closing) { imageClosed = true; } else { width = number('w'); height = number('h'); }
      } else if (name == 'stack') {
        if (closing) { if (stack.isEmpty) throw const FormatException('Unbalanced stack'); stack.removeLast(); }
        else if (!selfClosing) { stack.add((x: parent.x + number('x'), y: parent.y + number('y'), opacity: parent.opacity * double.parse(attrs['opacity'] ?? '1'), visible: parent.visible && attrs['visibility'] != 'hidden')); }
      } else if (name == 'layer' && !closing) {
        final image = img.decodePng(file(attrs['src'] ?? ''));
        if (image == null) throw const FormatException('Invalid layer PNG');
        final blend = _blends.indexOf((attrs['composite-op'] ?? 'svg:src-over').replaceFirst('svg:', ''));
        layers.add(FlatLayer(name: attrs['name'] ?? '', rgba: image.getBytes(order: img.ChannelOrder.rgba), left: parent.x + number('x'), top: parent.y + number('y'), width: image.width, height: image.height,
          opacity: parent.opacity * double.parse(attrs['opacity'] ?? '1'), visible: parent.visible && attrs['visibility'] != 'hidden', blend: blend < 0 ? LayerBlend.normal : LayerBlend.values[blend]));
      }
    }
    if (width <= 0 || height <= 0 || !imageClosed || stack.isNotEmpty) throw const FormatException('Invalid OpenRaster stack');
    return (width: width, height: height, layers: layers.reversed.toList());
  } on FormatException { rethrow; } catch (e) { throw FormatException('Invalid OpenRaster: $e'); }
}
