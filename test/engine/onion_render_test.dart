import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:drawly/engine/compositor.dart';
import 'package:drawly/engine/tiles.dart';
import 'package:drawly/model/document.dart';
import 'package:drawly/model/layer.dart';
import 'package:flutter_test/flutter_test.dart';

List<int> _at(Uint8List d, int w, int x, int y) => d.sublist((y * w + x) * 4, (y * w + x) * 4 + 4);

TilePlane _solid(ui.Rect r, ui.Color c) => TilePlane.empty.drawn((cv) => cv.drawRect(r, ui.Paint()..color = c), area: r);

/// The onion-skin options reach the compositor through renderCompImage.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('onion skin shows the previous drawing of the onion layer, never on export', () async {
    final left = _solid(const ui.Rect.fromLTWH(0, 0, 16, 32), const ui.Color(0xFF000000));
    final right = _solid(const ui.Rect.fromLTWH(16, 0, 16, 32), const ui.Color(0xFF000000));
    const cels = [Exposure(0, 1), Exposure(1, 2)];
    final layer = PaintLayer('L', LayerProps(name: 'L'), CelTrack(drawings: {1: left, 2: right}, xs: cels));
    final comp = Comp(id: 'c', name: 't', width: 32, height: 32, background: null, layers: [layer]);
    final project = Project(comps: {'c': comp}, mainId: 'c');
    const onion = OnionSkin(enabled: true, before: 1, after: 0);

    Future<int> alphaAt(int x, {OnionSkin? o, bool export = false, String? onionLayer = 'L'}) async {
      final img = renderCompImage(project, comp, 1, background: false, useCamera: false, forExport: export, onion: o, onionLayerId: onionLayer);
      final px = await imageToRgba(img, straight: true);
      img.dispose();
      return _at(px, 32, x, 16)[3];
    }

    expect(await alphaAt(4), 0, reason: 'no onion: frame 1 only shows the right half');
    expect(await alphaAt(4, o: onion), greaterThan(0), reason: 'the ghost of frame 0 is visible');
    expect(await alphaAt(4, o: onion), lessThan(255), reason: 'the ghost is translucent');
    expect(await alphaAt(4, o: onion, export: true), 0, reason: 'exports never show onion skin');
    expect(await alphaAt(4, o: onion, onionLayer: 'other'), 0, reason: 'only the onion layer gets ghosts');
    expect(await alphaAt(24, o: onion), 255, reason: 'the current drawing stays opaque');
  });
}
