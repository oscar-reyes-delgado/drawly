import 'dart:math' as math;
import 'dart:typed_data';

/// Planar audio samples in the range -1..1.
class AudioBuffer {
  AudioBuffer(this.sampleRate, this.channels) {
    if (sampleRate <= 0 || channels.isEmpty || channels.any((c) => c.length != channels.first.length)) {
      throw ArgumentError('Invalid audio dimensions');
    }
  }
  final int sampleRate;
  final List<Float32List> channels;
  int get frames => channels.first.length;
  int get channelCount => channels.length;
  double get duration => frames / sampleRate;
  Float32List mono() => Float32List.fromList(List.generate(frames, (i) => channels.fold<double>(0, (sum, c) => sum + c[i]) / channelCount));
}

String _tag(Uint8List b, int offset) => String.fromCharCodes(b.sublist(offset, offset + 4));

/// Whether the bytes have a RIFF/WAVE signature.
bool isWav(Uint8List bytes) => bytes.length >= 12 && _tag(bytes, 0) == 'RIFF' && _tag(bytes, 8) == 'WAVE';

/// Decodes integer PCM and IEEE float WAV, including extensible headers.
AudioBuffer decodeWav(Uint8List bytes) {
  if (!isWav(bytes)) throw const FormatException('Expected RIFF/WAVE');
  final d = ByteData.sublistView(bytes);
  int? format, count, rate, bits, align;
  final chunks = <Uint8List>[];
  for (var p = 12; p + 8 <= bytes.length;) {
    final tag = _tag(bytes, p), size = d.getUint32(p + 4, Endian.little);
    final start = p + 8, end = math.min(bytes.length, p + 8 + size);
    if (tag == 'fmt ') {
      if (end - start < 16) throw const FormatException('Truncated WAV format');
      format = d.getUint16(start, Endian.little);
      count = d.getUint16(start + 2, Endian.little);
      rate = d.getUint32(start + 4, Endian.little);
      align = d.getUint16(start + 12, Endian.little);
      bits = d.getUint16(start + 14, Endian.little);
      if (format == 0xfffe) {
        if (end - start < 40 || d.getUint16(start + 16, Endian.little) < 22) throw const FormatException('Truncated extensible WAV');
        format = d.getUint16(start + 24, Endian.little);
      }
    } else if (tag == 'data') {
      chunks.add(Uint8List.sublistView(bytes, start, end));
    }
    p = start + size + (size & 1);
  }
  if (format == null || count == null || count <= 0 || rate == null || rate <= 0 || bits == null || align == null || chunks.isEmpty) {
    throw const FormatException('Missing or invalid WAV format/data');
  }
  if (!(format == 1 && [8, 16, 24, 32].contains(bits)) && !(format == 3 && [32, 64].contains(bits))) {
    throw const FormatException('Unsupported WAV sample format');
  }
  final width = bits ~/ 8;
  if (align < count * width) throw const FormatException('Invalid WAV block alignment');
  final samples = List.generate(count, (_) => <double>[]);
  for (final chunk in chunks) {
    final data = ByteData.sublistView(chunk);
    for (var p = 0; p + align <= chunk.length; p += align) {
      for (var c = 0; c < count; c++) {
        final o = p + c * width;
        double value;
        if (format == 3) {
          value = bits == 32 ? data.getFloat32(o, Endian.little) : data.getFloat64(o, Endian.little);
        } else if (bits == 8) {
          value = (chunk[o] - 128) / 128;
        } else if (bits == 16) {
          value = data.getInt16(o, Endian.little) / 32768;
        } else if (bits == 24) {
          var n = chunk[o] | chunk[o + 1] << 8 | chunk[o + 2] << 16;
          if (n & 0x800000 != 0) n -= 0x1000000;
          value = n / 8388608;
        } else {
          value = data.getInt32(o, Endian.little) / 2147483648;
        }
        samples[c].add(value.isFinite ? value.clamp(-1, 1).toDouble() : 0);
      }
    }
  }
  return AudioBuffer(rate, samples.map(Float32List.fromList).toList());
}

/// Encodes interleaved little-endian 16-bit PCM WAV.
Uint8List encodeWav(AudioBuffer buffer) {
  final size = buffer.frames * buffer.channelCount * 2;
  final bytes = Uint8List(44 + size), d = ByteData(44 + size);
  void tag(int p, String s) { for (var i = 0; i < s.length; i++) { d.setUint8(p + i, s.codeUnitAt(i)); } }
  tag(0, 'RIFF'); d.setUint32(4, 36 + size, Endian.little); tag(8, 'WAVE'); tag(12, 'fmt ');
  d.setUint32(16, 16, Endian.little); d.setUint16(20, 1, Endian.little);
  d.setUint16(22, buffer.channelCount, Endian.little); d.setUint32(24, buffer.sampleRate, Endian.little);
  d.setUint32(28, buffer.sampleRate * buffer.channelCount * 2, Endian.little);
  d.setUint16(32, buffer.channelCount * 2, Endian.little); d.setUint16(34, 16, Endian.little);
  tag(36, 'data'); d.setUint32(40, size, Endian.little);
  for (var i = 0; i < buffer.frames; i++) {
    for (var c = 0; c < buffer.channelCount; c++) {
      final v = buffer.channels[c][i];
      d.setInt16(44 + (i * buffer.channelCount + c) * 2, v.isFinite ? (v.clamp(-1, 1) * 32768).round().clamp(-32768, 32767) : 0, Endian.little);
    }
  }
  bytes.setAll(0, d.buffer.asUint8List());
  return bytes;
}

/// Interleaved minimum/maximum pairs over the requested time range.
Float32List waveformPeaks(AudioBuffer buffer, int buckets, {double start = 0, double? end}) {
  if (buckets < 0) throw ArgumentError.value(buckets);
  final result = Float32List(buckets * 2);
  final first = (start * buffer.sampleRate).floor().clamp(0, buffer.frames);
  final last = ((end ?? buffer.duration) * buffer.sampleRate).ceil().clamp(first, buffer.frames);
  for (var b = 0; b < buckets; b++) {
    final lo = first + (last - first) * b ~/ buckets, hi = first + (last - first) * (b + 1) ~/ buckets;
    if (lo == hi) continue;
    var min = double.infinity, max = double.negativeInfinity;
    for (var i = lo; i < hi; i++) {
      for (final c in buffer.channels) { min = math.min(min, c[i]); max = math.max(max, c[i]); }
    }
    result[b * 2] = min; result[b * 2 + 1] = max;
  }
  return result;
}

/// RMS energy onsets using 1024-sample windows and a 512-sample hop.
List<double> detectBeats(AudioBuffer buffer, {double sensitivity = 1.5, double minInterval = 0.25}) {
  final mono = buffer.mono(), energies = <double>[];
  for (var p = 0; p < mono.length; p += 512) {
    var sum = 0.0;
    final end = math.min(p + 1024, mono.length);
    for (var i = p; i < end; i++) { sum += mono[i] * mono[i]; }
    energies.add(math.sqrt(sum / (end - p)));
  }
  final beats = <double>[];
  for (var i = 1; i < energies.length; i++) {
    final from = math.max(0, i - 43);
    var mean = 0.0;
    for (var j = from; j < i; j++) { mean += energies[j]; }
    mean /= i - from;
    final e = energies[i], time = (i * 512 + 512) / buffer.sampleRate;
    if (e > sensitivity * mean && e > energies[i - 1] && (i + 1 == energies.length || e >= energies[i + 1]) &&
        (beats.isEmpty || time - beats.last >= minInterval)) { beats.add(time); }
  }
  return beats;
}

/// Tempo inferred from the median positive inter-onset interval.
double? estimateBpm(List<double> beats) {
  if (beats.length < 2) return null;
  final intervals = [for (var i = 1; i < beats.length; i++) if (beats[i] > beats[i - 1]) beats[i] - beats[i - 1]]..sort();
  if (intervals.isEmpty) return null;
  final n = intervals.length;
  return 60 / (n.isOdd ? intervals[n ~/ 2] : (intervals[n ~/ 2 - 1] + intervals[n ~/ 2]) / 2);
}

/// Changes sample rate using linear interpolation.
AudioBuffer resample(AudioBuffer buffer, int sampleRate) {
  if (sampleRate <= 0) throw ArgumentError.value(sampleRate);
  final length = (buffer.duration * sampleRate).round();
  return AudioBuffer(sampleRate, buffer.channels.map((c) {
    final out = Float32List(length);
    for (var i = 0; i < length && c.isNotEmpty; i++) {
      final p = i * buffer.sampleRate / sampleRate, a = math.min(p.floor(), c.length - 1), b = math.min(a + 1, c.length - 1);
      out[i] = c[a] + (c[b] - c[a]) * (p - a);
    }
    return out;
  }).toList());
}

/// One clip's placement, trimming and gain in a mix.
class MixInput {
  const MixInput(this.buffer, {this.start = 0, this.volume = 1, this.fadeIn = 0, this.fadeOut = 0, this.trimStart = 0, this.trimEnd = 0, this.muted = false});
  final AudioBuffer buffer;
  final double start, volume, fadeIn, fadeOut, trimStart, trimEnd;
  final bool muted;
}

/// Sums clips and clips the final output to -1..1.
AudioBuffer mixDown(List<MixInput> clips, {required double duration, int sampleRate = 44100, int channels = 2}) {
  if (duration < 0 || sampleRate <= 0 || channels <= 0) throw ArgumentError('Invalid mix dimensions');
  final count = (duration * sampleRate).round();
  final sums = List.generate(channels, (_) => Float64List(count));
  for (final clip in clips) {
    if (clip.muted) continue;
    final audio = resample(clip.buffer, sampleRate);
    final from = (clip.trimStart * sampleRate).round().clamp(0, audio.frames);
    final end = audio.frames - (clip.trimEnd * sampleRate).round().clamp(0, audio.frames - from);
    final offset = (clip.start * sampleRate).round(), length = end - from;
    final mono = channels == 1 ? audio.mono() : null;
    for (var i = math.max(0, -offset); i < length && i + offset < count; i++) {
      var gain = clip.volume;
      if (clip.fadeIn > 0) gain *= (i / (sampleRate * clip.fadeIn)).clamp(0, 1);
      if (clip.fadeOut > 0) gain *= ((length - 1 - i) / (sampleRate * clip.fadeOut)).clamp(0, 1);
      for (var c = 0; c < channels; c++) {
        sums[c][i + offset] += (mono != null ? mono[from + i] : audio.channels[c % audio.channelCount][from + i]) * gain;
      }
    }
  }
  return AudioBuffer(sampleRate, sums.map((c) => Float32List.fromList(c.map((v) => v.clamp(-1, 1).toDouble()).toList())).toList());
}

/// Quantizes frame RMS against its 95th percentile to mouth openness.
List<int> mouthShapes(AudioBuffer buffer, {required int fps, int levels = 4}) {
  if (fps <= 0 || levels <= 0) throw ArgumentError('Invalid mouth shape dimensions');
  final mono = buffer.mono();
  final energy = List.generate((buffer.duration * fps).ceil(), (f) {
    final start = (f * buffer.sampleRate / fps).floor(), end = math.min(mono.length, ((f + 1) * buffer.sampleRate / fps).floor());
    var sum = 0.0;
    for (var i = start; i < end; i++) { sum += mono[i] * mono[i]; }
    return end > start ? math.sqrt(sum / (end - start)) : 0.0;
  });
  if (energy.isEmpty) return [];
  final sorted = [...energy]..sort();
  final reference = sorted[(sorted.length * 0.95).ceil() - 1];
  return energy.map((e) => e == 0 ? 0 : reference == 0 ? levels - 1 : ((e / reference).clamp(0, 1) * (levels - 1)).round()).toList();
}
