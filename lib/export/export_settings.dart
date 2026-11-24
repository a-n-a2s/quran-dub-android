// إعدادات التصدير (يوم 8، المواصفات القسم 6). جزء صافي بدون Flutter،
// مختبر بـ test/export.
import 'dart:math' as math;

import '../overlay/ayah_font.dart' show toArabicIndic;
import '../pipeline/project_input.dart';
import '../pipeline/recitation_segment.dart';

/// سقف جودة التصدير. اليوم = أبعاد المقطع الأصلي بدون سقف. يوم 18 (حدود
/// الخطط) بيحط [maxShortSide] = 720 / 1080 / 2160 حسب الخطة، بدون أي تعديل
/// على باقي خط التصدير.
class ExportQuality {
  /// أقصى طول لأقصر ضلع بالبكسل. null = بدون سقف (أبعاد الأصل).
  final int? maxShortSide;
  const ExportQuality({this.maxShortSide});

  static const ExportQuality original = ExportQuality();
  static const ExportQuality p720 = ExportQuality(maxShortSide: 720);
  static const ExportQuality p1080 = ExportQuality(maxShortSide: 1080);
  static const ExportQuality p2160 = ExportQuality(maxShortSide: 2160);

  @override
  String toString() => maxShortSide == null ? 'الأصل' : '${maxShortSide}p';
}

/// أبعاد الفيديو الناتج (بعد الدوران، زي ما المستخدم بيشوفه).
class ExportSize {
  final int width;
  final int height;
  const ExportSize(this.width, this.height);

  int get shortSide => math.min(width, height);

  @override
  bool operator ==(Object other) =>
      other is ExportSize && other.width == width && other.height == height;
  @override
  int get hashCode => Object.hash(width, height);
  @override
  String toString() => '$width×$height';
}

/// أبعاد الناتج من أبعاد المقطع بعد الدوران ([VideoInfo.rotatedWidth]/
/// [VideoInfo.rotatedHeight]) وسقف الجودة.
///
/// H.264 بده أبعاد **زوجية**: لو ضلع فردي بنقص بكسل واحد (قص بكسل من الطرف،
/// ما بيتغيّر الشكل ولا النسبة عملياً، ومع `LAYOUT_SCALE_TO_FIT_WITH_CROP`
/// بالـ Kotlin ما في تمطيط). ولو في سقف وتصغير: نفس النسبة، ومقرّب لأقرب زوجي.
ExportSize exportSizeFor(int width, int height,
    {ExportQuality quality = ExportQuality.original}) {
  if (width <= 0 || height <= 0) {
    throw ArgumentError('أبعاد الفيديو غير معروفة: ${width}x$height');
  }
  final short = math.min(width, height);
  final cap = quality.maxShortSide;
  if (cap == null || short <= cap) {
    return ExportSize(_floorEven(width), _floorEven(height));
  }
  final s = cap / short;
  return ExportSize(_roundEven(width * s), _roundEven(height * s));
}

int _floorEven(int v) => math.max(2, v - v % 2);
int _roundEven(double v) => math.max(2, 2 * (v / 2).round());

/// fps للحسابات: لو مش معروف (0) = 30. (التصدير نفسه بيحافظ على توقيت إطارات
/// الأصل، فالـ fps الناتج = الأصل.)
double effectiveFps(double fps) => fps > 0 && fps.isFinite ? fps : 30;

/// bitrate للفيديو (H.264): بكسلات × fps × 0.12 بت/بكسل (~7.5Mbps لـ
/// 1080×1920 بـ 30fps، ~3.3 لـ 720p، ~30 لـ 4K)، بحدود 1–50 Mbps. fps فوق 60
/// بينحسب 60.
int videoBitrateFor(ExportSize size, double fps) {
  final f = math.min(effectiveFps(fps), 60.0);
  final b = size.width * size.height * f * bitsPerPixel;
  return b.round().clamp(minVideoBitrate, maxVideoBitrate);
}

const double bitsPerPixel = 0.12;
const int minVideoBitrate = 1000000;
const int maxVideoBitrate = 50000000;

/// AAC لما الصوت بينعاد ترميزه (ملف تلاوة منفصل، أو صوت مش AAC). صوت الفيديو
/// AAC بينسخ زي ما هو بدون إعادة ترميز.
const int audioBitrate = 192000;

/// حجم الملف المتوقع (للتأكد من المساحة قبل ما نبلّش).
int estimateOutputBytes(int videoBitrate, double durationSeconds,
        {bool hasAudio = true}) =>
    ((videoBitrate + (hasAudio ? audioBitrate : 0)) * durationSeconds / 8 * 1.05)
        .round();

/// مصدر صوت الفيديو الناتج. يوم 11 (أدوات الفيديو) بيضيف التوطية والدمج.
sealed class ExportAudio {
  const ExportAudio();

  /// صوت الفيديو الأصلي زي ما هو.
  const factory ExportAudio.original() = OriginalAudio;

  /// ملف تلاوة منفصل بدل صوت الفيديو (صوت الفيديو مكتوم، نفس المعاينة).
  const factory ExportAudio.external(String path) = ExternalAudio;

  /// بدون صوت (فيديو أصلاً بدون مسار صوت).
  const factory ExportAudio.none() = NoAudio;

  String get kind;
  String? get path => null;

  Map<String, Object?> toJson() => {'kind': kind, 'path': path};

  /// حسب إدخال المشروع: لو ملف التلاوة المنفصل مفعّل → هو، وإلا صوت الفيديو
  /// (لو فيه)، وإلا بدون صوت.
  static ExportAudio forInput(ProjectInput input) {
    if (input.useExternalAudio && input.externalAudioPath != null) {
      return ExportAudio.external(input.externalAudioPath!);
    }
    return input.videoInfo.hasAudioTrack
        ? const ExportAudio.original()
        : const ExportAudio.none();
  }
}

class OriginalAudio extends ExportAudio {
  const OriginalAudio();
  @override
  String get kind => 'original';
}

class ExternalAudio extends ExportAudio {
  final String file;
  const ExternalAudio(this.file);
  @override
  String get kind => 'external';
  @override
  String? get path => file;
}

class NoAudio extends ExportAudio {
  const NoAudio();
  @override
  String get kind => 'none';
}

/// اسم الملف الناتج (ASCII بس، عشان كل التطبيقات والمشاركة):
/// `AyahStudio_050-027-030_20261124-153012.mp4` (سورة-أول آية-آخر آية)،
/// أو `AyahStudio_050-051_...` لو أكثر من سورة، أو بدون مرجع لو ما في آيات.
String exportFileName(List<RecitationSegment> segments, DateTime now) {
  final refs = [
    for (final s in segments)
      if (s.isAyah && s.surah != null && s.ayah != null) (s.surah!, s.ayah!)
  ];
  String two(int v) => v.toString().padLeft(2, '0');
  String three(int v) => v.toString().padLeft(3, '0');
  final stamp = '${now.year}${two(now.month)}${two(now.day)}-'
      '${two(now.hour)}${two(now.minute)}${two(now.second)}';
  var ref = '';
  if (refs.isNotEmpty) {
    final surahs = refs.map((r) => r.$1).toSet();
    if (surahs.length == 1) {
      final ayahs = refs.map((r) => r.$2);
      final lo = ayahs.reduce(math.min), hi = ayahs.reduce(math.max);
      ref = '_${three(surahs.first)}-${three(lo)}'
          '${hi != lo ? '-${three(hi)}' : ''}';
    } else {
      ref = '_${three(surahs.reduce(math.min))}-${three(surahs.reduce(math.max))}';
    }
  }
  return 'AyahStudio${ref}_$stamp.mp4';
}

/// عنوان قصير للإشعار: "٥٠:٢٧–٣٠"، أو "٥٠:٢٧ – ٥١:٣" لو أكثر من سورة.
String exportTitle(List<RecitationSegment> segments) {
  final refs = [
    for (final s in segments)
      if (s.isAyah && s.surah != null && s.ayah != null) (s.surah!, s.ayah!)
  ];
  if (refs.isEmpty) return '';
  String n(int v) => toArabicIndic(v);
  final a = refs.first, b = refs.last;
  if (a.$1 == b.$1) {
    final lo = refs.map((r) => r.$2).reduce(math.min);
    final hi = refs.map((r) => r.$2).reduce(math.max);
    return lo == hi ? '${n(a.$1)}:${n(lo)}' : '${n(a.$1)}:${n(lo)}–${n(hi)}';
  }
  return '${n(a.$1)}:${n(a.$2)} – ${n(b.$1)}:${n(b.$2)}';
}
