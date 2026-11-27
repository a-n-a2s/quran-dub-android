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

/// التصاق حد مقطع وقت السحب (نفس فكرة خطوط الإرشاد بسحب العناصر، يوم 9):
/// لو [value] قريبة من وحدة من [candidates] (حد الجار، أو موقع التشغيل) أقل
/// من [threshold] ثانية، بترجع القيمة الملتصقة (والـ index تبعها عشان الواجهة
/// تعمل هزّة خفيفة مرة وحدة)، وإلا نفسها و null.
(double, int?) snapSeconds(double value, List<double> candidates,
    {required double threshold}) {
  var best = value;
  int? which;
  var bestD = threshold;
  for (var i = 0; i < candidates.length; i++) {
    final d = (candidates[i] - value).abs();
    if (d <= bestD) {
      bestD = d;
      best = candidates[i];
      which = i;
    }
  }
  return (best, which);
}

/// قراءة ثواني من حقل كتابة: بيقبل الأرقام العربية-الهندية (٠–٩) والفارسية،
/// الفاصلة العشرية العربية (٫) أو الفاصلة (,) أو النقطة، وكمان دقائق:ثواني
/// (`1:05.3`). نص فاضي أو غلط → null (الحقل بيرجع لقيمته).
double? parseSecondsInput(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return null;
  final b = StringBuffer();
  for (final u in s.runes) {
    if (u >= 0x0660 && u <= 0x0669) {
      b.writeCharCode(0x30 + u - 0x0660);
    } else if (u >= 0x06F0 && u <= 0x06F9) {
      b.writeCharCode(0x30 + u - 0x06F0);
    } else if (u == 0x066B || u == 0x2C) {
      b.write('.');
    } else if (u == 0x066C || u == 0x20) {
      // فاصل آلاف أو مسافة: بنتجاهلهم.
    } else {
      b.writeCharCode(u);
    }
  }
  s = b.toString();
  final parts = s.split(':');
  if (parts.length > 2) return null;
  if (parts.length == 2) {
    final m = int.tryParse(parts[0]);
    final sec = double.tryParse(parts[1]);
    if (m == null || sec == null || m < 0 || sec < 0 || sec >= 60) return null;
    return m * 60 + sec;
  }
  final v = double.tryParse(s);
  if (v == null || v.isNaN || v.isInfinite || v < 0) return null;
  return v;
}

/// عرض ثواني بحقل البداية/النهاية: خانتين عشريتين (أدق من 0.1 المطلوبة).
String formatSecondsInput(double v) => v.toStringAsFixed(2);

/// عرض مختصر للخط الزمني: `0:07.4` أو `12:03.0`.
String formatClock(double seconds) {
  final s = seconds < 0 ? 0.0 : seconds;
  final m = s ~/ 60;
  final rest = s - m * 60;
  return '$m:${rest.toStringAsFixed(1).padLeft(4, '0')}';
}
