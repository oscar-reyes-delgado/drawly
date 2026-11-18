import 'dart:math' as math;

final math.Random _rng = math.Random();
int _counter = 0;

/// Short unique id (unique within and across sessions for practical purposes).
String newId([String prefix = 'n']) {
  _counter++;
  final r = _rng.nextInt(0x7FFFFFFF).toRadixString(36);
  final t = (DateTime.now().microsecondsSinceEpoch & 0xFFFFFFF).toRadixString(36);
  return '$prefix${_counter.toRadixString(36)}$t$r';
}
