import 'package:flutter_test/flutter_test.dart';
import 'package:quran_dub/overlay/overlay_timeline.dart';
import 'package:quran_dub/pipeline/recitation_segment.dart';

RecitationSegment mk(double s, double e,
        {SegmentKind kind = SegmentKind.fullAyah, String? userText, int ayah = 1}) =>
    RecitationSegment(
      start: s,
      end: e,
      kind: kind,
      surah: kind == SegmentKind.fullAyah || kind == SegmentKind.partialAyah
          ? 50
          : null,
      ayah: kind == SegmentKind.fullAyah || kind == SegmentKind.partialAyah
          ? ayah
          : null,
      text: kind == SegmentKind.istiadha || kind == SegmentKind.nonQuran
          ? ''
          : 'نص',
      userText: userText,
      confidence: 1,
    );

void main() {
  test('text stays until the next segment starts, not until its own end', () {
    final tl = OverlayTimeline.build([mk(1, 3), mk(6, 8, ayah: 2)]);
    expect(tl.items.length, 2);
    expect(tl.items[0].start, 1);
    expect(tl.items[0].holdEnd, 6); // مش 3
    // بنص الفجوة (بعد نهاية المقطع الأول بكتير) لسا ظاهر بالكامل.
    expect(tl.cueAt(4.5)!.opacity, 1.0);
    expect(tl.cueAt(4.5)!.item.segment.ayah, 1);
    expect(tl.cueAt(0.5), isNull); // قبل الأول
  });

  test('fade in at start, fade out right before the next segment', () {
    final tl = OverlayTimeline.build([mk(1, 3), mk(6, 8, ayah: 2)]);
    expect(tl.cueAt(1.0), isNull); // opacity 0 عند البداية بالضبط
    final mid = tl.cueAt(1.125)!.opacity; // نص الـ fade
    expect(mid, closeTo(0.5, 1e-9));
    expect(tl.cueAt(1.25)!.opacity, 1.0);
    expect(tl.cueAt(5.875)!.opacity, closeTo(0.5, 1e-9));
    expect(tl.cueAt(5.99)!.opacity, lessThan(0.01));
    // التالي بيبلّش fade in من 6.0.
    final next = tl.cueAt(6.125)!;
    expect(next.item.segment.ayah, 2);
    expect(next.opacity, closeTo(0.5, 1e-9));
  });

  test('never two segments at once; opacity monotonic in fades', () {
    final tl = OverlayTimeline.build(
        [mk(0, 2), mk(2, 4, ayah: 2), mk(4, 6, ayah: 3)]);
    for (var t = 0.0; t < 7; t += 0.01) {
      final matches = tl.items.where((i) => t >= i.start && t < i.holdEnd);
      expect(matches.length, lessThanOrEqualTo(1), reason: 't=$t');
    }
    var prev = 0.0;
    for (var t = 0.0; t <= 0.25; t += 0.01) {
      final o = tl.cueAt(t)?.opacity ?? 0;
      expect(o, greaterThanOrEqualTo(prev));
      prev = o;
    }
  });

  test('istiadha and empty non-Quran stay blank and end the previous text', () {
    final tl = OverlayTimeline.build([
      mk(0, 2, kind: SegmentKind.istiadha),
      mk(3, 5),
      mk(8, 10, kind: SegmentKind.nonQuran), // بدون نص مستخدم
      mk(12, 14, ayah: 2),
    ]);
    expect(tl.items.length, 2);
    expect(tl.cueAt(1), isNull); // الاستعاذة فاضية
    expect(tl.items[0].holdEnd, 8); // الأول بينتهي عند بداية غير القرآني
    expect(tl.cueAt(6)!.item.segment.ayah, 1);
    expect(tl.cueAt(9), isNull); // غير القرآني فاضي
    expect(tl.cueAt(11), isNull);
    expect(tl.cueAt(13)!.item.segment.ayah, 2);
  });

  test('non-Quran with user text is shown', () {
    final tl = OverlayTimeline.build([mk(0, 2, kind: SegmentKind.nonQuran, userText: 'مرحبا')]);
    expect(tl.items.length, 1);
    expect(tl.cueAt(1)!.item.segment.userText, 'مرحبا');
  });

  test('last segment keeps text for the tail, clamped to video duration', () {
    final a = OverlayTimeline.build([mk(1, 3)]);
    expect(a.items.single.holdEnd, closeTo(3.6, 1e-9));
    final b = OverlayTimeline.build([mk(1, 3)], videoDuration: 3.2);
    expect(b.items.single.holdEnd, 3.2);
    expect(b.cueAt(3.3), isNull);
  });

  test('optional cap on holding after the segment end', () {
    final tl = OverlayTimeline.build([mk(0, 2), mk(30, 32, ayah: 2)],
        config: const OverlayConfig(maxHoldAfterEnd: 3));
    expect(tl.items[0].holdEnd, 5);
    expect(tl.cueAt(10), isNull);
  });

  test('overlapping next segment cuts at its start; unsorted input is ok', () {
    final tl = OverlayTimeline.build([mk(5, 9, ayah: 2), mk(1, 6)]);
    expect(tl.items[0].segment.ayah, 1);
    expect(tl.items[0].holdEnd, 5);
    expect(tl.cueAt(4)!.item.segment.ayah, 1);
    expect(tl.cueAt(7)!.item.segment.ayah, 2);
  });

  test('short windows shrink the fades', () {
    final tl = OverlayTimeline.build([mk(0, 0.2), mk(0.2, 3, ayah: 2)]);
    final first = tl.items.first; // نافذة 0.2s
    final o = tl.opacityOf(first, 0.1);
    expect(o, closeTo(1.0, 1e-9)); // fades = 0.1 لكل واحد
    expect(tl.opacityOf(first, 0.05), closeTo(0.5, 1e-9));
  });

  test('empty and invalid windows are dropped', () {
    expect(OverlayTimeline.build([]).items, isEmpty);
    expect(OverlayTimeline.build([]).cueAt(1), isNull);
    final dup = OverlayTimeline.build([mk(2, 3), mk(2, 4, ayah: 2)]);
    expect(dup.items.length, 1);
    expect(dup.items.single.segment.ayah, 2);
  });
}
