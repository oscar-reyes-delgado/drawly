import '../model/document.dart';

/// Formats a nonnegative frame number as non-drop HH:MM:SS:FF.
String frameToTimecode(int frame, int fps) {
  if (frame < 0 || fps <= 0) throw ArgumentError('Invalid frame or frame rate');
  String pad(int n) => n.toString().padLeft(2, '0');
  final seconds = frame ~/ fps;
  return '${pad(seconds ~/ 3600)}:${pad(seconds ~/ 60 % 60)}:${pad(seconds % 60)}:${pad(frame % fps)}';
}

/// Parses non-drop timecode, rejecting malformed fields and invalid frame rates.
int timecodeToFrame(String timecode, int fps) {
  final match = RegExp(r'^(\d{2,}):(\d{2}):(\d{2}):(\d{2,})$').firstMatch(timecode);
  if (fps <= 0 || match == null) throw const FormatException('Invalid timecode');
  final p = [for (var i = 1; i <= 4; i++) int.parse(match[i]!)];
  if (p[1] >= 60 || p[2] >= 60 || p[3] >= fps) throw const FormatException('Timecode field out of range');
  return ((p[0] * 60 + p[1]) * 60 + p[2]) * fps + p[3];
}
List<Scene> _scenes(Timeline timeline, String title) => timeline.scenes.isEmpty ? [Scene(id: 'whole', name: title, start: 0, length: timeline.length)] : timeline.scenes;
String _line(String s) => s.replaceAll(RegExp(r'[\r\n]'), ' ');
String _xml(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;').replaceAll("'", '&apos;');

/// CMX3600 events, one per scene with exclusive out points.
String timelineToEdl(Timeline timeline, {required String title, String reel = 'AX'}) {
  final out = StringBuffer('TITLE: ${_line(title)}\nFCM: NON-DROP FRAME\n\n'), scenes = _scenes(timeline, title);
  for (var i = 0; i < scenes.length; i++) {
    final scene = scenes[i], duration = scene.transitionFrames.toString().padLeft(3, '0');
    final transition = scene.transition == 'fade' || scene.transition == 'dissolve' ? 'D    $duration' : scene.transition.startsWith('wipe') || scene.transition == 'iris' ? 'W001 $duration' : 'C';
    final start = frameToTimecode(scene.start, timeline.fps), end = frameToTimecode(scene.end, timeline.fps);
    out.writeln('${(i + 1).toString().padLeft(3, '0')}  ${_line(reel)}  V  $transition  $start $end $start $end');
    out.writeln('* FROM CLIP NAME: ${_line(scene.name)}');
  }
  return out.toString();
}

/// Final Cut Pro 7 XML with one video track and an audio track per audio clip.
String timelineToFcpXml(Timeline timeline, {required String title, required int width, required int height, String mediaName = 'drawly.mov'}) {
  if (width <= 0 || height <= 0 || timeline.fps <= 0) throw ArgumentError('Invalid sequence dimensions');
  final rate = '<rate><timebase>${timeline.fps}</timebase><ntsc>FALSE</ntsc></rate>';
  final sample = '<samplecharacteristics>$rate<width>$width</width><height>$height</height><anamorphic>FALSE</anamorphic><pixelaspectratio>square</pixelaspectratio><fielddominance>none</fielddominance></samplecharacteristics>';
  final out = StringBuffer('<?xml version="1.0" encoding="UTF-8"?><xmeml version="5"><sequence><name>${_xml(title)}</name>$rate<duration>${timeline.length}</duration><media><video><format>$sample</format><track>');
  var i = 0;
  for (final scene in _scenes(timeline, title)) {
    out.write('<clipitem id="video-${i++}"><name>${_xml(scene.name)}</name>$rate<duration>${timeline.length}</duration><start>${scene.start}</start><end>${scene.end}</end><in>${scene.start}</in><out>${scene.end}</out>');
    out.write('<file id="video-file-$i"><name>${_xml(mediaName)}</name><pathurl>${_xml(mediaName)}</pathurl>$rate<duration>${timeline.length}</duration><media><video>$sample</video></media></file></clipitem>');
  }
  out.write('</track></video><audio>');
  i = 0;
  for (final audio in timeline.audio) {
    final start = audio.startFrame, length = (audio.playLength * timeline.fps).round(), trim = (audio.trimStart * timeline.fps).round();
    out.write('<track><clipitem id="audio-${i++}"><name>${_xml(audio.name)}</name>$rate<enabled>${audio.muted ? 'FALSE' : 'TRUE'}</enabled><duration>${(audio.duration * timeline.fps).round()}</duration><start>$start</start><end>${start + length}</end><in>$trim</in><out>${trim + length}</out>');
    out.write('<file id="audio-file-$i"><name>${_xml(audio.name)}</name><pathurl>${_xml(audio.assetId)}</pathurl>$rate<duration>${(audio.duration * timeline.fps).round()}</duration><media><audio><channelcount>2</channelcount></audio></media></file><sourcetrack><mediatype>audio</mediatype><trackindex>1</trackindex></sourcetrack></clipitem></track>');
  }
  out.write('</audio></media></sequence></xmeml>');
  return out.toString();
}
