/// تطبيع النص العربي لـ "مفتاح رسم" (rasm skeleton) موحّد، عشان نقدر نقارن
/// نص خارج من محرك التعرف على الصوت (بدون تشكيل، وممكن بإملاء عادي أو
/// بالرسم العثماني) مع نص `text_uthmani` الكامل بقاعدة البيانات.
///
/// القواعد (لازم تضل مطابقة لـ tool/proto/matcher.py):
/// 1. حذف كل الحركات والتنوين والشدة والسكون، وعلامات المصحف الصغيرة
///    (علامات الوقف، الواو/الياء الصغيرة، الألف الخنجرية ٰ، المدّ، ...).
/// 2. حذف كل أشكال الألف والهمزة (ا أ إ آ ٱ ء): هاي أكثر حروف بيختلف فيها
///    الرسم العثماني عن الإملائي (العٰلمين/العالمين، الصلوٰة/الصلاة،
///    يٰأيها/يا أيها)، وحذفها بيوحّد الشكلين تقريباً بدون ما نخسر تمييز.
/// 3. توحيد: ؤ→و، ئ→ي، ى→ي، ة→ه.
/// 4. المسافات بتنحذف من المفتاح (المطابقة على الحروف بس)، لأنه تقسيم
///    الكلمات بيختلف أحياناً (مثلاً "هُدࣰ ى" بالمصدر، "يا أيها" بالإملائي).
class ArabicNormalizer {
  ArabicNormalizer._();

  /// الحروف اللي بتنحفظ بالمفتاح (27 حرف، بدون ألف/همزة).
  static const String alphabet = 'بتثجحخدذرزسشصضطظعغفقكلمنهوي';

  static final Map<int, int> _letterIndex = {
    for (var i = 0; i < alphabet.length; i++) alphabet.codeUnitAt(i): i,
  };

  /// رقم الحرف (0..26) بالأبجدية المختصرة، أو -1 لو مش حرف مفتاح.
  static int letterIndex(int codeUnit) => _letterIndex[codeUnit] ?? -1;

  static bool _isRemovedMark(int c) =>
      (c >= 0x064B && c <= 0x065F) || // حركات وتنوين وشدة وسكون وهمزة فوق/تحت
      c == 0x0670 || // ألف خنجرية
      (c >= 0x0610 && c <= 0x061A) ||
      (c >= 0x06D6 && c <= 0x06ED) || // علامات المصحف الصغيرة
      (c >= 0x08D3 && c <= 0x08FF) || // تنوين مفتوح وغيره
      c == 0x0640 || // تطويل
      (c >= 0x200C && c <= 0x200F); // محارف اتجاه/وصل

  static int _fold(int c) {
    switch (c) {
      case 0x0624: // ؤ
        return 0x0648; // و
      case 0x0626: // ئ
      case 0x0649: // ى
      case 0x06CC: // ی فارسية
        return 0x064A; // ي
      case 0x0629: // ة
      case 0x06C0:
        return 0x0647; // ه
      case 0x06A9: // ک
        return 0x0643; // ك
      default:
        return c;
    }
  }

  /// المفتاح المطبّع (حروف بس، بدون مسافات).
  static String key(String text) => keyWithMap(text).key;

  /// نفس [key] بس كمان بيرجّع لكل حرف بالمفتاح موقعه بالنص الأصلي
  /// (code unit index). هاد بنحتاجه لنرجع من نتيجة المطابقة لتوقيتات
  /// الحروف/الكلمات اللي طلعها محرك التعرف على الصوت.
  static NormalizedText keyWithMap(String text) {
    final buf = StringBuffer();
    final map = <int>[];
    for (var i = 0; i < text.length; i++) {
      final c = text.codeUnitAt(i);
      if (_isRemovedMark(c)) continue;
      final f = _fold(c);
      if (_letterIndex.containsKey(f)) {
        buf.writeCharCode(f);
        map.add(i);
      }
      // أي إشي ثاني (ألف، همزة، مسافة، ترقيم، أرقام) بيتجاهل.
    }
    return NormalizedText(buf.toString(), map);
  }

  /// نص "مبسّط" مقروء (بمسافات بين الكلمات، بدون تشكيل، مع الألفات)،
  /// مفيد للبحث النصي العادي وللعرض بالسجلات. هذا اللي بينحفظ بعمود
  /// `text_simple` بقاعدة البيانات.
  static String simple(String text) {
    final buf = StringBuffer();
    var lastSpace = true;
    for (var i = 0; i < text.length; i++) {
      var c = text.codeUnitAt(i);
      if (_isRemovedMark(c)) continue;
      if (c == 0x0671 || c == 0x0623 || c == 0x0625 || c == 0x0622) {
        c = 0x0627; // ٱ أ إ آ → ا
      }
      c = _fold(c);
      final isLetter = (c >= 0x0621 && c <= 0x064A);
      if (isLetter) {
        buf.writeCharCode(c);
        lastSpace = false;
      } else if (c == 0x20 && !lastSpace) {
        buf.write(' ');
        lastSpace = true;
      }
    }
    return buf.toString().trim();
  }
}

class NormalizedText {
  /// المفتاح المطبّع.
  final String key;

  /// `sourceIndex[i]` = موقع الحرف i من المفتاح بالنص الأصلي.
  final List<int> sourceIndex;

  const NormalizedText(this.key, this.sourceIndex);
}
