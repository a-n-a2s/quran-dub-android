// عمليات التصحيح اليدوي على قائمة المقاطع (يوم 10، المحرر 2): تغيير الآية،
// حذف، إضافة، تحريك الحدود، نص المستخدم، وتأكيد "بده مراجعة". جزء صافي بدون
// Flutter: الشاشة بس بتنادي هالدوال، والاختبارات بتجربها مباشرة.
//
// كل عملية بتغيّر عدد المقاطع أو ترتيبها بترجّع [SegmentEdit] فيه `mapping`
// (مكان كل مقطع قديم بالقائمة الجديدة) عشان المتصل يعيد ربط
// `OverlayStyle.segmentScales` بـ [remapSegmentScales] — المفاتيح هناك
// index بالقائمة.
import 'dart:math' as math;

import '../pipeline/quran_text_source.dart';
import '../pipeline/recitation_segment.dart';
import '../pipeline/segment_builder.dart';
import '../pipeline/segment_factory.dart';
import 'segment_scale_remap.dart';
import 'timeline_geometry.dart';

class SegmentEdit {
  final List<RecitationSegment> segments;

  /// بطول القائمة **القديمة**: `mapping[old]` = مكانه الجديد أو null (انحذف).
  final List<int?> mapping;

  /// مكان المقطع اللي العملية اشتغلت عليه بالقائمة الجديدة (للتحديد بالواجهة).
  final int? focus;

  const SegmentEdit(this.segments, this.mapping, {this.focus});

  SegmentScaleMap remapScales(SegmentScaleMap old) =>
      remapSegmentScales(old, mapping);

  /// إعادة ربط الشكل الخاص بكل آية (نفس المفاتيح).
  Map<int, T> remapMap<T>(Map<int, T> old) => remapIndexMap(old, mapping);
}

List<int?> _identity(int n) => [for (var i = 0; i < n; i++) i];

/// أجزاء نفس التلاوة لآية (جزء 1/3، 2/3، 3/3 متتاليين) اللي المقطع [index]
/// منها: (أول، آخر) بالقائمة، شاملين. مقطع مش آية أو آية بجزء واحد = نفسه.
(int, int) readingGroupAt(List<RecitationSegment> segs, int index) {
  final s = segs[index];
  if (!s.isAyah || s.partCount <= 1) return (index, index);
  bool sameReading(RecitationSegment a, RecitationSegment b) =>
      a.isAyah &&
      b.isAyah &&
      a.surah == b.surah &&
      a.ayah == b.ayah &&
      a.partCount == b.partCount &&
      b.part == a.part + 1;
  var from = index, to = index;
  while (from > 0 && sameReading(segs[from - 1], segs[from])) {
    from--;
  }
  while (to + 1 < segs.length && sameReading(segs[to], segs[to + 1])) {
    to++;
  }
  return (from, to);
}

/// تغيير آية المقطع [index] لـ [surah]:[ayah]. لو المقطع جزء من آية انقسمت
/// على وقفات القارئ، **كل أجزاء نفس التلاوة** بتتغيّر مع بعض (بنفس أوقاتها،
/// والنص والتفسير بينقسموا من جديد بنفس منطق خط الأنابيب). مقطع "مش قرآن" أو
/// بسملة بيصير آية. عدد المقاطع ما بيتغيّر → `mapping` ثابت.
SegmentEdit changeAyah(
  QuranTextSource text,
  List<RecitationSegment> segs,
  int index,
  int surah,
  int ayah, {
  PipelineOptions options = const PipelineOptions(),
}) {
  final (from, to) = readingGroupAt(segs, index);
  final rebuilt = buildAyahReading(
    text,
    surah,
    ayah,
    [for (var i = from; i <= to; i++) (segs[i].start, segs[i].end)],
    options: options,
  );
  final out = [...segs]..replaceRange(from, to + 1, rebuilt);
  return SegmentEdit(out, _identity(segs.length), focus: index);
}

/// حذف المقطع [index]. لو كان جزء من آية مقسومة، **الأجزاء الباقية بتضل زي
/// ما هي** (نصها، رقم الآية، تفسيرها) — طلب أنس 2026-11-28: "أحذف أي قسم ما
/// يتأثر باقي الأقسام". بس ترقيم الأجزاء بيتحدّث (3 أجزاء → 1/2 و2/2) عشان يضلوا
/// تلاوة وحدة بالمحرر. [text] و[options] ما عاد إلهم دور (مخلّيين للتوافق).
SegmentEdit deleteSegment(
  QuranTextSource? text,
  List<RecitationSegment> segs,
  int index, {
  PipelineOptions options = const PipelineOptions(),
}) {
  final (from, to) = readingGroupAt(segs, index);
  final out = [...segs]..removeAt(index);
  if (to > from) {
    final n = to - from; // عدد الباقي
    for (var k = 0; k < n; k++) {
      final i = from + k;
      out[i] = out[i].copyWith(part: k + 1, partCount: n);
    }
  }
  return SegmentEdit(out, mappingForDelete(segs.length, index));
}

/// إضافة [seg] بمكانها حسب وقت البداية. بيرفض (null) لو بتتقاطع مع مقطع
/// موجود، أو أقصر من [minSegmentSeconds].
SegmentEdit? insertSegment(
    List<RecitationSegment> segs, RecitationSegment seg) {
  if (seg.end - seg.start < minSegmentSeconds - 1e-9) return null;
  if (rangeOverlapsExisting(
      [for (final s in segs) (s.start, s.end)], seg.start, seg.end)) {
    return null;
  }
  var at = segs.indexWhere((s) => s.start > seg.start);
  if (at < 0) at = segs.length;
  final out = [...segs]..insert(at, seg);
  return SegmentEdit(out, mappingForInsert(segs.length, at), focus: at);
}

/// تحريك حدود المقطع [index] (سحب أو كتابة): ما بيتخطى جيرانه، ما بينزل عن
/// الحد الأدنى، وجوا مدة الفيديو. القائمة بتضل مرتبة فـ `mapping` ثابت.
SegmentEdit setBounds(List<RecitationSegment> segs, int index, double start,
    double end, {required double duration}) {
  final b = clampSegmentDrag(
    segments: [for (final s in segs) (s.start, s.end)],
    index: index,
    newStart: start,
    newEnd: end,
    duration: duration,
  );
  final out = [...segs];
  out[index] = segs[index].copyWith(start: b.start, end: b.end);
  return SegmentEdit(out, _identity(segs.length), focus: index);
}

/// نص المستخدم لمقطع غير قرآني (فاضي = الشاشة نظيفة بهالجزء).
SegmentEdit setUserText(List<RecitationSegment> segs, int index, String value) {
  final s = segs[index];
  final t = value.trim();
  final out = [...segs];
  out[index] = s.copyWith(
    userText: t.isEmpty ? null : value,
    clearUserText: t.isEmpty,
    // المستخدم قرّر شو يطلع هون: ما عاد بده مراجعة.
    needsReview: t.isEmpty ? s.needsReview : false,
  );
  return SegmentEdit(out, _identity(segs.length), focus: index);
}

/// تحويل المقطع [index] (آية غلط، أو بسملة) لمقطع "مش قرآن" بنفس وقته (لنص
/// المستخدم أو للفراغ). لو كان جزء من آية مقسومة، باقي أجزائها بتنبني من جديد.
SegmentEdit convertToNonQuran(
  QuranTextSource? text,
  List<RecitationSegment> segs,
  int index, {
  String userText = '',
  PipelineOptions options = const PipelineOptions(),
}) {
  final s = segs[index];
  final replacement =
      buildUserTextSegment(start: s.start, end: s.end, userText: userText)
          .copyWith(clearUserText: userText.trim().isEmpty);
  final (from, to) = readingGroupAt(segs, index);
  final out = [...segs]..[index] = replacement;
  if (text != null && to > from && s.surah != null && s.ayah != null) {
    for (final (a, b) in [(from, index - 1), (index + 1, to)]) {
      if (b < a) continue;
      final part = buildAyahReading(text, s.surah!, s.ayah!,
          [for (var i = a; i <= b; i++) (out[i].start, out[i].end)],
          options: options, confidence: out[a].confidence);
      out.replaceRange(a, b + 1, part);
    }
  }
  return SegmentEdit(out, _identity(segs.length), focus: index);
}

/// تأكيد مقطع "بده مراجعة"/"مستنتج" (وكل أجزاء نفس التلاوة معه): المستخدم
/// شافه وهو صح.
SegmentEdit confirmSegment(List<RecitationSegment> segs, int index) {
  final (from, to) = readingGroupAt(segs, index);
  final out = [...segs];
  for (var i = from; i <= to; i++) {
    out[i] = out[i].copyWith(needsReview: false, inferred: false);
  }
  return SegmentEdit(out, _identity(segs.length), focus: index);
}

/// رقم أول مقطع "بده مراجعة" بعد [after] (بالترتيب، وبيرجع من الأول)، أو null.
int? nextNeedingReview(List<RecitationSegment> segs, {int after = -1}) {
  bool wants(RecitationSegment s) =>
      (s.needsReview || s.inferred) && s.kind != SegmentKind.istiadha;
  for (var k = 1; k <= segs.length; k++) {
    final i = (after + k) % segs.length;
    if (i >= 0 && wants(segs[i])) return i;
  }
  return null;
}

/// بصمة ثابتة لقائمة مقاطع (لربط التعديلات المحفوظة بنتيجة التحليل اللي
/// انبنت عليها: تحليل جديد لنفس الفيديو = بصمة مختلفة → ما منحمّل تعديلات
/// قديمة فوقه).
String segmentsSignature(List<RecitationSegment> segs) {
  var h = 0x811c9dc5;
  void mix(String s) {
    for (final u in s.codeUnits) {
      h = ((h ^ u) * 0x01000193) & 0xffffffff;
    }
  }

  for (final s in segs) {
    mix('${s.start.toStringAsFixed(3)}|${s.end.toStringAsFixed(3)}|'
        '${s.kind.name}|${s.ref}|${s.part}/${s.partCount};');
  }
  return '${segs.length}-${h.toRadixString(16)}';
}

/// حدود التقسيم الحالية لآية المقطع [index] (عدد الكلمات قبل كل حد)، من نصوص
/// أجزاء نفس التلاوة. آية بجزء واحد = فاضية.
List<int> wordCutsAt(List<RecitationSegment> segs, int index) {
  final (from, to) = readingGroupAt(segs, index);
  final cuts = <int>[];
  var acc = 0;
  for (var i = from; i < to; i++) {
    acc += RegExp(r'\S+').allMatches(segs[i].text).length;
    cuts.add(acc);
  }
  return cuts;
}

/// تقسيم آية المقطع [index] يدوياً على حدود كلمات (طلب أنس 2026-11-28)، أو
/// رجعها **آية كاملة** بجزء واحد ([cuts] فاضية). كل أجزاء نفس التلاوة بتنبني من
/// جديد على نفس الوقت الكلي: لو عدد الأجزاء ما تغيّر بتضل أوقاتها، وإلا بتتوزّع
/// بنسبة طول كل جزء (والمستخدم بيظبطها بالمقابض). مقطع مش آية = بدون تغيير.
SegmentEdit splitAyahAtWords(QuranTextSource text, List<RecitationSegment> segs,
    int index, List<int> cuts) {
  final s = segs[index];
  if (!s.isAyah || s.surah == null || s.ayah == null) {
    return SegmentEdit(segs, _identity(segs.length), focus: index);
  }
  final (from, to) = readingGroupAt(segs, index);
  final oldCount = to - from + 1;
  final rebuilt = buildAyahReadingAtWords(
    text,
    s.surah!,
    s.ayah!,
    cuts,
    start: segs[from].start,
    end: segs[to].end,
    partTimes: [for (var i = from; i <= to; i++) (segs[i].start, segs[i].end)],
    confidence: s.confidence,
  );
  if (rebuilt.isEmpty) return SegmentEdit(segs, _identity(segs.length), focus: index);
  final out = [...segs]..replaceRange(from, to + 1, rebuilt);
  final delta = rebuilt.length - oldCount;
  final mapping = <int?>[
    for (var i = 0; i < segs.length; i++)
      i < from
          ? i
          : i > to
              ? i + delta
              : from + math.min(i - from, rebuilt.length - 1),
  ];
  return SegmentEdit(out, mapping,
      focus: from + math.min(index - from, rebuilt.length - 1));
}
