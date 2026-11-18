import 'dart:convert';
import 'dart:ui';
import 'package:drawly/engine/tiles.dart';
import 'package:drawly/io/lottie_export.dart';
import 'package:drawly/model/anim.dart';
import 'package:drawly/model/document.dart';
import 'package:drawly/model/layer.dart';
import 'package:drawly/model/layer_fx.dart';
import 'package:drawly/model/specs.dart';
import 'package:drawly/model/vector.dart';
import 'package:flutter_test/flutter_test.dart';

VectorArt art() => VectorArt([VShape(paths: [VPath.rect(const Rect.fromLTWH(0, 0, 20, 10))], fill: const VFill.solid(Color(0xffff0000)))]);
VectorLayer vector(String id, [LayerProps props = const LayerProps()]) => VectorLayer(id, props.copyWith(name: id), CelTrack.single(art()));
Project project(List<Layer> layers) => Project(mainId: 'c', comps: {'c': Comp(id: 'c', name: 'Test', width: 64, height: 64, layers: layers, timeline: const Timeline(length: 12))});
Future<Map<String, dynamic>> decoded(List<Layer> layers) async => jsonDecode((await exportLottie(project(layers))).json) as Map<String, dynamic>;
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('root fields and rectangle vertices, tangents and fill', () async {
    final j = await decoded([vector('a')]); expect(j.keys, containsAll(['v', 'fr', 'ip', 'op', 'w', 'h', 'layers'])); expect(j['op'], 12);
    final l = j['layers'][0]; expect(l['ty'], 4);
    final items = l['shapes'][0]['it'] as List, path = items.first['ks']['k'];
    expect(path['v'].length, 4); expect(path['c'], isTrue); expect(path['i'], List.filled(4, [0, 0]));
    expect(items.firstWhere((e) => e['ty'] == 'fl')['c']['k'], [1, 0, 0, 1]);
  });
  test('exposures split at keys and blank exposures stay empty', () async {
    final layer = VectorLayer('a', const LayerProps(), CelTrack(drawings: {1: art(), 2: art()}, xs: const [Exposure(0, 1), Exposure(6, 2)]));
    final j = await decoded([layer]); expect((j['layers'] as List).map((e) => [e['ip'], e['op']]), [[0, 6], [6, 12]]);
    final blank = await decoded([layer.withCels(CelTrack(drawings: {1: art()}, xs: const [Exposure(0, 1), Exposure(6, 0)]))]); expect(blank['layers'].length, 1); expect(blank['layers'][0]['op'], 6);
  });
  test('native keyframes, hold, position separation and anchors', () async {
    final j = await decoded([vector('a', const LayerProps(xf: Xform(ax: 3), tracks: {Prop.rotation: AnimTrack([AnimKey(0, 0, Ease.linear), AnimKey(10, 90)]), Prop.x: AnimTrack([AnimKey(0, 5, Ease.hold), AnimKey(10, 15)])}))]);
    final ks = j['layers'][0]['ks']; expect(ks['r']['a'], 1); expect(ks['r']['k'].length, 2); expect(ks['r']['k'][1]['s'], [90]);
    expect(ks['p']['s'], isTrue); expect(ks['p']['x']['k'][0]['h'], 1); expect(ks['p']['x']['k'][0]['s'], [8]);
  });
  test('unsupported easing is sampled per frame and scale keys are vectors', () async {
    final j = await decoded([vector('a', const LayerProps(tracks: {Prop.rotation: AnimTrack([AnimKey(0, 0, Ease(EaseType.cubicIn)), AnimKey(4, 64)]), Prop.scaleX: AnimTrack([AnimKey(0, 1, Ease.linear), AnimKey(4, 2)])}))]);
    final ks = j['layers'][0]['ks']; expect(ks['r']['k'].length, 5); expect(ks['r']['k'][2]['s'], [8]); expect(ks['s']['k'][2]['s'], [150, 100, 100]);
  });
  test('layer ordering and groups respect visibility with warnings', () async {
    final result = await exportLottie(project([vector('bottom'), GroupLayer('g', const LayerProps(opacity: 0.5), [vector('middle'), vector('top')]), vector('hidden', const LayerProps(visible: false)), vector('draft', const LayerProps(draft: true))]));
    expect((jsonDecode(result.json)['layers'] as List).map((l) => l['nm']), ['top', 'middle', 'bottom']); expect(result.warnings.length, 1);
  });
  test('raster embeds PNG and compensates cropped bounds under scale', () async {
    final plane = TilePlane.empty.drawn((c) => c.drawRect(const Rect.fromLTWH(10, 20, 4, 4), Paint()..color = const Color(0xffff0000)), area: const Rect.fromLTWH(10, 20, 4, 4));
    try {
      final layer = PaintLayer('p', const LayerProps(xf: Xform(sx: 2, sy: 3)), CelTrack.single(plane));
      final result = await exportLottie(project([layer])), j = jsonDecode(result.json);
      expect(j['assets'][0]['p'], startsWith('data:image/png;base64,')); expect(j['assets'][0]['w'], 4);
      expect(j['layers'][0]['ks']['a']['k'], [-10, -20, 0]);
      final omitted = await exportLottie(project([layer]), embedRaster: false); expect(jsonDecode(omitted.json)['layers'], isEmpty); expect(omitted.warnings.length, 1);
    } finally { for (final key in plane.keys) { plane[key]!.dispose(); } }
  });
  test('unsupported layers and features produce warnings without failing', () async {
    final result = await exportLottie(project([const TextLayer('text', LayerProps(name: 'text'), TextSpec()), vector('a', const LayerProps(blend: LayerBlend.multiply, fx: LayerFx(shadow: true), mask: TilePlane.empty))]));
    expect(result.warnings.length, 4); expect(jsonDecode(result.json)['layers'].length, 1);
  });
}
