import 'dart:convert';
import 'dart:io';

/// نص الآية للعرض + التفسير الميسر.
class AyahContent {
  final int surah;
  final int ayah;

  /// الرسم العثماني جاهز للعرض (بدون ۞ وعلامات الاتجاه، شوف [cleanForDisplay]).
  final String uthmani;
  final String tafsir;
  const AyahContent(this.surah, this.ayah, this.uthmani, this.tafsir);
}

/// مصدر نص الآيات والتفسير لخط الأنابيب (Dart صافي: من قاعدة البيانات
/// بالتطبيق، أو من ملف الأصول مباشرة بالاختبارات والـ CI).
class QuranTextSource {
  final Map<int, AyahContent> _byRef;
  QuranTextSource._(this._byRef);

  static int _k(int s, int a) => s * 1000 + a;

  AyahContent? ayah(int surah, int ayah) => _byRef[_k(surah, ayah)];

  int get length => _byRef.length;

  /// من صفوف (surah, ayah, uthmani, tafsir).
  factory QuranTextSource.fromRows(
      Iterable<(int, int, String, String)> rows) {
    final m = <int, AyahContent>{};
    for (final r in rows) {
      m[_k(r.$1, r.$2)] =
          AyahContent(r.$1, r.$2, cleanForDisplay(r.$3), cleanTafsir(r.$4));
    }
    return QuranTextSource._(m);
  }

  /// من assets/quran/quran_data.json.gz (نفس بيانات قاعدة البيانات).
  factory QuranTextSource.fromSeedBundle(List<int> gzipBytes) {
    final bundle = json.decode(utf8.decode(GZipCodec().decode(gzipBytes)))
        as Map<String, dynamic>;
    return QuranTextSource.fromRows([
      for (final raw in bundle['ayahs'] as List<dynamic>)
        (
          (raw as Map<String, dynamic>)['s'] as int,
          raw['a'] as int,
          raw['t'] as String,
          raw['f'] as String,
        ),
    ]);
  }

  factory QuranTextSource.fromSeedFile(String path) =>
      QuranTextSource.fromSeedBundle(File(path).readAsBytesSync());

  /// علامات بالمصدر ما بتنعرض فوق الفيديو (قسم "شكل الناتج النهائي"):
  /// ۞ (بداية الحزب)، ۩ (مكان السجدة)، وعلامات الاتجاه (LRM/RLM/ALM).
  /// علامات الوقف الصغيرة (ۖ ۗ ۚ ...) بتضل، هي جزء من رسم المصحف.
  static String cleanForDisplay(String text) => text
      .replaceAll(RegExp('[۞۩‎‏؜‪-‮]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static String cleanTafsir(String text) => text
      .replaceAll(RegExp('[‎‏؜‪-‮]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
