// بناء مقطع آية واحدة (تغيير الآية بالمحرر، يوم 10).
import 'package:flutter_test/flutter_test.dart';
import 'package:quran_dub/pipeline/quran_text_source.dart';
import 'package:quran_dub/pipeline/recitation_segment.dart';
import 'package:quran_dub/pipeline/segment_factory.dart';

void main() {
  final text = QuranTextSource.fromRows([
    (50, 27, 'نص الآية الأولى', 'تفسيرها'),
    (50, 28, 'نص الآية الثانية', 'تفسيرها الثاني'),
  ]);

  group('buildWholeAyahSegment', () {
    test('آية موجودة: مقطع كامل بجزء واحد، نفس نص وتفسير QuranTextSource', () {
      final s = buildWholeAyahSegment(
          text: text, surah: 50, ayah: 27, start: 1.0, end: 3.0);
      expect(s.kind, SegmentKind.fullAyah);
      expect(s.surah, 50);
      expect(s.ayah, 27);
      expect(s.part, 1);
      expect(s.partCount, 1);
      expect(s.text, 'نص الآية الأولى');
      expect(s.tafsir, 'تفسيرها');
      expect(s.tafsirFull, 'تفسيرها');
      expect(s.tafsirSplit, 'تفسيرها'); // جزء واحد: ما في تقسيم (نفس segment_builder)
      expect(s.showAyahNumber, isTrue);
      expect(s.needsReview, isFalse);
      expect(s.start, 1.0);
      expect(s.end, 3.0);
    });

    test('آية مش موجودة بالمصدر: مقطع "بده مراجعة" باقتراح بدل انهيار', () {
      final s = buildWholeAyahSegment(
          text: text, surah: 99, ayah: 1, start: 0, end: 1);
      expect(s.kind, SegmentKind.nonQuran);
      expect(s.surah, isNull);
      expect(s.needsReview, isTrue);
      expect(s.suggestedRef, '99:1');
    });

    test('end أصغر من start: بينصلح لـ start (ما بيصير مقطع بطول سلبي)', () {
      final s = buildWholeAyahSegment(
          text: text, surah: 50, ayah: 27, start: 5.0, end: 2.0);
      expect(s.end, greaterThanOrEqualTo(s.start));
    });

    test('نص المستخدم وبقية الحقول الاختيارية بتنمرر', () {
      final s = buildWholeAyahSegment(
        text: text,
        surah: 50,
        ayah: 28,
        start: 0,
        end: 1,
        confidence: 0.42,
        needsReview: true,
        asrText: 'كذا كذا',
        inferred: true,
      );
      expect(s.confidence, 0.42);
      expect(s.needsReview, isTrue);
      expect(s.asrText, 'كذا كذا');
      expect(s.inferred, isTrue);
    });
  });

  group('buildUserTextSegment', () {
    test('مقطع "مش قرآن" بنص المستخدم، ظاهر بس لو النص مش فاضي', () {
      final empty = buildUserTextSegment(start: 0, end: 2);
      expect(empty.isVisible, isFalse);
      final withText = buildUserTextSegment(start: 0, end: 2, userText: 'مقدمة');
      expect(withText.kind, SegmentKind.nonQuran);
      expect(withText.userText, 'مقدمة');
      expect(withText.isVisible, isTrue);
    });
  });

  group('RecitationSegment.toJson/fromJson', () {
    test('دورة كاملة (round-trip) تحافظ على كل الحقول المهمة', () {
      final s = buildWholeAyahSegment(
              text: text, surah: 50, ayah: 27, start: 1.25, end: 3.75)
          .copyWith(needsReview: true, userText: 'ملاحظة');
      final back = RecitationSegment.fromJson(s.toJson())!;
      expect(back.start, s.start);
      expect(back.end, s.end);
      expect(back.kind, s.kind);
      expect(back.surah, s.surah);
      expect(back.ayah, s.ayah);
      expect(back.text, s.text);
      expect(back.tafsir, s.tafsir);
      expect(back.needsReview, s.needsReview);
      expect(back.userText, s.userText);
    });

    test('fromJson لقيمة مش خريطة أو بدون start/end = null', () {
      expect(RecitationSegment.fromJson('كلام'), isNull);
      expect(RecitationSegment.fromJson({'end': 1}), isNull);
      expect(RecitationSegment.fromJson({'start': 0, 'end': 1}), isNotNull);
    });
  });

  group('copyWith الموسّع (يوم 10)', () {
    test('تعديل التوقيت و needsReview لوحدهم بدون ما يلمسوا باقي الحقول', () {
      final s = buildWholeAyahSegment(
          text: text, surah: 50, ayah: 27, start: 0, end: 2);
      final moved = s.copyWith(start: 0.5, end: 2.5, needsReview: true);
      expect(moved.start, 0.5);
      expect(moved.end, 2.5);
      expect(moved.needsReview, isTrue);
      expect(moved.surah, s.surah);
      expect(moved.text, s.text);
    });

    test('clearUserText بيصفّر النص بدون ما يحتاج قيمة جديدة', () {
      final s = buildUserTextSegment(start: 0, end: 1, userText: 'شي');
      expect(s.copyWith(clearUserText: true).userText, isNull);
    });
  });
}
