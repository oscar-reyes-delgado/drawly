import 'package:drawly/model/layer.dart';
import 'package:flutter_test/flutter_test.dart';

List<int> framesOf(CelTrack<Object?> t) => t.xs.map((e) => e.frame).toList();
List<int> drawingsOf(CelTrack<Object?> t) => t.xs.map((e) => e.drawing).toList();

void main() {
  // keys: frame 2 -> drawing 1 ('a'), frame 5 -> blank, frame 8 -> drawing 2 ('b')
  const track = CelTrack<String>(drawings: {1: 'a', 2: 'b'}, xs: [Exposure(2, 1), Exposure(5, 0), Exposure(8, 2)]);

  test('single', () {
    final t = CelTrack.single('only');
    expect(t.drawings, {1: 'only'});
    expect(framesOf(t), [0]);
    expect(t.at(0), 'only');
    expect(t.at(100), 'only');
  });

  test('exposureAt, drawingIdAt and at', () {
    expect(track.exposureAt(1), isNull);
    expect(track.exposureAt(4)!.frame, 2);
    expect(track.exposureAt(4)!.drawing, 1);

    expect(track.drawingIdAt(0), isNull, reason: 'before the first key');
    expect(track.drawingIdAt(2), 1);
    expect(track.drawingIdAt(4), 1, reason: 'held until the next key');
    expect(track.drawingIdAt(5), isNull, reason: 'blank exposure');
    expect(track.drawingIdAt(7), isNull, reason: 'blank is held too');
    expect(track.drawingIdAt(8), 2);
    expect(track.drawingIdAt(50), 2);

    expect(track.at(3), 'a');
    expect(track.at(6), isNull);
    expect(track.at(9), 'b');
  });

  test('withKey inserts sorted and replaces', () {
    final t = track.withKey(6, 2).withKey(0, 1).withKey(20, 1);
    expect(framesOf(t), [0, 2, 5, 6, 8, 20]);
    final r = track.withKey(5, 1);
    expect(framesOf(r), [2, 5, 8]);
    expect(drawingsOf(r), [1, 1, 2]);
  });

  test('key navigation', () {
    expect(track.hasKeyAt(5), isTrue);
    expect(track.hasKeyAt(4), isFalse);

    expect(track.prevKeyFrame(2), isNull);
    expect(track.prevKeyFrame(5), 2);
    expect(track.prevKeyFrame(7), 5);
    expect(track.prevKeyFrame(8), 5);

    expect(track.nextKeyFrame(0), 2);
    expect(track.nextKeyFrame(2), 5);
    expect(track.nextKeyFrame(6), 8);
    expect(track.nextKeyFrame(8), isNull);

    expect(track.lastKeyFrame, 8);
    expect(const CelTrack<String>(drawings: {}, xs: []).lastKeyFrame, 0);
  });

  test('newDrawingId and isShared', () {
    expect(track.newDrawingId, 3);
    expect(track.isShared(1), isFalse);
    expect(track.withKey(10, 1).isShared(1), isTrue);
  });

  test('withoutKey prunes unused drawings', () {
    final t = track.withoutKey(8);
    expect(framesOf(t), [2, 5]);
    expect(t.drawings.keys.toSet(), {1});

    final blankRemoved = track.withoutKey(5);
    expect(framesOf(blankRemoved), [2, 8]);
    expect(blankRemoved.drawings.keys.toSet(), {1, 2});
  });

  test('movedKey', () {
    final onto = track.movedKey(8, 2);
    expect(framesOf(onto), [2, 5]);
    expect(drawingsOf(onto), [2, 0]);
    expect(onto.drawings.keys.toSet(), {2}, reason: 'drawing 1 is no longer exposed');

    final later = track.movedKey(8, 10);
    expect(framesOf(later), [2, 5, 10]);
    expect(later.drawings.keys.toSet(), {1, 2});

    expect(identical(track.movedKey(4, 6), track), isTrue);
  });

  test('shifted inserts and removes frames', () {
    expect(framesOf(track.shifted(3, 2)), [2, 7, 10]);

    final removed = track.shifted(5, -3);
    expect(framesOf(removed), [2, 5]);
    expect(drawingsOf(removed), [1, 2]);
    expect(removed.drawings.keys.toSet(), {1, 2});

    final dropLast = track.shifted(8, -1);
    expect(framesOf(dropLast), [2, 5]);
    expect(dropLast.drawings.keys.toSet(), {1});
  });

  test('mapDrawings', () {
    final m = track.mapDrawings((s) => s.codeUnitAt(0));
    expect(m, isA<CelTrack<int>>());
    expect(m.drawings, {1: 0x61, 2: 0x62});
    expect(framesOf(m), framesOf(track));
  });
}
