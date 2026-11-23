// معلومات ومصدر مقطع المستخدم (يوم 6، المواصفات القسم 2). جزء صافي
// بدون Flutter، فبيتجرب بالاختبارات مباشرة.

/// شكل الفيديو الظاهر للمستخدم، بعد حساب الدوران.
enum VideoOrientation { portrait, landscape, square }

/// مصدر مقطع المستخدم.
enum VideoSource { gallery, camera }

/// معلومات فيديو خام من `lib/platform/video_info.dart` (MediaExtractor /
/// MediaMetadataRetriever بالـ Kotlin). [width]/[height] هم أبعاد الإطار
/// الخام *قبل* الدوران (نفس ما بترجّعه MediaFormat)، و[rotationDegrees]
/// دوران العرض المطلوب (0/90/180/270 عادة). استعمل [rotatedWidth] و
/// [rotatedHeight] للأبعاد الفعلية اللي المستخدم بيشوفها، عشان الناتج
/// (يوم 8) يطلع بنفس أبعاد المقطع الأصلي.
class VideoInfo {
  final int width;
  final int height;
  final int rotationDegrees;
  final int durationMs;

  /// 0 لو ما قدرنا نحدده (مثلاً ملف بدون KEY_FRAME_RATE صريح).
  final double fps;
  final bool hasAudioTrack;

  const VideoInfo({
    required this.width,
    required this.height,
    required this.rotationDegrees,
    required this.durationMs,
    required this.fps,
    required this.hasAudioTrack,
  });

  /// الدوران لأقرب 0/90/180/270 (حتى لو القيمة الخام غريبة أو سلبية).
  int get normalizedRotation {
    final r = rotationDegrees % 360;
    final positive = r < 0 ? r + 360 : r;
    final nearest = ((positive / 90).round() * 90) % 360;
    return nearest;
  }

  bool get _swapsDimensions =>
      normalizedRotation == 90 || normalizedRotation == 270;

  /// العرض الفعلي بعد الدوران (اللي المستخدم بيشوفه، وبده يطلع بيه الناتج).
  int get rotatedWidth => _swapsDimensions ? height : width;

  /// الارتفاع الفعلي بعد الدوران.
  int get rotatedHeight => _swapsDimensions ? width : height;

  VideoOrientation get orientation {
    if (rotatedWidth == rotatedHeight) return VideoOrientation.square;
    return rotatedWidth > rotatedHeight
        ? VideoOrientation.landscape
        : VideoOrientation.portrait;
  }

  double get durationSeconds => durationMs / 1000;

  /// مقطع قصير جداً عشان يتحلل (أقل من ثانية ونص صوت تقريباً).
  bool get tooShort => durationMs > 0 && durationMs < 1500;

  factory VideoInfo.fromJson(Map<String, Object?> j) => VideoInfo(
        width: (j['width'] as num).toInt(),
        height: (j['height'] as num).toInt(),
        rotationDegrees: (j['rotation'] as num).toInt(),
        durationMs: (j['durationMs'] as num).toInt(),
        fps: (j['fps'] as num).toDouble(),
        hasAudioTrack: j['hasAudioTrack'] as bool,
      );

  Map<String, Object?> toJson() => {
        'width': width,
        'height': height,
        'rotation': rotationDegrees,
        'durationMs': durationMs,
        'fps': fps,
        'hasAudioTrack': hasAudioTrack,
      };

  @override
  String toString() =>
      '${rotatedWidth}x$rotatedHeight (خام ${width}x$height، دوران ${rotationDegrees}°)، '
      '${durationSeconds.toStringAsFixed(1)}s، ${fps > 0 ? '${fps.toStringAsFixed(1)}fps، ' : ''}'
      '${hasAudioTrack ? 'فيه صوت' : 'بدون صوت'}';
}

/// إدخال المشروع (يوم 6، المواصفات القسم 2): مقطع المستخدم (من المعرض أو
/// تصوير مباشر)، + مصدر التلاوة الاختياري: صوت المقطع نفسه، أو ملف تلاوة
/// منفصل بيتركّب عليه (والتعرف بيصير على الملف المنفصل).
class ProjectInput {
  final String videoPath;
  final VideoSource source;
  final VideoInfo videoInfo;

  /// ملف تلاوة منفصل اختياري (المواصفات: "تلاوة من ملف صوت منفصل بيتركّب
  /// على الفيديو"). null = ما في ملف منفصل.
  final String? externalAudioPath;

  /// true = التعرف عـ [externalAudioPath] بدل صوت الفيديو.
  final bool useExternalAudio;

  const ProjectInput({
    required this.videoPath,
    required this.source,
    required this.videoInfo,
    this.externalAudioPath,
    this.useExternalAudio = false,
  });

  bool get hasExternalAudio => externalAudioPath != null;

  /// الملف اللي [RecitationPipeline.analyze] بده يتعرف عليه: ملف التلاوة
  /// المنفصل لو موجود ومُفعّل، وإلا صوت الفيديو نفسه (أو ملف صوت مباشر لو
  /// [source] أصلاً كان صوت بدون فيديو — نادراً، بس النوع نفسه بيشتغل).
  String get recognitionSourcePath =>
      (useExternalAudio && externalAudioPath != null)
          ? externalAudioPath!
          : videoPath;

  ProjectInput withExternalAudio(String path, {bool use = true}) =>
      ProjectInput(
        videoPath: videoPath,
        source: source,
        videoInfo: videoInfo,
        externalAudioPath: path,
        useExternalAudio: use,
      );

  ProjectInput withoutExternalAudio() => ProjectInput(
        videoPath: videoPath,
        source: source,
        videoInfo: videoInfo,
      );

  ProjectInput withUseExternalAudio(bool use) => ProjectInput(
        videoPath: videoPath,
        source: source,
        videoInfo: videoInfo,
        externalAudioPath: externalAudioPath,
        useExternalAudio: use,
      );
}
