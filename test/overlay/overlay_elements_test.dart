// العناصر الخمسة ومواقعها بإطار المعاينة/التصدير (يوم 9).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quran_dub/overlay/overlay_frame.dart';
import 'package:quran_dub/overlay/overlay_layout.dart';
import 'package:quran_dub/overlay/overlay_style.dart';
import 'package:quran_dub/overlay/overlay_timeline.dart';
import 'package:quran_dub/pipeline/recitation_segment.dart';

RecitationSegment seg() => RecitationSegment(
      start: 0,
      end: 5,
      kind: SegmentKind.fullAyah,
      surah: 50,
      ayah: 27,
      text: 'قَالَ قَرِينُهُۥ رَبَّنَا مَآ أَطۡغَيۡتُهُۥ',
      showAyahNumber: true,
      tafsir: 'تفسير',
      tafsirSplit: 'تفسير',
      tafsirFull: 'تفسير',
      confidence: 1,
    );

Future<void> pumpStyle(WidgetTester tester, Size size, OverlayStyle style,
    {Map<OverlayElement, GlobalKey>? keys}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Align(
      alignment: Alignment.topLeft,
      child: AyahOverlayFrame(
        videoWidth: size.width.toInt(),
        videoHeight: size.height.toInt(),
        cue: OverlayCue(OverlayItem(seg(), 0, 0, 5), 1),
        style: style,
        surahName: (n) => n == 50 ? 'سُوْرَةُ ق' : null,
        elementKeys: keys,
      ),
    ),
  ));
}

OverlayLayout enable(OverlayLayout l, OverlayElement e) =>
    l.update(e, (p) => p.copyWith(enabled: true));

void main() {
  perSegmentWidgetTests();
  const ayah = ValueKey('overlay-ayah');
  const tafsir = ValueKey('overlay-tafsir');
  const surah = ValueKey('overlay-surah-ref');
  const reciter = ValueKey('overlay-reciter');
  const sizes = [Size(1080, 1920), Size(1920, 1080), Size(1080, 1080)];

  test('نص اسم السورة ورقم الآية', () {
    expect(surahRefText(seg(), (n) => n == 50 ? 'سُوْرَةُ ق' : null), contains('ق'));
    expect(surahRefText(seg(), (n) => n == 50 ? 'سُوْرَةُ ق' : null), contains('٢٧'));
    // بدون اسم بالقاعدة: "سورة 50" بدل ما يطلع فاضي.
    expect(surahRefText(seg(), (n) => null), contains('50'));
  });

  testWidgets('الافتراضي: اسم السورة والقارئ مش ظاهرين، والآية عند 61%', (tester) async {
    for (final s in sizes) {
      await pumpStyle(tester, s, const OverlayStyle());
      expect(find.byKey(surah), findsNothing);
      expect(find.byKey(reciter), findsNothing);
      expect(find.byKey(ayah), findsOneWidget);
      expect(tester.getTopLeft(find.byKey(ayah)).dy, closeTo(s.height * 0.61, 1.5));
    }
  });

  testWidgets('اسم السورة فوق الآية، والآية بتضل عند 61%', (tester) async {
    for (final s in sizes) {
      await pumpStyle(tester, s,
          OverlayStyle(layout: enable(OverlayLayout.reference, OverlayElement.surahRef)));
      expect(find.byKey(surah), findsOneWidget);
      expect(tester.getBottomLeft(find.byKey(surah)).dy,
          lessThanOrEqualTo(tester.getTopLeft(find.byKey(ayah)).dy + 0.5));
      expect(tester.getTopLeft(find.byKey(ayah)).dy, closeTo(s.height * 0.61, 1.5));
    }
  });

  testWidgets('اسم القارئ تحت التفسير، ويطلع بس لو مكتوب', (tester) async {
    final l = enable(OverlayLayout.reference, OverlayElement.reciter);
    await pumpStyle(tester, const Size(1080, 1920),
        OverlayStyle(layout: l, reciterName: 'الشيخ محمد'));
    expect(find.byKey(reciter), findsOneWidget);
    expect(tester.getTopLeft(find.byKey(reciter)).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(find.byKey(tafsir)).dy - 0.5));
    expect(find.text('الشيخ محمد'), findsWidgets);
  });

  testWidgets('إطفاء الآية: التفسير بيبدأ عند 61%', (tester) async {
    final l = OverlayLayout.reference
        .update(OverlayElement.ayah, (p) => p.copyWith(enabled: false));
    await pumpStyle(tester, const Size(1080, 1920), OverlayStyle(layout: l));
    expect(find.byKey(ayah), findsNothing);
    expect(tester.getTopLeft(find.byKey(tafsir)).dy, closeTo(1920 * 0.61, 1.5));
  });

  testWidgets('عنصر منسحب: بمكانه النسبي بكل الأبعاد، وباقي العناصر ما بتتحرك',
      (tester) async {
    for (final s in sizes) {
      await pumpStyle(tester, s, const OverlayStyle());
      final tafsirBefore = tester.getTopLeft(find.byKey(tafsir));
      final l = OverlayLayout.reference.update(OverlayElement.ayah,
          (p) => p.copyWith(anchor: const ElementAnchor(0.5, 0.2)));
      await pumpStyle(tester, s, OverlayStyle(layout: l));
      final r = tester.getRect(find.byKey(ayah));
      expect(r.top, closeTo(s.height * 0.2, 2), reason: '$s');
      expect(r.center.dx, closeTo(s.width * 0.5, 2), reason: '$s');
      expect(tester.getTopLeft(find.byKey(tafsir)), tafsirBefore, reason: '$s');
    }
  });

  testWidgets('الحجم: 140% أكبر من 100% من 60%', (tester) async {
    double h(double sc) => sc;
    final heights = <double>[];
    for (final sc in [0.6, 1.0, 1.4]) {
      final l = OverlayLayout.reference.update(OverlayElement.ayah,
          (p) => p.copyWith(scale: h(sc), anchor: const ElementAnchor(0.5, 0.1)));
      await pumpStyle(tester, const Size(1080, 1920), OverlayStyle(layout: l));
      heights.add(tester.getSize(find.byKey(ayah)).height);
    }
    expect(heights[0], lessThan(heights[1]));
    expect(heights[1], lessThan(heights[2]));
  });

  testWidgets('الترجمة ما بترسم شي (يوم 12) حتى لو انشغّلت', (tester) async {
    final l = enable(OverlayLayout.reference, OverlayElement.translation);
    await pumpStyle(tester, const Size(1080, 1920), OverlayStyle(layout: l));
    expect(find.byKey(ayah), findsOneWidget);
    expect(find.byKey(const ValueKey('overlay-translation')), findsNothing);
  });

  testWidgets('elementKeys: مفتاح لكل عنصر ظاهر (للسحب بالمحرر)', (tester) async {
    final keys = {for (final e in OverlayElement.values) e: GlobalKey()};
    final l = enable(OverlayLayout.reference, OverlayElement.surahRef);
    await pumpStyle(tester, const Size(1080, 1920), OverlayStyle(layout: l), keys: keys);
    expect(keys[OverlayElement.ayah]!.currentContext, isNotNull);
    expect(keys[OverlayElement.tafsir]!.currentContext, isNotNull);
    expect(keys[OverlayElement.surahRef]!.currentContext, isNotNull);
    expect(keys[OverlayElement.reciter]!.currentContext, isNull);
  });

  testWidgets('الخلفية الشفافة: صندوق/شريط بلون عكس النص', (tester) async {
    for (final mode in [OverlayBackgroundMode.box, OverlayBackgroundMode.bar]) {
      await pumpStyle(
          tester,
          const Size(1080, 1920),
          OverlayStyle(background: OverlayBackground(mode: mode, opacity: 0.5)));
      final boxes = tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .map((d) => d.decoration)
          .whereType<BoxDecoration>()
          .toList();
      expect(boxes, isNotEmpty, reason: mode.name);
      expect(boxes.any((b) => b.color != null && b.color!.a > 0.4 && b.color!.a < 0.6),
          isTrue,
          reason: mode.name);
    }
  });
}

void perSegmentWidgetTests() {
  testWidgets('حجم مقطع بعينه: الآية أكبر بمقطعه من مقطع ثاني بنفس الشكل',
      (tester) async {
    Future<double> ayahHeight(int index) async {
      const size = Size(1080, 1920);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final style = OverlayStyle(
        layout: OverlayLayout.reference.update(OverlayElement.ayah,
            (p) => p.copyWith(anchor: const ElementAnchor(0.5, 0.1))),
        segmentScales: {1: {OverlayElement.ayah: 1.5}},
      );
      await tester.pumpWidget(MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: AyahOverlayFrame(
            videoWidth: 1080,
            videoHeight: 1920,
            cue: OverlayCue(OverlayItem(seg(), index, 0, 5), 1),
            style: style,
          ),
        ),
      ));
      return tester.getSize(find.byKey(const ValueKey('overlay-ayah'))).height;
    }

    final normal = await ayahHeight(0);
    final big = await ayahHeight(1);
    expect(big, greaterThan(normal * 1.2));
  });
}
