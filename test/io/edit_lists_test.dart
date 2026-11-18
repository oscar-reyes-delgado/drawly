import 'package:drawly/io/edit_lists.dart';
import 'package:drawly/model/document.dart';
import 'package:flutter_test/flutter_test.dart';
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const timeline = Timeline(fps: 24, length: 72, scenes: [Scene(id: 'a', name: 'A & B', start: 0, length: 24), Scene(id: 'b', name: 'Dissolve', start: 24, length: 24, transition: 'dissolve', transitionFrames: 12), Scene(id: 'c', name: 'Wipe', start: 48, length: 24, transition: 'wipeLeft', transitionFrames: 8)], audio: [AudioClip(id: 'audio', name: 'Sound & voice', assetId: 'sound.wav', startFrame: 12, duration: 2, trimStart: 0.25, trimEnd: 0.5)]);
  test('non-drop timecodes and round trips', () {
    expect(frameToTimecode(0, 24), '00:00:00:00'); expect(frameToTimecode(25, 24), '00:00:01:01'); expect(frameToTimecode(86400, 24), '01:00:00:00');
    for (final fps in [12, 24, 30, 60]) { for (var i = 0; i < 20; i++) { final f = i * 6789; expect(timecodeToFrame(frameToTimecode(f, fps), fps), f); } }
    for (final s in ['abc', '00:60:00:00', '00:00:60:00', '00:00:00:24', '-1:00:00:00']) { expect(() => timecodeToFrame(s, 24), throwsFormatException); }
  });
  test('EDL scenes, transition durations and exclusive out points', () {
    final edl = timelineToEdl(timeline, title: 'Test');
    expect(RegExp(r'^\d{3}', multiLine: true).allMatches(edl).map((m) => m[0]), ['001', '002', '003']);
    expect(edl, contains('D    012')); expect(edl, contains('W001 008')); expect(edl, contains('00:00:01:00 00:00:02:00 00:00:01:00 00:00:02:00')); expect(edl, contains('* FROM CLIP NAME: A & B'));
  });
  test('EDL without scenes covers entire sequence', () { final edl = timelineToEdl(const Timeline(fps: 24, length: 48), title: 'Full'); expect(RegExp(r'^\d{3}', multiLine: true).allMatches(edl).length, 1); expect(edl, contains('00:00:00:00 00:00:02:00')); });
  test('XML includes escaped names and trimmed audio in frames', () {
    final xml = timelineToFcpXml(timeline, title: 'A < "B"', width: 1920, height: 1080);
    expect(xml, contains('<xmeml version="5">')); expect(RegExp('<clipitem').allMatches(xml).length, 4); expect(xml, contains('<timebase>24</timebase>'));
    expect(xml, contains('A &amp; B')); expect(xml, contains('A &lt; &quot;B&quot;')); expect(xml, contains('<start>12</start><end>42</end><in>6</in><out>36</out>')); expect(xml, contains('<width>1920</width>'));
  });
}
