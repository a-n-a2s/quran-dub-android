// هندسة الخط الزمني (يوم 10): تحويل ثانية ↔ بكسل (حسب مستوى التكبير)،
// وحدود السحب (ما يتخطى جاره، حد أدنى للطول)، وفحص التداخل لمقطع جديد. جزء
// صافي بدون Flutter، فمستقل تماماً عن واجهة السحب الفعلية وبيتجرب لحاله.
import 'dart:math' as math;

/// تحويل ثانية ↔ بكسل لرسم الخط الزمني. [pixelsPerSecond] هو مستوى التكبير
/// (أكبر = خط أطول وأوضح).
class TimelineGeometry {
  final double durationSeconds;
  final double pixelsPerSecond;

  const TimelineGeometry(
      {required this.durationSeconds, required this.pixelsPerSecond});

  static const double minPixelsPerSecond = 10;
  static const double maxPixelsPerSecond = 2000;

  double get totalWidth => durationSeconds * pixelsPerSecond;

  double xOfSeconds(double seconds) => seconds * pixelsPerSecond;

  double secondsOfX(double x) => pixelsPerSecond <= 0
      ? 0
      : (x / pixelsPerSecond).clamp(0, durationSeconds).toDouble();

  TimelineGeometry zoomed(double factor, {double? focusSeconds}) {
    final next = (pixelsPerSecond * factor)
        .clamp(minPixelsPerSecond, maxPixelsPerSecond)
        .toDouble();
    return TimelineGeometry(durationSeconds: durationSeconds, pixelsPerSecond: next);
  }
}

/// أقل طول للمقطع (ثانية) — ما بنخلي المستخدم يسحب حد لحد ما يختفي المقطع.
const double minSegmentSeconds = 0.3;

/// نتيجة سحب حد مقطع: البداية والنهاية الجديدتين بعد تطبيق الحدود.
class ClampedBounds {
  final double start;
  final double end;
  const ClampedBounds(this.start, this.end);

  @override
  String toString() =>
      '[${start.toStringAsFixed(2)}, ${end.toStringAsFixed(2)}]';
}

/// سحب بداية/نهاية المقطع رقم [index] بقائمة [segments] (مرتّبة بالبداية،
/// (start, end) للمقاطع الظاهرة بالخط الزمني بس): ما يتخطى جاره (المقطع اللي
/// قبله أو بعده بنفس القائمة)، وما ينزل عن [minLength]، وجوا [0, duration].
ClampedBounds clampSegmentDrag({
  required List<(double, double)> segments,
  required int index,
  required double newStart,
  required double newEnd,
  double minLength = minSegmentSeconds,
  required double duration,
}) {
  final lowerBound = index > 0 ? segments[index - 1].$2 : 0.0;
  final upperBound =
      index < segments.length - 1 ? segments[index + 1].$1 : duration;

  var start = newStart
      .clamp(lowerBound, math.max(lowerBound, upperBound - minLength))
      .toDouble();
  var end = newEnd.clamp(start + minLength, upperBound).toDouble();
  // لو الحد الأعلى نفسه أضيق من minLength (جيران قريبين كتير)، منخلي المقطع
  // بأصغر طول ممكن بدل ما ينهار (end < start).
  if (end - start < minLength) {
    end = math.min(upperBound, start + minLength);
    start = math.max(lowerBound, end - minLength);
  }
  return ClampedBounds(start, end);
}

/// في مقطع موجود (من [existing]) بيتقاطع مع [start, end)؟ (لإضافة مقطع يدوي
/// جديد بدون ما يركب فوق موجود).
bool rangeOverlapsExisting(
    List<(double, double)> existing, double start, double end) {
  for (final (s, e) in existing) {
    if (start < e && end > s) return true;
  }
  return false;
}

/// أقرب نطاق فاضي بعد [afterSeconds] ما بيتقاطع مع [existing]، بطول
/// [length] ثانية (لاقتراح مكان افتراضي لمقطع جديد). بيرجع null لو ما في
/// مكان قبل [duration].
(double, double)? nextFreeRange(
  List<(double, double)> existing, {
  required double afterSeconds,
  required double duration,
  double length = 2.0,
}) {
  final sorted = [...existing]..sort((a, b) => a.$1.compareTo(b.$1));
  var t = math.max(0.0, afterSeconds);
  for (final (s, e) in sorted) {
    if (t + length <= s) return (t, t + length);
    if (e > t) t = e;
  }
  if (t + length <= duration) return (t, t + length);
  return null;
}
