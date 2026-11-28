// الخط الزمني الجديد زي CapCut: السهم ثابت بالنص والخط بيتحرّك تحته (السحب =
// تنقّل)، الكبسة على آية بتحددها، سحب المقبض بيبلّغ ثواني، والمسطرة.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quran_dub/pipeline/recitation_segment.dart';
import 'package:quran_dub/screens/widgets/editor_timeline.dart';

RecitationSegment _seg(double a, double b) => RecitationSegment(
    start: a, end: b, kind: SegmentKind.nonQuran, confidence: 1, userText: 'نص');

void main() {
  test('خطوة المسطرة حسب التكبير', () {
    expect(rulerStep(200), 0.5);
    expect(rulerStep(60), 2.0);
    expect(rulerStep(10), 10.0);
    expect(rulerStep(0.1), 300.0);
    expect(rulerLabel(5), '00:05');
    expect(rulerLabel(65), '01:05');
    expect(rulerLabel(3725), '1:02:05');
  });

  Future<
      ({
        ValueNotifier<double> playhead,
        List<double> scrubs,
        List<int?> selects,
        List<(int, bool, double)> drags,
        List<String> events,
      })> pump(WidgetTester t, {int? selected, List<RecitationSegment>? segs}) async {
    final playhead = ValueNotifier<double>(5);
    final scrubs = <double>[];
    final selects = <int?>[];
    final drags = <(int, bool, double)>[];
    final events = <String>[];
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 400,
            child: EditorTimeline(
              segments: segs ?? [_seg(1, 4), _seg(4.5, 7)],
              duration: 20,
              peaks: null,
              thumbs: const [],
              playhead: playhead,
              selectedIndex: selected,
              onScrubStart: () => events.add('start'),
              onScrub: (s) {
                scrubs.add(s);
                playhead.value = s;
              },
              onScrubEnd: () => events.add('end'),
              onSelect: selects.add,
              onHandleStart: (i, s) => events.add('h$i$s'),
              onDragHandle: (i, s, v) => drags.add((i, s, v)),
              onHandleEnd: () => events.add('hend'),
              onAdd: () => events.add('add'),
            ),
          ),
        ),
      ),
    ));
    await t.pump();
    return (playhead: playhead, scrubs: scrubs, selects: selects, drags: drags, events: events);
  }

  testWidgets('السحب لليسار = لقدّام بالوقت (السهم ثابت بالنص)', (t) async {
    final r = await pump(t);
    final center = t.getCenter(find.byType(EditorTimeline));
    final g = await t.startGesture(center);
    await g.moveBy(const Offset(-40, 0));
    await g.moveBy(const Offset(-40, 0));
    await g.up();
    await t.pumpAndSettle();
    expect(r.events.first, 'start');
    expect(r.events, contains('end'));
    expect(r.scrubs, isNotEmpty);
    expect(r.scrubs.last, greaterThan(5));
  });

  testWidgets('الكبسة على آية تحت السهم بتحددها', (t) async {
    // السهم عند 5ث، والمقطع الثاني من 4.5 لـ 7 بيمرق تحته.
    final r = await pump(t);
    final box = t.getTopLeft(find.byType(EditorTimeline));
    await t.tapAt(box + const Offset(200, TimelineMetrics.ayahTop + TimelineMetrics.ayahH / 2));
    await t.pump();
    expect(r.selects, [1]);
  });

  testWidgets('سحب مقبض النهاية بيبلّغ ثواني أكبر', (t) async {
    final r = await pump(t, selected: 1);
    final box = t.getTopLeft(find.byType(EditorTimeline));
    // التكبير الأولي: ~7 ثواني بعرض 400 → pps = 400/7×0.9. نهاية المقطع (7ث)
    // يمين السهم (5ث) بثانيتين، والمقبض مزاح 6px لبرا.
    const pps = 400 / 7 * 0.9;
    const x = 200 + 2 * pps + 6;
    final g = await t.startGesture(box + const Offset(x, TimelineMetrics.ayahTop + 10));
    await g.moveBy(const Offset(30, 0));
    await g.moveBy(const Offset(10, 0));
    await g.up();
    await t.pump();
    expect(r.events, contains('h1false'));
    expect(r.drags, isNotEmpty);
    expect(r.drags.last.$1, 1);
    expect(r.drags.last.$2, isFalse);
    expect(r.drags.last.$3, greaterThan(7));
    expect(r.events, contains('hend'));
  });

  testWidgets('خط زمني فاضي (بدون آيات) بيرسم بدون أخطاء', (t) async {
    await pump(t, segs: const []);
    expect(find.byType(EditorTimeline), findsOneWidget);
  });
}
