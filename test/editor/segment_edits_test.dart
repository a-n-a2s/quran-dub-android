// عمليات التصحيح اليدوي (يوم 10): تغيير الآية، حذف، إضافة، الحدود، نص
// المستخدم، التأكيد، وإعادة ربط segmentScales — على نص القرآن الحقيقي.
import 'package:flutter_test/flutter_test.dart';
import 'package:quran_dub/editor/segment_edits.dart';
import 'package:quran_dub/editor/timeline_geometry.dart';
import 'package:quran_dub/overlay/overlay_layout.dart';
import 'package:quran_dub/overlay/overlay_style.dart';
import 'package:quran_dub/pipeline/quran_text_source.dart';
import 'package:quran_dub/pipeline/recitation_segment.dart';
import 'package:quran_dub/pipeline/segment_builder.dart';
import 'package:quran_dub/pipeline/segment_factory.dart';

String _squash(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();
String _noSpace(String s) => s.replaceAll(RegExp(r'\s+'), '');

void main() {
  late QuranTextSource text;
  setUpAll(() {
    text = QuranTextSource.fromSeedFile('assets/quran/quran_data.json.gz');
  });

  RecitationSegment nonQuran(double a, double b, {String? user, bool review = false}) =>
      RecitationSegment(
          start: a, end: b, kind: SegmentKind.nonQuran, confidence: 0.2,
          userText: user, needsReview: review);

  group('buildAyahReading (نفس منطق خط الأنابيب)', () {
    test('جزء واحد: الآية كاملة برقمها وتفسيرها كامل', () {
      final r = buildAyahReading(text, 50, 28, [(1.0, 4.0)]);
      expect(r, hasLength(1));
      final s = r.single;
      expect(s.kind, SegmentKind.fullAyah);
      expect(s.text, text.ayah(50, 28)!.uthmani);
      expect(s.showAyahNumber, isTrue);
      expect(s.tafsir, text.ayah(50, 28)!.tafsir);
      expect(s.tafsirSplit, s.tafsirFull);
      expect((s.start, s.end), (1.0, 4.0));
    });

    test('جزئين لآية الكرسي: النص مقطوع على كلمة، والجزئين = الآية، الرقم مع الأخير، والتفسير الطويل مقسوم', () {
      final r = buildAyahReading(text, 2, 255, [(0.0, 6.0), (6.0, 14.0)]);
      expect(r, hasLength(2));
      expect(r.map((s) => s.kind), everyElement(SegmentKind.partialAyah));
      expect(r[0].partCount, 2);
      expect([r[0].part, r[1].part], [1, 2]);
      expect(r[0].showAyahNumber, isFalse);
      expect(r[1].showAyahNumber, isTrue);
      expect(_squash('${r[0].text} ${r[1].text}'), _squash(text.ayah(2, 255)!.uthmani));
      // كل جزء بيبلّش وبيخلص على حد كلمة (من كلمات الآية).
      final words = text.ayah(2, 255)!.uthmani.split(' ').toSet();
      expect(words, contains(r[0].text.split(' ').last));
      expect(words, contains(r[1].text.split(' ').first));
      // التفسير الطويل بينقسم بنسبة الوقت، والقطع مع بعض = التفسير كامل.
      expect(r[0].tafsirSplit, isNot(r[1].tafsirSplit));
      expect(_noSpace(r[0].tafsirSplit + r[1].tafsirSplit), _noSpace(r[0].tafsirFull));
    });

    test('جزئين لآية تفسيرها قصير (50:27): التفسير كامل تحت الجزئين (قرار أنس يوم 5)', () {
      final r = buildAyahReading(text, 50, 27, [(0.0, 2.0), (2.0, 3.5)]);
      expect(r[0].tafsirSplit, r[0].tafsirFull);
      expect(r[1].tafsirSplit, r[1].tafsirFull);
    });

    test('آية مش موجودة: مقاطع "مش قرآن" بدها مراجعة بنفس الأوقات', () {
      final r = buildAyahReading(text, 1, 99, [(0.0, 1.0), (1.0, 2.0)]);
      expect(r.map((s) => s.kind), everyElement(SegmentKind.nonQuran));
      expect(r.every((s) => s.needsReview && s.suggestedRef == '1:99'), isTrue);
    });
  });

  group('changeAyah', () {
    test('تغيير جزء من آية مقسومة: كل أجزاء التلاوة بتتغيّر بنفس أوقاتها، والعدد ثابت', () {
      final segs = [
        nonQuran(0, 0.8),
        ...buildAyahReading(text, 50, 27, [(1.0, 3.0), (3.0, 5.0)]),
        buildWholeAyahSegment(text: text, surah: 50, ayah: 28, start: 5, end: 8),
      ];
      final e = changeAyah(text, segs, 2, 2, 255);
      expect(e.segments, hasLength(4));
      expect(e.mapping, [0, 1, 2, 3]);
      expect(e.segments[1].ref, '2:255');
      expect(e.segments[2].ref, '2:255');
      expect((e.segments[1].start, e.segments[1].end), (1.0, 3.0));
      expect((e.segments[2].start, e.segments[2].end), (3.0, 5.0));
      expect(e.segments[2].showAyahNumber, isTrue);
      expect(e.segments[3].ref, '50:28'); // الجار ما تغيّر
      expect(e.segments.every((s) => !s.needsReview || s.kind == SegmentKind.nonQuran), isTrue);
    });

    test('مقطع "مش قرآن" بيصير آية (من الاقتراح)', () {
      final segs = [nonQuran(0, 2, review: true)];
      final e = changeAyah(text, segs, 0, 112, 1);
      expect(e.segments.single.kind, SegmentKind.fullAyah);
      expect(e.segments.single.ref, '112:1');
      expect(e.segments.single.needsReview, isFalse);
    });
  });

  group('deleteSegment + remap segmentScales', () {
    test('حذف جزء من آية بـ 3 أجزاء: الباقي بيصير 1/2 و2/2 والرقم مع الأخير', () {
      final segs = [
        ...buildAyahReading(text, 2, 255, [(0.0, 4.0), (4.0, 8.0), (8.0, 12.0)]),
        buildWholeAyahSegment(text: text, surah: 2, ayah: 256, start: 12, end: 18),
      ];
      final e = deleteSegment(text, segs, 0);
      expect(e.segments, hasLength(3));
      expect(e.mapping, [null, 0, 1, 2]);
      expect([e.segments[0].part, e.segments[0].partCount], [1, 2]);
      expect([e.segments[1].part, e.segments[1].partCount], [2, 2]);
      expect(e.segments[0].showAyahNumber, isFalse);
      expect(e.segments[1].showAyahNumber, isTrue);
      expect((e.segments[0].start, e.segments[1].end), (4.0, 12.0));
      expect(e.segments[2].ref, '2:256');
    });

    test('حجم خاص بمقطع بيلحقه لمكانه الجديد بعد الحذف، والمحذوف بيضيع حجمه', () {
      final segs = [
        for (var i = 0; i < 4; i++) nonQuran(i * 2.0, i * 2.0 + 1.5, user: 'نص $i'),
      ];
      const scales = <int, Map<OverlayElement, double>>{
        1: {OverlayElement.ayah: 1.4},
        3: {OverlayElement.tafsir: 0.7},
      };
      final e = deleteSegment(text, segs, 1);
      final remapped = e.remapScales(scales);
      expect(remapped, {2: {OverlayElement.tafsir: 0.7}});
      // نفس المقطع (نص 3) بالقائمة الجديدة بياخد نفس الحجم بالمعاينة/التصدير.
      final style = const OverlayStyle().copyWith(segmentScales: remapped);
      expect(e.segments[2].userText, 'نص 3');
      expect(style.forSegment(2).layout[OverlayElement.tafsir].scale, 0.7);
    });
  });

  group('insertSegment', () {
    final base = [
      nonQuran(0, 2, user: 'أ'),
      nonQuran(5, 7, user: 'ب'),
    ];

    test('بيندخل بمكانه حسب الوقت، والمفاتيح اللي بعده بتتزحزح', () {
      final e = insertSegment(base, buildUserTextSegment(start: 2.5, end: 4, userText: 'جديد'))!;
      expect(e.segments.map((s) => s.userText), ['أ', 'جديد', 'ب']);
      expect(e.focus, 1);
      expect(e.mapping, [0, 2]);
      expect(e.remapScales({1: {OverlayElement.ayah: 1.2}}), {2: {OverlayElement.ayah: 1.2}});
    });

    test('بأول وآخر القائمة', () {
      expect(insertSegment(base, buildUserTextSegment(start: 8, end: 9))!.focus, 2);
      expect(
          insertSegment([nonQuran(3, 4)], buildUserTextSegment(start: 0, end: 1))!.mapping,
          [1]);
    });

    test('بيرفض لو بيتقاطع مع مقطع موجود أو أقصر من الحد الأدنى', () {
      expect(insertSegment(base, buildUserTextSegment(start: 1.5, end: 3)), isNull);
      expect(insertSegment(base, buildUserTextSegment(start: 3, end: 3 + minSegmentSeconds / 2)),
          isNull);
    });
  });

  group('setBounds (سحب أو كتابة)', () {
    final segs = [nonQuran(0, 2), nonQuran(2, 4), nonQuran(4, 6)];

    test('ما بيتخطى الجيران ولا بيتداخل', () {
      final e = setBounds(segs, 1, 1.0, 5.0, duration: 6);
      expect((e.segments[1].start, e.segments[1].end), (2.0, 4.0));
      for (var i = 0; i + 1 < e.segments.length; i++) {
        expect(e.segments[i].end, lessThanOrEqualTo(e.segments[i + 1].start));
      }
    });

    test('ما بينزل عن الحد الأدنى، ونهاية أصغر من البداية بتنصلح', () {
      final e = setBounds(segs, 1, 3.0, 2.5, duration: 6);
      expect(e.segments[1].end - e.segments[1].start,
          greaterThanOrEqualTo(minSegmentSeconds - 1e-9));
      expect(e.segments[1].start, 3.0);
    });

    test('تعديل دقيق بـ 0.1 ثانية بيضل زي ما هو', () {
      final e = setBounds(segs, 1, 2.3, 3.7, duration: 6);
      expect(e.segments[1].start, closeTo(2.3, 1e-9));
      expect(e.segments[1].end, closeTo(3.7, 1e-9));
      expect(e.mapping, [0, 1, 2]);
    });
  });

  group('نص المستخدم والتحويل', () {
    test('setUserText: نص = ظاهر وما عاد بده مراجعة؛ فاضي = null والشاشة نظيفة', () {
      final segs = [nonQuran(0, 2, review: true)];
      final a = setUserText(segs, 0, 'اللهم تقبّل');
      expect(a.segments.single.userText, 'اللهم تقبّل');
      expect(a.segments.single.isVisible, isTrue);
      expect(a.segments.single.needsReview, isFalse);
      final b = setUserText(a.segments, 0, '   ');
      expect(b.segments.single.userText, isNull);
      expect(b.segments.single.isVisible, isFalse);
    });

    test('convertToNonQuran: الآية بتصير مقطع لنص المستخدم بنفس الوقت، وجيرانها من نفس الآية بينبنوا من جديد', () {
      final segs = buildAyahReading(text, 2, 255, [(0.0, 4.0), (4.0, 8.0), (8.0, 12.0)]);
      final e = convertToNonQuran(text, segs, 2);
      expect(e.segments, hasLength(3));
      expect(e.segments[2].kind, SegmentKind.nonQuran);
      expect((e.segments[2].start, e.segments[2].end), (8.0, 12.0));
      expect([e.segments[0].part, e.segments[0].partCount], [1, 2]);
      expect(e.segments[1].showAyahNumber, isTrue);
      final withText = setUserText(e.segments, 2, 'دعاء');
      expect(withText.segments[2].isVisible, isTrue);
    });
  });

  group('بده مراجعة', () {
    test('confirmSegment بيأكّد كل أجزاء نفس التلاوة', () {
      final segs = buildAyahReading(text, 2, 255, [(0.0, 4.0), (4.0, 8.0)],
          needsReview: true, inferred: true);
      expect(segs.every((s) => s.needsReview), isTrue);
      final e = confirmSegment(segs, 1);
      expect(e.segments.every((s) => !s.needsReview && !s.inferred), isTrue);
    });

    test('nextNeedingReview بيلف من الأول وبيتجاهل الاستعاذة', () {
      final segs = [
        const RecitationSegment(
            start: 0, end: 1, kind: SegmentKind.istiadha, confidence: 0.1, needsReview: true),
        nonQuran(1, 2, review: true),
        nonQuran(2, 3),
        nonQuran(3, 4, review: true),
      ];
      expect(nextNeedingReview(segs), 1);
      expect(nextNeedingReview(segs, after: 1), 3);
      expect(nextNeedingReview(segs, after: 3), 1);
      expect(nextNeedingReview([nonQuran(0, 1)]), isNull);
      expect(nextNeedingReview(const []), isNull);
    });
  });

  test('segmentsSignature: ثابتة لنفس التحليل، ومختلفة لتحليل ثاني', () {
    final a = [nonQuran(0, 1), nonQuran(1, 2)];
    expect(segmentsSignature(a), segmentsSignature([...a]));
    expect(segmentsSignature(a), isNot(segmentsSignature([nonQuran(0, 1), nonQuran(1, 2.5)])));
    expect(segmentsSignature(a), isNot(segmentsSignature([nonQuran(0, 1)])));
  });

  test('سلسلة تعديلات (حذف، إضافة، تغيير آية): كل حجم خاص بيضل على نفس المقطع', () {
    var segs = <RecitationSegment>[
      for (var i = 0; i < 5; i++) nonQuran(i * 2.0, i * 2.0 + 1.5, user: 'م$i'),
    ];
    var scales = <int, Map<OverlayElement, double>>{
      0: {OverlayElement.ayah: 0.8},
      2: {OverlayElement.ayah: 1.2},
      4: {OverlayElement.ayah: 1.5},
    };
    void run(SegmentEdit e) {
      scales = e.remapScales(scales);
      segs = e.segments;
    }

    run(deleteSegment(text, segs, 1)); // م0 م2 م3 م4
    run(insertSegment(segs, buildUserTextSegment(start: 1.6, end: 1.9, userText: 'جديد'))!);
    run(changeAyah(text, segs, 2, 112, 1)); // م2 صار آية (نفس مكانه)
    final byLabel = <String, double>{
      for (final k in scales.keys)
        (segs[k].userText ?? segs[k].ref!): scales[k]![OverlayElement.ayah]!,
    };
    expect(byLabel, {'م0': 0.8, '112:1': 1.2, 'م4': 1.5});
  });
}
