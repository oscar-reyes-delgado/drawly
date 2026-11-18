import 'dart:typed_data';

import '../model/layer.dart';

/// One raster layer flattened for interchange formats (ORA, PSD…).
class FlatLayer {
  const FlatLayer({
    required this.name,
    required this.rgba,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    this.opacity = 1,
    this.blend = LayerBlend.normal,
    this.visible = true,
  });

  final String name;

  /// Straight (non-premultiplied) RGBA8888, width * height * 4 bytes.
  final Uint8List rgba;
  final int left, top, width, height;
  final double opacity;
  final LayerBlend blend;
  final bool visible;
}
