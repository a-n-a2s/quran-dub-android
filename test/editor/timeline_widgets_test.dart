// الخط الزمني ولوحة تفاصيل المقطع (يوم 10): الحقول متزامنة مع القيمة (لما
// المقطع ينسحب بالخط الزمني الحقل بيتحدّث)، و±0.1 والكتابة بيبعتوا القيمة
// الصح، والكبسة على كتلة بتحددها، وسحب المقبض بيبلّغ ثواني.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quran_dub/editor/segment_edits.dart';
import 'package:quran_dub/editor/waveform.dart';
import 'package:quran_dub/overlay/overlay_layout.dart';
import 'package:quran_dub/pipeline/recitation_segment.dart';
import 'package:quran_dub/screens/widgets/segment_detail_panel.dart';
import 'package:quran_dub/screens/widgets/segment_timeline_view.dart';

RecitationSegment _seg(double a, double b, {bool review = false}) => RecitationSegment(
    start: a, end: b, kind: SegmentKind.nonQuran, confidence: 1,
    userText: 'نص', needsReview: review);

void main() {
  testWidgets('لوحة التفاصيل: ±0.1 والكتابة بيبعتوا القيمة، والحقل بيتبع التعديل من برا', (t) async {
    var segs = [_seg(1, 3), _seg(3, 5)];
    final calls = <(double, double)>[];
    final playhead = ValueNotifier<double>(2.2);
    late StateSetter rebuild;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: StatefulBuilder(builder: (context, set) {
            rebuild = set;
            return SegmentDetailPanel(
              segment: segs[0],
              index: 0,
              count: segs.length,
              playhead: playhead,
              surahName: (n) => 'سورة $n',
              scales: const {OverlayElement.ayah: 1.0},
              hasOwnScales: false,
              onBounds: (a, b) {
                calls.add((a, b));
                set(() => segs = setBounds(segs, 0, a, b, duration: 10).segments);
              },
              onChangeAyah: () {},
              onConvertToNonQuran: () {},
              onUserText: (_) {},
              onConfirm: () {},
              onDelete: () {},
              onScale: (_, __) {},
              onResetScales: () {},
              onPlay: () {},
              onStep: (_) {},
              onClose: () {},
            );
          }),
        ),
      ),
    ));
    final startField = find.byKey(const ValueKey('time-start'));
    final endField = find.byKey(const ValueKey('time-end'));
    expect(t.widget<TextField>(startField).controller!.text, '1.00');
    expect(t.widget<TextField>(endField).controller!.text, '3.00');

    await t.tap(find.text('+0.1').first); // البداية
    await t.pump();
    expect(calls.last.$1, closeTo(1.1, 1e-9));
    expect(t.widget<TextField>(startField).controller!.text, '1.10');

    // "من هون": البداية = موقع التشغيل.
    await t.tap(find.text('من هون'));
    await t.pump();
    expect(calls.last, (2.2, 3.0));

    // كتابة بأرقام عربية.
    await t.enterText(endField, '٢٫٩');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();
    expect(calls.last.$2, closeTo(2.9, 1e-9));

    // نهاية بعد الجار → مقصوصة لحد بدايته، والحقل بيعرض المقصوص.
    await t.enterText(endField, '4.5');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();
    expect(segs[0].end, 3.0);
    expect(t.widget<TextField>(endField).controller!.text, '3.00');

    // تعديل من برا (زي سحب المقبض بالخط الزمني) → الحقل بيتحدّث.
    rebuild(() => segs = setBounds(segs, 0, 1.5, 2.75, duration: 10).segments);
    await t.pump();
    expect(t.widget<TextField>(startField).controller!.text, '1.50');
    expect(t.widget<TextField>(endField).controller!.text, '2.75');
  });

  testWidgets('الخط الزمني: كبسة على كتلة بتحددها، وسحب المقبض بيبلّغ ثواني', (t) async {
    final segs = [_seg(1, 3), _seg(4, 6, review: true)];
    int? selected;
    final drags = <(int, bool, double)>[];
    late StateSetter set;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(builder: (context, s) {
          set = s;
          return SegmentTimelineView(
            segments: segs,
            duration: 10,
            peaks: WaveformPeaks.empty,
            playhead: ValueNotifier(0),
            selectedIndex: selected,
            onSeek: (_) {},
            onSelect: (i) => s(() => selected = i),
            onDragHandle: (i, isStart, v) => drags.add((i, isStart, v)),
          );
        }),
      ),
    ));
    expect(find.text('بده مراجعة'), findsWidgets); // المقطع الثاني مميّز
    await t.tap(find.text('نص').first);
    await t.pump();
    expect(selected, 0);
    set(() {});
    await t.pump();
    final endHandle = find.byKey(const ValueKey('handle-0-e'));
    expect(endHandle, findsOneWidget);
    await t.drag(endHandle, const Offset(60, 0));
    await t.pump();
    expect(drags, isNotEmpty);
    expect(drags.last.$1, 0);
    expect(drags.last.$2, isFalse);
    // 60px بتكبير 60px/ثانية ≈ ثانية وحدة بعد النهاية (3) — قبل حدود الجار.
    expect(drags.last.$3, greaterThan(3.5));
  });
}
