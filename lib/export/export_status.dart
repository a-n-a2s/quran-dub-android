// حالة التصدير وتقدّمه ورسائل الخطأ (يوم 8). جزء صافي بدون Flutter.

/// مراحل التصدير بالترتيب.
enum ExportPhase {
  idle,

  /// رسم صور النص بـ Flutter (بالتطبيق، قبل الخدمة).
  preparing,

  /// Media3 Transformer بيرمّز الفيديو (خدمة بالخلفية).
  encoding,

  /// نسخ الناتج للمعرض.
  saving,
  done,
  failed,
  cancelled;

  bool get isRunning =>
      this == preparing || this == encoding || this == saving;
  bool get isFinished => this == done || this == failed || this == cancelled;

  static ExportPhase parse(String? s) => ExportPhase.values
      .firstWhere((p) => p.name == s, orElse: () => ExportPhase.idle);
}

/// أوزان المراحل بالتقدّم الكلي (الترميز هو الأطول بكتير).
const double preparingWeight = 0.08;
const double savingWeight = 0.03;
const double encodingWeight = 1 - preparingWeight - savingWeight;

/// التقدّم الكلي 0..1 من المرحلة ونسبة إنجازها [fraction] (0..1).
double overallProgress(ExportPhase phase, double fraction) {
  final f = fraction.isNaN ? 0.0 : fraction.clamp(0.0, 1.0);
  return switch (phase) {
    ExportPhase.idle => 0,
    ExportPhase.preparing => preparingWeight * f,
    ExportPhase.encoding => preparingWeight + encodingWeight * f,
    ExportPhase.saving => preparingWeight + encodingWeight + savingWeight * f,
    ExportPhase.done => 1,
    ExportPhase.failed || ExportPhase.cancelled => 0,
  };
}

/// أنواع الأخطاء (نفس الكودات بـ `ExportService.kt`).
enum ExportErrorKind {
  noSpace,
  encoderUnsupported,
  decoderUnsupported,
  inputMissing,
  overlay,
  io,
  timeout,
  foreground,
  unknown;

  static ExportErrorKind parse(String? s) => ExportErrorKind.values
      .firstWhere((k) => k.name == s, orElse: () => ExportErrorKind.unknown);

  String get message => switch (this) {
        noSpace =>
          'المساحة على الجوال ما بتكفي للفيديو. فضّي شوية مساحة وجرّب كمان مرة.',
        encoderUnsupported =>
          'الجوال ما بيدعم ترميز فيديو بهالأبعاد أو الجودة (H.264). جرّب مقطع أصغر.',
        decoderUnsupported =>
          'ما قدرنا نقرأ صيغة الفيديو الأصلي على هالجوال.',
        inputMissing => 'ملف الفيديو الأصلي (أو ملف التلاوة) مش موجود. اختاره من جديد.',
        overlay => 'صار خطأ وإحنا نرسم النص على الفيديو.',
        io => 'صار خطأ بقراءة أو كتابة الملف.',
        timeout =>
          'أندرويد وقّف التصدير لأنه طوّل كتير بالخلفية. افتح التطبيق وجرّب كمان مرة.',
        foreground =>
          'أندرويد رفض تشغيل خدمة التصدير بالخلفية على هالجوال. انسخ تقرير التصدير وابعته.',
        unknown => 'صار خطأ بالتصدير.',
      };
}

/// حالة التصدير زي ما بتجي من الـ Kotlin (`ExportHub.kt`).
class ExportStatus {
  final String? id;
  final ExportPhase phase;

  /// نسبة إنجاز المرحلة الحالية (0..1).
  final double fraction;
  final ExportErrorKind? error;
  final String? errorDetail;

  /// بعد النجاح.
  final String? outputPath;
  final String? contentUri;
  final bool savedToGallery;
  final String? galleryPath;
  final int? width;
  final int? height;
  final int? fileSizeBytes;
  final int? durationMs;
  final int? elapsedMs;
  final String? videoEncoder;
  final int? averageVideoBitrate;

  const ExportStatus({
    this.id,
    required this.phase,
    this.fraction = 0,
    this.error,
    this.errorDetail,
    this.outputPath,
    this.contentUri,
    this.savedToGallery = false,
    this.galleryPath,
    this.width,
    this.height,
    this.fileSizeBytes,
    this.durationMs,
    this.elapsedMs,
    this.videoEncoder,
    this.averageVideoBitrate,
  });

  static const ExportStatus idle = ExportStatus(phase: ExportPhase.idle);

  double get progress => overallProgress(phase, fraction);

  factory ExportStatus.fromMap(Map<Object?, Object?> m) {
    int? i(String k) => (m[k] as num?)?.toInt();
    final phase = ExportPhase.parse(m['phase'] as String?);
    return ExportStatus(
      id: m['id'] as String?,
      phase: phase,
      fraction: ((m['fraction'] as num?) ?? 0).toDouble(),
      error: phase == ExportPhase.failed
          ? ExportErrorKind.parse(m['error'] as String?)
          : null,
      errorDetail: m['errorDetail'] as String?,
      outputPath: m['outputPath'] as String?,
      contentUri: m['contentUri'] as String?,
      savedToGallery: (m['savedToGallery'] as bool?) ?? false,
      galleryPath: m['galleryPath'] as String?,
      width: i('width'),
      height: i('height'),
      fileSizeBytes: i('fileSizeBytes'),
      durationMs: i('durationMs'),
      elapsedMs: i('elapsedMs'),
      videoEncoder: m['videoEncoder'] as String?,
      averageVideoBitrate: i('averageVideoBitrate'),
    );
  }

  ExportStatus copyWith({ExportPhase? phase, double? fraction}) => ExportStatus(
        id: id,
        phase: phase ?? this.phase,
        fraction: fraction ?? this.fraction,
        error: error,
        errorDetail: errorDetail,
        outputPath: outputPath,
        contentUri: contentUri,
        savedToGallery: savedToGallery,
        galleryPath: galleryPath,
        width: width,
        height: height,
        fileSizeBytes: fileSizeBytes,
        durationMs: durationMs,
        elapsedMs: elapsedMs,
        videoEncoder: videoEncoder,
        averageVideoBitrate: averageVideoBitrate,
      );

  /// سطر للمستخدم.
  String get label => switch (phase) {
        ExportPhase.idle => 'جاهز للتصدير',
        ExportPhase.preparing => 'تجهيز النص…',
        ExportPhase.encoding => 'تصدير الفيديو…',
        ExportPhase.saving => 'الحفظ بالمعرض…',
        ExportPhase.done => 'خلص التصدير ✅',
        ExportPhase.failed => (error ?? ExportErrorKind.unknown).message,
        ExportPhase.cancelled => 'انلغى التصدير.',
      };
}

/// حجم مقروء: 12.3MB.
String formatBytes(int bytes) {
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)}KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)}MB';
  }
  return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)}GB';
}
