// هندسة الخط الزمني: تحويل ثانية↔بكسل، حدود السحب، وفحص التداخل (يوم 10).
import 'package:flutter_test/flutter_test.dart';
import 'package:quran_dub/editor/timeline_geometry.dart';

void main() {
  group('TimelineGeometry', () {
    test('تحويل ثانية↔بكسل ورجوعها لنفس القيمة', () {
      const g = TimelineGeometry(durationSeconds: 60, pixelsPerSecond: 40);
      expect(g.xOfSeconds(2.5), 100);
      expect(g.secondsOfX(100), closeTo(2.5, 1e-9));
      expect(g.totalWidth, 2400);
    });

    test('secondsOfX بتنقص ضمن المدة', () {
      const g = TimelineGeometry(durationSeconds: 10, pixelsPerSecond: 50);
      expect(g.secondsOfX(-20), 0);
      expect(g.secondsOfX(10000), 10);
    });

    test('التكبير محصور بحدود معقولة', () {
      const g = TimelineGeometry(durationSeconds: 10, pixelsPerSecond: 40);
      final zoomedIn = g.zoomed(1000);
      expect(zoomedIn.pixelsPerSecond, TimelineGeometry.maxPixelsPerSecond);
      final zoomedOut = g.zoomed(0.0001);
      expect(zoomedOut.pixelsPerSecond, TimelineGeometry.minPixelsPerSecond);
    });
  });

  group('clampSegmentDrag', () {
    final segs = [(0.0, 2.0), (2.0, 4.0), (4.0, 6.0)];

    test('سحب عادي جوا الحدود بيضل كما هو', () {
      final r = clampSegmentDrag(
          segments: segs, index: 1, newStart: 2.3, newEnd: 3.7, duration: 10);
      expect(r.start, closeTo(2.3, 1e-9));
      expect(r.end, closeTo(3.7, 1e-9));
    });

    test('ما بيتخطى جاره السابق', () {
      final r = clampSegmentDrag(
          segments: segs, index: 1, newStart: 1.0, newEnd: 3.7, duration: 10);
      expect(r.start, 2.0); // أقل من نهاية الجار السابق ممنوع
    });

    test('ما بيتخطى جاره الجاي', () {
      final r = clampSegmentDrag(
          segments: segs, index: 1, newStart: 2.3, newEnd: 5.0, duration: 10);
      expect(r.end, 4.0);
    });

    test('أول مقطع: حده الأدنى صفر، آخر مقطع: حده الأعلى مدة الفيديو', () {
      final r0 = clampSegmentDrag(
          segments: segs, index: 0, newStart: -3, newEnd: 1.5, duration: 10);
      expect(r0.start, 0);
      final rLast = clampSegmentDrag(
          segments: segs, index: 2, newStart: 4.5, newEnd: 50, duration: 10);
      expect(rLast.end, 10);
    });

    test('ما ينزل عن الحد الأدنى للطول', () {
      final r = clampSegmentDrag(
          segments: segs,
          index: 1,
          newStart: 2.0,
          newEnd: 2.05,
          minLength: 0.3,
          duration: 10);
      expect(r.end - r.start, closeTo(0.3, 1e-9));
    });

    test('جيران قريبين كتير: ما بينهار (end أبداً أصغر من start)', () {
      final tight = [(0.0, 1.0), (1.05, 2.0)];
      final r = clampSegmentDrag(
          segments: tight,
          index: 0,
          newStart: 0.5,
          newEnd: 1.2,
          minLength: 0.3,
          duration: 10);
      expect(r.end, greaterThanOrEqualTo(r.start));
      expect(r.end - r.start, lessThanOrEqualTo(1.05));
    });
  });

  group('rangeOverlapsExisting / nextFreeRange', () {
    test('تقاطع واضح', () {
      final existing = [(0.0, 2.0), (5.0, 7.0)];
      expect(rangeOverlapsExisting(existing, 1.0, 3.0), isTrue);
      expect(rangeOverlapsExisting(existing, 2.0, 5.0), isFalse); // متلاصقين بس بدون تقاطع
      expect(rangeOverlapsExisting(existing, 6.0, 6.5), isTrue);
    });

    test('أقرب نطاق فاضي بعد وقت معيّن', () {
      final existing = [(0.0, 2.0), (2.5, 4.0)];
      final r = nextFreeRange(existing, afterSeconds: 0, duration: 20, length: 2);
      // أول فجوة فاضية فعلاً بطول 2 ثانية هي بعد نهاية آخر مقطع (4.0).
      expect(r, (4.0, 6.0));
    });

    test('ما في مكان قبل نهاية الفيديو', () {
      final existing = [(0.0, 9.5)];
      final r = nextFreeRange(existing, afterSeconds: 0, duration: 10, length: 2);
      expect(r, isNull);
    });
  });

  group('snapSeconds (التصاق الحد بالجار)', () {
    test('قريب = بيلتصق وبيرجّع رقم الهدف، بعيد = نفس القيمة', () {
      expect(snapSeconds(4.03, [4.0, 9.0], threshold: 0.1), (4.0, 0));
      expect(snapSeconds(8.95, [4.0, 9.0], threshold: 0.1), (9.0, 1));
      expect(snapSeconds(6.0, [4.0, 9.0], threshold: 0.1), (6.0, null));
      expect(snapSeconds(6.0, const [], threshold: 0.1), (6.0, null));
    });
  });

  group('حقول البداية/النهاية: parseSecondsInput / formatSecondsInput', () {
    test('أرقام عادية وعربية-هندية وفارسية، وفاصلة عشرية عربية أو فاصلة', () {
      expect(parseSecondsInput('12.5'), 12.5);
      expect(parseSecondsInput(' ١٢٫٥ '), 12.5);
      expect(parseSecondsInput('۳٫۲۵'), 3.25);
      expect(parseSecondsInput('3,25'), 3.25);
      expect(parseSecondsInput('7'), 7.0);
    });

    test('دقائق:ثواني', () {
      expect(parseSecondsInput('1:05.5'), 65.5);
      expect(parseSecondsInput('٢:٠٠'), 120.0);
      expect(parseSecondsInput('1:75'), isNull);
    });

    test('غلط = null (الحقل بيرجع لقيمته)', () {
      for (final bad in ['', '  ', 'abc', '-1', '1:2:3', '1.2.3']) {
        expect(parseSecondsInput(bad), isNull, reason: bad);
      }
    });

    test('العرض بخانتين (أدق من 0.1) والرجوع لنفس القيمة', () {
      expect(formatSecondsInput(3.0), '3.00');
      expect(formatSecondsInput(12.346), '12.35');
      for (final v in [0.0, 0.1, 2.3, 59.99, 125.4]) {
        expect(parseSecondsInput(formatSecondsInput(v)), closeTo(v, 0.005));
      }
    });

    test('formatClock للمسطرة', () {
      expect(formatClock(7.4), '0:07.4');
      expect(formatClock(65.4), '1:05.4');
      expect(formatClock(-3), '0:00.0');
    });
  });

  group('تحويل ثانية ↔ موضع مع التكبير', () {
    test('نفس الثانية بتطلع بنفس النسبة من عرض الخط بكل مستويات التكبير', () {
      for (final pps in [10.0, 60.0, 400.0]) {
        final g = TimelineGeometry(durationSeconds: 30, pixelsPerSecond: pps);
        expect(g.xOfSeconds(12) / g.totalWidth, closeTo(0.4, 1e-9));
        expect(g.secondsOfX(g.xOfSeconds(12.34)), closeTo(12.34, 1e-9));
      }
    });
  });
}
