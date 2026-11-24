import 'package:flutter_test/flutter_test.dart';
import 'package:quran_dub/overlay/playback_clock.dart';

void main() {
  test('paused: position stays', () {
    final c = PlaybackClock();
    c.report(position: 5, wall: 100, playing: false);
    expect(c.now(100), 5);
    expect(c.now(200), 5);
  });

  test('playing: extrapolates between 500ms reports', () {
    final c = PlaybackClock();
    c.report(position: 10, wall: 50, playing: true);
    expect(c.now(50.0), 10);
    expect(c.now(50.3), closeTo(10.3, 1e-9));
    // تبليغ جديد قريب من المتوقع: تصحيح ناعم (30%)، بدون قفزة لورا.
    c.report(position: 10.6, wall: 50.5, playing: true);
    expect(c.now(50.5), closeTo(10.5 + 0.1 * 0.3, 1e-9));
    expect(c.now(50.5), greaterThanOrEqualTo(10.5)); // ما رجع لورا
  });

  test('big difference (seek) snaps immediately', () {
    final c = PlaybackClock();
    c.report(position: 10, wall: 0, playing: true);
    c.report(position: 40, wall: 0.2, playing: true);
    expect(c.now(0.2), 40);
    c.report(position: 3, wall: 1.0, playing: true);
    expect(c.now(1.0), 3);
  });

  test('state change (play/pause) anchors at the reported position', () {
    final c = PlaybackClock();
    c.report(position: 1, wall: 0, playing: true);
    c.report(position: 1.4, wall: 0.45, playing: false);
    expect(c.now(0.45), 1.4);
    expect(c.now(9), 1.4);
    c.report(position: 1.4, wall: 9, playing: true);
    expect(c.now(9.5), closeTo(1.9, 1e-9));
    expect(c.playing, isTrue);
  });
}
