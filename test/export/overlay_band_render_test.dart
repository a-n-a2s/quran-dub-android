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
import 'package:quran_dub/overlay/overlay_frame.dart';
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

Future<Uint8List> capture(WidgetTester tester, GlobalKey key) async {
  final ro = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final bytes = await tester.runAsync(() async {
    final img = await ro.toImage(pixelRatio: 1);
    final d = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    img.dispose();
    return d!.buffer.asUint8List();
  });
  return bytes!;
}

void main() {
  setUpAll(() async {
    await loadFont('KFGQPC Hafs', 'assets/fonts/KFGQPC_HafsUthmanic_v18.ttf');
    await loadFont('Amiri Quran', 'assets/fonts/AmiriQuran.ttf');
    await loadFont('Amiri', 'assets/fonts/Amiri-Regular.ttf');
  });

  final styles = <String, OverlayStyle>{
    'أبيض': const OverlayStyle(),
    'أسود + ظل': const OverlayStyle(color: OverlayTextColor.black, shadow: true),
    'أبيض + ظل، أميري، كامل تحت كل جزء': const OverlayStyle(
        shadow: true,
        font: AyahFont.amiriQuran,
        tafsirMode: TafsirMode.fullUnderEachPart),
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
          final band = overlayBandFor(OverlayMetrics.forSize(w, h));
          final item = OverlayItem(sg.value, 0, 0, 5);
          final job = OverlayRenderJob(
              width: w, height: h, band: band, item: item, style: st.value);

          final fullKey = GlobalKey(), bandKey = GlobalKey();
          await tester.pumpWidget(MaterialApp(
            home: Align(
              alignment: Alignment.topLeft,
              child: Stack(clipBehavior: Clip.none, children: [
                // إطار المعاينة (نفس استعمال OverlayPreviewScreen).
                RepaintBoundary(
                  key: fullKey,
                  child: AyahOverlayFrame(
                    videoWidth: w,
                    videoHeight: h,
                    cue: OverlayCue(item, 1),
                    tafsirMode: st.value.tafsirMode,
                    font: st.value.font,
                    color: st.value.color,
                    shadow: st.value.shadow,
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

          // 1) برا الشريط: ولا بكسل فيه نص أو ظل.
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
          expect(ink, greaterThan(w * 10));

          // 3) أول سطر قريب من 61% (أول بكسل فيه حبر).
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
        });
      }
    }
  }
}
