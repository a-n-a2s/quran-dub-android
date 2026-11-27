// بناء مقطع آية واحدة كاملة (يوم 10: تغيير الآية بالمحرر، وإضافة مقطع
// يدوياً). جزء صافي بدون Flutter.
//
// **نفس منطق `segment_builder.dart`**: لما آية واحدة بجزء واحد (p == 1)،
// `_buildGroup` هناك بترجع نفس الشي بالضبط اللي هالدالة بترجعه: النص كامل
// (`QuranTextSource` خلاص نضّفه بـ `cleanForDisplay`)، `showAyahNumber` =
// true، والتفسير (`tafsir`/`tafsirFull`/`tafsirSplit`) كامل وبدون تقسيم
// (`TafsirSplitter` بس بيشتغل لما p > 1). فما في نسخة ثانية من منطق القص أو
// التقسيم — الآية الواحدة ببساطة ما بتحتاجهم.
import 'quran_text_source.dart';
import 'recitation_segment.dart';

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
  final content = text.ayah(surah, ayah);
  final found = content != null;
  return RecitationSegment(
    start: start,
    end: end < start ? start : end,
    kind: found ? SegmentKind.fullAyah : SegmentKind.nonQuran,
    surah: found ? surah : null,
    ayah: found ? ayah : null,
    part: 1,
    partCount: 1,
    text: content?.uthmani ?? '',
    showAyahNumber: found,
    tafsir: content?.tafsir ?? '',
    tafsirFull: content?.tafsir ?? '',
    tafsirSplit: content?.tafsir ?? '',
    confidence: confidence,
    needsReview: needsReview || !found,
    suggestedRef: found ? null : '$surah:$ayah',
    userText: userText,
    asrText: asrText,
    inferred: inferred,
  );
}

/// مقطع "مش قرآن" فاضي (لنص المستخدم) بنطاق وقت معيّن: لإضافة مقطع يدوي
/// للكلام غير القرآني (مقدمة، دعاء...) بدل آية.
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
