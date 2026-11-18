import 'package:flutter/material.dart';

import '../app/doc_layers.dart';
import '../core/i18n.dart';
import '../engine/text_render.dart';
import '../model/layer.dart';
import '../model/specs.dart';
import '../ui/dialogs/text_dialog.dart';
import 'tool.dart';

/// Click to add a text layer; click an existing text to edit it.
class TextTool extends Tool {
  @override
  String get id => 'text';
  @override
  String get label => tr('Texto', 'Text');
  @override
  IconData get icon => Icons.title;
  @override
  String get shortcut => 'T';
  @override
  String get hint => tr('Clic para añadir texto · Clic sobre un texto para editarlo', 'Click to add text · Click a text to edit it');
  @override
  MouseCursor get cursor => SystemMouseCursors.text;

  bool _open = false;

  @override
  void onDown(ToolEvent e) {
    final d = doc;
    final context = app.context;
    if (d == null || d.isBusy || context == null || _open) return;
    final f = d.frame.toDouble();
    TextLayer? hit;
    for (final l in walkLayers(d.comp.layers).toList().reversed) {
      if (l is! TextLayer || !l.props.visible || l.props.locked) continue;
      final local = d.comp.worldMatrix(l, f).inverse.apply(e.doc);
      if (TextRender.bounds(l.text).contains(local)) {
        hit = l;
        break;
      }
    }
    final initial = hit?.text ??
        TextSpec(
          font: ts.fontFamily,
          size: ts.fontSize,
          color: ts.fg,
          bold: ts.fontBold,
          italic: ts.fontItalic,
          align: ts.textAlign,
          pos: snapDoc(e.doc),
        );
    _open = true;
    showTextDialog(context, initial, isNew: hit == null).then((result) {
      _open = false;
      if (result == null) return;
      if (hit != null) {
        final id = hit.id;
        if (result.text.trim().isEmpty) return;
        d.selectLayer(id);
        d.updateLayer(tr('Editar texto', 'Edit text'), id, (l) => l is TextLayer ? l.withText(result) : l);
      } else if (result.text.trim().isNotEmpty) {
        d.addTextLayer(result);
        ts.set(() {
          ts.fontFamily = result.font;
          ts.fontSize = result.size;
          ts.fontBold = result.bold;
          ts.fontItalic = result.italic;
          ts.textAlign = result.align;
        });
      }
    });
  }
}
