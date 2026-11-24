// خطوط الآية (يوم 7، المواصفات القسم 3). جزء صافي بدون Flutter.
// الرخص والمصادر وسبب التحويل: assets/fonts/LICENSES.md

/// خط الآية. [family] هو اسم العائلة المعرّف بـ pubspec.yaml.
enum AyahFont {
  /// خط مصحف المدينة (مجمع الملك فهد، Hafs Uthmanic Ver18). الرخصة بتمنع
  /// تعديل الخط، فالتوافق بيصير على **النص** ([KfgqpcCompat]).
  kfgqpcHafs('KFGQPC Hafs', 'مصحف المدينة'),

  /// أميري قرآن (SIL OFL). بيغطي كل حروف النص بدون تحويل.
  amiriQuran('Amiri Quran', 'أميري قرآن');

  final String family;
  final String label;
  const AyahFont(this.family, this.label);

  /// الافتراضي. لو رخصة KFGQPC ما تأكدت بالكتابة (LICENSES.md): غيّره لـ
  /// [amiriQuran].
  static const AyahFont defaultFont = AyahFont.kfgqpcHafs;

  /// النص جاهز للتصيير بهالخط.
  String prepare(String text) => switch (this) {
        AyahFont.kfgqpcHafs => KfgqpcCompat.convert(text),
        AyahFont.amiriQuran => text,
      };

  /// علامة نهاية الآية **زي المصحف** (زخرفة حوالين الرقم، والرقم جواها
  /// بأرقام عربية-هندية)، كنص بنفس خط الآية (فبتقعد على نفس السطر وبنفس
  /// الارتفاع، مش أعلى من الكلام). (يوم 7، طلب أنس: بدل الدائرة البسيطة.)
  /// - خط مصحف المدينة (KFGQPC): الأرقام نفسها بتطلع بإطار المصحف المزخرف
  ///   (هيك مرمّزة بالخط، زي نص مجمع الملك فهد: "...ٱلرَّحِيمِ ١").
  /// - أميري قرآن: U+06DD (علامة نهاية الآية) قبل الأرقام → الخط بيحطهم
  ///   جواها.
  String ayahNumberMark(int ayah) => switch (this) {
        AyahFont.kfgqpcHafs => toArabicIndic(ayah),
        AyahFont.amiriQuran => '$endOfAyah${toArabicIndic(ayah)}',
      };
}

/// U+06DD ARABIC END OF AYAH.
const String endOfAyah = '\u06DD';

/// الأقواس المزخرفة (الذهبية). U+FD3F أول (يمين بالعربي) وU+FD3E آخر، مثل
/// التصوّر المرسوم. خط KFGQPC ما فيهم، فبيتصيّروا دايماً بأميري قرآن.
const String ayahOpenBracket = '﴿';
const String ayahCloseBracket = '﴾';

/// خط KFGQPC (Ver18) ما فيه U+08F0..08F2 (التنوين المفتوح بنص Tanzil عندنا)،
/// وبيرمّزهم بأماكن ثانية بالخط. هالتحويل بيصير وقت العرض بس.
class KfgqpcCompat {
  KfgqpcCompat._();

  static const Map<String, String> _map = {
    'ࣰ': 'ٗ', // تنوين فتح مفتوح
    'ࣱ': 'ٞ', // تنوين ضم مفتوح
    'ࣲ': 'ٖ', // تنوين كسر مفتوح
    'ٜ': '۪', // علامة وحيدة (11:41)
  };

  static const String _openTanween = 'ࣰࣱࣲ';

  static String convert(String text) {
    if (text.isEmpty) return text;
    final out = StringBuffer();
    for (var i = 0; i < text.length; i++) {
      final c = text[i];
      final mapped = _map[c];
      if (mapped == null) {
        out.write(c);
        continue;
      }
      out.write(mapped);
      // "هُدࣰ ى" بنص Tanzil: مسافة فاصلة بين التنوين المفتوح وألف/ألف مقصورة،
      // وبالخط الحرفين متصلين.
      if (_openTanween.contains(c) &&
          i + 2 < text.length &&
          text[i + 1] == ' ' &&
          (text[i + 2] == 'ا' || text[i + 2] == 'ى')) {
        i++;
      }
    }
    return out.toString();
  }
}

/// أرقام عربية-هندية (رقم الآية بعلامة نهاية الآية).
String toArabicIndic(int n) {
  const digits = '٠١٢٣٤٥٦٧٨٩';
  return n.toString().split('').map((d) {
    final v = int.tryParse(d);
    return v == null ? d : digits[v];
  }).join();
}
