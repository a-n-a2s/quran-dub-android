import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:quran_dub/overlay/snap_guides.dart';

void main() {
  const video = Size(1080, 1920);

  test('بيلتصق بمنتصف الفيديو أفقياً وعمودياً لما يقرّب', () {
    final r = Rect.fromCenter(center: const Offset(548, 955), width: 400, height: 100);
    final s = snapRect(r, video: video, threshold: 16);
    expect(s.rect.center.dx, closeTo(540, 1e-9));
    expect(s.rect.center.dy, closeTo(960, 1e-9));
    expect(s.guides.where((g) => g.kind == GuideKind.center).length, 2);
    expect(s.guides.any((g) => g.axis == GuideAxis.vertical && g.position == 540), isTrue);
    expect(s.guides.any((g) => g.axis == GuideAxis.horizontal && g.position == 960), isTrue);
  });

  test('بعيد عن الحد: ما بيلتصق وما في خطوط', () {
    final r = Rect.fromCenter(center: const Offset(700, 500), width: 400, height: 100);
    final s = snapRect(r, video: video, threshold: 16);
    expect(s.rect, r);
    expect(s.guides, isEmpty);
  });

  test('محاذاة مع عنصر ثاني (حافة أو مركز)', () {
    final other = Rect.fromLTWH(100, 1200, 500, 80);
    // حافة يسار قريبة من يسار العنصر الثاني.
    final r = Rect.fromLTWH(108, 700, 300, 60);
    final s = snapRect(r, video: video, others: [other], threshold: 16);
    expect(s.rect.left, closeTo(100, 1e-9));
    expect(s.guides.any((g) => g.kind == GuideKind.align && g.axis == GuideAxis.vertical && g.position == 100), isTrue);
  });

  test('أقرب هدف هو اللي بيفوز، والتحرك بحد العتبة', () {
    final r = Rect.fromCenter(center: const Offset(530, 100), width: 200, height: 50);
    final s = snapRect(r, video: video, threshold: 15);
    expect(s.rect.center.dx, closeTo(540, 1e-9));
    expect(s.rect.center.dy, 100);
  });

  test('snap=false: ما بيتحرك بس بيبيّن الخطوط القريبة', () {
    final r = Rect.fromCenter(center: const Offset(541, 400), width: 200, height: 50);
    final s = snapRect(r, video: video, threshold: 16, snap: false);
    expect(s.rect, r);
    expect(s.guides.length, 1);
    expect(s.guides.single.axis, GuideAxis.vertical);
    final far = snapRect(Rect.fromCenter(center: const Offset(600, 400), width: 200, height: 50),
        video: video, threshold: 16, snap: false);
    expect(far.guides, isEmpty);
  });

  test('بدون تكرار للخطوط', () {
    final a = Rect.fromLTWH(440, 100, 200, 50);
    final b = Rect.fromLTWH(440, 300, 200, 50);
    final s = snapRect(Rect.fromLTWH(440, 600, 200, 50), video: video, others: [a, b], threshold: 10);
    final keys = s.guides.map((g) => '${g.axis}${g.position}').toList();
    expect(keys.toSet().length, keys.length);
  });
}
