import 'package:flutter/material.dart';

import '../app/app_state.dart';
import '../app/commands.dart';
import 'theme.dart';

/// Menu order and grouping. Ids missing from the registry are skipped, and
/// commands of a category that are not listed here are appended at the end of
/// that menu, so new commands always show up somewhere.
const Map<CommandCategory, List<String>> kMenuLayout = {
  CommandCategory.file: [
    'file.new', 'file.open', 'file.library', 'file.openOra', '-', 'file.importImage', 'file.importSvg', '-', 'file.save', 'file.saveAs', '-',
    'file.export', 'file.exportPng', 'file.exportJpg', 'file.exportWebp', 'file.exportMp4', 'file.exportGif', 'file.exportApng', 'file.exportSequence', 'file.exportSvg', 'file.exportOra', 'file.exportPsd', 'file.exportLottie', 'file.exportEdl', 'file.exportFcpXml', '-',
    'file.close',
  ],
  CommandCategory.edit: [
    'edit.undo', 'edit.redo', '-', 'edit.cut', 'edit.copy', 'edit.copyMerged', 'edit.paste', 'edit.clear', '-',
    'edit.fillFg', 'edit.fillBg', 'edit.strokeSelection',
  ],
  CommandCategory.select: ['select.all', 'select.none', 'select.invert', '-', 'select.layerAlpha', '-', 'select.grow', 'select.shrink', 'select.feather', 'select.smooth'],
  CommandCategory.image: ['image.cropSelection', 'image.trim', '-', 'image.rotate90cw', 'image.rotate90ccw', 'image.rotate180', 'image.flipH', 'image.flipV', '-', 'image.flatten'],
  CommandCategory.layer: [
    'layer.newPaint', 'layer.newVector', 'layer.newGroup', '-', 'layer.duplicate', 'layer.delete', '-', 'layer.group', 'layer.ungroup', 'layer.mergeDown', 'layer.mergeVisible', 'layer.rasterize', '-',
    'layer.raise', 'layer.lower', 'layer.selectAbove', 'layer.selectBelow', '-', 'layer.flipH', 'layer.flipV', '-',
    'layer.addMask', 'layer.deleteMask', 'layer.applyMask', 'layer.invertMask', 'layer.toggleMask', '-', 'layer.toSymbol',
  ],
  CommandCategory.animation: [
    'anim.play', 'anim.watch', '-', 'anim.firstFrame', 'anim.prevFrame', 'anim.nextFrame', 'anim.lastFrame', 'anim.prevKey', 'anim.nextKey', '-',
    'anim.newKey', 'anim.dupKey', 'anim.blankKey', 'anim.deleteKey', '-', 'anim.insertFrame', 'anim.removeFrame', 'anim.copyFrame', 'anim.pasteFrame', '-', 'anim.loop', 'anim.pingPong',
  ],
  CommandCategory.view: [
    'view.zoomIn', 'view.zoomOut', 'view.fit', 'view.actual', '-', 'view.rotateCw', 'view.rotateCcw', 'view.rotateReset', 'view.flip', '-',
    'view.grid', 'view.pixelGrid', 'view.guides', 'view.rulers', 'view.snapGrid', 'view.snapGuides', '-', 'view.camera',
  ],
  CommandCategory.color: ['color.swap', 'color.reset', '-', 'color.importPalette'],
  CommandCategory.help: ['app.palette', 'app.prefs', 'app.easyMode'],
};

/// Categories shown as top-level menus, in order.
const List<CommandCategory> kMenuOrder = [
  CommandCategory.file, CommandCategory.edit, CommandCategory.select, CommandCategory.image, CommandCategory.filter,
  CommandCategory.layer, CommandCategory.animation, CommandCategory.view, CommandCategory.color, CommandCategory.help,
];

/// Builds the menu entries of [cat]: ids from [kMenuLayout] first ('-' = divider), then the rest.
List<String> menuEntries(CommandRegistry r, CommandCategory cat) {
  final listed = kMenuLayout[cat] ?? const <String>[];
  final out = <String>[];
  for (final id in listed) {
    if (id == '-') {
      if (out.isNotEmpty && out.last != '-') out.add('-');
    } else if (r.byId(id) != null) {
      out.add(id);
    }
  }
  final extra = [for (final c in r.all) if (c.category == cat && !listed.contains(c.id)) c.id];
  if (extra.isNotEmpty) {
    if (out.isNotEmpty && out.last != '-') out.add('-');
    out.addAll(extra);
  }
  while (out.isNotEmpty && out.last == '-') {
    out.removeLast();
  }
  return out;
}

/// The application menu bar (File, Edit, Select…), generated from the command registry.
class AppMenuBar extends StatelessWidget {
  const AppMenuBar({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppState.I;
    final r = app.commands;
    return MenuBar(
      style: const MenuStyle(
        elevation: WidgetStatePropertyAll(0),
        backgroundColor: WidgetStatePropertyAll(Colors.transparent),
        padding: WidgetStatePropertyAll(EdgeInsets.zero),
      ),
      children: [
        for (final cat in kMenuOrder)
          if (menuEntries(r, cat).isNotEmpty)
            SubmenuButton(
              menuChildren: [
                for (final id in menuEntries(r, cat))
                  if (id == '-')
                    const Divider(height: 8)
                  else
                    _item(context, r, r.byId(id)!),
              ],
              child: Text(commandCategoryLabel(cat), style: kSmall),
            ),
      ],
    );
  }

  Widget _item(BuildContext context, CommandRegistry r, Command c) {
    final key = r.shortcutOf(c.id).split('|').first;
    return MenuItemButton(
      onPressed: c.isEnabled ? () => r.run(c.id) : null,
      trailingIcon: key.isEmpty ? null : Padding(padding: const EdgeInsets.only(left: 24), child: Text(key, style: kTiny.copyWith(color: context.dim))),
      child: Text(c.label(), style: kSmall),
    );
  }
}
