import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quran_dub/overlay/ayah_font.dart';
import 'package:quran_dub/overlay/overlay_frame.dart';
import 'package:quran_dub/overlay/overlay_timeline.dart';
import 'package:quran_dub/pipeline/recitation_segment.dart';

RecitationSegment seg({
  bool number = true,
  SegmentKind kind = SegmentKind.fullAyah,
  String text = 'قَالَ قَرِينُهُۥ رَبَّنَا مَآ أَطۡغَيۡتُهُۥ',
  String split = 'جزء من التفسير',
  String full = 'التفسير كامل',
  String? userText,
}) =>
    RecitationSegment(
      start: 0,
      end: 5,
      kind: kind,
      surah: 50,
      ayah: 27,
      text: text,
      showAyahNumber: number,
      tafsir: split,
      tafsirSplit: split,
      tafsirFull: full,
      userText: userText,
      confidence: 1,
    );

OverlayCue cue(RecitationSegment s, [double opacity = 1]) =>
    OverlayCue(OverlayItem(s, 0, 0, 5), opacity);

Future<void> pump(WidgetTester tester, Size size, OverlayCue? c,
    {TafsirMode mode = TafsirMode.split,
    AyahFont font = AyahFont.kfgqpcHafs,
    OverlayTextColor color = OverlayTextColor.white,
    bool shadow = false}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Align(
      alignment: Alignment.topLeft,
      child: AyahOverlayFrame(
        videoWidth: size.width.toInt(),
        videoHeight: size.height.toInt(),
        cue: c,
        tafsirMode: mode,
        font: font,
        color: color,
        shadow: shadow,
      ),
    ),
  ));
}

void main() {
  const ayahKey = ValueKey('overlay-ayah');
  const tafsirKey = ValueKey('overlay-tafsir');
  const numberKey = ValueKey('overlay-ayah-number');

  testWidgets('first line at 61% of the height on portrait/landscape/square',
      (tester) async {
    for (final size in const [Size(1080, 1920), Size(1920, 1080), Size(1080, 1080)]) {
      await pump(tester, size, cue(seg()));
      final top = tester.getTopLeft(find.byKey(ayahKey)).dy;
      expect(top, closeTo(size.height * 0.61, 1.5), reason: '$size');
      // التفسير تحت الآية مباشرة.
      final ayahBottom = tester.getBottomLeft(find.byKey(ayahKey)).dy;
      final tafsirTop = tester.getTopLeft(find.byKey(tafsirKey)).dy;
      expect(tafsirTop, greaterThanOrEqualTo(ayahBottom - 0.5), reason: '$size');
      expect(tafsirTop - ayahBottom, lessThan(size.height * 0.05), reason: '$size');
      // الكتلة جوا الفيديو.
      expect(tester.getBottomLeft(find.byKey(tafsirKey)).dy,
          lessThanOrEqualTo(size.height + 0.5), reason: '$size');
    }
  });

  testWidgets('ayah number circle only with the last part', (tester) async {
    await pump(tester, const Size(1080, 1920), cue(seg(number: true)));
    expect(find.byKey(numberKey), findsOneWidget);
    expect(find.text('٢٧'), findsOneWidget);
    await pump(tester, const Size(1080, 1920), cue(seg(number: false)));
    expect(find.byKey(numberKey), findsNothing);
  });

  testWidgets('no box or background behind the text', (tester) async {
    await pump(tester, const Size(1080, 1920), cue(seg()));
    final frame = find.byType(AyahOverlayFrame);
    // ما في ColoredBox/DecoratedBox إلا دائرة الرقم (حدها بس، بدون تعبئة).
    final boxes = tester.widgetList<DecoratedBox>(
        find.descendant(of: frame, matching: find.byType(DecoratedBox)));
    for (final b in boxes) {
      final d = b.decoration as BoxDecoration;
      expect(d.color, isNull);
      expect(d.shape, BoxShape.circle);
    }
    expect(find.descendant(of: frame, matching: find.byType(ColoredBox)),
        findsNothing);
  });

  testWidgets('opacity follows the cue, null cue shows nothing', (tester) async {
    await pump(tester, const Size(1080, 1920), cue(seg(), 0.5));
    final o = tester.widget<Opacity>(find.descendant(
        of: find.byType(AyahOverlayFrame), matching: find.byType(Opacity)));
    expect(o.opacity, closeTo(0.5, 1e-9));
    await pump(tester, const Size(1080, 1920), null);
    expect(find.byKey(ayahKey), findsNothing);
    expect(find.byKey(tafsirKey), findsNothing);
    await pump(tester, const Size(1080, 1920), cue(seg(), 0.0));
    expect(find.byKey(ayahKey), findsNothing);
  });

  testWidgets('tafsir mode switches between split and full', (tester) async {
    await pump(tester, const Size(1080, 1920), cue(seg()));
    expect(find.text('جزء من التفسير.'), findsOneWidget);
    await pump(tester, const Size(1080, 1920), cue(seg()),
        mode: TafsirMode.fullUnderEachPart);
    expect(find.text('التفسير كامل.'), findsOneWidget);
    expect(find.text('جزء من التفسير.'), findsNothing);
  });

  testWidgets('basmala: ayah line without tafsir; non-Quran empty or user text',
      (tester) async {
    await pump(tester, const Size(1080, 1920),
        cue(seg(kind: SegmentKind.basmala, number: false)));
    expect(find.byKey(ayahKey), findsOneWidget);
    expect(find.byKey(tafsirKey), findsNothing);

    await pump(tester, const Size(1080, 1920),
        cue(seg(kind: SegmentKind.nonQuran, text: '', number: false)));
    expect(find.byKey(ayahKey), findsNothing);
    expect(find.byKey(tafsirKey), findsNothing);

    await pump(tester, const Size(1080, 1920),
        cue(seg(kind: SegmentKind.nonQuran, text: '', number: false, userText: 'مرحبا')));
    expect(find.text('مرحبا'), findsOneWidget);
  });

  testWidgets('very long block is scaled down to stay inside the video',
      (tester) async {
    final long = List.filled(60, 'ٱلۡحَمۡدُ لِلَّهِ رَبِّ ٱلۡعَٰلَمِينَ').join(' ');
    const size = Size(1080, 1920);
    await pump(tester, size, cue(seg(text: long, split: long, full: long)));
    final bottom = tester.getBottomLeft(find.byKey(tafsirKey)).dy;
    expect(bottom, lessThanOrEqualTo(size.height * 0.96 + 1.0));
    expect(tester.getTopLeft(find.byKey(ayahKey)).dy,
        closeTo(size.height * 0.61, 1.5));
  });

  testWidgets('both fonts render (Amiri Quran option)', (tester) async {
    await pump(tester, const Size(1080, 1920), cue(seg()),
        font: AyahFont.amiriQuran);
    expect(find.byKey(ayahKey), findsOneWidget);
  });

  // يوم 7 (طلب أنس): النص الأبيض ما بيّن فوق خلفية فاتحة.
  testWidgets('text color option: white with gold brackets, or all black',
      (tester) async {
    for (final c in OverlayTextColor.values) {
      await pump(tester, const Size(1080, 1920), cue(seg()), color: c);
      final ayah = tester.widget<Text>(find.byKey(ayahKey)).textSpan! as TextSpan;
      final open = ayah.children!.first as TextSpan;
      final close = ayah.children!.last as TextSpan;
      final tafsir = tester.widget<Text>(find.byKey(tafsirKey));
      final circle = tester.widget<Container>(find.byKey(numberKey)).decoration!
          as BoxDecoration;
      final txt = c == OverlayTextColor.white ? overlayWhite : overlayBlack;
      final br = c == OverlayTextColor.white ? overlayGold : overlayBlack;
      expect(ayah.style!.color, txt, reason: c.name);
      expect(open.style!.color, br, reason: c.name);
      expect(close.style!.color, br, reason: c.name);
      expect(tafsir.style!.color, txt, reason: c.name);
      expect((circle.border! as Border).top.color, txt, reason: c.name);
    }
    expect(OverlayTextColor.defaultColor, OverlayTextColor.white);
  });

  test('auto color: black over bright backgrounds, white otherwise', () {
    expect(OverlayTextColor.forBackground(0.15, 0.02), OverlayTextColor.white);
    expect(OverlayTextColor.forBackground(0.5, 0.3), OverlayTextColor.white);
    expect(OverlayTextColor.forBackground(0.85, 0.95), OverlayTextColor.black);
    expect(OverlayTextColor.forBackground(0.45, 0.6), OverlayTextColor.black);
  });

  // يوم 7 (طلب أنس): ظل اختياري بلون عكس النص.
  testWidgets('optional shadow in the opposite color (off by default)',
      (tester) async {
    await pump(tester, const Size(1080, 1920), cue(seg()));
    var ayah = tester.widget<Text>(find.byKey(ayahKey)).textSpan! as TextSpan;
    expect(ayah.style!.shadows, isNull);
    expect(tester.widget<Text>(find.byKey(tafsirKey)).style!.shadows, isNull);

    for (final c in OverlayTextColor.values) {
      await pump(tester, const Size(1080, 1920), cue(seg()),
          color: c, shadow: true);
      ayah = tester.widget<Text>(find.byKey(ayahKey)).textSpan! as TextSpan;
      final opposite =
          c == OverlayTextColor.white ? overlayBlack : overlayWhite;
      final shadows = ayah.style!.shadows!;
      expect(shadows, isNotEmpty);
      for (final sh in shadows) {
        expect(sh.color.withValues(alpha: 1), opposite, reason: c.name);
      }
      final open = ayah.children!.first as TextSpan;
      expect(open.style!.shadows, isNotEmpty); // الأقواس كمان
      final t = tester.widget<Text>(find.byKey(tafsirKey));
      expect(t.style!.shadows!.first.color.withValues(alpha: 1), opposite);
      // ولسا ما في خلفية/صندوق (الظل بس).
      expect(find.descendant(
              of: find.byType(AyahOverlayFrame), matching: find.byType(ColoredBox)),
          findsNothing);
    }
  });
}
