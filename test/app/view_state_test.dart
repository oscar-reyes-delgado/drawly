import 'dart:ui';

import 'package:drawly/app/view_state.dart';
import 'package:flutter_test/flutter_test.dart';

void expectOffset(Offset actual, Offset expected, [double eps = 1e-6]) {
  expect(actual.dx, closeTo(expected.dx, eps), reason: 'dx of $actual vs $expected');
  expect(actual.dy, closeTo(expected.dy, eps), reason: 'dy of $actual vs $expected');
}

void main() {
  const views = [
    ViewState(),
    ViewState(pan: Offset(120, -40), zoom: 2.5, rotation: 0.7),
    ViewState(pan: Offset(-30, 75), zoom: 0.3, rotation: -2.2, flip: true),
  ];
  const points = [Offset.zero, Offset(10, 20), Offset(-345.5, 1024)];
  const focal = Offset(321, 123);

  test('toDoc(toView(p)) == p', () {
    for (final v in views) {
      for (final p in points) {
        expectOffset(v.toDoc(v.toView(p)), p);
        expectOffset(v.toView(v.toDoc(p)), p);
      }
    }
  });

  test('zoomedAt keeps the document point under the focus fixed', () {
    for (final v in views) {
      final doc = v.toDoc(focal);
      final z = v.zoomedAt(focal, 1.7);
      expect(z.zoom, closeTo(v.zoom * 1.7, 1e-12));
      expectOffset(z.toView(doc), focal);
    }
  });

  test('rotatedAt keeps the document point under the focus fixed', () {
    for (final v in views) {
      final doc = v.toDoc(focal);
      final r = v.rotatedAt(focal, 0.9);
      expect(r.rotation, closeTo(v.rotation + 0.9, 1e-12));
      expectOffset(r.toView(doc), focal);
    }
  });

  test('flippedAt keeps the document point under the focus fixed', () {
    for (final v in views) {
      final doc = v.toDoc(focal);
      final f = v.flippedAt(focal);
      expect(f.flip, !v.flip);
      expectOffset(f.toView(doc), focal);
    }
  });

  test('fit centres the document and respects the margin', () {
    const viewport = Size(800, 600);
    const doc = Rect.fromLTWH(0, 0, 1000, 500);
    final v = ViewState.fit(viewport, doc, margin: 40);
    expect(v.zoom, closeTo(0.72, 1e-12));
    expectOffset(v.toView(doc.center), const Offset(400, 300));
    final tl = v.toView(doc.topLeft), br = v.toView(doc.bottomRight);
    expect(tl.dx, closeTo(40, 1e-9));
    expect(br.dx, closeTo(760, 1e-9));
    expect(tl.dy, greaterThanOrEqualTo(40));
    expect(br.dy, lessThanOrEqualTo(560));
  });

  test('zoom is clamped to [minZoom, maxZoom]', () {
    expect(const ViewState(zoom: 200).zoomedAt(focal, 10).zoom, ViewState.maxZoom);
    expect(const ViewState(zoom: 0.02).zoomedAt(focal, 0.1).zoom, ViewState.minZoom);
    expect(ViewState.fit(const Size(100, 100), const Rect.fromLTWH(0, 0, 1e6, 1e6)).zoom, ViewState.minZoom);
    expect(ViewState.fit(const Size(1000, 1000), const Rect.fromLTWH(0, 0, 0.5, 0.5), margin: 0).zoom, ViewState.maxZoom);
  });
}
