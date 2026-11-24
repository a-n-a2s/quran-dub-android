import 'dart:ui' show Color;

/// ألوان النص فوق الفيديو (من المقطع المرجعي).
const Color overlayWhite = Color(0xFFFFFFFF);
const Color overlayGold = Color(0xFFD9B55E);
const Color overlayBlack = Color(0xFF000000);

/// لون النص فوق الفيديو: **أبيض أو أسود بس** (طلب أنس يوم 7، وأكّده يوم 9:
/// "الآيات كلها بالأسود والأبيض"). الأبيض = شكل المقطع المرجعي (النص أبيض
/// والأقواس ذهبية). الأسود = كل شي أسود (الآية والأقواس وعلامة الرقم
/// والتفسير)، لأنه الذهبي كمان ما بيبيّن على الأبيض. الظل والخلفية الشفافة
/// بلون **عكس** لون النص ([shadow] / [backdrop]). الألوان الثانية مؤجّلة
/// (قرار أنس يوم 9).
enum OverlayTextColor {
  white('أبيض'),
  black('أسود');

  final String label;
  const OverlayTextColor(this.label);

  static const OverlayTextColor defaultColor = white;

  Color get text => this == white ? overlayWhite : overlayBlack;
  Color get bracket => this == white ? overlayGold : overlayBlack;

  /// لون الظل (لو المستخدم شغّله): **عكس لون النص** (طلب أنس): نص أبيض →
  /// ظل أسود، ونص أسود → ظل أبيض.
  Color get shadow => this == white ? overlayBlack : overlayWhite;

  /// لون الخلفية الشفافة (شريط/صندوق) ورا النص: نفس لون الظل (عكس النص).
  Color get backdrop => shadow;

  /// اللون الأوضح فوق خلفية متوسط سطوعها [luma] (0 أسود .. 1 أبيض) ونسبة
  /// البكسلات الفاتحة فيها [brightFraction] (بمنطقة النص).
  static OverlayTextColor forBackground(double luma, double brightFraction) =>
      luma > 0.58 || brightFraction > 0.5 ? black : white;
}
