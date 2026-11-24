import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:quran_dub/export/export_plan.dart';
import 'package:quran_dub/export/export_request.dart';
import 'package:quran_dub/export/export_settings.dart';
import 'package:quran_dub/overlay/ayah_font.dart';
import 'package:quran_dub/overlay/overlay_frame.dart';
import 'package:quran_dub/overlay/overlay_metrics.dart';
import 'package:quran_dub/overlay/overlay_style.dart';
import 'package:quran_dub/overlay/overlay_timeline.dart';
import 'package:quran_dub/pipeline/project_input.dart';
import 'package:quran_dub/pipeline/recitation_segment.dart';

RecitationSegment mk(double s, double e,
        {SegmentKind kind = SegmentKind.fullAyah, int ayah = 27}) =>
    RecitationSegment(
      start: s,
      end: e,
      kind: kind,
      surah: kind == SegmentKind.istiadha ? null : 50,
      ayah: kind == SegmentKind.istiadha ? null : ayah,
      text: kind == SegmentKind.istiadha ? '' : 'نص',
      confidence: 1,
    );

/// نفس الاستيفاء الخطي تبع `ExportPlan.Cue.alphaAt` بالـ Kotlin.
double kotlinAlphaAt(List<AlphaKey> keys, double t) {
  if (t <= keys.first.t) return keys.first.a;
  if (t >= keys.last.t) return keys.last.a;
  for (var i = 0; i < keys.length - 1; i++) {
    final a = keys[i], b = keys[i + 1];
    if (t >= a.t && t <= b.t) {
      final f = b.t > a.t ? (t - a.t) / (b.t - a.t) : 0;
      return a.a + (b.a - a.a) * f;
    }
  }
  return keys.last.a;
}

void main() {
  group('شريط الكتلة (OverlayBand)', () {
    for (final size in const [(1080, 1920), (1920, 1080), (1080, 1080), (2160, 3840), (720, 1280)]) {
      test('${size.$1}x${size.$2}: بيغطي الكتلة + هامش الظل، جوا الفيديو، زوجي', () {
        final m = OverlayMetrics.forSize(size.$1, size.$2);
        final b = overlayBandFor(m);
        expect(b.top, lessThanOrEqualTo(m.top - m.unit * 0.04));
        expect(b.bottom, greaterThanOrEqualTo(
            (m.bottomLimit + m.unit * 0.04).clamp(0, size.$2.toDouble())));
        expect(b.top, greaterThanOrEqualTo(0));
        expect(b.bottom, lessThanOrEqualTo(size.$2));
        expect(b.top.isEven, isTrue);
        expect(b.height.isEven, isTrue);
        // أصغر بكتير من الإطار كامل (ذاكرة): ~40% من الارتفاع.
        expect(b.height / size.$2, lessThan(0.5));
      });
    }

    test('المرجع 1080×1920: الشريط من ~58% لآخر الفيديو تقريباً', () {
      final b = overlayBandFor(OverlayMetrics.forSize(1080, 1920));
      expect(b.top / 1920, closeTo(0.58, 0.03));
      expect(b.bottom / 1920, closeTo(0.99, 0.03));
    });
  });

  group('شفافية الـ fade (من OverlayTimeline.opacityOf نفسها)', () {
    test('العينات + الاستيفاء الخطي = المنحنى الحقيقي (< 0.01)', () {
      final tl = OverlayTimeline.build(
          [mk(1, 3), mk(6, 6.3, ayah: 28), mk(7, 9, ayah: 29)],
          videoDuration: 10);
      for (final it in tl.items) {
        final keys = alphaKeysFor(tl, it);
        expect(keys.first.t, it.start);
        expect(keys.last.t, it.holdEnd);
        expect(keys.first.a, 0);
        expect(keys.last.a, 0);
        for (var t = it.start; t < it.holdEnd; t += 0.004) {
          expect((kotlinAlphaAt(keys, t) - tl.opacityOf(it, t)).abs(),
              lessThan(0.01),
              reason: 't=$t item ${it.start}..${it.holdEnd}');
        }
      }
    });

    test('الجزء الثابت بنص النافذة ما بياخد عينات (ملف الخطة صغير)', () {
      final tl = OverlayTimeline.build([mk(0, 30), mk(30, 31, ayah: 28)]);
      final keys = alphaKeysFor(tl, tl.items.first);
      // 0.25s fade in + 0.25s fade out بـ 60 عينة/ثانية ≈ 32 عينة، مش 1800.
      expect(keys.length, lessThan(45));
      expect(kotlinAlphaAt(keys, 15), 1.0);
    });

    test('الاستعاذة ما إلها صورة، بس بتقطع اللي قبلها', () {
      final tl = OverlayTimeline.build([
        mk(0, 2, kind: SegmentKind.istiadha),
        mk(2, 5),
        mk(5, 6, kind: SegmentKind.istiadha),
        mk(8, 10, ayah: 28),
      ]);
      final cues = exportCuesFor(tl, (i) => '/w/$i.png');
      expect(cues.length, 2);
      expect(cues[0].start, 2);
      expect(cues[0].end, 5);
      expect(cues[1].start, 8);
      expect(cues[1].png, '/w/1.png');
    });

    test('النوافذ ما بتتداخل (مقطع واحد بالأكثر بكل إطار)', () {
      final tl = OverlayTimeline.build(
          [for (var i = 0; i < 20; i++) mk(i * 1.5, i * 1.5 + 1, ayah: i + 1)],
          videoDuration: 40);
      final cues = exportCuesFor(tl, (i) => '$i');
      for (var i = 1; i < cues.length; i++) {
        expect(cues[i].start, greaterThanOrEqualTo(cues[i - 1].end));
      }
    });
  });

  group('الخطة كاملة', () {
    final videoInfo = VideoInfo(
        width: 1920,
        height: 1080,
        rotationDegrees: 90,
        durationMs: 58800,
        fps: 0,
        hasAudioTrack: true);
    final req = ExportRequest(
      input: ProjectInput(
          videoPath: '/v/in.mp4',
          source: VideoSource.gallery,
          videoInfo: videoInfo),
      segments: [mk(0, 1, kind: SegmentKind.istiadha), mk(1, 4), mk(4, 8, ayah: 28)],
      style: const OverlayStyle(
          color: OverlayTextColor.black,
          shadowStrength: 0.7,
          font: AyahFont.amiriQuran),
    );

    test('أبعاد بعد الدوران، fps 30 لو مش معروف، الشريط، المقاطع', () {
      final p = planForRequest(req,
          id: 'exp1', workDir: '/c/export/exp1', now: DateTime(2026, 11, 24, 9));
      expect(p.size, const ExportSize(1080, 1920));
      expect(p.sourceSize, const ExportSize(1080, 1920));
      expect(p.fps, 30);
      expect(p.audio, isA<OriginalAudio>());
      expect(p.cues.length, 2);
      expect(p.cues[0].png, '/c/export/exp1/overlays/cue_0000.png');
      expect(p.outputPath, '/c/export/exp1/output.mp4');
      expect(p.fileName, startsWith('AyahStudio_050-027-028_'));
      expect(p.band, overlayBandFor(OverlayMetrics.forSize(1080, 1920)));
      expect(p.style, req.style.toJson());
      // آخر مقطع مقصوص على مدة الفيديو.
      expect(p.cues.last.end, lessThanOrEqualTo(58.8));
    });

    test('الخطة JSON بالمفاتيح اللي بيقرأها ExportPlan.kt', () {
      final p = planForRequest(req,
          id: 'exp1', workDir: '/c/e', now: DateTime(2026, 11, 24, 9));
      final j = jsonDecode(jsonEncode(p.toJson())) as Map<String, dynamic>;
      for (final k in [
        'version', 'id', 'input', 'audio', 'width', 'height', 'videoBitrate',
        'audioBitrate', 'fps', 'durationMs', 'fileName', 'output', 'band',
        'cues', 'title', 'estimatedBytes', 'sourceWidth', 'sourceHeight',
        'style',
      ]) {
        expect(j.containsKey(k), isTrue, reason: k);
      }
      expect(j['durationMs'], 58800);
      final cue = (j['cues'] as List).first as Map<String, dynamic>;
      expect(cue.keys, containsAll(['start', 'end', 'png', 'alpha']));
      final alpha = cue['alpha'] as List;
      expect((alpha.first as List).length, 2);
      expect((j['band'] as Map).keys, containsAll(['top', 'height']));
    });

    test('ملف تلاوة منفصل → صوت external', () {
      final r2 = ExportRequest(
          input: req.input.withExternalAudio('/a/recite.mp3'),
          segments: req.segments);
      final p = planForRequest(r2, id: 'x', workDir: '/w', now: DateTime(2026));
      expect(p.audio.toJson(), {'kind': 'external', 'path': '/a/recite.mp3'});
    });

    test('الأسماء الإنجليزية للأنماط ثابتة (الخطة والتقارير)', () {
      final j = req.style.toJson();
      expect(j['tafsirMode'], 'split');
      expect(j['font'], 'amiriQuran');
      expect(j['tafsirFont'], 'amiri');
      expect(j['color'], 'black');
      expect(j['shadowStrength'], 0.7);
      expect(j.keys, containsAll(['background', 'layout', 'reciterName']));
      expect(OverlayStyle.fromJson(j), req.style);
      expect(TafsirMode.values.map((e) => e.name),
          ['split', 'fullUnderEachPart']);
    });
  });
}
