import 'dart:convert';

import 'package:drawly/model/anim.dart';
import 'package:flutter_test/flutter_test.dart';

List<int> framesOf(AnimTrack t) => t.keys.map((k) => k.frame).toList();

void main() {
  group('Ease', () {
    test('every type starts at 0 and ends at 1', () {
      for (final type in EaseType.values) {
        final e = Ease(type);
        expect(e.transform(0), 0, reason: type.name);
        expect(e.transform(1), 1, reason: type.name);
      }
    });

    test('known midpoints', () {
      expect(Ease.hold.transform(0.5), 0);
      expect(Ease.linear.transform(0.5), 0.5);
      expect(const Ease(EaseType.easeIn).transform(0.5), closeTo(0.25, 1e-12));
      expect(const Ease(EaseType.easeOut).transform(0.5), closeTo(0.75, 1e-12));
    });

    test('default bezier is monotonically increasing', () {
      const e = Ease(EaseType.bezier);
      var prev = -1.0;
      for (var i = 0; i <= 20; i++) {
        final v = e.transform(i / 20);
        expect(v, greaterThan(prev), reason: 'sample $i');
        prev = v;
      }
    });

    test('toJson / fromJson round trip', () {
      for (final type in EaseType.values) {
        final e = Ease(type);
        expect(Ease.fromJson(jsonDecode(jsonEncode(e.toJson()))), e, reason: type.name);
      }
      const custom = Ease(EaseType.bezier, 0.1, 0.7, 0.3, 0.9);
      final back = Ease.fromJson(jsonDecode(jsonEncode(custom.toJson())));
      expect(back, custom);
      expect(back.x1, 0.1);
      expect(back.y2, 0.9);
      expect(Ease.fromJson(null), Ease.linear);
    });
  });

  group('AnimTrack', () {
    const track = AnimTrack([AnimKey(0, 10, Ease.linear), AnimKey(10, 20, Ease.linear)]);

    test('valueAt holds outside the keys and interpolates between them', () {
      expect(track.valueAt(-5), 10);
      expect(track.valueAt(0), 10);
      expect(track.valueAt(5), closeTo(15, 1e-12));
      expect(track.valueAt(10), 20);
      expect(track.valueAt(15), 20);
      expect(AnimTrack.none.valueAt(3), isNull);
    });

    test('withKey keeps the order and replaces a key on the same frame', () {
      final t = track.withKey(const AnimKey(5, 0)).withKey(const AnimKey(-2, 1)).withKey(const AnimKey(30, 2));
      expect(framesOf(t), [-2, 0, 5, 10, 30]);
      final r = track.withKey(const AnimKey(10, 99));
      expect(framesOf(r), [0, 10]);
      expect(r.keyAt(10)!.value, 99);
    });

    test('withoutKey, movedKey and keyAt', () {
      expect(framesOf(track.withoutKey(0)), [10]);
      expect(framesOf(track.withoutKey(7)), [0, 10]);

      final moved = track.movedKey(0, 3);
      expect(framesOf(moved), [3, 10]);
      expect(moved.keyAt(3)!.value, 10);

      final onto = track.movedKey(0, 10);
      expect(framesOf(onto), [10]);
      expect(onto.keyAt(10)!.value, 10);

      expect(identical(track.movedKey(4, 6), track), isTrue);
      expect(track.keyAt(10)!.value, 20);
      expect(track.keyAt(5), isNull);
    });

    test('shifted inserts and removes frames', () {
      const t = AnimTrack([AnimKey(0, 0), AnimKey(5, 5), AnimKey(6, 6), AnimKey(7, 7)]);
      expect(framesOf(t.shifted(5, 2)), [0, 7, 8, 9]);
      final removed = t.shifted(5, -2);
      expect(framesOf(removed), [0, 5]);
      expect(removed.keyAt(5)!.value, 7);
    });
  });

  test('tracksToJson / tracksFromJson round trip', () {
    const tracks = {
      Prop.x: AnimTrack([AnimKey(0, 1, Ease.linear), AnimKey(12, 40, Ease(EaseType.bezier, 0.2, 0.1, 0.8, 0.95))]),
      Prop.opacity: AnimTrack([AnimKey(3, 0.5, Ease.hold)]),
      Prop.rotation: AnimTrack.none,
    };
    final back = tracksFromJson(jsonDecode(jsonEncode(tracksToJson(tracks))));
    expect(back.keys.toSet(), {Prop.x, Prop.opacity}, reason: 'empty tracks are not written');
    for (final p in [Prop.x, Prop.opacity]) {
      final a = tracks[p]!.keys, b = back[p]!.keys;
      expect(b.length, a.length);
      for (var i = 0; i < a.length; i++) {
        expect(b[i].frame, a[i].frame);
        expect(b[i].value, a[i].value);
        expect(b[i].ease, a[i].ease);
      }
    }
    expect(tracksFromJson(null), isEmpty);
  });
}
