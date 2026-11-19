import 'package:flutter/material.dart';

import '../../app/tool_state.dart';
import '../../core/color_utils.dart';
import '../../core/i18n.dart';
import '../dialogs/prompts.dart';
import '../theme.dart';

/// The 16 basic colours of the easy palette (ARGB, opaque).
const List<int> kEasyBasicColors = [
  0xFF000000,
  0xFF555555,
  0xFFAAAAAA,
  0xFFFFFFFF,
  0xFFE53935,
  0xFFFB8C00,
  0xFFFDD835,
  0xFF7CB342,
  0xFF2E7D32,
  0xFF00ACC1,
  0xFF1E88E5,
  0xFF283593,
  0xFF8E24AA,
  0xFFEC407A,
  0xFF6D4C41,
  0xFFFFCC99,
];

/// Basic palette, recent colours and favourites; tap = foreground colour.
class EasyColorBar extends StatelessWidget {
  const EasyColorBar({
    super.key,
    required this.ts,
    required this.favorites,
    required this.onFavoritesChanged,
    this.onMore,
    this.axis = Axis.horizontal,
  });

  final ToolState ts;
  final List<int> favorites;
  final ValueChanged<List<int>> onFavoritesChanged;
  final VoidCallback? onMore;
  final Axis axis;

  void _selectColor(int argb) {
    final c = Color(argb);
    ts.fg = c;
    ts.pushColorHistory(c);
  }

  void _addFavorite() {
    final argb = ts.fg.toARGB32();
    if (favorites.contains(argb)) return;
    onFavoritesChanged([...favorites, argb]);
  }

  Future<void> _removeFavorite(BuildContext context, int index) async {
    final confirmed = await confirmDialog(
      context,
      title: tr('Quitar favorito', 'Remove favourite'),
      message: tr('¿Quitar este color de favoritos?', 'Remove this colour from favourites?'),
      ok: tr('Quitar', 'Remove'),
      danger: true,
    );
    if (!confirmed) return;
    final next = [...favorites]..removeAt(index);
    onFavoritesChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ts,
      builder: (context, _) {
        final activeArgb = ts.fg.toARGB32();
        final recent = ts.colorHistory.take(8).map((c) => c.toARGB32()).toList(growable: false);

        final basicSwatches = [
          for (final argb in kEasyBasicColors)
            _ColorSwatchButton(
              key: ValueKey('easy.color.basic.$argb'),
              argb: argb,
              selected: argb == activeArgb,
              tooltip: '#${Color(argb).hex}',
              onTap: () => _selectColor(argb),
            ),
        ];

        final recentSwatches = [
          for (var i = 0; i < recent.length; i++)
            _ColorSwatchButton(
              key: ValueKey('easy.color.recent.$i'),
              argb: recent[i],
              selected: recent[i] == activeArgb,
              tooltip: '#${Color(recent[i]).hex}',
              onTap: () => _selectColor(recent[i]),
            ),
        ];

        final favoriteSwatches = [
          for (var i = 0; i < favorites.length; i++)
            _ColorSwatchButton(
              key: ValueKey('easy.color.fav.$i'),
              argb: favorites[i],
              selected: favorites[i] == activeArgb,
              tooltip: tr('Tocar para elegir; mantener pulsado para quitar', 'Tap to pick; long-press to remove'),
              onTap: () => _selectColor(favorites[i]),
              onLongPress: () => _removeFavorite(context, i),
            ),
          _AddFavoriteButton(onTap: _addFavorite),
        ];

        if (axis == Axis.horizontal) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _HorizontalSection(title: tr('Colores', 'Colors'), children: basicSwatches),
                if (recentSwatches.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  _HorizontalSection(title: tr('Recientes', 'Recent'), children: recentSwatches),
                ],
                const SizedBox(width: 12),
                _HorizontalSection(
                  title: favorites.isEmpty ? null : tr('Favoritos', 'Favorites'),
                  children: favoriteSwatches,
                ),
                if (onMore != null) ...[
                  const SizedBox(width: 12),
                  _MoreColorsButton(onTap: onMore!, compact: false),
                ],
              ],
            ),
          );
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _VerticalSection(title: tr('Colores', 'Colors'), children: basicSwatches),
              if (recentSwatches.isNotEmpty) ...[
                const SizedBox(height: 10),
                _VerticalSection(title: tr('Recientes', 'Recent'), children: recentSwatches),
              ],
              const SizedBox(height: 10),
              _VerticalSection(
                title: favorites.isEmpty ? null : tr('Favoritos', 'Favorites'),
                children: favoriteSwatches,
              ),
              if (onMore != null) ...[
                const SizedBox(height: 10),
                _MoreColorsButton(onTap: onMore!, compact: true),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: context.dim),
      ),
    );
  }
}

class _HorizontalSection extends StatelessWidget {
  const _HorizontalSection({required this.title, required this.children});

  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null) _SectionTitle(title!),
        Row(mainAxisSize: MainAxisSize.min, children: children),
      ],
    );
  }
}

class _VerticalSection extends StatelessWidget {
  const _VerticalSection({required this.title, required this.children});

  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null) _SectionTitle(title!),
        GridView.count(
          crossAxisCount: 4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 2,
          crossAxisSpacing: 2,
          children: [
            for (final child in children) FittedBox(fit: BoxFit.scaleDown, child: child),
          ],
        ),
      ],
    );
  }
}

class _ColorSwatchButton extends StatelessWidget {
  const _ColorSwatchButton({
    super.key,
    required this.argb,
    required this.selected,
    required this.tooltip,
    required this.onTap,
    this.onLongPress,
  });

  final int argb;
  final bool selected;
  final String tooltip;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final color = Color(argb);
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        selected: selected,
        label: tooltip,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 40,
              height: 40,
              child: Center(
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: selected ? cs.primary : context.line,
                      width: selected ? 3 : 1,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AddFavoriteButton extends StatelessWidget {
  const _AddFavoriteButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tr('Añadir color actual a favoritos', 'Add current colour to favourites'),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const Key('easy.color.addFavorite'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 40,
            height: 40,
            child: Center(
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: context.cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: context.line),
                ),
                child: Icon(Icons.star_outline, size: 20, color: context.cs.onSurface),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MoreColorsButton extends StatelessWidget {
  const _MoreColorsButton({required this.onTap, required this.compact});

  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final label = tr('Más colores…', 'More colours…');
    final labelWidget = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
    );
    return Tooltip(
      message: tr('Abrir selector de color completo', 'Open full colour picker'),
      child: Material(
        color: context.cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          key: const Key('easy.color.more'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
            padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 12, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: context.line),
            ),
            child: Row(
              mainAxisSize: compact ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.palette_outlined, size: 24, color: context.cs.onSurface),
                const SizedBox(width: 6),
                if (compact) Flexible(child: labelWidget) else labelWidget,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
