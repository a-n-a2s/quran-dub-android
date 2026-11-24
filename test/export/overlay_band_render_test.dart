// صور النص للتصدير = نفس إطار المعاينة بالبكسل (يوم 8). بالخطوط الحقيقية
// (KFGQPC/أميري من assets/fonts)، مش خط الاختبار.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quran_dub/export/export_plan.dart';
import 'package:quran_dub/export/overlay_renderer.dart';
import 'package:quran_dub/overlay/ayah_font.dart';
import 'package:quran_dub/overlay/overlay_colors.dart';
import 'package:quran_dub/overlay/overlay_frame.dart';
import 'package:quran_dub/overlay/overlay_layout.dart';
import 'package:quran_dub/overlay/overlay_metrics.dart';
import 'package:quran_dub/overlay/overlay_style.dart';
import 'package:quran_dub/overlay/overlay_timeline.dart';
import 'package:quran_dub/pipeline/recitation_segment.dart';

import 'fixtures.dart';

Future<void> loadFont(String family, String path) async {
  final bytes = File(path).readAsBytesSync();
  final loader = FontLoader(family)
    ..addFont(Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)));
  await loader.load();
}

Future<Uint8List> capture(WidgetTester tester, GlobalKey key,
    {ui.ImageByteFormat format = ui.ImageByteFormat.rawRgba}) async {
  final ro = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final bytes = await tester.runAsync(() async {
    final img = await ro.toImage(pixelRatio: 1);
    final d = await img.toByteData(format: format);
    img.dispose();
    return d!.buffer.asUint8List();
  });
  return bytes!;
}

const surahNames = <int, String>{50: 'سُوْرَةُ ق', 2: 'سُوْرَةُ البَقَرَة'};

OverlayStyle shadowStyle(double s, {OverlayTextColor c = OverlayTextColor.white}) =>
    OverlayStyle(color: c, shadowStrength: s);

/// layout مع سحب/تكبير/اسم سورة وقارئ (أصعب حالة للشريط).
OverlayLayout busyLayout() {
  var l = OverlayLayout.reference;
  l = l.update(OverlayElement.surahRef, (p) => p.copyWith(enabled: true));
  l = l.update(OverlayElement.reciter, (p) => p.copyWith(enabled: true));
  l = l.update(OverlayElement.ayah,
      (p) => p.copyWith(scale: 1.4, anchor: const ElementAnchor(0.5, 0.12)));
  l = l.update(OverlayElement.tafsir,
      (p) => p.copyWith(anchor: const ElementAnchor(0.5, 0.80)));
  return l;
}

OverlayLayout moved(OverlayElement e, double cx, double top, {double scale = 1}) =>
    OverlayLayout.reference
        .update(e, (p) => p.copyWith(anchor: ElementAnchor(cx, top), scale: scale));

void main() {
  setUpAll(() async {
    await loadFont('KFGQPC Hafs', 'assets/fonts/KFGQPC_HafsUthmanic_v18.ttf');
    await loadFont('Amiri Quran', 'assets/fonts/AmiriQuran.ttf');
    await loadFont('Amiri', 'assets/fonts/Amiri-Regular.ttf');
  });

  final styles = <String, OverlayStyle>{
    'أبيض': const OverlayStyle(),
    'أسود + ظل 70%': shadowStyle(0.7, c: OverlayTextColor.black),
    'أبيض + ظل 100%': shadowStyle(1.0),
    'أسود + ظل 100%': shadowStyle(1.0, c: OverlayTextColor.black),
    'أبيض + ظل 30%': shadowStyle(0.3),
    'أبيض + ظل، أميري، كامل تحت كل جزء': const OverlayStyle(
        shadowStrength: 0.7,
        font: AyahFont.amiriQuran,
        tafsirFont: TafsirFont.amiriQuran,
        tafsirMode: TafsirMode.fullUnderEachPart),
    'خلفية صندوق 90% + ظل 100%': OverlayStyle(
        shadowStrength: 1.0,
        background:
            const OverlayBackground(mode: OverlayBackgroundMode.box, opacity: 0.9)),
    'شريط شفاف 45%، أسود': OverlayStyle(
        color: OverlayTextColor.black,
        background:
            const OverlayBackground(mode: OverlayBackgroundMode.bar, opacity: 0.45)),
    'اسم السورة + القارئ + آية 140% مسحوبة لفوق + تفسير تحت + ظل 100%':
        OverlayStyle(
            shadowStrength: 1.0,
            reciterName: 'الشيخ محمد',
            layout: busyLayout(),
            background: const OverlayBackground(
                mode: OverlayBackgroundMode.box, opacity: 0.6)),
    'آية مسحوبة لفوق (12%) + ظل 100%': OverlayStyle(
        shadowStrength: 1.0, layout: moved(OverlayElement.ayah, 0.5, 0.12)),
    'آية مسحوبة قرب الأسفل (90%) أسود': OverlayStyle(
        color: OverlayTextColor.black,
        shadowStrength: 1.0,
        layout: moved(OverlayElement.ayah, 0.5, 0.90)),
    'آية على الحافة اليسرى cx=0 وكبيرة 160%': OverlayStyle(
        shadowStrength: 1.0, layout: moved(OverlayElement.ayah, 0.0, 0.3, scale: 1.6)),
    'آية على الحافة اليمنى cx=1 وصغيرة 60%': OverlayStyle(
        shadowStrength: 1.0, layout: moved(OverlayElement.ayah, 1.0, 0.3, scale: 0.6)),
    'تفسير تحت الآية صغير 60% وآية بدون': OverlayStyle(
        shadowStrength: 0.7,
        layout: OverlayLayout.reference
            .update(OverlayElement.ayah, (p) => p.copyWith(enabled: false))
            .update(OverlayElement.tafsir, (p) => p.copyWith(scale: 0.6))),
  };
  final sizes = [(1080, 1920), (1920, 1080), (1080, 1080)];
  final segments = <String, RecitationSegment>{
    '50:27 جزء 2 (بالرقم)': referenceSegments()[1],
    'آية الكرسي (كتلة طويلة)': longSegment(),
  };

  for (final size in sizes) {
    for (final st in styles.entries) {
      for (final sg in segments.entries) {
        testWidgets('${size.$1}x${size.$2} ${st.key} ${sg.key}: الشريط = إطار المعاينة، وما في شي برا الشريط',
            (tester) async {
          final (w, h) = size;
          tester.view.physicalSize = Size(w.toDouble(), h.toDouble());
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);
          final band =
              overlayBandFor(OverlayMetrics.forSize(w, h), layout: st.value.layout);
          final item = OverlayItem(sg.value, 0, 0, 5);
          final job = OverlayRenderJob(
              width: w,
              height: h,
              band: band,
              item: item,
              style: st.value,
              surahNames: surahNames);

          final fullKey = GlobalKey(), bandKey = GlobalKey();
          await tester.pumpWidget(MaterialApp(
            home: Align(
              alignment: Alignment.topLeft,
              child: Stack(clipBehavior: Clip.none, children: [
                // إطار المعاينة (نفس استعمال شاشة المحرر).
                RepaintBoundary(
                  key: fullKey,
                  child: AyahOverlayFrame(
                    videoWidth: w,
                    videoHeight: h,
                    cue: OverlayCue(item, 1),
                    style: st.value,
                    surahName: (n) => surahNames[n],
                  ),
                ),
                // صورة التصدير.
                Positioned(
                  left: 0,
                  top: 0,
                  child: RepaintBoundary(
                      key: bandKey, child: OverlayBandView(job: job)),
                ),
              ]),
            ),
          ));
          await tester.pump();

          final full = await capture(tester, fullKey);
          final cut = await capture(tester, bandKey);
          expect(cut.length, w * band.height * 4);
          expect(full.length, w * h * 4);

          // 1) برا الشريط: ولا بكسل فيه نص أو ظل أو خلفية.
          var outside = 0;
          for (var y = 0; y < h; y++) {
            if (y >= band.top && y < band.bottom) continue;
            final row = y * w * 4;
            for (var x = 0; x < w; x++) {
              if (full[row + x * 4 + 3] != 0) outside++;
            }
          }
          expect(outside, 0, reason: 'نص/ظل برا شريط التصدير ($band)');

          // 2) الشريط نفسه = نفس بكسلات إطار المعاينة.
          var diff = 0, ink = 0;
          for (var y = 0; y < band.height; y++) {
            final a = (band.top + y) * w * 4, b = y * w * 4;
            for (var x = 0; x < w * 4; x++) {
              if ((full[a + x] - cut[b + x]).abs() > 1) diff++;
            }
            for (var x = 0; x < w; x++) {
              if (cut[b + x * 4 + 3] > 0) ink++;
            }
          }
          expect(diff, 0, reason: 'صورة التصدير مختلفة عن المعاينة');
          // في نص فعلاً (مش صورة فاضية).
          expect(ink, greaterThan(w * 3));

          // 3) الوضع الافتراضي: أول سطر قريب من 61% (أول بكسل فيه حبر).
          if (st.value.layout.isReference &&
              !st.value.background.visible &&
              st.value.layout.isEnabled(OverlayElement.ayah)) {
            var firstInk = -1;
            for (var y = 0; y < h && firstInk < 0; y++) {
              final row = y * w * 4;
              for (var x = 0; x < w; x++) {
                if (full[row + x * 4 + 3] > 200) {
                  firstInk = y;
                  break;
                }
              }
            }
            final m = OverlayMetrics.forSize(w, h);
            expect(firstInk, greaterThanOrEqualTo(band.top));
            expect(firstInk, lessThan(m.top + m.ayahFontSize * m.ayahLineHeight));
          }
        });
      }
    }
  }

  // ---------------------------------------------------------------
  // يوم 9 (0ب/0ج): الظل لازم يكون موجود فعلاً بالصورة، وبيزيد مع الشدة.
  // "بكسل ظل" = بكسل شبه معتم بلون عكس النص (النص نفسه وحواف الحروف بلون النص).
  // ---------------------------------------------------------------
  Future<({int shadowPixels, int shadowAlphaSum, int textPixels})> shadowStats(
      WidgetTester tester, OverlayStyle st) async {
    const w = 1080, h = 1920;
    tester.view.physicalSize = Size(w.toDouble(), h.toDouble());
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final item = OverlayItem(referenceSegments()[1], 0, 0, 5);
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: RepaintBoundary(
          key: key,
          child: AyahOverlayFrame(
              videoWidth: w,
              videoHeight: h,
              cue: OverlayCue(item, 1),
              style: st,
              surahName: (n) => surahNames[n]),
        ),
      ),
    ));
    await tester.pump();
    final px = await capture(tester, key, format: ui.ImageByteFormat.rawStraightRgba);
    final white = st.color == OverlayTextColor.white;
    var shadowPixels = 0, alphaSum = 0, text = 0;
    for (var i = 0; i < px.length; i += 4) {
      final a = px[i + 3];
      if (a == 0) continue;
      final lum = (px[i] + px[i + 1] + px[i + 2]) / 3;
      final opposite = white ? lum < 60 : lum > 195;
      if (opposite && a > 30) {
        shadowPixels++;
        alphaSum += a;
      } else if (!opposite && a > 200) {
        text++;
      }
    }
    return (shadowPixels: shadowPixels, shadowAlphaSum: alphaSum, textPixels: text);
  }

  for (final color in OverlayTextColor.values) {
    testWidgets('شدة الظل (${color.name}): 0 = ما في ظل، وبيزيد بزيادة الشدة', (tester) async {
      final r = <double, ({int shadowPixels, int shadowAlphaSum, int textPixels})>{};
      for (final s in [0.0, 0.3, 0.6, 1.0]) {
        r[s] = await shadowStats(tester, shadowStyle(s, c: color));
      }
      expect(r[0.0]!.shadowPixels, 0, reason: 'بدون ظل');
      expect(r[0.0]!.textPixels, greaterThan(1000));
      // النص نفسه بيضل موجود (حواف الحروف فوق الظل بتتلوّن شوي فبنسمح بفرق).
      expect(r[1.0]!.textPixels, greaterThan(r[0.0]!.textPixels * 0.6));
      expect(r[0.3]!.shadowPixels, greaterThan(500), reason: 'ظل 30% لازم يبين');
      expect(r[0.6]!.shadowPixels, greaterThan(r[0.3]!.shadowPixels));
      expect(r[1.0]!.shadowPixels, greaterThan(r[0.6]!.shadowPixels));
      expect(r[0.6]!.shadowAlphaSum, greaterThan(r[0.3]!.shadowAlphaSum));
      expect(r[1.0]!.shadowAlphaSum, greaterThan(r[0.6]!.shadowAlphaSum));
      // 100% أكتر بوضوح (مش فرق شكلي).
      expect(r[1.0]!.shadowAlphaSum, greaterThan(r[0.3]!.shadowAlphaSum * 1.5));
    });
  }

  testWidgets('خلفية الصندوق/الشريط: لون عكس النص، وبتبان', (tester) async {
    for (final mode in [OverlayBackgroundMode.box, OverlayBackgroundMode.bar]) {
      final st = OverlayStyle(
          background: OverlayBackground(mode: mode, opacity: 0.6));
      final r = await shadowStats(tester, st);
      expect(r.shadowPixels, greaterThan(20000), reason: mode.name);
    }
  });
}
