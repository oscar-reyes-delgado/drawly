import 'package:drawly/app/document_controller.dart';
import 'package:drawly/app/easy_defaults.dart';
import 'package:drawly/app/settings.dart';
import 'package:drawly/model/layer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('easyProject: 1 frame, Background below Drawing, Drawing active', () {
    final p = easyProject(width: 320, height: 200, fps: 8);
    final c = p.main;
    expect([c.width, c.height, c.timeline.fps, c.timeline.length], [320, 200, 8, 1]);
    expect(c.layers.map((l) => l.props.name), ['Fondo', 'Dibujo']);
    expect(c.layers.every((l) => l is PaintLayer), isTrue);
    final d = DocumentController(p, title: 't');
    expect(d.activeLayerId, c.layers.last.id);
  });

  test('easyProjectFromSettings uses the easy defaults and can be transparent', () {
    final s = Settings()
      ..easyWidth = 64
      ..easyHeight = 48
      ..easyFps = 24;
    final c = easyProjectFromSettings(s, transparent: true).main;
    expect([c.width, c.height, c.timeline.fps], [64, 48, 24]);
    expect(c.background, isNull);
  });
}
