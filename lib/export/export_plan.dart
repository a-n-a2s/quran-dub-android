// خطة التصدير (يوم 8): كل اللي الـ Kotlin (Media3 Transformer) بيحتاجه عشان
// يحرق النص بالفيديو. جزء صافي بدون Flutter، مختبر بـ test/export.
//
// الفكرة: النص نفسه ما بينرسم بالـ Kotlin أبداً. كل مقطع ظاهر بـ
// [OverlayTimeline] بينرسم **مرة وحدة** بـ [AyahOverlayFrame] (نفس ويدجت
// المعاينة) كصورة شفافة PNG بأبعاد الناتج الحقيقية، مقصوصة على شريط الكتلة
// ([OverlayBand]). الـ Kotlin بيحط الصورة فوق الإطارات من [ExportCue.start]
// لـ [ExportCue.end]، وبشفافية بتتبع [OverlayTimeline.opacityOf] بالضبط
// ([ExportCue.alpha] عينات منها). هيك أي تغيير بالشكل أو بالتوقيت (يوم 9/10)
// بينعكس على التصدير بدون ما نلمس الـ Kotlin.
import 'dart:math' as math;

import '../overlay/overlay_metrics.dart';
import '../overlay/overlay_timeline.dart';
import 'export_settings.dart';

/// الشريط الأفقي من الفيديو اللي فيه النص (بعرض الفيديو كامل). بنرسم وبنحرق
/// هالشريط بس بدل الإطار كامل (ذاكرة أقل بكتير، خصوصاً 4K).
class OverlayBand {
  final int top;
  final int height;
  const OverlayBand(this.top, this.height);

  int get bottom => top + height;

  Map<String, Object?> toJson() => {'top': top, 'height': height};
  @override
  String toString() => 'شريط $top..$bottom';
}

/// هامش فوق وتحت الكتلة كنسبة من الوحدة: الظل (لو مشغّل) بيطلع شوي برا حدود
/// الحروف (نعومة ~2.5×[OverlayMetrics.shadowBlur] + إزاحة)، وعلامات التشكيل
/// فوق أول سطر.
const double bandMarginUnits = 0.05;

/// شريط الكتلة من نفس [OverlayMetrics] اللي بيستعملها [AyahOverlayFrame]:
/// من [OverlayMetrics.top] لـ [OverlayMetrics.bottomLimit] + هامش، ضمن حدود
/// الفيديو. الحدود زوجية (البداية والارتفاع) عشان مركز الشريط يكون على بكسل
/// كامل (بدون أي نعومة من أخذ العينات بالـ GPU).
///
/// يوم 9 (سحب العناصر لأي مكان): لازم الشريط يغطي كل العناصر — أسهل شي يصير
/// الإطار كامل `OverlayBand(0, height)` أو اتحاد مستطيلات العناصر. هاد المكان
/// الوحيد اللي بيتغيّر.
OverlayBand overlayBandFor(OverlayMetrics m) {
  final margin = m.unit * bandMarginUnits;
  var top = (m.top - margin).floor();
  top = math.max(0, top - top % 2);
  var bottom = math.min(m.height, (m.bottomLimit + margin).ceil());
  if ((bottom - top).isOdd) bottom = bottom < m.height ? bottom + 1 : bottom - 1;
  return OverlayBand(top, math.max(2, bottom - top));
}

/// عينة شفافية: بالثانية [t] الشفافية [a] (0..1).
class AlphaKey {
  final double t;
  final double a;
  const AlphaKey(this.t, this.a);
  List<double> toJson() => [_r(t, 1e6), _r(a, 1e4)];
  @override
  String toString() => '(${t.toStringAsFixed(3)}, ${a.toStringAsFixed(3)})';
}

double _r(double v, double scale) => (v * scale).round() / scale;

/// عينات شفافية المقطع [item] من [OverlayTimeline.opacityOf] نفسها (مش نسخة
/// من منحنى الـ fade): كل [step] ثانية على نافذة العرض كاملة، وبنشيل العينات
/// اللي بنص خط مستقيم (الجزء الثابت بنص النافذة). الـ Kotlin بيوصل بينها
/// خطياً: الفرق عن المنحنى الحقيقي < 0.01 بـ step = 1/60.
List<AlphaKey> alphaKeysFor(OverlayTimeline tl, OverlayItem item,
    {double step = 1 / 60}) {
  final start = item.start, end = item.holdEnd;
  final n = math.max(2, ((end - start) / step).ceil());
  final raw = <AlphaKey>[];
  for (var i = 0; i <= n; i++) {
    final t = i == n ? end : start + (end - start) * i / n;
    // opacityOf(end) = 0 (النافذة [start, end))، وهاد المطلوب بآخرها.
    raw.add(AlphaKey(t, tl.opacityOf(item, t)));
  }
  final out = <AlphaKey>[raw.first];
  for (var i = 1; i < raw.length - 1; i++) {
    final p = out.last, c = raw[i], nx = raw[i + 1];
    // c على الخط بين آخر عينة محفوظة واللي بعدها؟ بنشيلها.
    final lerp = p.a + (nx.a - p.a) * (c.t - p.t) / (nx.t - p.t);
    if ((lerp - c.a).abs() > 1e-4) out.add(c);
  }
  out.add(raw.last);
  return out;
}

/// مقطع محروق: صورة النص (PNG شفافة بحجم [OverlayBand]) من [start] لـ [end].
class ExportCue {
  final int index;
  final double start;
  final double end;
  final String png;
  final List<AlphaKey> alpha;

  const ExportCue({
    required this.index,
    required this.start,
    required this.end,
    required this.png,
    required this.alpha,
  });

  Map<String, Object?> toJson() => {
        'start': _r(start, 1e6),
        'end': _r(end, 1e6),
        'png': png,
        'alpha': [for (final k in alpha) k.toJson()],
      };
}

/// تحويل الخط الزمني لقائمة مقاطع محروقة. [pngPathOf] = مسار صورة المقطع رقم
/// i بـ [OverlayTimeline.items].
List<ExportCue> exportCuesFor(
    OverlayTimeline tl, String Function(int i) pngPathOf) {
  return [
    for (var i = 0; i < tl.items.length; i++)
      ExportCue(
        index: i,
        start: tl.items[i].start,
        end: tl.items[i].holdEnd,
        png: pngPathOf(i),
        alpha: alphaKeysFor(tl, tl.items[i]),
      ),
  ];
}

/// كل شي الـ Kotlin بيحتاجه (`ExportPlan.kt` بيقرأ نفس المفاتيح).
class ExportPlan {
  static const int version = 1;

  final String id;
  final String inputPath;
  final ExportAudio audio;
  final ExportSize size;

  /// أبعاد المقطع الأصلي بعد الدوران (للتقرير/الفحص بعد التصدير).
  final ExportSize sourceSize;
  final int videoBitrate;
  final double fps;
  final double durationSeconds;
  final String fileName;

  /// ملف مؤقت بالـ cache، وبعدين بينسخ للمعرض (Movies/AyahStudio).
  final String outputPath;
  final OverlayBand band;
  final List<ExportCue> cues;

  /// عنوان الإشعار (مثلاً "ق ٢٧–٣٠").
  final String title;

  const ExportPlan({
    required this.id,
    required this.inputPath,
    required this.audio,
    required this.size,
    required this.sourceSize,
    required this.videoBitrate,
    required this.fps,
    required this.durationSeconds,
    required this.fileName,
    required this.outputPath,
    required this.band,
    required this.cues,
    required this.title,
  });

  bool get hasAudio => audio is! NoAudio;

  int get estimatedBytes =>
      estimateOutputBytes(videoBitrate, durationSeconds, hasAudio: hasAudio);

  Map<String, Object?> toJson() => {
        'version': version,
        'id': id,
        'input': inputPath,
        'audio': audio.toJson(),
        'width': size.width,
        'height': size.height,
        'sourceWidth': sourceSize.width,
        'sourceHeight': sourceSize.height,
        'videoBitrate': videoBitrate,
        'audioBitrate': audioBitrate,
        'fps': fps,
        'durationMs': (durationSeconds * 1000).round(),
        'fileName': fileName,
        'output': outputPath,
        'estimatedBytes': estimatedBytes,
        'band': band.toJson(),
        'cues': [for (final c in cues) c.toJson()],
        'title': title,
      };
}
