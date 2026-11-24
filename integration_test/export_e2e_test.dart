// تجربة التصدير الحقيقي على محاكي أندرويد (يوم 8، `.github/workflows/export-e2e.yml`).
//
// الـ CI بيولّد مقاطع اختبار (عمودي/أفقي/مربّع/مدوّر/أبعاد فردية/ملف تلاوة
// منفصل) وبيحطها بـ files/e2e_in مع cases.json. لكل حالة: بنفتح ExportScreen
// نفسها (autoStart) → صور النص بـ AyahOverlayFrame → ExportService (Media3) →
// المعرض. بعدين بنقارن إطارات من الناتج مع (إطار الأصل + صورة النص بشفافية
// OverlayTimeline.opacityOf) بنفس اللحظة: لو الحرق بمكانه وبشكله، الفرق صغير.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:quran_dub/export/export_plan.dart';
import 'package:quran_dub/export/export_request.dart';
import 'package:quran_dub/export/export_status.dart';
import 'package:quran_dub/overlay/ayah_font.dart';
import 'package:quran_dub/overlay/overlay_frame.dart';
import 'package:quran_dub/overlay/overlay_style.dart';
import 'package:quran_dub/pipeline/project_input.dart';
import 'package:quran_dub/pipeline/recitation_segment.dart';
import 'package:quran_dub/platform/video_info.dart';
import 'package:quran_dub/screens/export_screen.dart';

import '../test/export/fixtures.dart';

Future<Uint8List> decodePngRgba(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  final frame = await codec.getNextFrame();
  final d = await frame.image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
  frame.image.dispose();
  return d!.buffer.asUint8List();
}

Future<Uint8List> encodePng(Uint8List rgba, int w, int h) async {
  final c = Completer<ui.Image>();
  ui.decodeImageFromPixels(rgba, w, h, ui.PixelFormat.rgba8888, c.complete);
  final img = await c.future;
  final d = await img.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();
  return d!.buffer.asUint8List();
}

/// تصغير بالعيّنة (للصور المرفقة بالتقرير).
Uint8List shrink(Uint8List rgba, int w, int h, int f) {
  final sw = w ~/ f, sh = h ~/ f;
  final out = Uint8List(sw * sh * 4);
  for (var y = 0; y < sh; y++) {
    for (var x = 0; x < sw; x++) {
      final s = ((y * f) * w + x * f) * 4, d = (y * sw + x) * 4;
      out[d] = rgba[s];
      out[d + 1] = rgba[s + 1];
      out[d + 2] = rgba[s + 2];
      out[d + 3] = 255;
    }
  }
  return out;
}

class FrameCheck {
  final double t;
  final double alpha;
  final double maeText; // ناتج مقابل المتوقع (الأصل + النص) بمكان الحروف
  final double maeTextVsSource; // ناتج مقابل الأصل بمكان الحروف (لازم كبير: النص ظاهر)
  final double maeOutside; // برا الشريط: ناتج مقابل الأصل (لازم صغير)
  final int expectedFirstRow;
  final int outFirstRow;
  FrameCheck(this.t, this.alpha, this.maeText, this.maeTextVsSource,
      this.maeOutside, this.expectedFirstRow, this.outFirstRow);
  Map<String, Object?> toJson() => {
        't': t,
        'alpha': alpha,
        'maeText': maeText,
        'maeTextVsSource': maeTextVsSource,
        'maeOutside': maeOutside,
        'expectedFirstRow': expectedFirstRow,
        'outFirstRow': outFirstRow,
      };
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // ExportScreen/OverlayRenderHost بيستنوا إطارات حقيقية (endOfFrame).
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('تصدير حقيقي: الأبعاد، الصوت، ومكان وشكل النص المحروق', (tester) async {
    final support = await getApplicationSupportDirectory();
    final inDir = Directory('${support.path}/e2e_in');
    final outDir = Directory('${support.path}/e2e_out')..createSync(recursive: true);
    // الـ CI بيحط المقاطع بعد ما ينزل التطبيق.
    for (var i = 0; i < 900 && !File('${inDir.path}/READY').existsSync(); i++) {
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    expect(File('${inDir.path}/READY').existsSync(), isTrue,
        reason: 'ما وصلت مقاطع الاختبار');
    final cases = (jsonDecode(File('${inDir.path}/cases.json').readAsStringSync())
            as List)
        .cast<Map<String, dynamic>>();

    final summary = <Map<String, Object?>>[];
    var allOk = true;
    for (final c in cases) {
      final r = await _runCase(tester, c, inDir.path, outDir.path);
      summary.add(r);
      if (r['ok'] != true) allOk = false;
      // ignore: avoid_print
      print('E2E_CASE ${jsonEncode(r)}');
    }
    File('${outDir.path}/summary.json').writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(summary));
    // ignore: avoid_print
    print('E2E_SUMMARY ${jsonEncode(summary)}');
    expect(allOk, isTrue, reason: const JsonEncoder.withIndent(' ').convert(summary));
  }, timeout: const Timeout(Duration(minutes: 45)));
}

Future<Map<String, Object?>> _runCase(WidgetTester tester, Map<String, dynamic> c,
    String inDir, String outDir) async {
  final name = c['name'] as String;
  final problems = <String>[];
  final result = <String, Object?>{'name': name};
  try {
    final videoPath = '$inDir/${c['file']}';
    final info = await VideoInfoReader.read(videoPath);
    result['source'] = info.toString();
    var input = ProjectInput(
        videoPath: videoPath, source: VideoSource.gallery, videoInfo: info);
    if (c['audio'] != null) input = input.withExternalAudio('$inDir/${c['audio']}');
    final style = OverlayStyle(
      color: c['color'] == 'black' ? OverlayTextColor.black : OverlayTextColor.white,
      shadow: c['shadow'] == true,
      font: c['font'] == 'amiriQuran' ? AyahFont.amiriQuran : AyahFont.kfgqpcHafs,
      tafsirMode: c['tafsir'] == 'fullUnderEachPart'
          ? TafsirMode.fullUnderEachPart
          : TafsirMode.split,
    );
    final List<RecitationSegment> segments = c['long'] == true
        ? [longSegment(start: 0.5, end: 5.5)]
        : referenceSegments(offset: 0.3);
    final req = ExportRequest(
        input: input, segments: segments, style: style, keepWorkFiles: true);

    final done = Completer<(ExportStatus, ExportPlan?, String?)>();
    await tester.pumpWidget(MaterialApp(
      home: ExportScreen(
        key: ValueKey(name),
        request: req,
        autoStart: true,
        onFinished: (s, p, w) {
          if (!done.isCompleted) done.complete((s, p, w));
        },
      ),
    ));
    final (status, plan, workDir) =
        await done.future.timeout(const Duration(minutes: 8));
    result['status'] = status.phase.name;
    result['elapsedMs'] = status.elapsedMs;
    result['encoder'] = status.videoEncoder;
    result['savedToGallery'] = status.savedToGallery;
    result['galleryPath'] = status.galleryPath;
    if (status.phase != ExportPhase.done || plan == null) {
      problems.add('ما خلص: ${status.phase.name} ${status.error?.name} ${status.errorDetail}');
      return result..['problems'] = problems..['ok'] = false;
    }
    if (!status.savedToGallery) problems.add('ما انحفظ بالمعرض');
    final out = status.outputPath!;
    final W = plan.size.width, H = plan.size.height;
    result['planSize'] = '${W}x$H';
    result['band'] = plan.band.toString();

    // 1) الأبعاد (مستقيم)، المدة، fps، الصوت.
    final oi = await VideoInfoReader.read(out);
    result['output'] = oi.toString();
    if (oi.rotatedWidth != W || oi.rotatedHeight != H) {
      problems.add('أبعاد الناتج ${oi.rotatedWidth}x${oi.rotatedHeight} بدل ${W}x$H');
    }
    if ((oi.durationMs - info.durationMs).abs() > 250) {
      problems.add('المدة ${oi.durationMs}ms بدل ${info.durationMs}ms');
    }
    if (info.fps > 0 && oi.fps > 0 && (oi.fps - info.fps).abs() > 1.0) {
      problems.add('fps ${oi.fps} بدل ${info.fps}');
    }
    final wantAudio = c['audio'] != null || info.hasAudioTrack;
    if (oi.hasAudioTrack != wantAudio) problems.add('الصوت: ${oi.hasAudioTrack}');
    if (W.isOdd || H.isOdd) problems.add('أبعاد فردية');

    // 2) الإطارات: النص بمكانه وبشكله (منتصف كل مقطع + نص الـ fade).
    final tl = req.timeline;
    final checks = <FrameCheck>[];
    final times = <(int, double)>[];
    for (var i = 0; i < tl.items.length; i++) {
      final it = tl.items[i];
      times.add((i, (it.start + it.holdEnd) / 2));
    }
    // لحظة بنص أول fade in (شفافية ~0.5).
    final first = tl.items.first;
    times.add((0, first.start + tl.config.fadeIn / 2));
    for (final (i, t) in times) {
      final alpha = tl.opacityOf(tl.items[i], t);
      final us = (t * 1e6).round();
      final outF = await VideoInfoReader.frameRgba(out, us, W, H);
      final srcF = await VideoInfoReader.frameRgba(videoPath, us, W, H);
      final ov = await decodePngRgba(File(plan.cues[i].png).readAsBytesSync());
      final b = plan.band;
      final expected = Uint8List.fromList(srcF);
      var textN = 0;
      double textErr = 0, textVsSrc = 0;
      var expFirst = -1, outFirst = -1;
      for (var y = 0; y < b.height; y++) {
        var rowExpInk = false, rowOutInk = false;
        for (var x = 0; x < W; x++) {
          final o = (y * W + x) * 4;
          final a = ov[o + 3] / 255 * alpha;
          final p = ((b.top + y) * W + x) * 4;
          for (var k = 0; k < 3; k++) {
            expected[p + k] = (srcF[p + k] * (1 - a) + ov[o + k] * a).round();
          }
          if (a > 0.6) {
            textN++;
            for (var k = 0; k < 3; k++) {
              textErr += (outF[p + k] - expected[p + k]).abs();
              textVsSrc += (outF[p + k] - srcF[p + k]).abs();
            }
            rowExpInk = true;
          }
          if ((outF[p] - srcF[p]).abs() + (outF[p + 1] - srcF[p + 1]).abs() +
                  (outF[p + 2] - srcF[p + 2]).abs() >
              240) {
            rowOutInk = true;
          }
        }
        if (rowExpInk && expFirst < 0) expFirst = b.top + y;
        if (rowOutInk && outFirst < 0) outFirst = b.top + y;
      }
      double outside = 0;
      var outsideN = 0;
      for (var y = 0; y < H; y += 7) {
        if (y >= b.top && y < b.bottom) continue;
        for (var x = 0; x < W; x += 7) {
          final p = (y * W + x) * 4;
          for (var k = 0; k < 3; k++) {
            outside += (outF[p + k] - srcF[p + k]).abs();
          }
          outsideN += 3;
        }
      }
      final chk = FrameCheck(
        t,
        alpha,
        textN == 0 ? -1 : textErr / (textN * 3),
        textN == 0 ? -1 : textVsSrc / (textN * 3),
        outsideN == 0 ? 0 : outside / outsideN,
        expFirst,
        outFirst,
      );
      checks.add(chk);
      // صورة مقارنة (المتوقع فوق، الناتج تحت) مصغّرة ×4، بمجلد e2e_out.
      final f = 4;
      final sw = W ~/ f, sh = H ~/ f;
      final both = Uint8List(sw * sh * 2 * 4)
        ..setAll(0, shrink(expected, W, H, f))
        ..setAll(sw * sh * 4, shrink(outF, W, H, f));
      final png = await encodePng(both, sw, sh * 2);
      File('$outDir/${name}_t${t.toStringAsFixed(2)}.png').writeAsBytesSync(png);
      // بدقة كاملة: شريط النص (المتوقع = المعاينة فوق الأصل، والناتج) لمقطع
      // واحد بكل حالة (الثاني لو موجود: آخر جزء من 50:27 مع علامة الرقم).
      if (i == math.min(1, tl.items.length - 1) && alpha > 0.95 && times.indexOf((i, t)) == i) {
        final bytes = b.height * W * 4, off = b.top * W * 4;
        File('$outDir/${name}_band_expected.png').writeAsBytesSync(await encodePng(
            Uint8List.sublistView(expected, off, off + bytes), W, b.height));
        File('$outDir/${name}_band_output.png').writeAsBytesSync(await encodePng(
            Uint8List.sublistView(outF, off, off + bytes), W, b.height));
      }

      if (alpha > 0.95) {
        if (chk.maeTextVsSource < 25) {
          problems.add('t=$t: النص مش ظاهر بالناتج (فرق عن الأصل ${chk.maeTextVsSource.toStringAsFixed(1)})');
        }
        // ترميز H.264 بيغبّش أطراف الحروف الرفيعة شوي (خصوصاً الكتلة الطويلة
        // المصغّرة)، فالحد نسبي من فرق النص عن الأصل.
        if (chk.maeText > 40 || chk.maeText > 0.3 * chk.maeTextVsSource) {
          problems.add('t=$t: النص مختلف عن المعاينة (MAE ${chk.maeText.toStringAsFixed(1)})');
        }
        if (chk.expectedFirstRow >= 0 &&
            (chk.outFirstRow - chk.expectedFirstRow).abs() > 6) {
          problems.add('t=$t: أول سطر عند ${chk.outFirstRow} بدل ${chk.expectedFirstRow}');
        }
      } else if (chk.maeText > 40) {
        problems.add('t=$t (fade ${alpha.toStringAsFixed(2)}): MAE ${chk.maeText.toStringAsFixed(1)}');
      }
      if (chk.maeOutside > 8) {
        problems.add('t=$t: تغيّر برا شريط النص (${chk.maeOutside.toStringAsFixed(1)})');
      }
    }
    result['frames'] = [for (final k in checks) k.toJson()];
    // نسخة من الناتج وصور النص للتقرير.
    File(out).copySync('$outDir/$name.mp4');
    if (plan.cues.isNotEmpty) File(plan.cues.first.png).copySync('$outDir/${name}_cue0.png');
    if (workDir != null) {
      try {
        Directory(workDir).deleteSync(recursive: true);
      } catch (_) {}
    }
  } catch (e, st) {
    problems.add('استثناء: $e\n$st');
  }
  result['problems'] = problems;
  result['ok'] = problems.isEmpty;
  // بين الحالات: نرجع شاشة فاضية.
  await tester.pumpWidget(const SizedBox.shrink());
  return result;
}

