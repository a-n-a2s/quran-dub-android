import 'dart:math' as math;

import '../pipeline/recitation_segment.dart';

/// إعدادات توقيت العرض والـ fade (يوم 7).
class OverlayConfig {
  /// مدة ظهور النص (fade in) من بداية المقطع، بالثواني.
  final double fadeIn;

  /// مدة اختفاءه (fade out) قبل نهاية فترة العرض.
  final double fadeOut;

  /// آخر مقطع بالفيديو: كم ثانية بيضل النص بعد نهاية الكلام.
  final double tailAfterLast;

  /// اختياري: أقصى مدة بيضل فيها النص بعد نهاية المقطع لو الفجوة للمقطع
  /// الجاي طويلة. null = بيضل لحد ما يبلّش المقطع الجاي (طلب أنس، يوم 5
  /// لاحظ إنه دقة توقيت النهاية أضعف من البداية).
  final double? maxHoldAfterEnd;

  const OverlayConfig({
    this.fadeIn = 0.25,
    this.fadeOut = 0.25,
    this.tailAfterLast = 0.6,
    this.maxHoldAfterEnd,
  });
}

/// مقطع ظاهر + نافذة عرضه [start, holdEnd).
class OverlayItem {
  final RecitationSegment segment;

  /// مكانه بقائمة المقاطع الأصلية (مرتّبة بالبداية).
  final int index;
  final double start;

  /// نهاية العرض: بداية المقطع **الجاي** (أي نوع: حتى الاستعاذة وغير
  /// القرآني، عشان النص يختفي وقت ما يبلّش الكلام الغير ظاهر) — مش نهاية
  /// المقطع الحالي.
  final double holdEnd;

  const OverlayItem(this.segment, this.index, this.start, this.holdEnd);
}

/// مقطع + شفافيته بلحظة معينة.
class OverlayCue {
  final OverlayItem item;
  final double opacity;
  const OverlayCue(this.item, this.opacity);
}

/// خط زمني للنص فوق الفيديو: متى بيطلع كل مقطع، ومتى بيختفي، وبأي شفافية.
/// جزء صافي (بدون Flutter) وبيتجرب بالاختبارات.
///
/// القواعد:
/// - المقاطع غير الظاهرة ([RecitationSegment.isVisible] = false: استعاذة،
///   وغير القرآني بدون نص مستخدم) **ما بتنعرض أبداً**، بس بتحدد نهاية المقطع
///   اللي قبلها (النص ما بيضل ظاهر فوق كلام مش قرآن).
/// - نافذة العرض: من بداية المقطع لحد بداية اللي بعده، فمافي تداخل بين
///   مقطعين وبيكون مقطع واحد بس ظاهر بأي لحظة.
/// - fade in بأول النافذة وfade out بآخرها (smoothstep). لو النافذة قصيرة
///   بتتصغّر الـ fades نص نص.
class OverlayTimeline {
  final List<OverlayItem> items;
  final OverlayConfig config;

  const OverlayTimeline._(this.items, this.config);

  factory OverlayTimeline.build(
    List<RecitationSegment> segments, {
    OverlayConfig config = const OverlayConfig(),
    double? videoDuration,
  }) {
    // ترتيب بالبداية، وعند التساوي بترتيب الإدخال (List.sort مش ثابت).
    final order = List<int>.generate(segments.length, (i) => i)
      ..sort((a, b) {
        final c = segments[a].start.compareTo(segments[b].start);
        return c != 0 ? c : a.compareTo(b);
      });
    final sorted = [for (final i in order) segments[i]];
    final items = <OverlayItem>[];
    for (var i = 0; i < sorted.length; i++) {
      final s = sorted[i];
      if (!s.isVisible) continue;
      double holdEnd;
      if (i + 1 < sorted.length) {
        holdEnd = sorted[i + 1].start;
        // مقطع الجاي بيبلّش قبل ما ينتهي هاد: بيقطع عنده.
        if (holdEnd > s.end && config.maxHoldAfterEnd != null) {
          holdEnd = math.min(holdEnd, s.end + config.maxHoldAfterEnd!);
        }
      } else {
        holdEnd = s.end + config.tailAfterLast;
      }
      if (videoDuration != null && videoDuration > 0) {
        holdEnd = math.min(holdEnd, videoDuration);
      }
      if (holdEnd <= s.start) continue; // نافذة فاضية
      items.add(OverlayItem(s, i, s.start, holdEnd));
    }
    return OverlayTimeline._(items, config);
  }

  /// المقطع الظاهر بالثانية [t] مع شفافيته، أو null لو ما في شي ظاهر.
  OverlayCue? cueAt(double t) {
    final item = _itemAt(t);
    if (item == null) return null;
    final o = opacityOf(item, t);
    return o <= 0 ? null : OverlayCue(item, o);
  }

  OverlayItem? _itemAt(double t) {
    // النوافذ مرتّبة وغير متداخلة: بحث ثنائي.
    var lo = 0, hi = items.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final it = items[mid];
      if (t < it.start) {
        hi = mid - 1;
      } else if (t >= it.holdEnd) {
        lo = mid + 1;
      } else {
        return it;
      }
    }
    return null;
  }

  double opacityOf(OverlayItem item, double t) {
    final window = item.holdEnd - item.start;
    if (window <= 0 || t < item.start || t >= item.holdEnd) return 0;
    final fi = math.min(config.fadeIn, window / 2);
    final fo = math.min(config.fadeOut, window / 2);
    return _ramp(t - item.start, fi) * _ramp(item.holdEnd - t, fo);
  }

  static double _ramp(double x, double d) {
    if (d <= 0) return x >= 0 ? 1 : 0;
    final v = (x / d).clamp(0.0, 1.0);
    return v * v * (3 - 2 * v); // smoothstep
  }
}
