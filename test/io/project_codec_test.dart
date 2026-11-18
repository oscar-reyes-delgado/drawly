import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:archive/archive.dart';
import 'package:drawly/engine/tiles.dart';
import 'package:drawly/io/project_codec.dart';
import 'package:drawly/model/anim.dart';
import 'package:drawly/model/document.dart';
import 'package:drawly/model/filter_spec.dart';
import 'package:drawly/model/gradient.dart';
import 'package:drawly/model/layer.dart';
import 'package:drawly/model/layer_fx.dart';
import 'package:drawly/model/specs.dart';
import 'package:drawly/model/vector.dart';
import 'package:flutter_test/flutter_test.dart';

TilePlane solidPlane(Rect r, Color color) =>
    TilePlane.empty.drawn((c) => c.drawRect(r, Paint()..color = color), area: r);

Future<void> expectPlanesEqual(TilePlane actual, TilePlane expected, Rect rect) async {
  final aBytes = await actual.readRgba(rect);
  final eBytes = await expected.readRgba(rect);
  expect(aBytes.length, eBytes.length);
  var maxDiff = 0;
  for (var i = 0; i < aBytes.length; i++) {
    final d = (aBytes[i] - eBytes[i]).abs();
    if (d > maxDiff) maxDiff = d;
  }
  expect(maxDiff, lessThanOrEqualTo(1));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('round trip of a full-featured project', () async {
    const area1 = Rect.fromLTWH(10, 10, 80, 60);
    const area2 = Rect.fromLTWH(40, 30, 90, 70);
    const maskArea = Rect.fromLTWH(20, 20, 50, 50);
    const selArea = Rect.fromLTWH(5, 5, 40, 40);
    const savedSelArea = Rect.fromLTWH(15, 25, 30, 30);

    final drawing1 = solidPlane(area1, const Color(0xFFFF2244));
    final drawing2 = solidPlane(area2, const Color(0xFF22AAFF));
    final layerMask = solidPlane(maskArea, const Color(0x80000000));
    final selMaskPlane = solidPlane(selArea, const Color(0xFFFFFFFF));
    final savedSelPlane = solidPlane(savedSelArea, const Color(0xFFC00000));
    final symPlane = solidPlane(const Rect.fromLTWH(0, 0, 32, 32), const Color(0xFF00FF88));

    final symbolComp = Comp(
      id: 'comp_sym',
      name: 'Symbol Comp',
      width: 128,
      height: 128,
      background: null,
      layers: [
        PaintLayer(
          'L_sym_paint',
          const LayerProps(name: 'Sym Paint'),
          CelTrack.single(symPlane),
        ),
      ],
    );

    final paintLayer = PaintLayer(
      'L_paint',
      LayerProps(
        name: 'Hero Paint',
        opacity: 0.5,
        blend: LayerBlend.multiply,
        locked: true,
        lockAlpha: true,
        clip: false,
        reference: true,
        mask: layerMask,
        maskEnabled: true,
        fx: const LayerFx(
          shadow: true,
          shadowColor: Color(0xFF112233),
          shadowDx: 4,
          shadowDy: 8,
          shadowBlur: 10,
          shadowOpacity: 0.75,
        ),
        xf: const Xform(x: 12, y: -6, sx: 1.25, sy: 0.8, rot: 15, ax: 64, ay: 64),
        tracks: const {
          Prop.x: AnimTrack([
            AnimKey(0, 10, Ease.linear),
            AnimKey(10, 80, Ease(EaseType.bezier, 0.2, 0.1, 0.8, 0.9)),
          ]),
          Prop.opacity: AnimTrack([
            AnimKey(0, 0.5, Ease.hold),
            AnimKey(8, 1.0, Ease.linear),
          ]),
        },
        colorTag: 3,
        depth: 25,
      ),
      CelTrack<TilePlane>(
        drawings: {1: drawing1, 2: drawing2},
        xs: const [Exposure(0, 1), Exposure(3, 2), Exposure(5, 0)],
      ),
    );

    final vectorShape = VShape(
      id: 'shape_1',
      name: 'GradBox',
      paths: [VPath.rect(const Rect.fromLTWH(10, 10, 100, 80), radius: 8)],
      fill: const VFill.gradient(
        GradientSpec(
          kind: GradientKind.radial,
          stops: [
            GradStop(0, Color(0xFFFFAA00)),
            GradStop(1, Color(0xFF8800FF)),
          ],
          from: Offset(20, 20),
          to: Offset(90, 70),
          repeat: true,
        ),
      ),
      stroke: const VStroke(
        color: Color(0xFF001122),
        width: 4,
        cap: StrokeCap.square,
        join: StrokeJoin.bevel,
        dash: [8, 4],
        profile: WidthProfile.taperBoth,
      ),
      opacity: 0.9,
      evenOdd: true,
    );

    final vectorLayer = VectorLayer(
      'L_vec',
      const LayerProps(name: 'Vectors'),
      CelTrack.single(VectorArt([vectorShape])),
    );

    final textLayer = TextLayer(
      'L_txt',
      const LayerProps(name: 'Title Text'),
      const TextSpec(
        text: 'Hello Drawly',
        font: 'Roboto',
        size: 42,
        color: Color(0xFFFFEE00),
        bold: true,
        italic: true,
        pos: Offset(30, 50),
        anim: TextAnimKind.wave,
      ),
    );

    final groupChild = PaintLayer(
      'L_grp_child',
      const LayerProps(name: 'Inside Group'),
      CelTrack.single(drawing1),
    );
    final groupLayer = GroupLayer(
      'L_grp',
      const LayerProps(name: 'Folder', collapsed: true),
      [groupChild],
      passThrough: false,
    );

    final adjustLayer = AdjustLayer(
      'L_adj',
      const LayerProps(name: 'Curves Adj'),
      const FilterSpec(
        type: 'curves',
        curves: {
          'rgb': [Offset(0, 0), Offset(0.5, 0.65), Offset(1, 1)],
          'r': [Offset(0, 0.1), Offset(1, 0.9)],
        },
      ),
    );

    final instanceLayer = InstanceLayer(
      'L_inst',
      const LayerProps(name: 'Sym Instance'),
      'comp_sym',
      start: 2,
      loop: false,
      speed: 1.5,
      fixedFrame: 3,
    );

    final particleLayer = ParticleLayer(
      'L_part',
      const LayerProps(name: 'Sparks'),
      const ParticleSpec(
        emitter: Rect.fromLTWH(10, 20, 100, 15),
        rate: 9,
        life: 36,
        shape: ParticleShape.star,
        additive: true,
        floorY: 200,
      ),
    );

    final timeline = Timeline(
      fps: 24,
      length: 48,
      loopStart: 2,
      loopEnd: 40,
      markers: const [Marker(4, 'Intro', 0xFF00FF00)],
      scenes: const [
        Scene(
          id: 'sc_1',
          name: 'Act 1',
          start: 0,
          length: 24,
          notes: 'opening shot',
          transition: 'dissolve',
          transitionFrames: 4,
        ),
      ],
      camera: const Camera(
        enabled: true,
        tracks: {
          Prop.x: AnimTrack([AnimKey(0, 0), AnimKey(24, 50)]),
          Prop.zoom: AnimTrack([AnimKey(0, 1), AnimKey(24, 1.5)]),
        },
        shakeAmp: 2,
        focalLength: 900,
      ),
      audio: const [
        AudioClip(
          id: 'aud_1',
          name: 'BGM',
          assetId: 'bgm.wav',
          startFrame: 1,
          volume: 0.8,
          fadeIn: 0.2,
          fadeOut: 0.5,
          duration: 4.0,
          kind: 'music',
        ),
      ],
    );

    final mainComp = Comp(
      id: 'comp_main',
      name: 'Main Shot',
      width: 256,
      height: 256,
      background: const Color(0xFFF0F4F8),
      infinite: true,
      layers: [
        paintLayer,
        vectorLayer,
        textLayer,
        groupLayer,
        adjustLayer,
        instanceLayer,
        particleLayer,
      ],
      timeline: timeline,
      guides: const [Guide(true, 128), Guide(false, 64)],
      artboards: const [Artboard('ab_1', 'Card', Rect.fromLTWH(0, 0, 128, 128))],
      selection: SelectionMask(selMaskPlane, selArea),
      savedSelections: {'hero_sel': SelectionMask(savedSelPlane, savedSelArea)},
      assist: const AssistSpec(
        kind: AssistKind.perspective2,
        points: [Offset(0, 128), Offset(256, 128)],
        snap: true,
        visible: false,
      ),
      symmetry: const SymmetrySpec(
        kind: SymmetryKind.radial,
        center: Offset(128, 128),
        count: 8,
        angle: 30,
      ),
    );

    final audioBytes = Uint8List.fromList([0x52, 0x49, 0x46, 0x46, 1, 2, 3, 4]);
    final project = Project(
      comps: {'comp_main': mainComp, 'comp_sym': symbolComp},
      mainId: 'comp_main',
      meta: const DocMeta(
        dpi: 600,
        colorMode: ColorMode.cmyk,
        bitDepth: 16,
        profile: 'FOGRA39',
        indexedColors: 128,
        softProof: true,
      ),
      assets: {'bgm.wav': audioBytes},
      palette: const [0xFFFF0000, 0xFF00FF00, 0xFF0000FF],
    );

    final encProgress = <double>[];
    final decProgress = <double>[];
    final bytes = await ProjectCodec.encode(project, onProgress: encProgress.add);
    expect(encProgress, isNotEmpty);
    expect(encProgress.last, closeTo(1.0, 1e-9));

    final archive = ZipDecoder().decodeBytes(bytes);
    expect(archive.findFile('manifest.json'), isNotNull);
    expect(archive.findFile('project.json'), isNotNull);
    expect(archive.findFile('thumbnail.png'), isNotNull);
    expect(archive.findFile('assets/bgm.wav'), isNotNull);

    final restored = await ProjectCodec.decode(bytes, onProgress: decProgress.add);
    expect(decProgress, isNotEmpty);
    expect(decProgress.last, closeTo(1.0, 1e-9));

    expect(restored.mainId, 'comp_main');
    expect(restored.comps.keys.toSet(), {'comp_main', 'comp_sym'});
    expect(restored.meta.colorMode, ColorMode.cmyk);
    expect(restored.meta.dpi, 600);
    expect(restored.meta.bitDepth, 16);
    expect(restored.meta.profile, 'FOGRA39');
    expect(restored.meta.softProof, isTrue);
    expect(restored.palette, [0xFFFF0000, 0xFF00FF00, 0xFF0000FF]);
    expect(restored.assets['bgm.wav'], audioBytes);

    final mc = restored.main;
    expect(mc.id, 'comp_main');
    expect(mc.name, 'Main Shot');
    expect(mc.width, 256);
    expect(mc.height, 256);
    expect(mc.background, const Color(0xFFF0F4F8));
    expect(mc.infinite, isTrue);
    expect(mc.layers.map((l) => l.id).toList(), [
      'L_paint',
      'L_vec',
      'L_txt',
      'L_grp',
      'L_adj',
      'L_inst',
      'L_part',
    ]);

    final rp = mc.layers[0] as PaintLayer;
    expect(rp.name, 'Hero Paint');
    expect(rp.opacity, 0.5);
    expect(rp.blend, LayerBlend.multiply);
    expect(rp.locked, isTrue);
    expect(rp.props.lockAlpha, isTrue);
    expect(rp.props.reference, isTrue);
    expect(rp.props.fx.shadow, isTrue);
    expect(rp.props.fx.shadowDx, 4);
    expect(rp.props.fx.shadowDy, 8);
    expect(rp.props.fx.shadowOpacity, 0.75);
    expect(rp.props.tracks[Prop.x]!.keys[1].ease, const Ease(EaseType.bezier, 0.2, 0.1, 0.8, 0.9));
    expect(rp.props.tracks[Prop.opacity]!.keys[0].ease, Ease.hold);
    expect(rp.cels.xs.map((e) => [e.frame, e.drawing]).toList(), [
      [0, 1],
      [3, 2],
      [5, 0],
    ]);
    await expectPlanesEqual(rp.cels.drawings[1]!, drawing1, const Rect.fromLTWH(0, 0, 256, 256));
    await expectPlanesEqual(rp.cels.drawings[2]!, drawing2, const Rect.fromLTWH(0, 0, 256, 256));
    await expectPlanesEqual(rp.props.mask!, layerMask, const Rect.fromLTWH(0, 0, 256, 256));

    final rv = mc.layers[1] as VectorLayer;
    final rShape = rv.cels.at(0)!.shapes.single;
    expect(rShape.id, 'shape_1');
    expect(rShape.name, 'GradBox');
    expect(rShape.fill.kind, FillKind.gradient);
    expect(rShape.fill.gradient!.kind, GradientKind.radial);
    expect(rShape.fill.gradient!.repeat, isTrue);
    expect(rShape.stroke!.dash, [8, 4]);
    expect(rShape.stroke!.profile, WidthProfile.taperBoth);
    expect(rShape.evenOdd, isTrue);

    final rt = mc.layers[2] as TextLayer;
    expect(rt.text.text, 'Hello Drawly');
    expect(rt.text.bold, isTrue);
    expect(rt.text.anim, TextAnimKind.wave);

    final rg = mc.layers[3] as GroupLayer;
    expect(rg.passThrough, isFalse);
    expect(rg.children.single.id, 'L_grp_child');
    await expectPlanesEqual(
      (rg.children.single as PaintLayer).cels.at(0)!,
      drawing1,
      const Rect.fromLTWH(0, 0, 256, 256),
    );

    final ra = mc.layers[4] as AdjustLayer;
    expect(ra.filter.type, 'curves');
    expect(ra.filter.curves['rgb']!.length, 3);
    expect(ra.filter.curves['rgb']![1], const Offset(0.5, 0.65));

    final ri = mc.layers[5] as InstanceLayer;
    expect(ri.compId, 'comp_sym');
    expect(ri.fixedFrame, 3);
    expect(ri.loop, isFalse);
    expect(ri.speed, 1.5);

    final rpt = mc.layers[6] as ParticleLayer;
    expect(rpt.spec.shape, ParticleShape.star);
    expect(rpt.spec.additive, isTrue);
    expect(rpt.spec.floorY, 200);

    expect(mc.selection!.bounds, selArea);
    await expectPlanesEqual(mc.selection!.mask, selMaskPlane, const Rect.fromLTWH(0, 0, 256, 256));
    expect(mc.savedSelections['hero_sel']!.bounds, savedSelArea);
    await expectPlanesEqual(
      mc.savedSelections['hero_sel']!.mask,
      savedSelPlane,
      const Rect.fromLTWH(0, 0, 256, 256),
    );

    expect(mc.guides.length, 2);
    expect(mc.guides[0].vertical, isTrue);
    expect(mc.guides[0].pos, 128);
    expect(mc.artboards.single.name, 'Card');
    expect(mc.assist.kind, AssistKind.perspective2);
    expect(mc.assist.visible, isFalse);
    expect(mc.symmetry.kind, SymmetryKind.radial);
    expect(mc.symmetry.count, 8);
    expect(mc.timeline.markers.single.label, 'Intro');
    expect(mc.timeline.scenes.single.transition, 'dissolve');
    expect(mc.timeline.camera.enabled, isTrue);
    expect(mc.timeline.audio.single.assetId, 'bgm.wav');
  });

  test('deduplicates shared TilePlane tiles across drawings and layers', () async {
    final shared = solidPlane(const Rect.fromLTWH(10, 10, 100, 100), const Color(0xFF336699));
    expect(shared.tileCount, 1);

    final layer1 = PaintLayer(
      'L1',
      const LayerProps(name: 'L1'),
      CelTrack<TilePlane>(
        drawings: {1: shared, 2: shared},
        xs: const [Exposure(0, 1), Exposure(2, 2)],
      ),
    );
    final layer2 = PaintLayer(
      'L2',
      const LayerProps(name: 'L2'),
      CelTrack.single(shared),
    );
    final comp = Comp(id: 'c', name: 'c', width: 256, height: 256, layers: [layer1, layer2]);
    final project = Project(comps: {'c': comp}, mainId: 'c');

    final bytes = await ProjectCodec.encode(project, thumbnail: false);
    final archive = ZipDecoder().decodeBytes(bytes);
    final tileFiles = archive.files.where((f) => f.isFile && f.name.startsWith('tiles/')).toList();
    expect(tileFiles.length, 1);

    final decoded = await ProjectCodec.decode(bytes);
    final dl1 = decoded.main.layers[0] as PaintLayer;
    final dl2 = decoded.main.layers[1] as PaintLayer;
    final key = shared.keys.single;
    expect(identical(dl1.cels.drawings[1]![key], dl1.cels.drawings[2]![key]), isTrue);
    expect(identical(dl1.cels.drawings[1]![key], dl2.cels.drawings[1]![key]), isTrue);
  });

  test('Project.blank() round trip', () async {
    final blank = Project.blank(width: 640, height: 480, name: 'Blank Test');
    final bytes = await ProjectCodec.encode(blank);
    final restored = await ProjectCodec.decode(bytes);
    expect(restored.main.width, 640);
    expect(restored.main.height, 480);
    expect(restored.main.name, 'Blank Test');
    expect(restored.main.layers.length, 1);
    expect(restored.main.layers.first, isA<PaintLayer>());
  });

  test('throws FormatException on invalid archives or newer format versions', () async {
    // 1. Random non-zip bytes
    expect(
      () => ProjectCodec.decode(Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8])),
      throwsFormatException,
    );

    // 2. Zip without project.json
    final missingProjectZip = Archive()
      ..addFile(ArchiveFile.string('manifest.json', jsonEncode({'format': 'drawly', 'version': 1})));
    final missingProjectBytes = Uint8List.fromList(ZipEncoder().encodeBytes(missingProjectZip));
    expect(
      () => ProjectCodec.decode(missingProjectBytes),
      throwsFormatException,
    );

    // 3. Zip with version: 999
    final futureZip = Archive()
      ..addFile(ArchiveFile.string('manifest.json', jsonEncode({'format': 'drawly', 'version': 999})))
      ..addFile(ArchiveFile.string('project.json', jsonEncode({'mainId': 'c', 'comps': []})));
    final futureBytes = Uint8List.fromList(ZipEncoder().encodeBytes(futureZip));
    expect(
      () => ProjectCodec.decode(futureBytes),
      throwsFormatException,
    );
  });

  test('unknown layer type in project.json is skipped gracefully', () async {
    final blank = Project.blank(width: 256, height: 256);
    final bytes = await ProjectCodec.encode(blank, thumbnail: false);
    final archive = ZipDecoder().decodeBytes(bytes);

    final projectFile = archive.findFile('project.json')!;
    final projectMap = jsonDecode(utf8.decode(projectFile.content)) as Map<String, dynamic>;
    final comps = projectMap['comps'] as List;
    final firstComp = comps.first as Map<String, dynamic>;
    final layers = firstComp['layers'] as List;
    layers.add({
      'type': 'future_3d_hologram',
      'id': 'L_unknown',
      'props': {'name': 'Mystery'},
    });

    final modifiedArchive = Archive()
      ..addFile(ArchiveFile.string('manifest.json', jsonEncode({'format': 'drawly', 'version': 1})))
      ..addFile(ArchiveFile.string('project.json', jsonEncode(projectMap)));
    final modifiedBytes = Uint8List.fromList(ZipEncoder().encodeBytes(modifiedArchive));

    final restored = await ProjectCodec.decode(modifiedBytes);
    expect(restored.main.layers.length, 1);
    expect(restored.main.layers.single.id, blank.main.layers.single.id);
  });
}
