import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// H.264 MP4 encoder provided by the platform (Media Foundation on Windows,
/// MediaCodec on Android). Unavailable elsewhere: check [isAvailable].
class VideoEncoder {
  VideoEncoder._(this._id);
  final int _id;

  static const MethodChannel _channel = MethodChannel('drawly/video');
  static bool? _available;

  /// Whether this platform can encode MP4 (cached after the first call).
  static Future<bool> isAvailable() async {
    if (_available != null) return _available!;
    if (kIsWeb) return _available = false;
    try {
      return _available = await _channel.invokeMethod<bool>('available') ?? false;
    } on MissingPluginException {
      return _available = false;
    } on PlatformException {
      return _available = false;
    }
  }

  /// Even size accepted by H.264 for a [w] x [h] picture (rounded down, at least 2).
  static (int, int) evenSize(int w, int h) => (w < 2 ? 2 : w & ~1, h < 2 ? 2 : h & ~1);

  /// Starts a file at [path]; [width] and [height] must be even.
  static Future<VideoEncoder> begin(String path, {required int width, required int height, required int fps, int? bitrate}) async {
    final rate = bitrate ?? (width * height * fps * 0.2).round().clamp(1000000, 40000000);
    final id = await _channel.invokeMethod<int>('begin', {'path': path, 'width': width, 'height': height, 'fps': fps, 'bitrate': rate});
    if (id == null) throw PlatformException(code: 'begin', message: 'No video handle');
    return VideoEncoder._(id);
  }

  /// Adds one opaque frame (straight RGBA, width * height * 4 bytes).
  Future<void> addFrame(Uint8List rgba) => _channel.invokeMethod<void>('addFrame', {'id': _id, 'rgba': rgba});

  /// Closes the file; false when the platform could not finish it.
  Future<bool> finish() async => await _channel.invokeMethod<bool>('finish', {'id': _id}) ?? false;

  /// Stops and deletes the partial file.
  Future<void> abort() => _channel.invokeMethod<void>('abort', {'id': _id});
}
