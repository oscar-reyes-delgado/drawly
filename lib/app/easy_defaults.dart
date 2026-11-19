import 'package:flutter/painting.dart';

import '../core/i18n.dart';
import '../model/document.dart';
import '../model/layer.dart';
import 'settings.dart';

/// A ready-to-draw project for beginners: one frame, a static «Background»
/// layer at the bottom and a «Drawing» layer on top (the active one once opened).
Project easyProject({String name = '', int width = 1920, int height = 1080, int fps = 12, Color? background = const Color(0xFFFFFFFF)}) {
  final p = Project.blank(width: width, height: height, background: background, name: name, fps: fps, frames: 1);
  final comp = p.main;
  final bottom = comp.layers.first;
  final fondo = bottom.withProps(bottom.props.copyWith(name: tr('Fondo', 'Background')));
  final dibujo = PaintLayer.create(tr('Dibujo', 'Drawing'));
  final top = dibujo.withProps(dibujo.props.copyWith(xf: fondo.props.xf));
  return p.withComp(comp.copyWith(layers: [fondo, top]));
}

/// [easyProject] with the user's easy-mode defaults.
Project easyProjectFromSettings(Settings s, {String name = '', bool transparent = false}) =>
    easyProject(name: name, width: s.easyWidth, height: s.easyHeight, fps: s.easyFps, background: transparent ? null : const Color(0xFFFFFFFF));
