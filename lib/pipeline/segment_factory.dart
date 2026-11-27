// بناء مقطع آية واحدة كاملة (يوم 10: تغيير الآية بالمحرر، وإضافة مقطع
// يدوياً). جزء صافي بدون Flutter.
//
// **نفس منطق `segment_builder.dart`**: بيمرّ بـ [buildAyahReading] (اللي
// بيستعمل `_buildGroup` تبع خط الأنابيب نفسه) بجزء واحد، فالنص (مقطوع
// ومنضّف) ورقم الآية والتفسير (`tafsir`/`tafsirFull`/`tafsirSplit`) بيطلعوا
// بالضبط زي ما خط الأنابيب بيطلّعهم لآية ما انقسمت. ما في نسخة ثانية من
// منطق القص أو التقسيم.
import 'quran_text_source.dart';
import 'recitation_segment.dart';
import 'segment_builder.dart';

/// آية مش موجودة بالقاعدة (رقم غلط): بنرجّع مقطع فاضي "بده مراجعة" بدل ما
/// نرمي استثناء، عشان واجهة المحرر تقدر تبلّغ المستخدم بدل ما تنهار.
RecitationSegment buildWholeAyahSegment({
  required QuranTextSource text,
  required int surah,
  required int ayah,
  required double start,
  required double end,
  double confidence = 1.0,
  bool needsReview = false,
  String asrText = '',
  String? userText,
  bool inferred = false,
}) {
  final seg = buildAyahReading(text, surah, ayah, [(start, end < start ? start : end)],
          confidence: confidence,
          needsReview: needsReview,
          asrText: asrText,
          inferred: inferred)
      .single;
  return userText == null ? seg : seg.copyWith(userText: userText);
}

/// مقطع "مش قرآن" (لنص المستخدم) بنطاق وقت معيّن: لإضافة مقطع يدوي للكلام
/// غير القرآني (مقدمة، دعاء...) بدل آية.
RecitationSegment buildUserTextSegment({
  required double start,
  required double end,
  String userText = '',
}) =>
    RecitationSegment(
      start: start,
      end: end < start ? start : end,
      kind: SegmentKind.nonQuran,
      confidence: 1,
      userText: userText,
    );
