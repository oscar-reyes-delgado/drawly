import 'package:drawly/app/settings.dart';
import 'package:drawly/ui/easy/easy_prefs.dart';
import 'package:drawly/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Settings s;
  var advanced = 0;

  Future<void> open(WidgetTester tester, {Size size = const Size(1000, 900)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    s = Settings()..lang = 'es';
    advanced = 0;
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Settings(), Brightness.dark),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(onPressed: () => showEasyPrefs(context, settings: s, onAdvancedMode: () => advanced++), child: const Text('open')),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text).first);
    await tester.tap(find.text(text).first);
    await tester.pumpAndSettle();
  }

  testWidgets('theme and language', (tester) async {
    await open(tester);
    await tapText(tester, 'Claro');
    expect(s.themeMode, ThemeMode.light);
    await tapText(tester, 'English');
    expect(s.lang, 'en');
    s.update((x) => x.lang = 'es');
  });

  testWidgets('default size and fps', (tester) async {
    await open(tester);
    await tapText(tester, '1080×1920');
    expect([s.easyWidth, s.easyHeight], [1080, 1920]);
    await tester.ensureVisible(find.byKey(const ValueKey('fps.24')));
    await tester.tap(find.byKey(const ValueKey('fps.24')));
    await tester.pumpAndSettle();
    expect(s.easyFps, 24);
  });

  testWidgets('autosave switch and pen sensitivity', (tester) async {
    await open(tester);
    final sw = find.byKey(const ValueKey('prefs.autosave'));
    await tester.ensureVisible(sw);
    await tester.tap(sw);
    await tester.pumpAndSettle();
    expect(s.autosaveMinutes, 0);
    await tester.tap(sw);
    await tester.pumpAndSettle();
    expect(s.autosaveMinutes, 3);
    await tapText(tester, 'Firme');
    expect(s.pressureGamma, 1.6);
  });

  testWidgets('switch to advanced closes the dialog and calls back', (tester) async {
    await open(tester);
    final b = find.byKey(const ValueKey('prefs.toAdvanced'));
    await tester.ensureVisible(b);
    await tester.tap(b);
    await tester.pumpAndSettle();
    expect(advanced, 1);
    expect(find.text('Ajustes'), findsNothing);
  });

  testWidgets('fits a phone without overflow', (tester) async {
    await open(tester, size: const Size(360, 640));
    expect(tester.takeException(), isNull);
  });
}
