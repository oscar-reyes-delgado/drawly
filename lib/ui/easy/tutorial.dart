import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../theme.dart';

/// What the tutorial can observe of the app (built by the shell on each change).
class TutorialSnapshot {
  const TutorialSnapshot({
    this.hasDocument = false,
    this.toolId = '',
    this.brushId = '',
    this.frameCount = 0,
    this.framesWithDrawing = 0,
    this.onion = false,
    this.playing = false,
    this.exported = false,
  });
  final bool hasDocument;
  final String toolId, brushId;

  /// Timeline length.
  final int frameCount;

  /// Frames whose active layer drawing is not empty.
  final int framesWithDrawing;
  final bool onion, playing, exported;
}

class TutorialStep {
  const TutorialStep({required this.id, required this.title, required this.text, this.target, required this.done});
  final String id;

  /// Already translated.
  final String title, text;

  /// `ValueKey<String>` of the widget to point at, e.g. 'easy.addFrame'.
  final String? target;
  final bool Function(TutorialSnapshot s) done;
}

/// The nine steps of the bouncing ball tutorial, in order.
List<TutorialStep> bouncingBallSteps() => [
      TutorialStep(
        id: 'new',
        title: tr('1. Crea un proyecto', '1. Create a project'),
        text: tr('Toca «+ Nuevo» para empezar una animación.', 'Tap «+ New» to start an animation.'),
        target: 'easy.home.new',
        done: (s) => s.hasDocument,
      ),
      TutorialStep(
        id: 'pencil',
        title: tr('2. Elige el lápiz', '2. Pick the pencil'),
        text: tr('Toca el lápiz para dibujar líneas limpias.', 'Tap the pencil to draw clean lines.'),
        target: 'easy.tool.pencil',
        done: (s) => s.toolId == 'brush' && s.brushId == 'fineliner',
      ),
      TutorialStep(
        id: 'draw1',
        title: tr('3. Dibuja una pelota', '3. Draw a ball'),
        text: tr('Dibuja una pelota en la parte de arriba del lienzo.', 'Draw a ball near the top of the canvas.'),
        done: (s) => s.framesWithDrawing >= 1,
      ),
      TutorialStep(
        id: 'addFrame',
        title: tr('4. Añade un fotograma', '4. Add a frame'),
        text: tr('Toca «+» para crear el siguiente dibujo de la animación.', 'Tap «+» to create the next drawing of the animation.'),
        target: 'easy.addFrame',
        done: (s) => s.frameCount >= 2,
      ),
      TutorialStep(
        id: 'onion',
        title: tr('5. Papel cebolla', '5. Onion skin'),
        text: tr('Activa el papel cebolla para ver el dibujo anterior.', 'Turn on onion skin to see the previous drawing.'),
        target: 'easy.onion',
        done: (s) => s.onion,
      ),
      TutorialStep(
        id: 'draw2',
        title: tr('6. Dibuja otra vez', '6. Draw again'),
        text: tr('Dibuja la pelota un poco más abajo.', 'Draw the ball a little lower.'),
        done: (s) => s.framesWithDrawing >= 2,
      ),
      TutorialStep(
        id: 'more',
        title: tr('7. Repite', '7. Repeat'),
        text: tr('Añade más fotogramas: la pelota toca el suelo y vuelve a subir.', 'Add more frames: the ball hits the ground and goes back up.'),
        target: 'easy.addFrame',
        done: (s) => s.frameCount >= 4 && s.framesWithDrawing >= 4,
      ),
      TutorialStep(
        id: 'play',
        title: tr('8. Reprodúcela', '8. Play it'),
        text: tr('Toca reproducir para ver tu animación.', 'Tap play to watch your animation.'),
        target: 'easy.play',
        done: (s) => s.playing,
      ),
      TutorialStep(
        id: 'export',
        title: tr('9. Expórtala', '9. Export it'),
        text: tr('Guárdala como vídeo o GIF para compartirla.', 'Save it as a video or GIF to share it.'),
        target: 'easy.export',
        done: (s) => s.exported,
      ),
    ];

class TutorialController extends ChangeNotifier {
  TutorialController(this.steps);
  final List<TutorialStep> steps;

  int _index = 0;
  bool _skipped = false;

  /// First step not done yet; steps.length when finished.
  int get index => _index;
  bool get finished => _skipped || _index >= steps.length;
  bool get skipped => _skipped;
  TutorialStep? get current => finished ? null : steps[_index];

  /// Advances over every step already done (never goes back).
  void update(TutorialSnapshot s) {
    if (finished) return;
    final start = _index;
    while (_index < steps.length && steps[_index].done(s)) {
      _index++;
    }
    if (_index != start) notifyListeners();
  }

  void skip() {
    _skipped = true;
    notifyListeners();
  }

  void restart() {
    _skipped = false;
    _index = 0;
    notifyListeners();
  }
}

/// Draws a dimmed layer with a hole around the target widget (found by its
/// `ValueKey<String>` in the tree) and a bubble with the step text, «Skip» and a
/// counter «3 / 9». Touches still reach the app underneath.
class TutorialOverlay extends StatefulWidget {
  const TutorialOverlay({super.key, required this.controller, required this.child});
  final TutorialController controller;
  final Widget child;

  @override
  State<TutorialOverlay> createState() => _TutorialOverlayState();
}

class _TutorialOverlayState extends State<TutorialOverlay> {
  final GlobalKey _childKey = GlobalKey();
  Rect? _hole;

  /// Highlighted area (for tests).
  @visibleForTesting
  Rect? get debugHole => _hole;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(TutorialOverlay old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  /// Finds the target after layout and keeps the hole in sync (the app moves).
  void _locate() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = widget.controller.current?.target;
      Rect? rect;
      final rootCtx = _childKey.currentContext;
      final root = rootCtx?.findRenderObject() as RenderBox?;
      if (target != null && rootCtx != null && root != null && root.hasSize) {
        Element? found;
        void visit(Element e) {
          if (found != null) return;
          final k = e.widget.key;
          if (k is ValueKey<String> && k.value == target) {
            final ro = e.renderObject;
            if (ro is RenderBox && ro.attached && ro.hasSize) {
              found = e;
              return;
            }
          }
          e.visitChildren(visit);
        }

        rootCtx.visitChildElements(visit);
        final box = found?.renderObject as RenderBox?;
        if (box != null) {
          final topLeft = box.localToGlobal(Offset.zero, ancestor: root);
          rect = (topLeft & box.size).inflate(6);
        }
      }
      if (rect != _hole) setState(() => _hole = rect);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final step = c.current;
    final child = KeyedSubtree(key: _childKey, child: widget.child);
    if (step == null) {
      _hole = null; // a later restart must not show the old hole
      return child;
    }
    // a menu, brush panel, sheet or dialog is open on top: step aside until it
    // closes (the dimming and the bubble would cover it or point behind it)
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return child;
    _locate();
    final i = c.index;
    return LayoutBuilder(builder: (context, box) {
      final size = box.biggest;
      final hole = _hole;
      // the bubble goes below the target when it is in the upper half, above otherwise
      double fit(double v, double lo, double hi) => v.clamp(lo, math.max(lo, hi));
      final bubbleW = math.max(0.0, math.min(300.0, size.width - 16));
      final placeBelow = hole == null || hole.center.dy < size.height / 2;
      final left = hole == null ? (size.width - bubbleW) / 2 : fit(hole.center.dx - bubbleW / 2, 8, size.width - bubbleW - 8);
      return Stack(children: [
        child,
        Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _DimPainter(hole, context.cs.primary)))),
        Positioned(
          left: fit(left, 0, size.width - bubbleW),
          width: bubbleW,
          top: placeBelow ? (hole == null ? null : fit(hole.bottom + 12, 8, size.height - 160)) : null,
          bottom: placeBelow ? (hole == null ? 24 : null) : fit(size.height - hole.top + 12, 8, size.height - 160),
          child: Material(
            key: const ValueKey('tutorial.bubble'),
            elevation: 8,
            borderRadius: BorderRadius.circular(14),
            color: context.panel,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(step.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text(step.text, style: const TextStyle(fontSize: 14)),
                Row(children: [
                  Text('${i + 1} / ${c.steps.length}', style: TextStyle(fontSize: 13, color: context.dim)),
                  const Spacer(),
                  TextButton(key: const ValueKey('tutorial.skip'), onPressed: c.skip, child: Text(tr('Omitir', 'Skip'))),
                ]),
              ]),
            ),
          ),
        ),
      ]);
    });
  }
}

class _DimPainter extends CustomPainter {
  _DimPainter(this.hole, this.accent);
  final Rect? hole;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final all = Path()..addRect(Offset.zero & size);
    final h = hole;
    if (h == null) {
      canvas.drawPath(all, Paint()..color = const Color(0x55000000));
      return;
    }
    final rr = RRect.fromRectAndRadius(h, const Radius.circular(12));
    canvas.drawPath(Path.combine(PathOperation.difference, all, Path()..addRRect(rr)), Paint()..color = const Color(0x88000000));
    canvas.drawRRect(rr, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = accent);
  }

  @override
  bool shouldRepaint(_DimPainter old) => old.hole != hole || old.accent != accent;
}
