/// نوع المقطع بقائمة خط الأنابيب (يوم 5).
enum SegmentKind {
  /// آية كاملة بجزء واحد.
  fullAyah,

  /// جزء من آية (الآية انقسمت على وقفات القارئ، أو المقطع بلّش/خلص بنصها).
  partialAyah,

  /// بسملة انقرأت قبل سورة (بنفس ستايل الآية، بدون تفسير). بسملة الفاتحة
  /// هي الآية 1:1 فبتطلع [fullAyah] مع تفسيرها.
  basmala,

  /// استعاذة: ما بتنكتب أبداً (المواصفات، القسم 3).
  istiadha,

  /// مش قرآن (مقدمة، دعاء، أو مقطع ما انطابق): مكان لنص المستخدم، والشاشة
  /// فاضية فيه افتراضياً.
  nonQuran,
}

/// طريقة عرض التفسير لما الآية تنقسم على أكثر من جزء.
enum TafsirMode {
  /// (الافتراضي، حسب المواصفات القسم 3) كل جزء بياخد قطعة من التفسير،
  /// مقسومة على حدود الجمل/الفواصل بنسبة طول الجزء.
  split,

  /// زي المقطع المرجعي تبع أنس: التفسير كامل تحت كل جزء.
  fullUnderEachPart,
}

class RecitationSegment {
  /// بالثواني من بداية الملف (وقت الكلام نفسه).
  final double start;
  final double end;
  final SegmentKind kind;

  /// للآيات والبسملة (البسملة: null).
  final int? surah;
  final int? ayah;

  /// رقم الجزء (من 1) من [partCount] لنفس الآية بهالتلاوة.
  final int part;
  final int partCount;

  /// النص العثماني للعرض: الآية كاملة أو الجزء مقطوع على حدود الكلمات.
  /// فاضي للاستعاذة وللأجزاء غير القرآنية.
  final String text;

  /// رقم الآية بيطلع مع آخر جزء بس (ولما الجزء بيوصل لآخر الآية).
  final bool showAyahNumber;

  /// التفسير المعروض تحت هالجزء (حسب [TafsirMode]).
  final String tafsir;

  /// تفسير الآية كامل (لخيار "تفسير كامل تحت كل جزء" وللمحرر).
  final String tafsirFull;

  /// قطعة التفسير الخاصة بهالجزء بنمط [TafsirMode.split] دايماً (بغض النظر
  /// عن [tafsir]): الآية اللي ما انقسمت أو تفسيرها قصير = نفس [tafsirFull].
  /// بيخلّي المعاينة تبدّل بين النمطين بدون إعادة التحليل (يوم 7). فاضي
  /// للبسملة/الاستعاذة/غير القرآني.
  final String tafsirSplit;

  final double confidence;

  /// ثقة واطية أو موقع مش محسوم → بده مراجعة (التصحيح اليدوي، القسم 4).
  final bool needsReview;

  /// للأجزاء غير القرآنية: لو التطبيق شكّ إنها آية بثقة واطية، اقتراحه
  /// ("سورة:آية") للمحرر.
  final String? suggestedRef;

  /// نص المستخدم للأجزاء غير القرآنية (null = الشاشة فاضية).
  final String? userText;

  /// نص التعرف الخام للمقطع (للتطوير والمراجعة).
  final String asrText;

  /// آية التعرف ما طلّعها بس أكيد انقرأت: بين آيتين انطابقوا بنفس السورة
  /// وبوقت كافي بينهم (مثلاً فاتحة العفاسي: 1:3 ← … ← 1:5). توقيتها مقدّر
  /// بنسبة طولها، ودايماً "بده مراجعة".
  final bool inferred;

  const RecitationSegment({
    required this.start,
    required this.end,
    required this.kind,
    this.surah,
    this.ayah,
    this.part = 1,
    this.partCount = 1,
    this.text = '',
    this.showAyahNumber = false,
    this.tafsir = '',
    this.tafsirFull = '',
    this.tafsirSplit = '',
    required this.confidence,
    this.needsReview = false,
    this.suggestedRef,
    this.userText,
    this.asrText = '',
    this.inferred = false,
  });

  String? get ref => surah == null ? null : '$surah:$ayah';
  bool get isAyah =>
      kind == SegmentKind.fullAyah || kind == SegmentKind.partialAyah;

  /// بيطلع إشي على الشاشة؟
  bool get isVisible => switch (kind) {
        SegmentKind.istiadha => false,
        SegmentKind.nonQuran => (userText ?? '').isNotEmpty,
        _ => true,
      };

  /// (يوم 10، المحرر 2): زوّدنا الحقول اللي ممكن المحرر يعدّلها (التوقيت،
  /// "بده مراجعة"...) بدون ما نكسر استخدامات `copyWith(userText: ...)` و
  /// `copyWith(tafsir: ...)` الموجودة من قبل.
  RecitationSegment copyWith({
    double? start,
    double? end,
    SegmentKind? kind,
    int? surah,
    int? ayah,
    int? part,
    int? partCount,
    String? text,
    bool? showAyahNumber,
    String? tafsir,
    String? tafsirFull,
    String? tafsirSplit,
    double? confidence,
    bool? needsReview,
    String? suggestedRef,
    bool clearSuggestedRef = false,
    String? userText,
    bool clearUserText = false,
    String? asrText,
    bool? inferred,
  }) =>
      RecitationSegment(
        start: start ?? this.start,
        end: end ?? this.end,
        kind: kind ?? this.kind,
        surah: surah ?? this.surah,
        ayah: ayah ?? this.ayah,
        part: part ?? this.part,
        partCount: partCount ?? this.partCount,
        text: text ?? this.text,
        showAyahNumber: showAyahNumber ?? this.showAyahNumber,
        tafsir: tafsir ?? this.tafsir,
        tafsirFull: tafsirFull ?? this.tafsirFull,
        tafsirSplit: tafsirSplit ?? this.tafsirSplit,
        confidence: confidence ?? this.confidence,
        needsReview: needsReview ?? this.needsReview,
        suggestedRef: clearSuggestedRef ? null : (suggestedRef ?? this.suggestedRef),
        userText: clearUserText ? null : (userText ?? this.userText),
        asrText: asrText ?? this.asrText,
        inferred: inferred ?? this.inferred,
      );

  String get kindLabel => switch (kind) {
        SegmentKind.fullAyah => 'آية',
        SegmentKind.partialAyah => 'جزء $part/$partCount',
        SegmentKind.basmala => 'بسملة',
        SegmentKind.istiadha => 'استعاذة (مخفية)',
        SegmentKind.nonQuran => 'مش قرآن (فاضي)',
      };

  /// سطر ملخص: [0.10–5.51s] 1:1 آية ثقة 90%
  String describe() {
    final where = ref ?? '';
    final review = needsReview ? ' ⚠️ بده مراجعة' : '';
    final sug = (suggestedRef == null ? '' : ' (اقتراح $suggestedRef)') +
        (inferred ? ' (مستنتجة: التعرف ما طلّعها)' : '');
    return '[${start.toStringAsFixed(2)}–${end.toStringAsFixed(2)}s] '
        '${where.isEmpty ? '' : '$where '}$kindLabel'
        '${showAyahNumber ? ' ﴿$ayah﴾' : ''} ثقة ${(confidence * 100).round()}%'
        '$sug$review';
  }

  Map<String, Object?> toJson() => {
        'start': start,
        'end': end,
        'kind': kind.name,
        'surah': surah,
        'ayah': ayah,
        'part': part,
        'part_count': partCount,
        'text': text,
        'show_ayah_number': showAyahNumber,
        'tafsir': tafsir,
        'tafsir_full': tafsirFull,
        'tafsir_split': tafsirSplit,
        'confidence': double.parse(confidence.toStringAsFixed(3)),
        'needs_review': needsReview,
        'suggested_ref': suggestedRef,
        'user_text': userText,
        'asr_text': asrText,
        'inferred': inferred,
      };

  /// من [toJson] (يوم 10: تخزين تعديلات المحرر محلياً، `ProjectEditStore`).
  /// حقل ناقص أو بنوع غلط بياخد الافتراضي، فملف تالف جزئياً ما بيوقّع
  /// التطبيق (نفس مبدأ `OverlayTemplate.fromJson`).
  static RecitationSegment? fromJson(Object? j) {
    if (j is! Map) return null;
    final start = j['start'], end = j['end'];
    if (start is! num || end is! num) return null;
    SegmentKind kind = SegmentKind.nonQuran;
    for (final k in SegmentKind.values) {
      if (k.name == j['kind']) kind = k;
    }
    int? asInt(Object? v) => v is num ? v.toInt() : null;
    String asStr(Object? v, [String fallback = '']) => v is String ? v : fallback;
    return RecitationSegment(
      start: start.toDouble(),
      end: end.toDouble(),
      kind: kind,
      surah: asInt(j['surah']),
      ayah: asInt(j['ayah']),
      part: asInt(j['part']) ?? 1,
      partCount: asInt(j['part_count']) ?? 1,
      text: asStr(j['text']),
      showAyahNumber: j['show_ayah_number'] == true,
      tafsir: asStr(j['tafsir']),
      tafsirFull: asStr(j['tafsir_full']),
      tafsirSplit: asStr(j['tafsir_split']),
      confidence: (j['confidence'] is num) ? (j['confidence'] as num).toDouble() : 0,
      needsReview: j['needs_review'] == true,
      suggestedRef: j['suggested_ref'] is String ? j['suggested_ref'] as String : null,
      userText: j['user_text'] is String ? j['user_text'] as String : null,
      asrText: asStr(j['asr_text']),
      inferred: j['inferred'] == true,
    );
  }
}
