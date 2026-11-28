// طلب أنس 2026-11-28: تقسيم الآية يدوياً على حدود كلمات (أو رجعها كاملة)،
// وشكل خاص لآية معينة (بيغلب على العام لهالآية بس، وبيوصل للتصدير).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quran_dub/editor/project_edit_store.dart';
import 'package:quran_dub/editor/segment_edits.dart';
import 'package:quran_dub/overlay/overlay_colors.dart';
import 'package:quran_dub/overlay/overlay_layout.dart';
import 'package:quran_dub/overlay/overlay_style.dart';
import 'package:quran_dub/pipeline/quran_text_source.dart';
import 'package:quran_dub/pipeline/recitation_segment.dart';
import 'package:quran_dub/pipeline/segment_builder.dart';

String _squash(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

void main() {
  late QuranTextSource text;
  setUpAll(() {
    text = QuranTextSource.fromSeedFile('assets/quran/quran_data.json.gz');
  });

  RecitationSegment nq(double a, double b) =>
      RecitationSegment(start: a, end: b, kind: SegmentKind.nonQuran, confidence: 0.2);

  group('تقسيم الآية على كلمات', () {
    test('كلمات الآية', () {
      final w = ayahWords(text, 2, 255);
      expect(w.length, greaterThan(40));
      expect(_squash(w.join(' ')), _squash(text.ayah(2, 255)!.uthmani));
      expect(ayahWords(text, 999, 1), isEmpty);
    });

    test('حدود على كلمات بالضبط: كل سطر = الكلمات المختارة، والرقم مع الأخير', () {
      final w = ayahWords(text, 2, 255);
      final r = buildAyahReadingAtWords(text, 2, 255, [5, 12],
          start: 10, end: 40);
      expect(r, hasLength(3));
      expect(_squash(r[0].text), _squash(w.sublist(0, 5).join(' ')));
      expect(_squash(r[1].text), _squash(w.sublist(5, 12).join(' ')));
      expect(_squash(r[2].text), _squash(w.sublist(12).join(' ')));
      expect([for (final s in r) s.showAyahNumber], [false, false, true]);
      expect([for (final s in r) s.part], [1, 2, 3]);
      expect(r.first.start, 10);
      expect(r.last.end, 40);
      for (var i = 0; i + 1 < r.length; i++) {
        expect(r[i].end, closeTo(r[i + 1].start, 1e-9));
        expect(r[i].end, greaterThan(r[i].start));
      }
    });

    test('حدود غلط بتنشال (0، آخر كلمة، تكرار)', () {
      final n = ayahWords(text, 50, 28).length;
      final r = buildAyahReadingAtWords(text, 50, 28, [0, 3, 3, n, n + 4], start: 0, end: 4);
      expect(r, hasLength(2));
    });

    test('تقسيم مقطع آية كاملة لثلاث أسطر وبعدين رجوع لآية كاملة', () {
      final base = [
        nq(0, 1),
        ...buildAyahReading(text, 2, 255, [(1.0, 20.0)]),
        nq(20, 21),
      ];
      final e = splitAyahAtWords(text, base, 1, [4, 9]);
      expect(e.segments, hasLength(5));
      expect(e.focus, 1);
      expect(wordCutsAt(e.segments, 1), [4, 9]);
      expect(wordCutsAt(e.segments, 3), [4, 9]);
      expect(e.mapping, [0, 1, 4]);
      expect(e.segments[1].start, 1.0);
      expect(e.segments[3].end, 20.0);
      expect(_squash(e.segments.sublist(1, 4).map((s) => s.text).join(' ')),
          _squash(text.ayah(2, 255)!.uthmani));

      // نفس عدد الأجزاء: الأوقات بتضل.
      final shrunk = (e.segments[1].start + e.segments[1].end) / 2;
      final moved = setBounds(e.segments, 1, 1.0, shrunk, duration: 30).segments;
      final e2 = splitAyahAtWords(text, moved, 2, [6, 9]);
      expect(e2.segments[1].end, closeTo(shrunk, 1e-9));
      expect(e2.segments[2].start, moved[2].start);
      expect(wordCutsAt(e2.segments, 1), [6, 9]);

      // آية كاملة.
      final whole = splitAyahAtWords(text, e2.segments, 3, const []);
      expect(whole.segments, hasLength(3));
      expect(whole.segments[1].kind, SegmentKind.fullAyah);
      expect(whole.segments[1].showAyahNumber, isTrue);
      expect((whole.segments[1].start, whole.segments[1].end), (1.0, 20.0));
      expect(whole.mapping, [0, 1, 1, 1, 2]);
    });

    test('مقطع مش آية: بدون تغيير', () {
      final base = [nq(0, 1)];
      final e = splitAyahAtWords(text, base, 0, [2]);
      expect(identical(e.segments, base), isTrue);
    });
  });

  group('شكل خاص لآية', () {
    test('forSegment: الشكل الخاص بيغلب للآية بس، والقارئ من العام', () {
      const own = OverlayStyle(color: OverlayTextColor.black, shadowStrength: 1);
      const global = OverlayStyle(reciterName: 'العفاسي');
      final s = global.copyWith(segmentStyles: {2: own});
      expect(s.forSegment(2).color, OverlayTextColor.black);
      expect(s.forSegment(2).shadowStrength, 1);
      expect(s.forSegment(2).reciterName, 'العفاسي');
      expect(s.forSegment(1).color, global.color);
      expect(s.hasOwnStyle(2), isTrue);
      expect(s.forSegment(2).segmentStyles, isEmpty);
    });

    test('الحجم الخاص فوق الشكل الخاص، والشريط بيغطي المواقع الخاصة', () {
      final moved = OverlayLayout.reference.update(
          OverlayElement.ayah, (p) => p.copyWith(anchor: const ElementAnchor(0.5, 0.1)));
      final s = const OverlayStyle().copyWith(
        segmentStyles: {0: OverlayStyle(layout: moved)},
        segmentScales: {0: {OverlayElement.ayah: 1.4}},
      );
      expect(s.forSegment(0).layout[OverlayElement.ayah].scale, closeTo(1.4, 1e-9));
      expect(s.forSegment(0).layout[OverlayElement.ayah].anchor, isNotNull);
      expect(s.allLayouts.length, 2);
    });

    test('JSON (الخطة) بيحفظ الشكل الخاص، والقالب لأ', () {
      final s = const OverlayStyle().copyWith(
          segmentStyles: {3: const OverlayStyle(color: OverlayTextColor.black)});
      final back = OverlayStyle.fromJson(s.toJson());
      expect(back, s);
      expect(back.forSegment(3).color, OverlayTextColor.black);
      expect(s.toJson(forTemplate: true).containsKey('segmentStyles'), isFalse);
    });

    test('إعادة الربط بعد التقسيم بتحافظ على الشكل الخاص', () {
      final base = [nq(0, 1), ...buildAyahReading(text, 2, 255, [(1.0, 20.0)]), nq(20, 21)];
      final e = splitAyahAtWords(text, base, 1, [4]);
      final m = e.remapMap({1: 'خاص', 2: 'بعدها'});
      expect(m, {1: 'خاص', 4: 'بعدها'});
    });

    test('مخزن التعديلات بيحفظ ويرجّع الشكل الخاص', () async {
      final dir = await Directory.systemTemp.createTemp('seg_styles');
      addTearDown(() => dir.delete(recursive: true));
      final store = ProjectEditStore(File('${dir.path}/p.json'));
      final segs = [nq(0, 1), nq(1, 2)];
      await store.save(segs,
          segmentStyles: {1: const OverlayStyle(color: OverlayTextColor.black, shadowStrength: 0.5)});
      final back = await store.loadEdits();
      expect(back!.segmentStyles[1]!.color, OverlayTextColor.black);
      expect(back.segmentStyles[1]!.shadowStrength, 0.5);
    });
  });
}
