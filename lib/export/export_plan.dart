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

import '../overlay/overlay_layout.dart';
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
  bool operator ==(Object other) =>
      other is OverlayBand && other.top == top && other.height == height;
  @override
  int get hashCode => Object.hash(top, height);
  @override
  String toString() => 'شريط $top..$bottom';
}

/// الأجزاء العمودية من الفيديو اللي ممكن يطلع فيها حبر (نص أو ظل أو خلفية)
/// لتخطيط [layout]، كأزواج (أعلى، أسفل) بالبكسل، **بدون** هامش الظل. بتتحسب
/// من نفس [OverlayMetrics] ونفس قواعد [AyahOverlayFrame] (من غير قياس نص):
///  - الكتلة الأساسية: من [OverlayMetrics.top] لـ [OverlayMetrics.bottomLimit]
///    (الكتلة الأطول بتتصغّر لتتسع، فما بتتعدّاها).
///  - اسم السورة بمكانه الافتراضي: فوق أول سطر الآية، بارتفاع سطرين كحد أقصى.
///  - العنصر المنسحب: من أعلاه لحد أسفل الصندوق اللي بيتسع فيه
///    ([OverlayMetrics.detachedHeightAt]؛ وعناصر السطر الواحد بارتفاع سطرين).
List<(double, double)> overlayInkRanges(OverlayMetrics m, OverlayLayout layout) {
  final out = <(double, double)>[];
  double singleLineSize(OverlayElement e) => switch (e) {
        OverlayElement.surahRef => m.unit * OverlayMetrics.surahRefSizeRatio,
        OverlayElement.reciter => m.unit * OverlayMetrics.reciterSizeRatio,
        _ => m.unit * OverlayMetrics.translationSizeRatio,
      };
  var flowVisible = false;
  for (final e in flowElements) {
    if (layout.isEnabled(e) && !layout[e].isDetached) flowVisible = true;
  }
  if (flowVisible) out.add((m.top, m.bottomLimit));
  final sr = layout[OverlayElement.surahRef];
  if (sr.enabled && !sr.isDetached) {
    final h = m.singleLineMaxHeight(singleLineSize(OverlayElement.surahRef), sr.scale);
    final bottom = m.top - m.unit * OverlayMetrics.surahRefGapRatio;
    out.add((bottom - h, bottom));
  }
  for (final e in layout.detached) {
    final top = layout[e].anchor!.top * m.height;
    var h = m.detachedHeightAt(top);
    if (e == OverlayElement.surahRef || e == OverlayElement.reciter) {
      h = math.min(h, m.singleLineMaxHeight(singleLineSize(e), layout[e].scale));
    }
    out.add((top, top + h));
  }
  return out;
}

/// شريط الكتلة من نفس [OverlayMetrics] اللي بيستعملها [AyahOverlayFrame]:
/// اتحاد [overlayInkRanges] + هامش ([OverlayMetrics.bandMargin])، ضمن حدود
/// الفيديو. الهامش مش حسب شدة الظل الحالية بل أكبر ظل ممكن (100%)، فالشريط
/// ما بيتغيّر لما المستخدم يحرّك السلايدر وبيغطي أقوى ظل. الحدود زوجية (البداية والارتفاع) عشان مركز الشريط يكون على بكسل
/// كامل (بدون أي نعومة من أخذ العينات بالـ GPU).
///
/// يوم 9 (سحب العناصر لأي مكان): بالافتراضي (آية + تفسير) نفس شريط يوم 8
/// بالضبط. لما عنصر ينسحب أو يتشغّل اسم السورة، الشريط بيتسع ليغطي اتحاد
/// مستطيلاتهم. هاد المكان الوحيد اللي بيتغيّر بالتصدير.
OverlayBand overlayBandFor(OverlayMetrics m,
    {OverlayLayout layout = OverlayLayout.reference}) {
  final ranges = overlayInkRanges(m, layout);
  if (ranges.isEmpty) ranges.add((m.top, m.bottomLimit));
  var lo = ranges.first.$1, hi = ranges.first.$2;
  for (final r in ranges) {
    lo = math.min(lo, r.$1);
    hi = math.max(hi, r.$2);
  }
  final margin = m.bandMargin;
  var top = (lo - margin).floor();
  top = math.max(0, top - top % 2);
  var bottom = math.min(m.height, (hi + margin).ceil());
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

  /// شكل النص (يوم 9): نفس [OverlayStyle.toJson] اللي انرسمت فيه الصور —
  /// للتقرير والفحص بس (الـ Kotlin ما بيقرأه، الصور جاهزة).
  final Map<String, Object?> style;

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
    this.style = const {},
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
        'style': style,
      };
}
