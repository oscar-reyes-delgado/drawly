import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui';

import 'package:archive/archive.dart';

import '../core/ids.dart';
import '../engine/compositor.dart';
import '../engine/tiles.dart';
import '../model/anim.dart';
import '../model/document.dart';
import '../model/filter_spec.dart';
import '../model/layer.dart';
import '../model/layer_fx.dart';
import '../model/specs.dart';
import '../model/vector.dart';

/// Version written to manifest.json.
const int kProjectFormatVersion = 1;

class _TileRegistry {
  final Map<ui.Image, int> indexByImage = Map<ui.Image, int>.identity();
  final List<ui.Image> images = <ui.Image>[];

  int register(ui.Image image) => indexByImage.putIfAbsent(image, () {
        final idx = images.length;
        images.add(image);
        return idx;
      });
}

/// Native `.drawly` ZIP project archive encoder and decoder.
class ProjectCodec {
  const ProjectCodec._();

  /// Serialises [project] into the bytes of a `.drawly` file.
  static Future<Uint8List> encode(
    Project project, {
    bool thumbnail = true,
    void Function(double progress)? onProgress,
  }) async {
    final reg = _TileRegistry();
    final projectMap = _projectToJson(project, reg);

    final archive = Archive();
    final manifestJson = jsonEncode({
      'format': 'drawly',
      'version': kProjectFormatVersion,
    });
    archive.addFile(ArchiveFile.string('manifest.json', manifestJson));
    archive.addFile(ArchiveFile.string('project.json', jsonEncode(projectMap)));

    final totalTiles = reg.images.length;
    if (totalTiles == 0) {
      onProgress?.call(1.0);
    } else {
      for (var i = 0; i < totalTiles; i++) {
        final bd = await reg.images[i].toByteData(format: ui.ImageByteFormat.png);
        if (bd == null) {
          throw const FormatException('Failed to encode raster tile as PNG.');
        }
        final pngBytes = bd.buffer.asUint8List(bd.offsetInBytes, bd.lengthInBytes);
        archive.addFile(ArchiveFile.bytes('tiles/$i.png', pngBytes));
        onProgress?.call((i + 1) / totalTiles);
      }
    }

    project.assets.forEach((id, bytes) {
      archive.addFile(ArchiveFile.bytes('assets/$id', bytes));
    });

    if (thumbnail) {
      ui.Image? thumb;
      try {
        final main = project.main;
        final maxSide = math.max(main.width, main.height);
        final scale = maxSide > 0 ? 256.0 / maxSide : 1.0;
        thumb = renderCompImage(project, main, 0, scale: scale, forExport: true, useCamera: false);
        final bd = await thumb.toByteData(format: ui.ImageByteFormat.png);
        if (bd != null) {
          archive.addFile(
            ArchiveFile.bytes('thumbnail.png', bd.buffer.asUint8List(bd.offsetInBytes, bd.lengthInBytes)),
          );
        }
      } catch (_) {
        // Optional thumbnail: never fail project encoding if rendering fails.
      } finally {
        thumb?.dispose();
      }
    }

    final encoded = ZipEncoder().encodeBytes(archive);
    return Uint8List.fromList(encoded);
  }

  /// Parses a `.drawly` file. Throws [FormatException] when the bytes are not
  /// a valid project or the version is newer than [kProjectFormatVersion].
  static Future<Project> decode(
    Uint8List bytes, {
    void Function(double progress)? onProgress,
  }) async {
    if (bytes.length < 4 ||
        bytes[0] != 0x50 ||
        bytes[1] != 0x4B ||
        (bytes[2] != 0x03 && bytes[2] != 0x05 && bytes[2] != 0x07)) {
      throw const FormatException('Not a valid ZIP archive.');
    }

    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (e) {
      throw FormatException('Corrupt ZIP archive: $e');
    }

    final filesByName = <String, ArchiveFile>{
      for (final f in archive.files)
        if (f.isFile) f.name: f,
    };

    final manifestFile = filesByName['manifest.json'];
    if (manifestFile == null) {
      throw const FormatException('Missing manifest.json in .drawly archive.');
    }
    final projectFile = filesByName['project.json'];
    if (projectFile == null) {
      throw const FormatException('Missing project.json in .drawly archive.');
    }

    final Map<String, dynamic> manifest;
    try {
      final decoded = jsonDecode(utf8.decode(manifestFile.content));
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('manifest.json is not a JSON object.');
      }
      manifest = decoded;
    } catch (e) {
      if (e is FormatException) rethrow;
      throw FormatException('Invalid manifest.json: $e');
    }

    if (manifest['format'] != 'drawly') {
      throw FormatException('Unsupported archive format: ${manifest['format']}.');
    }
    final versionRaw = manifest['version'];
    if (versionRaw is! num) {
      throw const FormatException('Missing or invalid format version in manifest.json.');
    }
    final version = versionRaw.toInt();
    if (version < 1 || version > kProjectFormatVersion) {
      throw FormatException(
        'Unsupported .drawly version $version (max supported: $kProjectFormatVersion).',
      );
    }

    final Map<String, dynamic> projectJson;
    try {
      final decoded = jsonDecode(utf8.decode(projectFile.content));
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('project.json is not a JSON object.');
      }
      projectJson = decoded;
    } catch (e) {
      if (e is FormatException) rethrow;
      throw FormatException('Invalid project.json: $e');
    }

    final tileFiles = <int, Uint8List>{};
    for (final entry in filesByName.entries) {
      final name = entry.key;
      if (name.startsWith('tiles/') && name.endsWith('.png')) {
        final idxStr = name.substring('tiles/'.length, name.length - '.png'.length);
        final idx = int.tryParse(idxStr);
        if (idx != null) {
          tileFiles[idx] = entry.value.content;
        }
      }
    }

    final decodedTiles = <int, ui.Image>{};
    final sortedTileIndices = tileFiles.keys.toList()..sort();
    final totalTiles = sortedTileIndices.length;
    try {
      if (totalTiles == 0) {
        onProgress?.call(1.0);
      } else {
        for (var i = 0; i < totalTiles; i++) {
          final n = sortedTileIndices[i];
          final pngBytes = tileFiles[n]!;
          final ui.Image img;
          try {
            img = await decodeImageBytes(pngBytes);
          } catch (e) {
            throw FormatException('Failed to decode tile tiles/$n.png: $e');
          }
          if (img.width != kTile || img.height != kTile) {
            final w = img.width, h = img.height;
            img.dispose();
            throw FormatException('Tile tiles/$n.png is ${w}x$h, expected ${kTile}x$kTile.');
          }
          decodedTiles[n] = img;
          onProgress?.call((i + 1) / totalTiles);
        }
      }

      return _projectFromJson(projectJson, decodedTiles, filesByName);
    } catch (e) {
      for (final img in decodedTiles.values) {
        img.dispose();
      }
      if (e is FormatException) rethrow;
      throw FormatException('Malformed project data: $e');
    }
  }
}

Map<String, dynamic> _projectToJson(Project project, _TileRegistry reg) => {
      'mainId': project.mainId,
      'meta': project.meta.toJson(),
      'palette': project.palette,
      'assets': project.assets.keys.toList(),
      'comps': [for (final c in project.comps.values) _compToJson(c, reg)],
    };

Project _projectFromJson(
  Map<String, dynamic> m,
  Map<int, ui.Image> tiles,
  Map<String, ArchiveFile> filesByName,
) {
  final meta = DocMeta.fromJson(m['meta']);
  final palette = ((m['palette'] as List?) ?? const []).map((e) => (e as num).toInt()).toList();

  final assets = <String, Uint8List>{};
  final assetIds = ((m['assets'] as List?) ?? const []).map((e) => e as String).toList();
  for (final id in assetIds) {
    final f = filesByName['assets/$id'];
    if (f != null) {
      assets[id] = Uint8List.fromList(f.content);
    }
  }
  for (final e in filesByName.entries) {
    if (e.key.startsWith('assets/')) {
      final id = e.key.substring('assets/'.length);
      if (id.isNotEmpty && !assets.containsKey(id)) {
        assets[id] = Uint8List.fromList(e.value.content);
      }
    }
  }

  final compsList = (m['comps'] as List?) ?? const [];
  final comps = <String, Comp>{};
  for (final rawComp in compsList) {
    if (rawComp is Map<String, dynamic>) {
      final c = _compFromJson(rawComp, tiles);
      comps[c.id] = c;
    }
  }
  if (comps.isEmpty) {
    throw const FormatException('Project contains no compositions.');
  }

  final requestedMainId = m['mainId'] as String?;
  final mainId = (requestedMainId != null && comps.containsKey(requestedMainId))
      ? requestedMainId
      : comps.keys.first;

  return Project(
    comps: comps,
    mainId: mainId,
    meta: meta,
    assets: assets,
    palette: palette,
  );
}

List<List<int>> _planeToJson(TilePlane plane, _TileRegistry reg) => [
      for (final k in plane.keys) [k, reg.register(plane[k]!)],
    ];

TilePlane _planeFromJson(dynamic j, Map<int, ui.Image> tiles) {
  if (j == null) return TilePlane.empty;
  final list = j as List;
  if (list.isEmpty) return TilePlane.empty;
  final map = <int, ui.Image?>{};
  for (final pair in list) {
    final p = pair as List;
    final key = (p[0] as num).toInt();
    final n = (p[1] as num).toInt();
    final img = tiles[n];
    if (img == null) {
      throw FormatException('Referenced tile tiles/$n.png does not exist in archive.');
    }
    map[key] = img;
  }
  return TilePlane.empty.withTiles(map);
}

Map<String, dynamic> _selToJson(SelectionMask sel, _TileRegistry reg) => {
      'mask': _planeToJson(sel.mask, reg),
      'b': [sel.bounds.left, sel.bounds.top, sel.bounds.width, sel.bounds.height],
    };

SelectionMask _selFromJson(dynamic j, Map<int, ui.Image> tiles) {
  final m = j as Map<String, dynamic>;
  final mask = _planeFromJson(m['mask'], tiles);
  final b = m['b'] as List?;
  final bounds = (b != null && b.length >= 4)
      ? Rect.fromLTWH(
          (b[0] as num).toDouble(),
          (b[1] as num).toDouble(),
          (b[2] as num).toDouble(),
          (b[3] as num).toDouble(),
        )
      : (mask.bounds ?? Rect.zero);
  return SelectionMask(mask, bounds);
}

Map<String, dynamic> _compToJson(Comp comp, _TileRegistry reg) => {
      'id': comp.id,
      'name': comp.name,
      'w': comp.width,
      'h': comp.height,
      'bg': comp.background?.toARGB32(),
      'infinite': comp.infinite,
      'layers': [for (final l in comp.layers) _layerToJson(l, reg)],
      'timeline': comp.timeline.toJson(),
      'guides': [for (final g in comp.guides) g.toJson()],
      'artboards': [for (final a in comp.artboards) a.toJson()],
      'selection': comp.selection == null ? null : _selToJson(comp.selection!, reg),
      'savedSelections': {
        for (final e in comp.savedSelections.entries) e.key: _selToJson(e.value, reg),
      },
      'assist': comp.assist.toJson(),
      'symmetry': comp.symmetry.toJson(),
    };

Comp _compFromJson(Map<String, dynamic> m, Map<int, ui.Image> tiles) {
  final hasBg = m.containsKey('bg');
  final Color? bg = hasBg
      ? (m['bg'] == null ? null : Color((m['bg'] as num).toInt()))
      : const Color(0xFFFFFFFF);

  final savedSelections = <String, SelectionMask>{};
  final rawSaved = m['savedSelections'] as Map?;
  if (rawSaved != null) {
    rawSaved.forEach((k, v) {
      if (v != null) {
        savedSelections[k as String] = _selFromJson(v, tiles);
      }
    });
  }

  return Comp(
    id: m['id'] as String? ?? newId('C'),
    name: m['name'] as String? ?? '',
    width: (m['w'] as num?)?.toInt() ?? 1920,
    height: (m['h'] as num?)?.toInt() ?? 1080,
    background: bg,
    infinite: m['infinite'] as bool? ?? false,
    layers: _layersFromJson(m['layers'] as List?, tiles),
    timeline: Timeline.fromJson(m['timeline']),
    guides: ((m['guides'] as List?) ?? const []).map(Guide.fromJson).toList(),
    artboards: ((m['artboards'] as List?) ?? const []).map(Artboard.fromJson).toList(),
    selection: m['selection'] == null ? null : _selFromJson(m['selection'], tiles),
    savedSelections: savedSelections,
    assist: AssistSpec.fromJson(m['assist']),
    symmetry: SymmetrySpec.fromJson(m['symmetry']),
  );
}

Map<String, dynamic> _propsToJson(LayerProps p, _TileRegistry reg) => {
      'name': p.name,
      'visible': p.visible,
      'opacity': p.opacity,
      'blend': p.blend.name,
      'locked': p.locked,
      'lockAlpha': p.lockAlpha,
      'lockPosition': p.lockPosition,
      'clip': p.clip,
      'reference': p.reference,
      'draft': p.draft,
      'mask': p.mask == null ? null : _planeToJson(p.mask!, reg),
      'maskEnabled': p.maskEnabled,
      'fx': p.fx.toJson(),
      'xf': p.xf.toJson(),
      'tracks': tracksToJson(p.tracks),
      'parentId': p.parentId,
      'colorTag': p.colorTag,
      'collapsed': p.collapsed,
      'depth': p.depth,
    };

LayerProps _propsFromJson(dynamic j, Map<int, ui.Image> tiles) {
  if (j == null) return const LayerProps();
  final m = j as Map<String, dynamic>;
  return LayerProps(
    name: m['name'] as String? ?? '',
    visible: m['visible'] as bool? ?? true,
    opacity: (m['opacity'] as num?)?.toDouble() ?? 1,
    blend: LayerBlend.values.firstWhere((b) => b.name == m['blend'], orElse: () => LayerBlend.normal),
    locked: m['locked'] as bool? ?? false,
    lockAlpha: m['lockAlpha'] as bool? ?? false,
    lockPosition: m['lockPosition'] as bool? ?? false,
    clip: m['clip'] as bool? ?? false,
    reference: m['reference'] as bool? ?? false,
    draft: m['draft'] as bool? ?? false,
    mask: m['mask'] == null ? null : _planeFromJson(m['mask'], tiles),
    maskEnabled: m['maskEnabled'] as bool? ?? true,
    fx: LayerFx.fromJson(m['fx']),
    xf: Xform.fromJson(m['xf']),
    tracks: tracksFromJson(m['tracks']),
    parentId: m['parentId'] as String?,
    colorTag: (m['colorTag'] as num?)?.toInt() ?? 0,
    collapsed: m['collapsed'] as bool? ?? false,
    depth: (m['depth'] as num?)?.toDouble() ?? 0,
  );
}

Map<String, dynamic> _layerToJson(Layer layer, _TileRegistry reg) {
  final base = <String, dynamic>{
    'type': switch (layer) {
      PaintLayer() => 'paint',
      VectorLayer() => 'vector',
      TextLayer() => 'text',
      GroupLayer() => 'group',
      AdjustLayer() => 'adjust',
      InstanceLayer() => 'instance',
      ParticleLayer() => 'particles',
    },
    'id': layer.id,
    'props': _propsToJson(layer.props, reg),
  };

  switch (layer) {
    case PaintLayer():
      base['cels'] = {
        'drawings': {
          for (final e in layer.cels.drawings.entries) '${e.key}': _planeToJson(e.value, reg),
        },
        'xs': [
          for (final x in layer.cels.xs) [x.frame, x.drawing],
        ],
      };
      if (layer.rig != null) base['rig'] = layer.rig!.toJson();
    case VectorLayer():
      base['cels'] = {
        'drawings': {
          for (final e in layer.cels.drawings.entries) '${e.key}': e.value.toJson(),
        },
        'xs': [
          for (final x in layer.cels.xs) [x.frame, x.drawing],
        ],
      };
    case TextLayer():
      base['text'] = layer.text.toJson();
    case GroupLayer():
      base['children'] = [for (final c in layer.children) _layerToJson(c, reg)];
      base['passThrough'] = layer.passThrough;
    case AdjustLayer():
      base['filter'] = layer.filter.toJson();
    case InstanceLayer():
      base['compId'] = layer.compId;
      base['start'] = layer.start;
      base['loop'] = layer.loop;
      base['speed'] = layer.speed;
      base['fixedFrame'] = layer.fixedFrame;
    case ParticleLayer():
      base['spec'] = layer.spec.toJson();
  }
  return base;
}

List<Layer> _layersFromJson(List<dynamic>? rawList, Map<int, ui.Image> tiles) {
  if (rawList == null) return const <Layer>[];
  final out = <Layer>[];
  for (final item in rawList) {
    if (item is Map<String, dynamic>) {
      final layer = _layerFromJson(item, tiles);
      if (layer != null) out.add(layer);
    }
  }
  return out;
}

Layer? _layerFromJson(Map<String, dynamic> m, Map<int, ui.Image> tiles) {
  final type = m['type'] as String?;
  final id = m['id'] as String? ?? newId('L');
  final props = _propsFromJson(m['props'], tiles);

  switch (type) {
    case 'paint':
      final celsMap = m['cels'] as Map<String, dynamic>?;
      if (celsMap == null) {
        return PaintLayer(id, props, CelTrack.single(TilePlane.empty));
      }
      final drawingsRaw = (celsMap['drawings'] as Map?) ?? const {};
      final drawings = <int, TilePlane>{};
      drawingsRaw.forEach((k, v) {
        final dId = int.tryParse(k.toString());
        if (dId != null) drawings[dId] = _planeFromJson(v, tiles);
      });
      final xsRaw = (celsMap['xs'] as List?) ?? const [];
      final xs = <Exposure>[
        for (final pair in xsRaw)
          Exposure(((pair as List)[0] as num).toInt(), (pair[1] as num).toInt()),
      ];
      final rig = LayerRig.fromJson(m['rig']);
      return PaintLayer(id, props, CelTrack(drawings: drawings, xs: xs), rig: rig == null || rig.isEmpty ? null : rig);

    case 'vector':
      final celsMap = m['cels'] as Map<String, dynamic>?;
      if (celsMap == null) {
        return VectorLayer(id, props, CelTrack.single(VectorArt.empty));
      }
      final drawingsRaw = (celsMap['drawings'] as Map?) ?? const {};
      final drawings = <int, VectorArt>{};
      drawingsRaw.forEach((k, v) {
        final dId = int.tryParse(k.toString());
        if (dId != null) drawings[dId] = VectorArt.fromJson(v);
      });
      final xsRaw = (celsMap['xs'] as List?) ?? const [];
      final xs = <Exposure>[
        for (final pair in xsRaw)
          Exposure(((pair as List)[0] as num).toInt(), (pair[1] as num).toInt()),
      ];
      return VectorLayer(id, props, CelTrack(drawings: drawings, xs: xs));

    case 'text':
      final text = m['text'] == null ? const TextSpec() : TextSpec.fromJson(m['text']);
      return TextLayer(id, props, text);

    case 'group':
      final children = _layersFromJson(m['children'] as List?, tiles);
      final passThrough = m['passThrough'] as bool? ?? true;
      return GroupLayer(id, props, children, passThrough: passThrough);

    case 'adjust':
      final filter = m['filter'] == null ? kFilters.first.defaults : FilterSpec.fromJson(m['filter']);
      return AdjustLayer(id, props, filter);

    case 'instance':
      return InstanceLayer(
        id,
        props,
        m['compId'] as String? ?? '',
        start: (m['start'] as num?)?.toInt() ?? 0,
        loop: m['loop'] as bool? ?? true,
        speed: (m['speed'] as num?)?.toDouble() ?? 1,
        fixedFrame: (m['fixedFrame'] as num?)?.toInt(),
      );

    case 'particles':
      final spec = m['spec'] == null ? const ParticleSpec() : ParticleSpec.fromJson(m['spec']);
      return ParticleLayer(id, props, spec);

    default:
      // Unknown layer types are skipped without failing.
      return null;
  }
}
