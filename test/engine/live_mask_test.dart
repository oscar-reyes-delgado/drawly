import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:drawly/engine/compositor.dart';
import 'package:drawly/engine/tiles.dart';
import 'package:drawly/model/document.dart';
import 'package:drawly/model/layer.dart';
import 'package:flutter_test/flutter_test.dart';

List<int> _at(Uint8List d, int w, int x, int y) => d.sublist((y * w + x) * 4, (y * w + x) * 4 + 4);

TilePlane _solid(ui.Rect r, ui.Color c) => TilePlane.empty.drawn((cv) => cv.drawRect(r, ui.Paint()..color = c), area: r);

/// A live edit that replaces the layer mask (liquify on a mask) must change
/// the mask, not the layer content.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('LiveEdit.replace with onMask replaces the mask and keeps the content', () async {
    const all = ui.Rect.fromLTWH(0, 0, 32, 32);
    final layer = PaintLayer('L', LayerProps(name: 'L', mask: TilePlane.empty), CelTrack.single(_solid(all, const ui.Color(0xFFFF0000))));
    final comp = Comp(id: 'c', name: 't', width: 32, height: 32, background: null, layers: [layer]);
    final project = Project(comps: {'c': comp}, mainId: 'c');
    final newMask = _solid(const ui.Rect.fromLTWH(0, 0, 16, 32), const ui.Color(0xFF000000));

    final img = renderCompImage(project, comp, 0, background: false, useCamera: false, live: LiveEdit(layerId: 'L', replace: newMask, onMask: true));
    final px = await imageToRgba(img, straight: true);
    img.dispose();
    expect(_at(px, 32, 4, 16)[3], 0, reason: 'the live mask hides the left half');
    expect(_at(px, 32, 24, 16), [255, 0, 0, 255], reason: 'the content is still the red layer');
  });
}
