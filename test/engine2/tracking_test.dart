import 'dart:math' as math;
import 'dart:typed_data';
import 'package:drawly/engine/tracking.dart';
import 'package:flutter_test/flutter_test.dart';
GrayFrame noise() { final random = math.Random(1); return GrayFrame(Uint8List.fromList(List.generate(4096, (_) => random.nextInt(256))), 64, 64); }
GrayFrame shift(GrayFrame a, int dx, int dy) => GrayFrame(Uint8List.fromList([for (var y = 0; y < 64; y++) for (var x = 0; x < 64; x++) x - dx >= 0 && x - dx < 64 && y - dy >= 0 && y - dy < 64 ? a.pixels[(y - dy) * 64 + x - dx] : 0]), 64, 64);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('textured square follows six frames at three and one pixels', () {
    final random = math.Random(1), texture = List.generate(21 * 21, (_) => random.nextInt(256));
    final frames = [for (var f = 0; f < 6; f++) GrayFrame(Uint8List.fromList([for (var y = 0; y < 64; y++) for (var x = 0; x < 64; x++)
      x >= 10 + f * 3 && x < 31 + f * 3 && y >= 10 + f && y < 31 + f ? texture[(y - 10 - f) * 21 + x - 10 - f * 3] : random.nextInt(30)]), 64, 64)];
    final points = trackPoint(frames, const Offset(20, 20), patch: 15, search: 8);
    for (var f = 0; f < 6; f++) { expect((points[f] - Offset(20 + f * 3.0, 20 + f.toDouble())).distance, lessThanOrEqualTo(1)); }
  });
  test('self correlation, flat patches and clipped borders', () {
    final a = noise();
    for (final p in [const Offset(32, 32), const Offset(1, 1)]) { final match = trackPatch(a, a, p, search: 5); expect(match.pos, p); expect(match.score, greaterThan(0.99)); }
    final flat = GrayFrame(Uint8List(4096), 64, 64); expect(trackPatch(flat, flat, const Offset(20, 20)).score, 0);
    expect(trackPoint([a, flat], const Offset(20, 20), search: 5).last, const Offset(20, 20));
  });
  test('global translation estimated by median grid motion', () { final a = noise(); final motion = estimateShake([a, shift(a, 5, -3)], search: 8); expect(motion.first, Offset.zero); expect((motion.last - const Offset(5, -3)).distance, lessThanOrEqualTo(1)); });
  test('stabilization preserves lengths and constant motion', () {
    expect(stabilizeOffsets(List.filled(5, const Offset(4, 7)), window: 99), List.filled(5, Offset.zero));
    expect(stabilizeOffsets([]), isEmpty); expect(stabilizeOffsets([Offset.zero, const Offset(9, 0), Offset.zero], window: 3)[1], const Offset(-6, 0));
  });
  test('RGBA luminance is rounded and invalid dimensions rejected', () { expect(grayFromRgba(Uint8List.fromList([255, 255, 255, 255, 0, 0, 0, 255, 255, 0, 0, 255]), 3, 1).pixels, [255, 0, 54]); expect(() => grayFromRgba(Uint8List(0), 3, 1), throwsArgumentError); });
}
