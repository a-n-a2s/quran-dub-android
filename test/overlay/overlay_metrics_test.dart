import 'package:flutter_test/flutter_test.dart';
import 'package:quran_dub/overlay/overlay_metrics.dart';
import 'package:quran_dub/pipeline/project_input.dart';

VideoInfo info(int w, int h, int rot) => VideoInfo(
    width: w,
    height: h,
    rotationDegrees: rot,
    durationMs: 59000,
    fps: 30,
    hasAudioTrack: true);

void main() {
  test('reference clip 1080x1920: first line at ~61%, sizes from the mock', () {
    final m = OverlayMetrics.forSize(1080, 1920);
    expect(m.unit, 1080);
    expect(m.top / 1920, closeTo(0.61, 1e-9));
    // إطار المرجع 450 عرض: آية 25px → 60px عند 1080.
    expect(m.ayahFontSize, closeTo(60, 1e-9));
    expect(m.tafsirFontSize, closeTo(36, 1e-9));
    expect(m.gap, closeTo(14.4, 1e-9));
    expect(m.circleSize, closeTo(62.4, 1e-9));
    expect(m.circleBorder, closeTo(3.6, 1e-9));
    expect(m.numberFontSize, closeTo(28.8, 1e-9));
    // حواف 26/450 من كل جنب.
    expect(m.maxTextWidth, closeTo(1080 * (1 - 2 * 26 / 450), 1e-9));
    expect(m.bottomLimit, greaterThan(m.top));
  });

  test('same look on landscape, square and portrait (unit = shorter side)', () {
    final p = OverlayMetrics.forSize(1080, 1920);
    final l = OverlayMetrics.forSize(1920, 1080);
    final s = OverlayMetrics.forSize(1080, 1080);
    for (final m in [l, s]) {
      expect(m.ayahFontSize, closeTo(p.ayahFontSize, 1e-9));
      expect(m.tafsirFontSize, closeTo(p.tafsirFontSize, 1e-9));
      expect(m.top / m.height, closeTo(0.61, 1e-9));
    }
    // الأفقي: العرض محدود عشان الأسطر ما تطوّل كتير.
    expect(l.maxTextWidth, lessThan(1920 * 0.9));
    expect(l.maxTextWidth, closeTo(1080 * 1.15, 1e-9));
    expect(s.maxTextWidth, closeTo(1080 * (1 - 2 * 26 / 450), 1e-9));
  });

  test('scales linearly with resolution (720p / 4K same proportions)', () {
    final a = OverlayMetrics.forSize(720, 1280);
    final b = OverlayMetrics.forSize(2160, 3840);
    expect(b.ayahFontSize / a.ayahFontSize, closeTo(3, 1e-9));
    expect(b.top / b.height, closeTo(a.top / a.height, 1e-9));
  });

  test('uses rotated dimensions from VideoInfo', () {
    // فيديو مخزّن 1920x1080 بدوران 90° = عمودي 1080x1920.
    final v = info(1920, 1080, 90);
    expect(v.orientation, VideoOrientation.portrait);
    final m = OverlayMetrics.forSize(v.rotatedWidth, v.rotatedHeight);
    expect([m.width, m.height], [1080, 1920]);
    expect(m.top, closeTo(1920 * 0.61, 1e-9));
    final land = info(1920, 1080, 0);
    expect(land.orientation, VideoOrientation.landscape);
    final sq = info(1080, 1080, 270);
    expect(sq.orientation, VideoOrientation.square);
  });
}
