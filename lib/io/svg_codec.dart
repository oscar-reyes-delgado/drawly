import 'dart:math' as math;
import 'dart:ui';

import '../core/color_utils.dart';
import '../core/mat2d.dart';
import '../model/gradient.dart';
import '../model/vector.dart';

String _num(double v) {
  if (!v.isFinite) return '0';
  final rounded = (v * 1000).round() / 1000;
  if (rounded == 0) return '0';
  if (rounded == rounded.roundToDouble()) return rounded.round().toString();
  var s = rounded.toStringAsFixed(3);
  while (s.endsWith('0')) {
    s = s.substring(0, s.length - 1);
  }
  if (s.endsWith('.')) {
    s = s.substring(0, s.length - 1);
  }
  return s;
}

String _esc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

/// Exports [art] as an SVG document string of the given [size].
String vectorArtToSvg(
  VectorArt art, {
  required Size size,
  Color? background,
  String? title,
}) {
  final w = _num(size.width);
  final h = _num(size.height);
  final sb = StringBuffer()
    ..writeln('<svg xmlns="http://www.w3.org/2000/svg" width="$w" height="$h" viewBox="0 0 $w $h">');

  if (title != null && title.isNotEmpty) {
    sb.writeln('  <title>${_esc(title)}</title>');
  }

  final gradIds = <int, String>{};
  final defs = <String>[];
  for (var i = 0; i < art.shapes.length; i++) {
    final fill = art.shapes[i].fill;
    if (fill.kind == FillKind.gradient && fill.gradient != null) {
      final gid = 'grad_${defs.length}';
      gradIds[i] = gid;
      defs.add(_gradientDefXml(gid, fill.gradient!));
    }
  }

  if (defs.isNotEmpty) {
    sb.writeln('  <defs>');
    for (final d in defs) {
      sb.write(d);
    }
    sb.writeln('  </defs>');
  }

  if (background != null && background.a > 0) {
    final op = background.a < 1.0 ? ' fill-opacity="${_num(background.a)}"' : '';
    sb.writeln('  <rect data-background="true" width="$w" height="$h" fill="#${background.hex}"$op/>');
  }

  for (var i = 0; i < art.shapes.length; i++) {
    final s = art.shapes[i];
    final d = vpathsToPathData(s.paths);
    if (d.isEmpty) continue;

    final attrs = <String>[
      'id="${_esc(s.id)}"',
      'd="$d"',
    ];

    final fill = s.fill;
    switch (fill.kind) {
      case FillKind.none:
        attrs.add('fill="none"');
      case FillKind.solid || FillKind.pattern:
        attrs.add('fill="#${fill.color.hex}"');
        if (fill.color.a < 1.0) {
          attrs.add('fill-opacity="${_num(fill.color.a)}"');
        }
      case FillKind.gradient:
        final gid = gradIds[i];
        attrs.add(gid != null ? 'fill="url(#$gid)"' : 'fill="#${fill.color.hex}"');
    }

    if (s.evenOdd) {
      attrs.add('fill-rule="evenodd"');
    }

    final st = s.stroke;
    if (st != null) {
      attrs.add('stroke="#${st.color.hex}"');
      if (st.color.a < 1.0) {
        attrs.add('stroke-opacity="${_num(st.color.a)}"');
      }
      attrs.add('stroke-width="${_num(st.width)}"');
      attrs.add('stroke-linecap="${switch (st.cap) {
        StrokeCap.butt => 'butt',
        StrokeCap.round => 'round',
        StrokeCap.square => 'square',
      }}"');
      attrs.add('stroke-linejoin="${switch (st.join) {
        StrokeJoin.miter => 'miter',
        StrokeJoin.round => 'round',
        StrokeJoin.bevel => 'bevel',
      }}"');
      if (st.miterLimit != 4) {
        attrs.add('stroke-miterlimit="${_num(st.miterLimit)}"');
      }
      if (st.dash.isNotEmpty) {
        attrs.add('stroke-dasharray="${st.dash.map(_num).join(' ')}"');
      }
    } else {
      attrs.add('stroke="none"');
    }

    if (s.opacity < 1.0) {
      attrs.add('opacity="${_num(s.opacity)}"');
    }

    sb.writeln('  <path ${attrs.join(' ')}/>');
  }

  sb.write('</svg>');
  return sb.toString();
}

String _gradientDefXml(String id, GradientSpec g) {
  final spread = switch (g.kind) {
    GradientKind.reflected => ' spreadMethod="reflect"',
    _ => g.repeat ? ' spreadMethod="repeat"' : '',
  };
  final stopsXml = StringBuffer();
  for (final s in g.sorted) {
    final op = s.color.a < 1.0 ? ' stop-opacity="${_num(s.color.a)}"' : '';
    stopsXml.writeln('      <stop offset="${_num(s.t.clamp(0.0, 1.0))}" stop-color="#${s.color.hex}"$op/>');
  }

  if (g.kind == GradientKind.radial) {
    final r = (g.to - g.from).distance;
    return '    <radialGradient id="$id" gradientUnits="userSpaceOnUse" '
        'cx="${_num(g.from.dx)}" cy="${_num(g.from.dy)}" r="${_num(r)}"$spread>\n'
        '$stopsXml'
        '    </radialGradient>\n';
  }
  return '    <linearGradient id="$id" gradientUnits="userSpaceOnUse" '
      'x1="${_num(g.from.dx)}" y1="${_num(g.from.dy)}" x2="${_num(g.to.dx)}" y2="${_num(g.to.dy)}"$spread>\n'
      '$stopsXml'
      '    </linearGradient>\n';
}

/// SVG path data <-> editable paths (absolute commands on output).
String vpathsToPathData(List<VPath> paths) {
  final parts = <String>[];
  for (final vp in paths) {
    if (vp.nodes.isEmpty) continue;
    final first = vp.nodes.first;
    parts.add('M ${_num(first.p.dx)} ${_num(first.p.dy)}');
    for (var i = 1; i < vp.nodes.length; i++) {
      _appendSegmentCmd(parts, vp.nodes[i - 1], vp.nodes[i]);
    }
    if (vp.closed && vp.nodes.length > 1) {
      final last = vp.nodes.last;
      if (last.hasOut || first.hasIn) {
        _appendSegmentCmd(parts, last, first);
      }
      parts.add('Z');
    } else if (vp.closed) {
      parts.add('Z');
    }
  }
  return parts.join(' ');
}

void _appendSegmentCmd(List<String> out, VNode a, VNode b) {
  if (!a.hasOut && !b.hasIn) {
    out.add('L ${_num(b.p.dx)} ${_num(b.p.dy)}');
  } else {
    out.add(
      'C ${_num(a.hOut.dx)} ${_num(a.hOut.dy)} '
      '${_num(b.hIn.dx)} ${_num(b.hIn.dy)} '
      '${_num(b.p.dx)} ${_num(b.p.dy)}',
    );
  }
}

/// Parses SVG path data (`d`) into a list of [VPath] subpaths.
List<VPath> pathDataToVPaths(String d) {
  final out = <VPath>[];
  final scanner = _PathScanner(d);

  var nodes = <VNode>[];
  var cur = Offset.zero;
  var start = Offset.zero;
  Offset? lastCubicCtrl;
  Offset? lastQuadCtrl;

  void flush(bool closed) {
    if (nodes.isEmpty) return;
    if (closed && nodes.length > 1 && (nodes.last.p - nodes.first.p).distance < 1e-5) {
      final last = nodes.removeLast();
      if (last.hasIn) {
        nodes[0] = nodes.first.copyWith(hIn: last.hIn);
      }
    }
    out.add(VPath(nodes, closed: closed));
    nodes = <VNode>[];
  }

  void ensureStarted() {
    if (nodes.isEmpty) {
      start = cur;
      nodes.add(VNode(cur));
    }
  }

  void lineTo(Offset p) {
    ensureStarted();
    nodes.add(VNode(p));
    cur = p;
    lastCubicCtrl = null;
    lastQuadCtrl = null;
  }

  void cubicTo(Offset c1, Offset c2, Offset p) {
    ensureStarted();
    nodes[nodes.length - 1] = nodes.last.copyWith(hOut: c1);
    nodes.add(VNode(p, hIn: c2));
    cur = p;
  }

  void quadTo(Offset q, Offset p) {
    final c1 = cur + (q - cur) * (2.0 / 3.0);
    final c2 = p + (q - p) * (2.0 / 3.0);
    cubicTo(c1, c2, p);
    lastQuadCtrl = q;
    lastCubicCtrl = null;
  }

  void arcTo(double rxIn, double ryIn, double rotDeg, bool largeArc, bool sweep, Offset p2) {
    final p1 = cur;
    if ((p1 - p2).distance < 1e-9) return;
    var rx = rxIn.abs();
    var ry = ryIn.abs();
    if (rx < 1e-9 || ry < 1e-9) {
      lineTo(p2);
      return;
    }

    final phi = degToRad(rotDeg % 360.0);
    final cosPhi = math.cos(phi);
    final sinPhi = math.sin(phi);

    final dx2 = (p1.dx - p2.dx) / 2.0;
    final dy2 = (p1.dy - p2.dy) / 2.0;
    final x1p = cosPhi * dx2 + sinPhi * dy2;
    final y1p = -sinPhi * dx2 + cosPhi * dy2;

    var rxSq = rx * rx;
    var rySq = ry * ry;
    final x1pSq = x1p * x1p;
    final y1pSq = y1p * y1p;

    final radiiCheck = x1pSq / rxSq + y1pSq / rySq;
    if (radiiCheck > 1.0) {
      final s = math.sqrt(radiiCheck);
      rx *= s;
      ry *= s;
      rxSq = rx * rx;
      rySq = ry * ry;
    }

    final sign = (largeArc == sweep) ? -1.0 : 1.0;
    final num = math.max(0.0, rxSq * rySq - rxSq * y1pSq - rySq * x1pSq);
    final den = rxSq * y1pSq + rySq * x1pSq;
    final coef = sign * (den == 0.0 ? 0.0 : math.sqrt(num / den));
    final cxp = coef * (rx * y1p / ry);
    final cyp = coef * -(ry * x1p / rx);

    final cx = cosPhi * cxp - sinPhi * cyp + (p1.dx + p2.dx) / 2.0;
    final cy = sinPhi * cxp + cosPhi * cyp + (p1.dy + p2.dy) / 2.0;

    double vecAngle(double ux, double uy, double vx, double vy) {
      final dot = ux * vx + uy * vy;
      final len = math.sqrt(ux * ux + uy * uy) * math.sqrt(vx * vx + vy * vy);
      final cosA = (len == 0.0 ? 1.0 : dot / len).clamp(-1.0, 1.0);
      final ang = math.acos(cosA);
      return (ux * vy - uy * vx) < 0 ? -ang : ang;
    }

    final ux = (x1p - cxp) / rx;
    final uy = (y1p - cyp) / ry;
    final vx = (-x1p - cxp) / rx;
    final vy = (-y1p - cyp) / ry;

    final theta1 = vecAngle(1.0, 0.0, ux, uy);
    var dtheta = vecAngle(ux, uy, vx, vy);
    if (!sweep && dtheta > 0) dtheta -= 2 * math.pi;
    if (sweep && dtheta < 0) dtheta += 2 * math.pi;

    final segs = math.max(1, (dtheta.abs() / (math.pi / 2)).ceil());
    final delta = dtheta / segs;
    final alpha = (4.0 / 3.0) * math.tan(delta / 4.0);

    Offset mapUnit(double u, double v) => Offset(
          cx + cosPhi * rx * u - sinPhi * ry * v,
          cy + sinPhi * rx * u + cosPhi * ry * v,
        );

    for (var i = 0; i < segs; i++) {
      final a0 = theta1 + i * delta;
      final a1 = a0 + delta;
      final cos0 = math.cos(a0), sin0 = math.sin(a0);
      final cos1 = math.cos(a1), sin1 = math.sin(a1);
      final c1 = mapUnit(cos0 - alpha * sin0, sin0 + alpha * cos0);
      final c2 = mapUnit(cos1 + alpha * sin1, sin1 - alpha * cos1);
      final end = (i == segs - 1) ? p2 : mapUnit(cos1, sin1);
      cubicTo(c1, c2, end);
    }
    lastCubicCtrl = null;
    lastQuadCtrl = null;
  }

  var cmd = '';
  while (!scanner.isDone) {
    final nextCmd = scanner.readCommand();
    if (nextCmd != null) {
      cmd = nextCmd;
    } else if (cmd.isEmpty) {
      break;
    }

    final rel = cmd == cmd.toLowerCase();
    switch (cmd.toUpperCase()) {
      case 'M':
        flush(false);
        final x = scanner.readNumber();
        final y = scanner.readNumber();
        if (x == null || y == null) break;
        final pt = rel ? cur + Offset(x, y) : Offset(x, y);
        cur = pt;
        start = pt;
        nodes = <VNode>[VNode(pt)];
        lastCubicCtrl = null;
        lastQuadCtrl = null;
        cmd = rel ? 'l' : 'L';
      case 'Z':
        flush(true);
        cur = start;
        lastCubicCtrl = null;
        lastQuadCtrl = null;
        cmd = '';
      case 'L':
        final x = scanner.readNumber();
        final y = scanner.readNumber();
        if (x == null || y == null) {
          cmd = '';
          break;
        }
        lineTo(rel ? cur + Offset(x, y) : Offset(x, y));
      case 'H':
        final x = scanner.readNumber();
        if (x == null) {
          cmd = '';
          break;
        }
        lineTo(Offset(rel ? cur.dx + x : x, cur.dy));
      case 'V':
        final y = scanner.readNumber();
        if (y == null) {
          cmd = '';
          break;
        }
        lineTo(Offset(cur.dx, rel ? cur.dy + y : y));
      case 'C':
        final x1 = scanner.readNumber(), y1 = scanner.readNumber();
        final x2 = scanner.readNumber(), y2 = scanner.readNumber();
        final x = scanner.readNumber(), y = scanner.readNumber();
        if (x1 == null || y1 == null || x2 == null || y2 == null || x == null || y == null) {
          cmd = '';
          break;
        }
        final base = rel ? cur : Offset.zero;
        final c1 = base + Offset(x1, y1);
        final c2 = base + Offset(x2, y2);
        final p = base + Offset(x, y);
        cubicTo(c1, c2, p);
        lastCubicCtrl = c2;
        lastQuadCtrl = null;
      case 'S':
        final x2 = scanner.readNumber(), y2 = scanner.readNumber();
        final x = scanner.readNumber(), y = scanner.readNumber();
        if (x2 == null || y2 == null || x == null || y == null) {
          cmd = '';
          break;
        }
        final base = rel ? cur : Offset.zero;
        final c1 = lastCubicCtrl != null ? (cur * 2.0 - lastCubicCtrl!) : cur;
        final c2 = base + Offset(x2, y2);
        final p = base + Offset(x, y);
        cubicTo(c1, c2, p);
        lastCubicCtrl = c2;
        lastQuadCtrl = null;
      case 'Q':
        final x1 = scanner.readNumber(), y1 = scanner.readNumber();
        final x = scanner.readNumber(), y = scanner.readNumber();
        if (x1 == null || y1 == null || x == null || y == null) {
          cmd = '';
          break;
        }
        final base = rel ? cur : Offset.zero;
        quadTo(base + Offset(x1, y1), base + Offset(x, y));
      case 'T':
        final x = scanner.readNumber(), y = scanner.readNumber();
        if (x == null || y == null) {
          cmd = '';
          break;
        }
        final base = rel ? cur : Offset.zero;
        final q = lastQuadCtrl != null ? (cur * 2.0 - lastQuadCtrl!) : cur;
        quadTo(q, base + Offset(x, y));
      case 'A':
        final rx = scanner.readNumber();
        final ry = scanner.readNumber();
        final rot = scanner.readNumber();
        final laf = scanner.readFlag();
        final sf = scanner.readFlag();
        final x = scanner.readNumber();
        final y = scanner.readNumber();
        if (rx == null || ry == null || rot == null || laf == null || sf == null || x == null || y == null) {
          cmd = '';
          break;
        }
        final p = rel ? cur + Offset(x, y) : Offset(x, y);
        arcTo(rx, ry, rot, laf == 1, sf == 1, p);
      default:
        cmd = '';
    }
  }

  flush(false);
  return out;
}

class _PathScanner {
  _PathScanner(this.src);
  final String src;
  int pos = 0;

  void _skipSeparators() {
    while (pos < src.length) {
      final c = src.codeUnitAt(pos);
      if (c <= 0x20 || c == 0x2C /* , */) {
        pos++;
      } else {
        break;
      }
    }
  }

  bool get isDone {
    _skipSeparators();
    return pos >= src.length;
  }

  String? readCommand() {
    _skipSeparators();
    if (pos >= src.length) return null;
    final ch = src[pos];
    if ('MmLlHhVvCcSsQqTtAaZz'.contains(ch)) {
      pos++;
      return ch;
    }
    return null;
  }

  int? readFlag() {
    _skipSeparators();
    if (pos >= src.length) return null;
    final c = src.codeUnitAt(pos);
    if (c == 0x30 /* 0 */ || c == 0x31 /* 1 */) {
      pos++;
      return c - 0x30;
    }
    return null;
  }

  double? readNumber() {
    _skipSeparators();
    if (pos >= src.length) return null;
    final start = pos;
    var c = src.codeUnitAt(pos);
    if (c == 0x2B /* + */ || c == 0x2D /* - */) {
      pos++;
    }
    var hasDigits = false;
    while (pos < src.length) {
      c = src.codeUnitAt(pos);
      if (c >= 0x30 && c <= 0x39) {
        hasDigits = true;
        pos++;
      } else {
        break;
      }
    }
    if (pos < src.length && src.codeUnitAt(pos) == 0x2E /* . */) {
      pos++;
      while (pos < src.length) {
        c = src.codeUnitAt(pos);
        if (c >= 0x30 && c <= 0x39) {
          hasDigits = true;
          pos++;
        } else {
          break;
        }
      }
    }
    if (!hasDigits) {
      pos = start;
      return null;
    }
    if (pos < src.length) {
      c = src.codeUnitAt(pos);
      if (c == 0x65 /* e */ || c == 0x45 /* E */) {
        final expStart = pos;
        pos++;
        if (pos < src.length) {
          c = src.codeUnitAt(pos);
          if (c == 0x2B || c == 0x2D) pos++;
        }
        var expDigits = false;
        while (pos < src.length) {
          c = src.codeUnitAt(pos);
          if (c >= 0x30 && c <= 0x39) {
            expDigits = true;
            pos++;
          } else {
            break;
          }
        }
        if (!expDigits) pos = expStart;
      }
    }
    return double.tryParse(src.substring(start, pos));
  }
}

// ---------------------------------------------------------------------------
// SVG XML Scanner & Importer
// ---------------------------------------------------------------------------

class _XmlToken {
  const _XmlToken(this.tag, this.attrs, {required this.isClose, required this.isSelfClosing});
  final String tag;
  final Map<String, String> attrs;
  final bool isClose;
  final bool isSelfClosing;
}

Iterable<_XmlToken> _scanXmlTags(String xml) sync* {
  var i = 0;
  final n = xml.length;
  while (i < n) {
    final lt = xml.indexOf('<', i);
    if (lt < 0 || lt + 1 >= n) break;

    if (xml.startsWith('<!--', lt)) {
      final end = xml.indexOf('-->', lt + 4);
      i = end < 0 ? n : end + 3;
      continue;
    }
    if (xml.startsWith('<![CDATA[', lt)) {
      final end = xml.indexOf(']]>', lt + 9);
      i = end < 0 ? n : end + 3;
      continue;
    }
    final nextCh = xml[lt + 1];
    if (nextCh == '?' || nextCh == '!') {
      final end = xml.indexOf('>', lt + 2);
      i = end < 0 ? n : end + 1;
      continue;
    }

    var p = lt + 1;
    var isClose = false;
    if (p < n && xml[p] == '/') {
      isClose = true;
      p++;
    }

    while (p < n && xml.codeUnitAt(p) <= 0x20) {
      p++;
    }
    final nameStart = p;
    while (p < n) {
      final c = xml[p];
      if (c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '/' || c == '>') break;
      p++;
    }
    var tag = xml.substring(nameStart, p);
    final colonIdx = tag.indexOf(':');
    if (colonIdx >= 0) tag = tag.substring(colonIdx + 1);
    tag = tag.toLowerCase();

    if (isClose) {
      final gt = xml.indexOf('>', p);
      i = gt < 0 ? n : gt + 1;
      if (tag.isNotEmpty) {
        yield _XmlToken(tag, const {}, isClose: true, isSelfClosing: false);
      }
      continue;
    }

    final attrs = <String, String>{};
    var isSelfClosing = false;
    while (p < n) {
      while (p < n && xml.codeUnitAt(p) <= 0x20) {
        p++;
      }
      if (p >= n) break;
      if (xml[p] == '/') {
        isSelfClosing = true;
        p++;
        while (p < n && xml[p] != '>') {
          p++;
        }
        if (p < n && xml[p] == '>') p++;
        break;
      }
      if (xml[p] == '>') {
        p++;
        break;
      }

      final aStart = p;
      while (p < n) {
        final c = xml[p];
        if (c == '=' || c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '/' || c == '>') break;
        p++;
      }
      final attrName = xml.substring(aStart, p).toLowerCase();
      while (p < n && xml.codeUnitAt(p) <= 0x20) {
        p++;
      }
      var attrVal = '';
      if (p < n && xml[p] == '=') {
        p++;
        while (p < n && xml.codeUnitAt(p) <= 0x20) {
          p++;
        }
        if (p < n && (xml[p] == '"' || xml[p] == "'")) {
          final quote = xml[p];
          p++;
          final vStart = p;
          final vEnd = xml.indexOf(quote, p);
          if (vEnd < 0) {
            attrVal = xml.substring(vStart);
            p = n;
          } else {
            attrVal = xml.substring(vStart, vEnd);
            p = vEnd + 1;
          }
        } else {
          final vStart = p;
          while (p < n && xml.codeUnitAt(p) > 0x20 && xml[p] != '/' && xml[p] != '>') {
            p++;
          }
          attrVal = xml.substring(vStart, p);
        }
      }
      if (attrName.isNotEmpty) {
        attrs[attrName] = _unescape(attrVal.trim());
      }
    }
    i = p;
    if (tag.isNotEmpty) {
      yield _XmlToken(tag, attrs, isClose: false, isSelfClosing: isSelfClosing);
    }
  }
}

String _unescape(String s) => s
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&amp;', '&');

double? _parseLength(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final s = raw.trim().toLowerCase();
  if (s.endsWith('%')) return null;
  final cleaned = s.replaceAll(RegExp(r'[a-z]+$'), '').trim();
  return double.tryParse(cleaned);
}

List<double> _parseNumberList(String? raw) {
  if (raw == null || raw.isEmpty) return const <double>[];
  final out = <double>[];
  final scanner = _PathScanner(raw);
  while (!scanner.isDone) {
    final v = scanner.readNumber();
    if (v == null) break;
    out.add(v);
  }
  return out;
}

/// Size from width/height, else from viewBox; null when neither is present.
Size? svgSize(String svg) {
  for (final tok in _scanXmlTags(svg)) {
    if (!tok.isClose && tok.tag == 'svg') {
      final w = _parseLength(tok.attrs['width']);
      final h = _parseLength(tok.attrs['height']);
      if (w != null && h != null && w > 0 && h > 0) {
        return Size(w, h);
      }
      final vb = _parseNumberList(tok.attrs['viewbox']);
      if (vb.length >= 4 && vb[2] > 0 && vb[3] > 0) {
        return Size(vb[2], vb[3]);
      }
      return null;
    }
  }
  return null;
}

const Map<String, int> _namedColors = {
  'black': 0xFF000000,
  'white': 0xFFFFFFFF,
  'red': 0xFFFF0000,
  'green': 0xFF008000,
  'blue': 0xFF0000FF,
  'yellow': 0xFFFFFF00,
  'cyan': 0xFF00FFFF,
  'aqua': 0xFF00FFFF,
  'magenta': 0xFFFF00FF,
  'fuchsia': 0xFFFF00FF,
  'gray': 0xFF808080,
  'grey': 0xFF808080,
  'orange': 0xFFFFA500,
  'purple': 0xFF800080,
  'brown': 0xFFA52A2A,
  'pink': 0xFFFFC0CB,
};

(bool isNone, Color? color) _parseSvgPaint(String? raw) {
  if (raw == null) return (false, null);
  final s = raw.trim().toLowerCase();
  if (s.isEmpty) return (false, null);
  if (s == 'none' || s == 'transparent') return (true, null);
  if (s.startsWith('url(')) return (false, const Color(0xFF808080));
  if (s.startsWith('#')) {
    final c = parseHex(s);
    return (false, c);
  }
  if (s.startsWith('rgb(') && s.endsWith(')')) {
    final inner = s.substring(4, s.length - 1);
    final parts = inner.split(RegExp(r'[\s,]+')).where((p) => p.isNotEmpty).toList();
    if (parts.length >= 3) {
      int ch(String part) {
        if (part.endsWith('%')) {
          final pct = double.tryParse(part.substring(0, part.length - 1)) ?? 0;
          return (pct * 2.55).round().clamp(0, 255);
        }
        return (double.tryParse(part) ?? 0).round().clamp(0, 255);
      }

      return (false, Color.fromARGB(255, ch(parts[0]), ch(parts[1]), ch(parts[2])));
    }
  }
  final named = _namedColors[s];
  if (named != null) return (false, Color(named));
  return (false, null);
}

Mat2D _parseTransform(String? raw) {
  if (raw == null || raw.trim().isEmpty) return Mat2D.identity;
  var m = Mat2D.identity;
  final re = RegExp(r'([a-zA-Z]+)\s*\(([^)]*)\)');
  for (final match in re.allMatches(raw)) {
    final fn = match.group(1)!.toLowerCase();
    final args = _parseNumberList(match.group(2));
    if (args.isEmpty) continue;
    Mat2D step = Mat2D.identity;
    switch (fn) {
      case 'matrix':
        if (args.length >= 6) {
          step = Mat2D(args[0], args[1], args[2], args[3], args[4], args[5]);
        }
      case 'translate':
        final tx = args[0];
        final ty = args.length > 1 ? args[1] : 0.0;
        step = Mat2D.translation(tx, ty);
      case 'scale':
        final sx = args[0];
        final sy = args.length > 1 ? args[1] : sx;
        step = Mat2D.scale(sx, sy);
      case 'rotate':
        final rad = degToRad(args[0]);
        if (args.length >= 3) {
          final cx = args[1], cy = args[2];
          step = Mat2D.translation(cx, cy) * Mat2D.rotation(rad) * Mat2D.translation(-cx, -cy);
        } else {
          step = Mat2D.rotation(rad);
        }
      case 'skewx':
        step = Mat2D.skew(degToRad(args[0]), 0);
      case 'skewy':
        step = Mat2D.skew(0, degToRad(args[0]));
    }
    m = m * step;
  }
  return m;
}

class _SvgStyleState {
  const _SvgStyleState({
    this.fillNone = false,
    this.fillColor = const Color(0xFF000000),
    this.fillOpacity = 1.0,
    this.evenOdd = false,
    this.strokeColor,
    this.strokeOpacity = 1.0,
    this.strokeWidth = 1.0,
    this.strokeCap = StrokeCap.round,
    this.strokeJoin = StrokeJoin.round,
    this.miterLimit = 4.0,
    this.dash = const <double>[],
    this.opacity = 1.0,
    this.transform = Mat2D.identity,
  });

  final bool fillNone;
  final Color fillColor;
  final double fillOpacity;
  final bool evenOdd;
  final Color? strokeColor;
  final double strokeOpacity;
  final double strokeWidth;
  final StrokeCap strokeCap;
  final StrokeJoin strokeJoin;
  final double miterLimit;
  final List<double> dash;
  final double opacity;
  final Mat2D transform;

  _SvgStyleState applyAttrs(Map<String, String> attrs, {Mat2D? extraTransform}) {
    final merged = <String, String>{...attrs};
    final styleRaw = attrs['style'];
    if (styleRaw != null && styleRaw.isNotEmpty) {
      for (final decl in styleRaw.split(';')) {
        final colon = decl.indexOf(':');
        if (colon > 0) {
          final k = decl.substring(0, colon).trim().toLowerCase();
          final v = decl.substring(colon + 1).trim();
          if (k.isNotEmpty && v.isNotEmpty) {
            merged[k] = v;
          }
        }
      }
    }

    var nextFillNone = fillNone;
    var nextFillColor = fillColor;
    if (merged.containsKey('fill')) {
      final (isNone, col) = _parseSvgPaint(merged['fill']);
      if (isNone) {
        nextFillNone = true;
      } else if (col != null) {
        nextFillNone = false;
        nextFillColor = col;
      }
    }

    var nextFillOp = fillOpacity;
    if (merged.containsKey('fill-opacity')) {
      final v = double.tryParse(merged['fill-opacity']!);
      if (v != null) nextFillOp = v.clamp(0.0, 1.0);
    }

    var nextEvenOdd = evenOdd;
    if (merged.containsKey('fill-rule')) {
      nextEvenOdd = merged['fill-rule']!.trim().toLowerCase() == 'evenodd';
    }

    var nextStrokeColor = strokeColor;
    if (merged.containsKey('stroke')) {
      final (isNone, col) = _parseSvgPaint(merged['stroke']);
      if (isNone) {
        nextStrokeColor = null;
      } else if (col != null) {
        nextStrokeColor = col;
      }
    }

    var nextStrokeOp = strokeOpacity;
    if (merged.containsKey('stroke-opacity')) {
      final v = double.tryParse(merged['stroke-opacity']!);
      if (v != null) nextStrokeOp = v.clamp(0.0, 1.0);
    }

    var nextStrokeWidth = strokeWidth;
    if (merged.containsKey('stroke-width')) {
      final v = _parseLength(merged['stroke-width']);
      if (v != null) nextStrokeWidth = math.max(0.0, v);
    }

    var nextCap = strokeCap;
    if (merged.containsKey('stroke-linecap')) {
      nextCap = switch (merged['stroke-linecap']!.trim().toLowerCase()) {
        'butt' => StrokeCap.butt,
        'square' => StrokeCap.square,
        _ => StrokeCap.round,
      };
    }

    var nextJoin = strokeJoin;
    if (merged.containsKey('stroke-linejoin')) {
      nextJoin = switch (merged['stroke-linejoin']!.trim().toLowerCase()) {
        'miter' => StrokeJoin.miter,
        'bevel' => StrokeJoin.bevel,
        _ => StrokeJoin.round,
      };
    }

    var nextMiter = miterLimit;
    if (merged.containsKey('stroke-miterlimit')) {
      final v = double.tryParse(merged['stroke-miterlimit']!);
      if (v != null && v > 0) nextMiter = v;
    }

    var nextDash = dash;
    if (merged.containsKey('stroke-dasharray')) {
      final rawDash = merged['stroke-dasharray']!.trim().toLowerCase();
      nextDash = rawDash == 'none' ? const <double>[] : _parseNumberList(rawDash);
    }

    var nextOpacity = opacity;
    if (merged.containsKey('opacity')) {
      final v = double.tryParse(merged['opacity']!);
      if (v != null) nextOpacity = (opacity * v.clamp(0.0, 1.0)).clamp(0.0, 1.0);
    }

    var nextXf = transform;
    if (extraTransform != null && !extraTransform.isIdentity) {
      nextXf = nextXf * extraTransform;
    }
    if (merged.containsKey('transform')) {
      nextXf = nextXf * _parseTransform(merged['transform']);
    }

    return _SvgStyleState(
      fillNone: nextFillNone,
      fillColor: nextFillColor,
      fillOpacity: nextFillOp,
      evenOdd: nextEvenOdd,
      strokeColor: nextStrokeColor,
      strokeOpacity: nextStrokeOp,
      strokeWidth: nextStrokeWidth,
      strokeCap: nextCap,
      strokeJoin: nextJoin,
      miterLimit: nextMiter,
      dash: nextDash,
      opacity: nextOpacity,
      transform: nextXf,
    );
  }
}

const Set<String> _ignoredContainers = {
  'defs',
  'text',
  'image',
  'use',
  'clippath',
  'mask',
  'filter',
  'lineargradient',
  'radialgradient',
  'pattern',
  'style',
  'script',
  'title',
  'desc',
  'metadata',
};

/// Imports a subset of SVG into a [VectorArt].
VectorArt svgToVectorArt(String svg) {
  final shapes = <VShape>[];
  final stack = <_SvgStyleState>[const _SvgStyleState()];
  final tagStack = <String>[];
  var ignoreDepth = 0;

  for (final tok in _scanXmlTags(svg)) {
    if (tok.isClose) {
      if (ignoreDepth > 0) {
        if (_ignoredContainers.contains(tok.tag)) {
          ignoreDepth--;
        }
        continue;
      }
      if (tagStack.isNotEmpty) {
        tagStack.removeLast();
        if (stack.length > 1) stack.removeLast();
      }
      continue;
    }

    if (ignoreDepth > 0) {
      if (!tok.isSelfClosing && _ignoredContainers.contains(tok.tag)) {
        ignoreDepth++;
      }
      continue;
    }

    if (_ignoredContainers.contains(tok.tag)) {
      if (!tok.isSelfClosing) {
        ignoreDepth++;
      }
      continue;
    }

    Mat2D? viewBoxXf;
    if (tok.tag == 'svg') {
      final w = _parseLength(tok.attrs['width']);
      final h = _parseLength(tok.attrs['height']);
      final vb = _parseNumberList(tok.attrs['viewbox']);
      if (vb.length >= 4 && vb[2] > 0 && vb[3] > 0) {
        final sx = (w != null && w > 0) ? w / vb[2] : 1.0;
        final sy = (h != null && h > 0) ? h / vb[3] : 1.0;
        viewBoxXf = Mat2D.scale(sx, sy) * Mat2D.translation(-vb[0], -vb[1]);
      }
    }

    final current = stack.last.applyAttrs(tok.attrs, extraTransform: viewBoxXf);

    if (tok.attrs['data-background'] == 'true') {
      if (!tok.isSelfClosing) {
        tagStack.add(tok.tag);
        stack.add(current);
      }
      continue;
    }

    final rawPaths = _shapeElementToVPaths(tok.tag, tok.attrs);
    if (rawPaths != null && rawPaths.isNotEmpty) {
      final xf = current.transform;
      final transformedPaths = xf.isIdentity ? rawPaths : [for (final p in rawPaths) p.transformed(xf)];
      final fill = current.fillNone
          ? const VFill.none()
          : VFill.solid(
              current.fillColor.withValues(
                alpha: (current.fillColor.a * current.fillOpacity).clamp(0.0, 1.0),
              ),
            );
      VStroke? stroke;
      if (current.strokeColor != null && current.strokeWidth > 0) {
        final scale = xf.scaleFactor;
        stroke = VStroke(
          color: current.strokeColor!.withValues(
            alpha: (current.strokeColor!.a * current.strokeOpacity).clamp(0.0, 1.0),
          ),
          width: current.strokeWidth * scale,
          cap: current.strokeCap,
          join: current.strokeJoin,
          miterLimit: current.miterLimit,
          dash: current.dash,
        );
      }

      shapes.add(
        VShape(
          id: tok.attrs['id'],
          name: tok.attrs['id'] ?? '',
          paths: transformedPaths,
          fill: fill,
          stroke: stroke,
          opacity: current.opacity,
          evenOdd: current.evenOdd,
        ),
      );
    }

    if (!tok.isSelfClosing) {
      tagStack.add(tok.tag);
      stack.add(current);
    }
  }

  return VectorArt(shapes);
}

List<VPath>? _shapeElementToVPaths(String tag, Map<String, String> attrs) {
  switch (tag) {
    case 'path':
      final d = attrs['d'];
      if (d == null || d.isEmpty) return null;
      return pathDataToVPaths(d);

    case 'rect':
      final x = _parseLength(attrs['x']) ?? 0.0;
      final y = _parseLength(attrs['y']) ?? 0.0;
      final w = _parseLength(attrs['width']) ?? 0.0;
      final h = _parseLength(attrs['height']) ?? 0.0;
      if (w <= 0 || h <= 0) return null;
      final rxAttr = _parseLength(attrs['rx']);
      final ryAttr = _parseLength(attrs['ry']);
      final rx = rxAttr ?? ryAttr ?? 0.0;
      final ry = ryAttr ?? rxAttr ?? 0.0;
      final r = Rect.fromLTWH(x, y, w, h);
      if (rx <= 0 || ry <= 0) {
        return [VPath.rect(r)];
      }
      if ((rx - ry).abs() < 1e-6) {
        return [VPath.rect(r, radius: rx)];
      }
      final crx = math.min(rx, w / 2);
      final cry = math.min(ry, h / 2);
      const k = 0.5522847498;
      final cx = crx * k, cy = cry * k;
      final l = r.left, t = r.top, rt = r.right, b = r.bottom;
      return [
        VPath([
          VNode(Offset(l + crx, t), hIn: Offset(l + crx - cx, t)),
          VNode(Offset(rt - crx, t), hOut: Offset(rt - crx + cx, t)),
          VNode(Offset(rt, t + cry), hIn: Offset(rt, t + cry - cy)),
          VNode(Offset(rt, b - cry), hOut: Offset(rt, b - cry + cy)),
          VNode(Offset(rt - crx, b), hIn: Offset(rt - crx + cx, b)),
          VNode(Offset(l + crx, b), hOut: Offset(l + crx - cx, b)),
          VNode(Offset(l, b - cry), hIn: Offset(l, b - cry + cy)),
          VNode(Offset(l, t + cry), hOut: Offset(l, t + cry - cy)),
        ], closed: true),
      ];

    case 'circle':
      final cx = _parseLength(attrs['cx']) ?? 0.0;
      final cy = _parseLength(attrs['cy']) ?? 0.0;
      final r = _parseLength(attrs['r']) ?? 0.0;
      if (r <= 0) return null;
      return [VPath.ellipse(Rect.fromCircle(center: Offset(cx, cy), radius: r))];

    case 'ellipse':
      final cx = _parseLength(attrs['cx']) ?? 0.0;
      final cy = _parseLength(attrs['cy']) ?? 0.0;
      final rx = _parseLength(attrs['rx']) ?? 0.0;
      final ry = _parseLength(attrs['ry']) ?? 0.0;
      if (rx <= 0 || ry <= 0) return null;
      return [VPath.ellipse(Rect.fromCenter(center: Offset(cx, cy), width: rx * 2, height: ry * 2))];

    case 'line':
      final x1 = _parseLength(attrs['x1']) ?? 0.0;
      final y1 = _parseLength(attrs['y1']) ?? 0.0;
      final x2 = _parseLength(attrs['x2']) ?? 0.0;
      final y2 = _parseLength(attrs['y2']) ?? 0.0;
      return [VPath.line(Offset(x1, y1), Offset(x2, y2))];

    case 'polyline':
    case 'polygon':
      final nums = _parseNumberList(attrs['points']);
      if (nums.length < 4) return null;
      final pts = <Offset>[
        for (var i = 0; i + 1 < nums.length; i += 2) Offset(nums[i], nums[i + 1]),
      ];
      return [VPath.polyline(pts, closed: tag == 'polygon')];

    default:
      return null;
  }
}
