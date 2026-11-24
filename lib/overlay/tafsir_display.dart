import '../pipeline/recitation_segment.dart';

/// التفسير المعروض فوق الفيديو (يوم 7، شكل المقطع المرجعي): أبيض، خط أصغر،
/// **بدون تشكيل**، وبآخره نقطة. جزء صافي بدون Flutter.
class TafsirDisplay {
  TafsirDisplay._();

  // فتحتان/ضمتان/كسرتان/فتحة/ضمة/كسرة/شدة/سكون (064B..0652) + الألف الخنجرية.
  // ما بنشيل 0653..0655 (مدة/همزة فوق/تحت) لأنها جزء من الحرف لو كانت مفصولة.
  static final RegExp _tashkeel = RegExp('[ً-ْٰ]');

  static String stripTashkeel(String s) => s.replaceAll(_tashkeel, '');

  /// بيضمن نهاية جملة: بيضيف نقطة، وبيبدّل الفاصلة الأخيرة (، ,) بنقطة. لو
  /// منتهي أصلاً بـ . ؟ ! ؛ : بيتركه.
  static String withFinalStop(String s) {
    final t = s.trim();
    if (t.isEmpty) return '';
    final last = t[t.length - 1];
    if ('.؟?!؛:'.contains(last)) return t;
    if ('،,'.contains(last)) return '${t.substring(0, t.length - 1).trimRight()}.';
    return '$t.';
  }

  /// التفسير الخام حسب النمط (من دون تنسيق العرض).
  static String select(RecitationSegment seg, TafsirMode mode) {
    if (!seg.isAyah) return '';
    switch (mode) {
      case TafsirMode.split:
        // مقاطع من نسخة قديمة بدون tafsirSplit بترجع لـ tafsir.
        return seg.tafsirSplit.isNotEmpty ? seg.tafsirSplit : seg.tafsir;
      case TafsirMode.fullUnderEachPart:
        return seg.tafsirFull.isNotEmpty ? seg.tafsirFull : seg.tafsir;
    }
  }

  /// النص النهائي المعروض تحت الآية. فاضي للبسملة/الاستعاذة/غير القرآني
  /// (البسملة بدون تفسير، إلا بالفاتحة لأنها آية: بتطلع [SegmentKind.fullAyah]).
  static String forDisplay(RecitationSegment seg, TafsirMode mode) =>
      withFinalStop(stripTashkeel(select(seg, mode)));
}
