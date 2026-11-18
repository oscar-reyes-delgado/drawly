import 'dart:typed_data';
import 'dart:ui';

import '../core/i18n.dart';
import '../core/ids.dart';
import '../core/mat2d.dart';
import '../engine/compositor.dart';
import '../engine/tiles.dart';
import '../io/flat_layer.dart';
import '../io/ora_codec.dart';
import '../io/palette_codec.dart';
import '../io/psd_writer.dart';
import '../io/svg_codec.dart';
import '../model/anim.dart';
import '../model/document.dart';
import '../model/layer.dart';
import 'doc_layers.dart';
import 'document_controller.dart';

export '../io/flat_layer.dart' show FlatLayer;
export '../io/palette_codec.dart' show PaletteFile, PaletteFormat, paletteExtension;

void _disposePlane(TilePlane plane) {
  for (final k in plane.keys) {
    plane[k]?.dispose();
  }
}

bool _hasNonZeroAlpha(Uint8List rgba) {
  for (var i = 3; i < rgba.length; i += 4) {
    if (rgba[i] != 0) return true;
  }
  return false;
}

Uint8List _premultiplyRgba(Uint8List straight) {
  final out = Uint8List(straight.length);
  for (var i = 0; i < straight.length; i += 4) {
    final a = straight[i + 3];
    if (a == 0) continue;
    if (a == 255) {
      out[i] = straight[i];
      out[i + 1] = straight[i + 1];
      out[i + 2] = straight[i + 2];
      out[i + 3] = 255;
    } else {
      out[i] = (straight[i] * a + 127) ~/ 255;
      out[i + 1] = (straight[i + 1] * a + 127) ~/ 255;
      out[i + 2] = (straight[i + 2] * a + 127) ~/ 255;
      out[i + 3] = a;
    }
  }
  return out;
}

/// Layers of the current composition at the current frame, flattened for ORA / PSD
/// (bottom to top; groups are flattened into one layer each; each layer is cropped to its content).
Future<List<FlatLayer>> flattenForInterchange(DocumentController doc) async {
  final project = doc.project;
  final comp = doc.comp;
  final frame = doc.frame.toDouble();
  final out = <FlatLayer>[];

  for (final layer in comp.layers) {
    final opacity = layer.props.opacityAt(frame);
    final cleanTracks = Map<Prop, AnimTrack>.of(layer.props.tracks)..remove(Prop.opacity);
    final rasterLayer = layer.withProps(
      layer.props.copyWith(
        visible: true,
        opacity: 1,
        blend: LayerBlend.normal,
        clip: false,
        tracks: cleanTracks,
      ),
    );
    final rasterComp = comp.updateLayer(layer.id, (_) => rasterLayer);
    final rasterProject = project.withComp(rasterComp);
    final plane = rasterizeLayer(rasterProject, rasterComp, rasterLayer, frame);

    try {
      final bounds = await plane.contentBounds();
      if (bounds == null) {
        out.add(
          FlatLayer(
            name: layer.name,
            rgba: Uint8List(0),
            left: 0,
            top: 0,
            width: 0,
            height: 0,
            opacity: opacity,
            blend: layer.blend,
            visible: layer.visible,
          ),
        );
      } else {
        final aligned = bounds.roundedOut;
        final rgba = await plane.readRgba(aligned, straight: true);
        out.add(
          FlatLayer(
            name: layer.name,
            rgba: rgba,
            left: aligned.left.round(),
            top: aligned.top.round(),
            width: aligned.width.round(),
            height: aligned.height.round(),
            opacity: opacity,
            blend: layer.blend,
            visible: layer.visible,
          ),
        );
      }
    } finally {
      _disposePlane(plane);
    }
  }
  return out;
}

/// Straight RGBA of the whole composition at the current frame (width * height * 4).
Future<Uint8List> mergedRgba(DocumentController doc) async {
  final img = renderCompImage(
    doc.project,
    doc.comp,
    doc.frame.toDouble(),
    background: true,
    forExport: true,
    useCamera: false,
  );
  try {
    return await imageToRgba(img, straight: true);
  } finally {
    img.dispose();
  }
}

/// Encodes the current composition at the current frame as an OpenRaster `.ora` archive.
Future<Uint8List> documentToOra(DocumentController doc) async {
  final comp = doc.comp;
  final flat = await flattenForInterchange(doc);
  final oraLayers = [
    for (final l in flat)
      if (l.width > 0 && l.height > 0)
        l
      else
        FlatLayer(
          name: l.name,
          rgba: Uint8List(4),
          left: 0,
          top: 0,
          width: 1,
          height: 1,
          opacity: l.opacity,
          blend: l.blend,
          visible: l.visible,
        ),
  ];
  final merged = await mergedRgba(doc);
  return encodeOra(
    oraLayers,
    width: comp.width,
    height: comp.height,
    mergedRgba: merged,
    dpi: doc.project.meta.dpi,
  );
}

/// Encodes the current composition at the current frame as a layered Adobe `.psd` file.
Future<Uint8List> documentToPsd(DocumentController doc) async {
  final comp = doc.comp;
  final layers = await flattenForInterchange(doc);
  final merged = await mergedRgba(doc);
  return encodePsd(layers, width: comp.width, height: comp.height, mergedRgba: merged);
}

/// New project with one PaintLayer per ORA layer (same names, offsets, opacity, blend and visibility),
/// transparent background, size from the file. Throws FormatException on bad data.
Future<Project> projectFromOra(Uint8List bytes, {String name = 'ORA'}) async {
  final ora = await decodeOra(bytes);
  final blank = Project.blank(width: ora.width, height: ora.height, background: null, name: name);
  final layers = <Layer>[];

  for (final l in ora.layers) {
    TilePlane plane = TilePlane.empty;
    if (l.width > 0 && l.height > 0 && _hasNonZeroAlpha(l.rgba)) {
      final img = await imageFromRgba(_premultiplyRgba(l.rgba), l.width, l.height);
      try {
        plane = TilePlane.fromImage(img, origin: Offset(l.left.toDouble(), l.top.toDouble()));
      } finally {
        img.dispose();
      }
    }
    layers.add(
      PaintLayer(
        newId('L'),
        LayerProps(
          name: l.name,
          visible: l.visible,
          opacity: l.opacity.clamp(0.0, 1.0),
          blend: l.blend,
          xf: Xform(ax: ora.width / 2, ay: ora.height / 2),
        ),
        CelTrack.single(plane),
      ),
    );
  }

  return blank.withComp(blank.main.copyWith(layers: layers));
}

/// Adds a VectorLayer with the SVG's shapes above the active layer; returns its id.
/// Throws FormatException when the SVG has no drawable shapes.
String importSvgLayer(DocumentController doc, String svg, {String name = 'SVG'}) {
  final art = svgToVectorArt(svg);
  if (art.isEmpty) {
    throw const FormatException('SVG has no drawable shapes');
  }
  final id = newId('L');
  final layer = VectorLayer(
    id,
    LayerProps(name: name, xf: Xform(ax: doc.comp.width / 2, ay: doc.comp.height / 2)),
    CelTrack.single(art),
  );
  doc.addLayer(layer, label: tr('Importar SVG', 'Import SVG'));
  return id;
}

/// Parses a palette file (GPL, HEX, PAL, ACO, ASE) into colours; null when unknown.
PaletteFile? readPalette(Uint8List bytes, String fileName) => decodePalette(bytes, fileName: fileName);

/// Encodes the given colours for saving as [format].
Uint8List writePalette(String name, List<int> colors, PaletteFormat format) =>
    encodePalette(PaletteFile(name, colors), format);
