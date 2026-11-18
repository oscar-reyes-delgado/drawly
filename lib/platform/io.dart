// Local file system access; resolves to a no-op implementation on the web.
export 'io_stub.dart' if (dart.library.io) 'io_native.dart';
