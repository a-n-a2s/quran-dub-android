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

  /// دائرة رقم الآية.
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
}
