import 'dart:math' as math;

/// مقاسات النص فوق الفيديو (يوم 7). جزء صافي بدون Flutter.
///
/// المصدر: التصوّر المرسوم للمقطع المرجعي (إطار 450×800): الآية 25px، التفسير
/// 15px، ارتفاع سطر الآية 1.9 والتفسير 1.75، فجوة 6px، حواف 26px، دائرة الرقم
/// 26px بحد 1.5px ورقم 12px، وأول سطر بـ ~61% من الارتفاع (مقطع أنس 1080×1920).
/// كل شي بيتحسب كنسبة من **الوحدة** = أقصر ضلع (عرض الفيديو العمودي والمربّع،
/// وارتفاع الأفقي)، فنفس الشكل بالضبط على كل الأبعاد، والتصدير (يوم 8)
/// بيستعمل نفس المقاسات بأبعاد المقطع الأصلي.
class OverlayMetrics {
  /// أبعاد الفيديو الفعلية بعد الدوران (VideoInfo.rotatedWidth/Height).
  final int width;
  final int height;

  /// الوحدة = min(width, height).
  final double unit;

  final double ayahFontSize;
  final double tafsirFontSize;
  final double ayahLineHeight;
  final double tafsirLineHeight;

  /// الفجوة بين آخر سطر آية وأول سطر تفسير.
  final double gap;

  /// دائرة رقم الآية (يوم 7 الأول). من تصليحات يوم 7 الرقم صار علامة نهاية
  /// الآية زي المصحف بنفس خط الآية ([AyahFont.ayahNumberMark])، فهالمقاسات
  /// ما عادت بتنستعمل بالرسم (باقية للتوافق، والمحرر يوم 9 ممكن يستعملها).
  final double circleSize;
  final double circleBorder;
  final double numberFontSize;
  final double circleMargin;

  /// أعلى الكتلة (أول سطر آية) من أعلى الفيديو.
  final double top;

  /// آخر حد تحتاني للكتلة: لو أطول، بتصغّر لتتسع (ما بتطلع برا الفيديو).
  final double bottomLimit;

  /// أقصى عرض للنص.
  final double maxTextWidth;

  const OverlayMetrics._({
    required this.width,
    required this.height,
    required this.unit,
    required this.ayahFontSize,
    required this.tafsirFontSize,
    required this.ayahLineHeight,
    required this.tafsirLineHeight,
    required this.gap,
    required this.circleSize,
    required this.circleBorder,
    required this.numberFontSize,
    required this.circleMargin,
    required this.top,
    required this.bottomLimit,
    required this.maxTextWidth,
  });

  // نسب من إطار المرجع (عرض 450).
  static const double _refW = 450;
  static const double ayahSizeRatio = 25 / _refW;
  static const double tafsirSizeRatio = 15 / _refW;
  static const double ayahLineHeightValue = 1.9;
  static const double tafsirLineHeightValue = 1.75;
  static const double gapRatio = 6 / _refW;
  static const double sidePaddingRatio = 26 / _refW;
  static const double circleRatio = 26 / _refW;
  static const double circleBorderRatio = 1.5 / _refW;
  static const double numberSizeRatio = 12 / _refW;
  static const double circleMarginRatio = 6 / _refW;

  // يوم 9: عناصر جديدة (نفس الأسلوب: نسب من عرض إطار المرجع 450).
  /// اسم السورة ورقم الآية (Amiri): أصغر من التفسير شوي.
  static const double surahRefSizeRatio = 14 / _refW;

  /// اسم القارئ (Amiri).
  static const double reciterSizeRatio = 14 / _refW;

  /// الترجمة (يوم 12 بيعبّيها).
  static const double translationSizeRatio = 14 / _refW;

  /// اسم السورة بيقعد فوق أول سطر الآية بهالمسافة (الآية إلها فراغ علوي من
  /// ارتفاع السطر 1.9).
  static const double surahRefGapRatio = 2 / _refW;

  /// خلفية شفافة ورا العنصر (صندوق/شريط): حشوة وزوايا (جزء من تخطيط العنصر،
  /// فما بتأثر على الافتراضي بدون خلفية).
  static const double backdropPadXRatio = 10 / _refW;
  static const double backdropPadYRatio = 4 / _refW;
  static const double backdropRadiusRatio = 8 / _refW;

  /// أقصى عدد أسطر لعناصر السطر الواحد (اسم السورة، القارئ): أطول من هيك
  /// بيتقطع، فارتفاعها محدود وبنعرف نحسب شريط التصدير.
  static const int singleLineElementMaxLines = 2;

  /// أقل ارتفاع متاح لعنصر منسحب لقريب من أسفل الفيديو (كسر من الوحدة).
  static const double minDetachedHeightUnits = 0.12;
  /// أول سطر الآية عند 61% من ارتفاع الفيديو (مقطع أنس المرجعي).
  static const double topFraction = 0.61;

  /// هامش تحتاني أدنى.
  static const double bottomMarginFraction = 0.04;

  /// أقصى عرض نص كنسبة من الوحدة (بيمنع أسطر طويلة جداً بالفيديو الأفقي).
  static const double maxWidthUnits = 1.15;

  factory OverlayMetrics.forSize(int width, int height) {
    assert(width > 0 && height > 0);
    final u = math.min(width, height).toDouble();
    final side = u * sidePaddingRatio;
    final maxW = math.min(width - 2 * side, u * maxWidthUnits);
    return OverlayMetrics._(
      width: width,
      height: height,
      unit: u,
      ayahFontSize: u * ayahSizeRatio,
      tafsirFontSize: u * tafsirSizeRatio,
      ayahLineHeight: ayahLineHeightValue,
      tafsirLineHeight: tafsirLineHeightValue,
      gap: u * gapRatio,
      circleSize: u * circleRatio,
      circleBorder: u * circleBorderRatio,
      numberFontSize: u * numberSizeRatio,
      circleMargin: u * circleMarginRatio,
      top: height * topFraction,
      bottomLimit: height * (1 - bottomMarginFraction),
      maxTextWidth: maxW,
    );
  }

  /// أعلى نقطة للكتلة بعد ما تتسع بالمساحة المتاحة (للاختبار وللتصدير).
  double get availableHeight => bottomLimit - top;

  // -------------------------------------------------------------------
  // يوم 9: الظل بشدة 0..1، شريط الكتلة، العناصر المنسحبة
  // -------------------------------------------------------------------

  /// ظل النص بشدة [strength] من 0 (بدون ظل) لـ 1 (أقوى ظل معقول وواضح). الشدة
  /// بتأثر على **الكثافة والحجم/النعومة** معاً (مش بس الشفافية): طبقتين،
  /// واحدة قريبة وكثيفة (بتفصل حواف الحروف عن الخلفية) وواحدة أنعم وأوسع،
  /// وبتتكرّر الطبقة (تراكم) كل ما زادت الشدة. كله نسبة من [unit]، فنفس الشكل
  /// بكل الأبعاد. اللون بيجي من [OverlayTextColor.shadow] (عكس لون النص).
  List<ShadowLayer> shadowLayers(double strength) {
    final s = strength.clamp(0.0, 1.0).toDouble();
    if (s <= 0) return const [];
    final px = unit / _refW; // بكسل واحد من إطار المرجع
    final near = ShadowLayer(
        dy: px * (0.8 + 1.0 * s), blur: px * (1.0 + 1.4 * s), alpha: 0.25 + 0.70 * s);
    final soft = ShadowLayer(
        dy: px * 0.5 * s, blur: px * (2.5 + 6.5 * s), alpha: 0.15 + 0.70 * s);
    final nearCount = 1 + (s > 0.5 ? 1 : 0) + (s > 0.85 ? 1 : 0);
    final softCount = s > 0.6 ? 2 : 1;
    return [
      for (var i = 0; i < nearCount; i++) near,
      for (var i = 0; i < softCount; i++) soft,
    ];
  }

  /// أبعد مسافة (بالبكسل) بيوصل لها الظل بشدة 1.0 عن حروف النص (3.5 سيغما
  /// للنعومة + الإزاحة). شريط التصدير لازم يغطيها.
  double get maxShadowExtent {
    var e = 0.0;
    for (final l in shadowLayers(1.0)) {
      e = math.max(e, 3.5 * ShadowLayer.sigmaOf(l.blur) + l.dy);
    }
    return e;
  }

  /// هامش شريط التصدير فوق وتحت الكتلة: أكبر ظل ممكن (شدة 1) + 3% من الوحدة
  /// للتشكيل وفروقات رسم الحواف (كان 5% من الوحدة بيوم 8).
  double get bandMargin => math.max(unit * 0.05, maxShadowExtent + unit * 0.03);

  /// ارتفاع الصندوق اللي بيتسع فيه عنصر منسحب أعلاه عند [topPx]: لحد الحد
  /// التحتاني، وبأقل ارتفاع ([minDetachedHeightUnits]) لو قريب من الأسفل.
  /// العنصر الأطول من هيك بيتصغّر ليتسع (زي الكتلة الأساسية).
  double detachedHeightAt(double topPx) =>
      math.max(bottomLimit - topPx, unit * minDetachedHeightUnits);

  /// أقصى ارتفاع لعنصر السطر الواحد (اسم السورة/القارئ) بحجم [scale] مع
  /// الحشوة (لحساب شريط التصدير).
  double singleLineMaxHeight(double fontSize, double scale) =>
      singleLineElementMaxLines * fontSize * scale * tafsirLineHeight +
      2 * unit * backdropPadYRatio * scale;
}

/// طبقة ظل: إزاحة لتحت [dy] ونعومة [blur] (blurRadius بتاع Flutter) وشفافية
/// [alpha]، كلها بالبكسل.
class ShadowLayer {
  final double dy;
  final double blur;
  final double alpha;
  const ShadowLayer({required this.dy, required this.blur, required this.alpha});

  /// سيغما الـ Gaussian الفعلية لـ blurRadius بـ Flutter (`Shadow.blurSigma`).
  static double sigmaOf(double blurRadius) =>
      blurRadius > 0 ? blurRadius * 0.57735 + 0.5 : 0;
}
