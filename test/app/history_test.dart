import 'package:drawly/app/history.dart';
import 'package:drawly/model/document.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final project = Project.blank();
  HistoryEntry e(String label) => HistoryEntry(label, project, compId: 'c');
  List<String> labels(History h) => h.entries.map((x) => x.label).toList();

  test('push, undo, redo', () {
    final h = History(e('0'));
    expect(h.canUndo, isFalse);
    expect(h.canRedo, isFalse);
    expect(h.undo(), isNull);

    h
      ..push(e('1'))
      ..push(e('2'));
    expect(h.index, 2);
    expect(h.canUndo, isTrue);
    expect(h.canRedo, isFalse);

    expect(h.undo()!.label, '1');
    expect(h.index, 1);
    expect(h.canRedo, isTrue);
    expect(h.redo()!.label, '2');
    expect(h.redo(), isNull);
    expect(h.current.label, '2');
  });

  test('editing after undo discards redo states (linear)', () {
    final h = History(e('0'))
      ..push(e('1'))
      ..push(e('2'))
      ..undo()
      ..push(e('3'));
    expect(labels(h), ['0', '1', '3']);
    expect(h.index, 2);
    expect(h.canRedo, isFalse);
  });

  test('editing after undo keeps later states (non-linear)', () {
    final h = History(e('0'))..nonLinear = true;
    h
      ..push(e('1'))
      ..push(e('2'))
      ..undo()
      ..push(e('3'));
    expect(labels(h), ['0', '1', '2', '3']);
    expect(h.index, 3);
    expect(h.current.label, '3');
  });

  test('maxEntries trims from the start and keeps index valid', () {
    final h = History(e('0'), maxEntries: 3);
    for (final l in ['1', '2', '3', '4']) {
      h.push(e(l));
    }
    expect(labels(h), ['2', '3', '4']);
    expect(h.index, 2);
    expect(h.current.label, '4');
    expect(h.undo()!.label, '3');
    expect(h.undo()!.label, '2');
    expect(h.canUndo, isFalse);
  });

  test('replaceCurrent', () {
    final h = History(e('0'))..push(e('1'));
    h.replaceCurrent(e('1b'));
    expect(labels(h), ['0', '1b']);
    expect(h.index, 1);
    expect(h.current.label, '1b');
  });

  test('jumpTo clamps the index', () {
    final h = History(e('0'))
      ..push(e('1'))
      ..push(e('2'));
    expect(h.jumpTo(0).label, '0');
    expect(h.index, 0);
    expect(h.jumpTo(99).label, '2');
    expect(h.index, 2);
    expect(h.jumpTo(-5).label, '0');
    expect(h.index, 0);
  });

  test('clear', () {
    final h = History(e('0'))
      ..push(e('1'))
      ..push(e('2'));
    h.clear(e('new'));
    expect(labels(h), ['new']);
    expect(h.index, 0);
    expect(h.canUndo, isFalse);
    expect(h.canRedo, isFalse);
  });
}
