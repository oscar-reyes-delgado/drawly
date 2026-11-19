import '../app/app_state.dart';
import 'bone_tool.dart';
import 'brush_tool.dart';
import 'fill_tools.dart';
import 'ik_tool.dart';
import 'liquify_tool.dart';
import 'move_tool.dart';
import 'select_tools.dart';
import 'shape_tool.dart';
import 'text_tool.dart';
import 'track_tool.dart';
import 'transform_tool.dart';
import 'tool.dart';
import 'view_tools.dart';

/// Order of the tools in the toolbar.
const List<String> kToolbarOrder = [
  'move', 'transform',
  'marquee',
  'lasso', 'polylasso',
  'wand', 'eyedropper',
  'brush', 'eraser',
  'smudge', 'bucket',
  'gradient', 'shape',
  'text', 'hand',
  'zoom', 'rotateView',
  'liquify', 'ik', 'bones', 'track',
];

/// Tools where holding Alt temporarily switches to the eyedropper.
const Set<String> kAltPicksColor = {'brush', 'bucket', 'gradient', 'shape', 'text'};

void registerTools(AppState app) {
  final tools = <Tool>[
    MoveTool(),
    TransformTool(),
    MarqueeTool(),
    LassoTool(),
    PolyLassoTool(),
    WandTool(),
    EyedropperTool(),
    BrushTool('brush'),
    BrushTool('eraser'),
    BrushTool('smudge'),
    BucketTool(),
    GradientTool(),
    ShapeTool(),
    TextTool(),
    HandTool(),
    ZoomTool(),
    RotateViewTool(),
    LiquifyTool(),
    IkTool(),
    BoneTool(),
    TrackTool(),
  ];
  for (final t in tools) {
    app.toolMap[t.id] = t;
  }
}
