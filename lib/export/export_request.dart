// تجهيز خطة التصدير من المشروع (يوم 8). الجزء الصافي ([planForRequest])
// مختبر بـ test/export؛ رسم الصور نفسه بـ [OverlayRenderController].
import '../overlay/overlay_metrics.dart';
import '../overlay/overlay_style.dart';
import '../overlay/overlay_timeline.dart';
import '../pipeline/project_input.dart';
import '../pipeline/recitation_segment.dart';
import 'export_plan.dart';
import 'export_settings.dart';

/// شو بدنا نصدّر: المقطع، المقاطع (بعد التصحيح لاحقاً يوم 10)، وشكل النص
/// اللي اختاره المستخدم بالمعاينة.
class ExportRequest {
  final ProjectInput input;
  final List<RecitationSegment> segments;
  final OverlayStyle style;
  final ExportQuality quality;

  /// أسماء السور (رقم → اسم) لعنصر "اسم السورة ورقم الآية" (من جدول `surahs`).
  /// بدونها بيطلع "سورة 50".
  final Map<int, String>? surahNames;

  /// للتجربة بالـ CI: الـ Kotlin ما بيمسح صور النص والملف المؤقت.
  final bool keepWorkFiles;

  const ExportRequest({
    required this.input,
    required this.segments,
    this.style = const OverlayStyle(),
    this.quality = ExportQuality.original,
    this.surahNames,
    this.keepWorkFiles = false,
  });

  ExportSize get size => exportSizeFor(
      input.videoInfo.rotatedWidth, input.videoInfo.rotatedHeight,
      quality: quality);

  /// نفس الخط الزمني تبع المعاينة بالضبط (نفس الدالة ونفس المدة).
  OverlayTimeline get timeline {
    final info = input.videoInfo;
    return OverlayTimeline.build(segments,
        videoDuration: info.durationMs > 0 ? info.durationSeconds : null);
  }
}

/// مسار صورة المقطع رقم [i] بمجلد العمل.
String overlayPngPath(String workDir, int i) =>
    '$workDir/overlays/cue_${i.toString().padLeft(4, '0')}.png';

/// الخطة كاملة (بدون رسم): الأبعاد، الـ bitrate، الشريط، المقاطع، الصوت...
ExportPlan planForRequest(
  ExportRequest req, {
  required String id,
  required String workDir,
  required DateTime now,
}) {
  final size = req.size;
  final info = req.input.videoInfo;
  final metrics = OverlayMetrics.forSize(size.width, size.height);
  final tl = req.timeline;
  final fps = effectiveFps(info.fps);
  return ExportPlan(
    id: id,
    inputPath: req.input.videoPath,
    audio: ExportAudio.forInput(req.input),
    size: size,
    sourceSize: ExportSize(info.rotatedWidth, info.rotatedHeight),
    videoBitrate: videoBitrateFor(size, fps),
    fps: fps,
    durationSeconds: info.durationSeconds,
    fileName: exportFileName(req.segments, now),
    outputPath: '$workDir/output.mp4',
    band: overlayBandFor(metrics, layout: req.style.layout),
    cues: exportCuesFor(tl, (i) => overlayPngPath(workDir, i)),
    title: exportTitle(req.segments),
    style: req.style.toJson(),
  );
}
