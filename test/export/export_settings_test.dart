import 'package:flutter_test/flutter_test.dart';
import 'package:quran_dub/export/export_settings.dart';
import 'package:quran_dub/pipeline/project_input.dart';
import 'package:quran_dub/pipeline/recitation_segment.dart';

RecitationSegment ayah(int surah, int ayah, {SegmentKind kind = SegmentKind.fullAyah}) =>
    RecitationSegment(
      start: 0,
      end: 1,
      kind: kind,
      surah: surah,
      ayah: ayah,
      text: 'نص',
      confidence: 1,
    );

VideoInfo info({int w = 1080, int h = 1920, int rot = 0, bool audio = true}) =>
    VideoInfo(
        width: w,
        height: h,
        rotationDegrees: rot,
        durationMs: 59000,
        fps: 30,
        hasAudioTrack: audio);

void main() {
  group('exportSizeFor (أبعاد زوجية بدون تغيير الشكل)', () {
    test('العمودي/الأفقي/المربّع: نفس أبعاد الأصل', () {
      expect(exportSizeFor(1080, 1920), const ExportSize(1080, 1920));
      expect(exportSizeFor(1920, 1080), const ExportSize(1920, 1080));
      expect(exportSizeFor(1080, 1080), const ExportSize(1080, 1080));
      expect(exportSizeFor(3840, 2160), const ExportSize(3840, 2160));
    });

    test('ضلع فردي بينقص بكسل واحد بس (قص، مش تمطيط)', () {
      expect(exportSizeFor(1081, 1921), const ExportSize(1080, 1920));
      expect(exportSizeFor(719, 1280), const ExportSize(718, 1280));
      expect(exportSizeFor(3, 3), const ExportSize(2, 2));
      // نسبة العرض للارتفاع بتضل نفسها تقريباً (< 0.1%).
      final s = exportSizeFor(1081, 1921);
      expect((s.width / s.height - 1081 / 1921).abs(), lessThan(0.001));
    });

    test('بدون سقف (اليوم) = الأصل حتى لو 4K', () {
      expect(exportSizeFor(2160, 3840), const ExportSize(2160, 3840));
    });

    test('سقف الجودة (يوم 18): بيصغّر أقصر ضلع، نفس النسبة، زوجي', () {
      expect(exportSizeFor(2160, 3840, quality: ExportQuality.p1080),
          const ExportSize(1080, 1920));
      expect(exportSizeFor(1080, 1920, quality: ExportQuality.p720),
          const ExportSize(720, 1280));
      expect(exportSizeFor(1920, 1080, quality: ExportQuality.p720),
          const ExportSize(1280, 720));
      // أصغر من السقف: ما بيكبّر.
      expect(exportSizeFor(720, 1280, quality: ExportQuality.p1080),
          const ExportSize(720, 1280));
      final odd = exportSizeFor(1000, 1777, quality: ExportQuality.p720);
      expect(odd.width.isEven && odd.height.isEven, isTrue);
      expect(odd.width, 720);
      expect((odd.width / odd.height - 1000 / 1777).abs(), lessThan(0.003));
    });

    test('أبعاد غير معروفة → خطأ', () {
      expect(() => exportSizeFor(0, 1920), throwsArgumentError);
    });

    test('الأبعاد بعد الدوران من VideoInfo', () {
      final i = info(w: 1920, h: 1080, rot: 90);
      expect(exportSizeFor(i.rotatedWidth, i.rotatedHeight),
          const ExportSize(1080, 1920));
    });
  });

  group('bitrate', () {
    test('معقول لكل الأبعاد', () {
      final b1080 = videoBitrateFor(const ExportSize(1080, 1920), 30);
      expect(b1080, inInclusiveRange(6000000, 9000000));
      final b720 = videoBitrateFor(const ExportSize(720, 1280), 30);
      expect(b720, inInclusiveRange(2500000, 4500000));
      final b4k = videoBitrateFor(const ExportSize(2160, 3840), 30);
      expect(b4k, inInclusiveRange(25000000, 35000000));
      // نفس عدد البكسلات = نفس الـ bitrate (عمودي/أفقي).
      expect(videoBitrateFor(const ExportSize(1920, 1080), 30), b1080);
    });

    test('fps غير معروف = 30، وفوق 60 بينحسب 60، وحدود دنيا/عليا', () {
      expect(effectiveFps(0), 30);
      expect(effectiveFps(double.nan), 30);
      expect(videoBitrateFor(const ExportSize(1080, 1920), 0),
          videoBitrateFor(const ExportSize(1080, 1920), 30));
      expect(videoBitrateFor(const ExportSize(1080, 1920), 120),
          videoBitrateFor(const ExportSize(1080, 1920), 60));
      expect(videoBitrateFor(const ExportSize(160, 90), 30), minVideoBitrate);
      expect(videoBitrateFor(const ExportSize(4320, 7680), 60), maxVideoBitrate);
    });

    test('حجم متوقع', () {
      // 8Mbps + صوت لـ 60 ثانية ≈ 61MB.
      final bytes = estimateOutputBytes(8000000, 60);
      expect(bytes / 1e6, closeTo(64.5, 2));
      expect(estimateOutputBytes(8000000, 60, hasAudio: false),
          lessThan(bytes));
    });
  });

  group('مصدر الصوت', () {
    test('الأصل / ملف منفصل / بدون صوت', () {
      final base = ProjectInput(
          videoPath: '/v.mp4', source: VideoSource.gallery, videoInfo: info());
      expect(ExportAudio.forInput(base), isA<OriginalAudio>());
      final ext = base.withExternalAudio('/a.m4a');
      final a = ExportAudio.forInput(ext);
      expect(a, isA<ExternalAudio>());
      expect(a.path, '/a.m4a');
      expect(a.toJson(), {'kind': 'external', 'path': '/a.m4a'});
      // ملف منفصل موجود بس مطفي → صوت الفيديو.
      expect(ExportAudio.forInput(ext.withUseExternalAudio(false)),
          isA<OriginalAudio>());
      final mute = ProjectInput(
          videoPath: '/v.mp4',
          source: VideoSource.camera,
          videoInfo: info(audio: false));
      expect(ExportAudio.forInput(mute), isA<NoAudio>());
    });
  });

  group('اسم الملف والعنوان', () {
    final now = DateTime(2026, 11, 24, 15, 30, 12);
    test('سورة وحدة', () {
      expect(
          exportFileName(
              [ayah(50, 27, kind: SegmentKind.partialAyah), ayah(50, 27), ayah(50, 30)],
              now),
          'AyahStudio_050-027-030_20261124-153012.mp4');
      expect(exportFileName([ayah(112, 1)], now),
          'AyahStudio_112-001_20261124-153012.mp4');
      expect(exportTitle([ayah(50, 27), ayah(50, 30)]), '٥٠:٢٧–٣٠');
      expect(exportTitle([ayah(1, 1)]), '١:١');
    });

    test('أكثر من سورة، وبدون آيات', () {
      expect(exportFileName([ayah(113, 5), ayah(114, 1)], now),
          'AyahStudio_113-114_20261124-153012.mp4');
      expect(exportFileName([], now), 'AyahStudio_20261124-153012.mp4');
      final nonQuran = RecitationSegment(
          start: 0, end: 1, kind: SegmentKind.nonQuran, text: '', confidence: 0);
      expect(exportFileName([nonQuran], now), 'AyahStudio_20261124-153012.mp4');
      expect(exportTitle([nonQuran]), '');
    });

    test('ASCII بس', () {
      final n = exportFileName([ayah(50, 27)], now);
      expect(RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(n), isTrue);
    });
  });
}
