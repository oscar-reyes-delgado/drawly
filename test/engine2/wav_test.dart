import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:drawly/engine/audio/wav.dart';

AudioBuffer tone({int channels = 1}) => AudioBuffer(8000, List.generate(channels, (c) => Float32List.fromList(List.generate(8000, (i) => math.sin(2 * math.pi * 440 * i / 8000) * (c == 0 ? 1 : 0.5)))));
AudioBuffer constant(double value, {int rate = 8000}) => AudioBuffer(rate, [Float32List.fromList(List.filled(rate, value))]);

Uint8List handmade(int format, int bits, List<int> samples, {bool list = false, bool extensible = false, bool oversized = false}) {
  final fmt = ByteData(extensible ? 40 : 16);
  fmt.setUint16(0, extensible ? 0xfffe : format, Endian.little);
  fmt.setUint16(2, 1, Endian.little); fmt.setUint32(4, 8000, Endian.little);
  fmt.setUint32(8, 8000 * bits ~/ 8, Endian.little); fmt.setUint16(12, bits ~/ 8, Endian.little); fmt.setUint16(14, bits, Endian.little);
  if (extensible) { fmt.setUint16(16, 22, Endian.little); fmt.setUint16(18, bits, Endian.little); fmt.setUint16(24, format, Endian.little); }
  final out = BytesBuilder();
  void chunk(String name, List<int> bytes, {int? size}) {
    out.add(name.codeUnits); final n = ByteData(4)..setUint32(0, size ?? bytes.length, Endian.little);
    out.add(n.buffer.asUint8List()); out.add(bytes); if (bytes.length.isOdd) out.addByte(0);
  }
  chunk('fmt ', fmt.buffer.asUint8List());
  if (list) chunk('LIST', [1, 2, 3]);
  chunk('data', samples, size: oversized ? samples.length + 100 : null);
  final body = out.takeBytes(), header = ByteData(4)..setUint32(0, body.length + 4, Endian.little);
  return Uint8List.fromList([... 'RIFF'.codeUnits, ...header.buffer.asUint8List(), ...'WAVE'.codeUnits, ...body]);
}

void main() {
  for (final channels in [1, 2]) {
    test('16-bit sine round trip with $channels channels', () {
      final source = tone(channels: channels), bytes = encodeWav(source), decoded = decodeWav(bytes);
      expect(isWav(bytes), isTrue); expect(decoded.sampleRate, 8000); expect(decoded.frames, 8000); expect(decoded.channelCount, channels);
      for (var c = 0; c < channels; c++) { for (var i = 0; i < source.frames; i++) { expect(decoded.channels[c][i], closeTo(source.channels[c][i], 2 / 32768)); } }
    });
  }
  test('8-bit unsigned PCM and odd padded LIST chunk', () {
    expect(decodeWav(handmade(1, 8, [0, 128, 255], list: true)).channels.single, orderedEquals([-1, 0, 127 / 128]));
  });
  test('24-bit sign extension and oversized data declaration', () {
    expect(decodeWav(handmade(1, 24, [0, 0, 128, 0, 0, 0, 255, 255, 127], oversized: true)).channels.single,
        orderedEquals([-1, 0, 8388607 / 8388608]));
  });
  test('32-bit float and extensible subformat', () {
    final data = ByteData(12)..setFloat32(0, -0.5, Endian.little)..setFloat32(4, 0, Endian.little)..setFloat32(8, 0.75, Endian.little);
    for (final ext in [false, true]) { expect(decodeWav(handmade(3, 32, data.buffer.asUint8List(), extensible: ext)).channels.single, orderedEquals([-0.5, 0, 0.75])); }
  });
  test('32-bit integer and 64-bit float samples', () {
    final integer = ByteData(8)..setInt32(0, -2147483648, Endian.little)..setInt32(4, 1073741824, Endian.little);
    final floating = ByteData(16)..setFloat64(0, -0.25, Endian.little)..setFloat64(8, 0.5, Endian.little);
    expect(decodeWav(handmade(1, 32, integer.buffer.asUint8List())).channels.single, orderedEquals([-1, 0.5]));
    expect(decodeWav(handmade(3, 64, floating.buffer.asUint8List())).channels.single, orderedEquals([-0.25, 0.5]));
  });
  test('invalid and truncated format headers fail clearly', () {
    final bytes = Uint8List.fromList([1, 2, 3, 4]);
    expect(isWav(bytes), isFalse); expect(() => decodeWav(bytes), throwsFormatException);
    final invalid = handmade(1, 16, [0, 0]); invalid[32] = 0;
    expect(() => decodeWav(invalid), throwsFormatException);
    expect(() => decodeWav(handmade(2, 16, [0, 0])), throwsFormatException);
  });
  test('peaks preserve extrema, silence and selected ranges', () {
    final peaks = waveformPeaks(tone(), 10);
    for (var i = 0; i < 10; i++) { expect(peaks[i * 2], closeTo(-1, 0.01)); expect(peaks[i * 2 + 1], closeTo(1, 0.01)); }
    expect(waveformPeaks(constant(0), 10), everyElement(0));
    expect(waveformPeaks(constant(0.5), 1, start: 0.2, end: 0.4), orderedEquals([0.5, 0.5]));
    expect(waveformPeaks(tone(), 0), isEmpty);
  });
  test('click onsets and median tempo', () {
    const rate = 44100;
    final samples = Float32List(rate * 3);
    for (final t in [0.5, 1.0, 1.5, 2.0]) { for (var i = 0; i < 220; i++) { samples[(t * rate).round() + i] = 1; } }
    final beats = detectBeats(AudioBuffer(rate, [samples]));
    expect(beats.length, 4);
    for (var i = 0; i < 4; i++) { expect(beats[i], closeTo((i + 1) * 0.5, 0.05)); }
    expect(estimateBpm(beats), closeTo(120, 2)); expect(estimateBpm([]), isNull);
    expect(detectBeats(constant(0)), isEmpty);
  });
  test('mix placement, volume, fade, mute and clipping', () {
    final source = constant(1);
    final mixed = mixDown([MixInput(source, start: 0.25, volume: 0.5)], duration: 1.5, sampleRate: 8000);
    expect(mixed.channels[0][1999], 0); expect(mixed.channels[0][2000], 0.5); expect(mixed.channels[1][2000], 0.5);
    final fade = mixDown([MixInput(source, fadeIn: 0.5, fadeOut: 0.25)], duration: 1, sampleRate: 8000, channels: 1);
    expect(fade.channels.single.first, 0); expect(fade.channels.single[2000], 0.5); expect(fade.channels.single.last, 0);
    expect(mixDown([MixInput(source, muted: true)], duration: 1, sampleRate: 8000).channels.first, everyElement(0));
    expect(mixDown([MixInput(source), MixInput(source)], duration: 1, sampleRate: 8000).channels.first, everyElement(1));
  });
  test('trimming, negative starts and stereo downmix', () {
    final source = AudioBuffer(4, [Float32List.fromList([0, 0.25, 0.5, 1]), Float32List.fromList([0, 0.25, 0.5, 0])]);
    final mixed = mixDown([MixInput(source, trimStart: 0.25, trimEnd: 0.25)], duration: 1, sampleRate: 4, channels: 1);
    expect(mixed.channels.single, orderedEquals([0.25, 0.5, 0, 0]));
    expect(mixDown([MixInput(source, start: -0.5)], duration: 0.5, sampleRate: 4, channels: 1).channels.single, orderedEquals([0.5, 0.5]));
  });
  test('resampling preserves duration and interpolates', () {
    final source = tone(channels: 2), result = resample(source, 11025);
    expect(result.duration, source.duration); expect(result.channelCount, 2);
    expect(resample(AudioBuffer(2, [Float32List.fromList([0, 1])]), 4).channels.single, orderedEquals([0, 0.5, 1, 1]));
  });
  test('mouth shapes normalize bursts and preserve frame count', () {
    expect(mouthShapes(constant(0), fps: 24), List.filled(24, 0));
    final samples = Float32List(8000);
    for (var i = 2000; i < 4000; i++) { samples[i] = 1; }
    final shapes = mouthShapes(AudioBuffer(8000, [samples]), fps: 24);
    expect(shapes.length, 24); expect(shapes[7], 3); expect(shapes.first, 0);
    expect(mouthShapes(AudioBuffer(8000, [Float32List(1)]), fps: 24).length, 1);
  });
}
