import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_state.dart';
import '../../app/commands.dart';
import '../../core/i18n.dart';
import '../theme.dart';
import '../widgets.dart';

/// Searchable list of every command (Ctrl+K).
Future<void> showCommandPalette(BuildContext context) async {
  final id = await showDialog<String>(context: context, builder: (_) => const _Palette());
  if (id != null) AppState.I.commands.run(id);
}

class _Palette extends StatefulWidget {
  const _Palette();

  @override
  State<_Palette> createState() => _PaletteState();
}

class _PaletteState extends State<_Palette> {
  final TextEditingController _q = TextEditingController();
  final ScrollController _scroll = ScrollController();
  late List<Command> _results = AppState.I.commands.search('');
  int _index = 0;

  @override
  void dispose() {
    _q.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _move(int delta) {
    if (_results.isEmpty) return;
    setState(() => _index = (_index + delta).clamp(0, _results.length - 1));
    const h = 34.0;
    final top = _index * h;
    if (_scroll.hasClients) {
      if (top < _scroll.offset) _scroll.jumpTo(top);
      if (top + h > _scroll.offset + 340) _scroll.jumpTo(top + h - 340);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final reg = AppState.I.commands;
    return Dialog(
      alignment: const Alignment(0, -0.6),
      child: SizedBox(
        width: 560,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Focus(
              onKeyEvent: (_, e) {
                if (e is KeyUpEvent) return KeyEventResult.ignored;
                if (e.logicalKey == LogicalKeyboardKey.arrowDown) {
                  _move(1);
                  return KeyEventResult.handled;
                }
                if (e.logicalKey == LogicalKeyboardKey.arrowUp) {
                  _move(-1);
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: TextField(
                controller: _q,
                autofocus: true,
                decoration: InputDecoration(prefixIcon: const Icon(Icons.search, size: 18), hintText: tr('Buscar un comando…', 'Search for a command…')),
                onChanged: (v) => setState(() {
                  _results = reg.search(v);
                  _index = 0;
                }),
                onSubmitted: (_) {
                  if (_results.isNotEmpty) Navigator.pop(context, _results[_index].id);
                },
              ),
            ),
          ),
          SizedBox(
            height: fitDialogHeight(context, 340, margin: 120),
            child: _results.isEmpty
                ? Center(child: Text(tr('Sin resultados', 'No results'), style: kSmall.copyWith(color: context.dim)))
                : ListView.builder(
                    controller: _scroll,
                    itemExtent: 34,
                    itemCount: _results.length,
                    itemBuilder: (_, i) {
                      final c = _results[i];
                      final enabled = c.isEnabled;
                      final key = reg.shortcutOf(c.id);
                      return InkWell(
                        onTap: enabled ? () => Navigator.pop(context, c.id) : null,
                        child: Container(
                          color: i == _index ? cs.primary.withValues(alpha: 0.18) : null,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(children: [
                            SizedBox(width: 92, child: Text(commandCategoryLabel(c.category), style: kTiny.copyWith(color: context.dim), overflow: TextOverflow.ellipsis)),
                            Expanded(child: Text(c.label(), style: kSmall.copyWith(color: enabled ? cs.onSurface : cs.onSurface.withValues(alpha: 0.4)), overflow: TextOverflow.ellipsis)),
                            if (key.isNotEmpty) Text(key, style: kTiny.copyWith(color: context.dim)),
                          ]),
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }
}
