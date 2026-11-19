import 'package:drawly/app/settings.dart';
import 'package:drawly/app/tool_state.dart';
import 'package:drawly/core/i18n.dart';
import 'package:drawly/ui/easy/easy_color_bar.dart';
import 'package:drawly/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: buildTheme(Settings(), Brightness.dark),
      home: Scaffold(body: child),
    );

void main() {
  test('kEasyBasicColors has 16 unique opaque colours', () {
    expect(kEasyBasicColors.length, 16);
    expect(kEasyBasicColors.toSet().length, 16);
    for (final c in kEasyBasicColors) {
      expect((c >>> 24) & 0xFF, 0xFF);
    }
  });

  testWidgets('tapping red sets ts.fg, pushes to colorHistory and shows Recent section', (tester) async {
    final ts = ToolState();
    await tester.pumpWidget(_wrap(EasyColorBar(
      ts: ts,
      favorites: const [],
      onFavoritesChanged: (_) {},
    )));

    expect(find.text(tr('Recientes', 'Recent')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('easy.color.basic.4293212469')));
    await tester.pump();

    expect(ts.fg, const Color(0xFFE53935));
    expect(ts.colorHistory, contains(const Color(0xFFE53935)));
    expect(find.text(tr('Recientes', 'Recent')), findsOneWidget);
  });

  testWidgets('star button adds current colour to favorites without duplicating', (tester) async {
    final ts = ToolState()..fg = const Color(0xFF1E88E5);
    var favs = <int>[0xFF000000];
    var callCount = 0;

    await tester.pumpWidget(_wrap(StatefulBuilder(
      builder: (context, setState) => EasyColorBar(
        ts: ts,
        favorites: favs,
        onFavoritesChanged: (next) {
          callCount++;
          setState(() => favs = next);
        },
      ),
    )));

    await tester.ensureVisible(find.byKey(const Key('easy.color.addFavorite')));
    await tester.tap(find.byKey(const Key('easy.color.addFavorite')));
    await tester.pump();

    expect(callCount, 1);
    expect(favs, [0xFF000000, 0xFF1E88E5]);

    // Tapping again with the same colour must not duplicate it.
    await tester.tap(find.byKey(const Key('easy.color.addFavorite')));
    await tester.pump();

    expect(callCount, 1);
    expect(favs, [0xFF000000, 0xFF1E88E5]);
  });

  testWidgets('long-pressing a favorite and confirming removes it', (tester) async {
    final ts = ToolState();
    var favs = <int>[0xFFE53935, 0xFF1E88E5];

    await tester.pumpWidget(_wrap(StatefulBuilder(
      builder: (context, setState) => EasyColorBar(
        ts: ts,
        favorites: favs,
        onFavoritesChanged: (next) => setState(() => favs = next),
      ),
    )));

    expect(find.text(tr('Favoritos', 'Favorites')), findsOneWidget);

    await tester.ensureVisible(find.byKey(const ValueKey('easy.color.fav.0')));
    await tester.longPress(find.byKey(const ValueKey('easy.color.fav.0')));
    await tester.pumpAndSettle();

    expect(find.text(tr('Quitar favorito', 'Remove favourite')), findsOneWidget);
    await tester.tap(find.text(tr('Quitar', 'Remove')));
    await tester.pumpAndSettle();

    expect(favs, [0xFF1E88E5]);
  });

  testWidgets('onMore is called when tapping More colours and hidden when null', (tester) async {
    final ts = ToolState();
    var moreCalled = 0;

    await tester.pumpWidget(_wrap(EasyColorBar(
      ts: ts,
      favorites: const [],
      onFavoritesChanged: (_) {},
      onMore: () => moreCalled++,
    )));

    await tester.ensureVisible(find.byKey(const Key('easy.color.more')));
    await tester.tap(find.byKey(const Key('easy.color.more')));
    await tester.pump();
    expect(moreCalled, 1);

    await tester.pumpWidget(_wrap(EasyColorBar(
      ts: ts,
      favorites: const [],
      onFavoritesChanged: (_) {},
    )));
    expect(find.byKey(const Key('easy.color.more')), findsNothing);
  });

  testWidgets('horizontal at 360px width and vertical at 120px width do not overflow', (tester) async {
    final ts = ToolState();
    for (final c in kEasyBasicColors.take(10)) {
      ts.pushColorHistory(Color(c));
    }

    await tester.pumpWidget(_wrap(SizedBox(
      width: 360,
      child: EasyColorBar(
        ts: ts,
        favorites: const [0xFF000000, 0xFFE53935, 0xFF1E88E5, 0xFF2E7D32, 0xFFFDD835],
        onFavoritesChanged: (_) {},
        onMore: () {},
        axis: Axis.horizontal,
      ),
    )));
    await tester.pump();
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(_wrap(SizedBox(
      width: 120,
      height: 400,
      child: EasyColorBar(
        ts: ts,
        favorites: const [0xFF000000, 0xFFE53935, 0xFF1E88E5, 0xFF2E7D32, 0xFFFDD835],
        onFavoritesChanged: (_) {},
        onMore: () {},
        axis: Axis.vertical,
      ),
    )));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
