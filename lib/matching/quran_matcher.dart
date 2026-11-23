import 'dart:math' as math;
import 'dart:typed_data';

import 'arabic_normalizer.dart';

/// آية بالشكل اللي بيحتاجه الـ matcher (مستقل عن sqflite وعن Flutter، عشان
/// نقدر نشغّله بـ `dart test` وبأدوات سطر الأوامر وبـ isolate).
class MatchableAyah {
  final int surah;
  final int ayah;
  final String text; // text_uthmani (أو أي نص للآية، بيتطبّع داخلياً)
  const MatchableAyah(this.surah, this.ayah, this.text);
}

/// نوع المقدمة اللي بيقرأها القارئ قبل الآيات (مش جزء من آية مرقّمة،
/// إلا البسملة بالفاتحة).
enum PreambleType { istiadha, basmala }

class Preamble {
  final PreambleType type;
  final int queryStart; // بمفتاح الاستعلام المطبّع
  final int queryEnd;
  const Preamble(this.type, this.queryStart, this.queryEnd);
  @override
  String toString() => '${type.name}[$queryStart,$queryEnd)';
}

/// جزء الآية اللي غطّاه المقطع المسموع.
class AyahSpan {
  final int surah;
  final int ayah;

  /// نسبة حروف الآية اللي انسمعت بالمقطع (0..1). أقل من 1 يعني المقطع
  /// بلّش أو خلص بنص الآية.
  final double coverage;

  /// موقع الآية بمفتاح الاستعلام المطبّع [queryStart, queryEnd). مع
  /// `NormalizedText.sourceIndex` بنرجع منه لتوقيتات محرك التعرف.
  final int queryStart;
  final int queryEnd;

  /// الجزء المسموع من الآية نفسها، بمفتاح الآية المطبّع [keyStart, keyEnd)
  /// (0 = أول حرف بالآية). keyEnd = -1 يعني لآخر الآية. (يوم 5: لتقطيع النص
  /// العثماني على حدود الكلمات لكل جزء.)
  final int keyStart;
  final int keyEnd;

  const AyahSpan(this.surah, this.ayah, this.coverage, this.queryStart,
      this.queryEnd,
      {this.keyStart = 0, this.keyEnd = -1});

  @override
  String toString() =>
      '$surah:$ayah (${(coverage * 100).toStringAsFixed(0)}%, q[$queryStart,$queryEnd))';
}

class AlternativeMatch {
  final int surah;
  final int ayah;
  final double similarity;
  const AlternativeMatch(this.surah, this.ayah, this.similarity);
  @override
  String toString() => '$surah:$ayah@${similarity.toStringAsFixed(2)}';
}

class QuranMatch {
  /// 1 - (مسافة التعديل / طول الاستعلام). 1.0 = تطابق حرفي كامل.
  final double similarity;

  /// ثقة نهائية (0..1) بتجمع التشابه + طول المقطع + تفرّد الموقع/السياق.
  final double confidence;

  /// لو في موقع ثاني بالقرآن قريب جداً بالتشابه وما حسمه السياق.
  final bool isAmbiguous;

  /// لو الموقع المختار بيكمّل مباشرة من المقطع السابق (previousEnd).
  final bool continuesContext;

  /// موقع المطابقة بنص القرآن المتصل (للتسلسل: مرّر corpusEnd كـ
  /// previousEnd للمقطع اللي بعده).
  final int corpusStart;
  final int corpusEnd;

  final List<AyahSpan> ayahs;
  final List<Preamble> preambles;
  final List<AlternativeMatch> alternatives;
  final NormalizedText query;

  /// عدد حروف المفتاح اللي انطابقت (بدون المقدمات).
  final int letters;

  const QuranMatch({
    required this.similarity,
    required this.confidence,
    required this.isAmbiguous,
    required this.continuesContext,
    required this.corpusStart,
    required this.corpusEnd,
    required this.ayahs,
    required this.preambles,
    required this.alternatives,
    required this.query,
    this.letters = 0,
  });

  QuranMatch copyWith({
    double? confidence,
    bool? isAmbiguous,
    bool? continuesContext,
    List<AyahSpan>? ayahs,
    List<Preamble>? preambles,
  }) =>
      QuranMatch(
        similarity: similarity,
        confidence: confidence ?? this.confidence,
        isAmbiguous: isAmbiguous ?? this.isAmbiguous,
        continuesContext: continuesContext ?? this.continuesContext,
        corpusStart: corpusStart,
        corpusEnd: corpusEnd,
        ayahs: ayahs ?? this.ayahs,
        preambles: preambles ?? this.preambles,
        alternatives: alternatives,
        query: query,
        letters: letters,
      );

  /// المقطع كله استعاذة/بسملة بدون آيات.
  bool get isPreambleOnly => ayahs.isEmpty && preambles.isNotEmpty;

  AyahSpan? get first => ayahs.isEmpty ? null : ayahs.first;
  AyahSpan? get last => ayahs.isEmpty ? null : ayahs.last;

  @override
  String toString() {
    final where = ayahs.isEmpty
        ? '-'
        : (ayahs.length == 1
            ? '${ayahs.first.surah}:${ayahs.first.ayah}'
            : '${ayahs.first.surah}:${ayahs.first.ayah} → ${ayahs.last.surah}:${ayahs.last.ayah}');
    return 'QuranMatch($where, confidence=${confidence.toStringAsFixed(2)}, '
        'similarity=${similarity.toStringAsFixed(2)}, ambiguous=$isAmbiguous, '
        'context=$continuesContext, preambles=$preambles, ayahs=$ayahs, '
        'alternatives=$alternatives)';
  }
}

/// مطابقة ضبابية (fuzzy) بين نص خارج من محرك التعرف على الصوت وبين نص
/// القرآن الكامل.
///
/// الخوارزمية (seed-and-verify، زي فكرة BLAST):
/// 1. **تطبيع**: الطرفين بيتحولوا لمفتاح رسم ([ArabicNormalizer]).
/// 2. **فهرسة**: كل القرآن (6236 آية) بينحط بنص واحد متصل (~270 ألف حرف)
///    مع فهرس n-gram (4 حروف) → مواقعها.
/// 3. **ترشيح**: كل 4-gram بالاستعلام بيصوّت لـ "قُطر" (موقع البداية
///    المتوقع = موقع الـ gram بالقرآن - موقعه بالاستعلام)، بوزن أقل للـ
///    grams الشائعة. بناخد أعلى المرشحين.
/// 4. **تحقق**: لكل مرشح، محاذاة شبه-شاملة (semi-global edit distance)
///    بين الاستعلام ونافذة من القرآن حوالين المرشح، بتعطي أفضل بداية
///    ونهاية بالضبط رغم الحذف/الإضافة/الاستبدال.
/// 5. **سياق**: لو مررنا نهاية المقطع السابق، الموقع اللي بيكمّل منه
///    بياخد أولوية (بيحسم الآيات المكررة زي "فبأي آلاء ربكما تكذبان").
/// 6. **تفصيل**: traceback للمحاذاة بيقسّم المقطع على الآيات، مع نسبة
///    تغطية كل آية وموقعها بالاستعلام (للتوقيت لاحقاً).
class QuranMatcher {
  static const int gramSize = 4;
  static const int _bucket = 8;
  static const int _maxGramFrequency = 3000;
  static const double _contextBonus = 0.08;
  static const double _surahStartBonus = 0.05;

  /// تكلفة "فجوة" (حروف من القرآن مش موجودة بالاستعلام، يعني التعرف على
  /// الصوت أسقطها) بنظام affine gap: فتح الفجوة [_gapOpen] + تمديدها
  /// [_gapExtend] لكل حرف زيادة، بدل حرف بحرف بتكلفة 1 (uniform). هيك فجوة
  /// طويلة (آية كاملة ضايعة من التعرف) بتكلّف أقل بكثير من مجموع حروفها،
  /// فالمحاذاة بتكمّل بعدها بدل ما تتوقف قبلها. (يوم 5، بعد ملاحظة فاتحة
  /// العفاسي: "مالك يوم الدين" أسقطها التعرف، والمحاذاة القديمة فضّلت
  /// تتوقف عند 1:5 بدل ما تكمّل لـ 1:6 لأنه عبور الفجوة كان أغلى من
  /// تجاهل باقي المقطع). القيم دُقّقت بـ tool/proto/matcher.py على نفس
  /// السيناريو وعلى كل اختبارات test/matching بدون أي تراجع.
  static const double _gapOpen = 1.5;
  static const double _gapExtend = 0.35;

  /// حد أدنى لطول الاستعلام (حروف مفتاح) عشان نحاول نطابق.
  static const int minQueryLetters = 6;

  /// حد أعلى (~دقيقتين تلاوة). المقاطع الأطول لازم تتقسّم (VAD) قبل.
  static const int maxQueryLetters = 1200;

  final Int32List _surah;
  final Int32List _ayah;
  final Int32List _starts; // بداية كل آية بالنص المتصل (+ عنصر أخير = الطول)
  final Uint8List _codes; // النص المتصل كأرقام حروف 0..26
  final Map<int, Int32List> _grams;
  final Uint8List _basmala;
  final Uint8List _istiadha;
  final int _fatihaFirstIndex; // فهرس 1:1 لو موجود
  final Set<int> _surahStarts; // مواقع بداية كل سورة (+ بداية 1:2)

  QuranMatcher._(this._surah, this._ayah, this._starts, this._codes,
      this._grams, this._basmala, this._istiadha, this._fatihaFirstIndex,
      this._surahStarts);

  int get corpusLength => _codes.length;
  int get ayahCount => _surah.length;

  factory QuranMatcher.build(List<MatchableAyah> ayahs) {
    final n = ayahs.length;
    final surah = Int32List(n);
    final ayah = Int32List(n);
    final starts = Int32List(n + 1);
    final codes = <int>[];
    var fatiha = -1;
    for (var i = 0; i < n; i++) {
      final a = ayahs[i];
      surah[i] = a.surah;
      ayah[i] = a.ayah;
      if (a.surah == 1 && a.ayah == 1) fatiha = i;
      starts[i] = codes.length;
      codes.addAll(_toCodes(ArabicNormalizer.key(a.text)));
    }
    starts[n] = codes.length;
    final c = Uint8List.fromList(codes);

    // فهرس 4-grams: أول عدّ، بعدين تعبئة (أسرع وأوفر من List.add).
    final counts = <int, int>{};
    for (var i = 0; i + gramSize <= c.length; i++) {
      final h = _hash(c, i);
      counts[h] = (counts[h] ?? 0) + 1;
    }
    final grams = <int, Int32List>{};
    final fill = <int, int>{};
    counts.forEach((h, cnt) {
      grams[h] = Int32List(cnt);
      fill[h] = 0;
    });
    for (var i = 0; i + gramSize <= c.length; i++) {
      final h = _hash(c, i);
      final f = fill[h]!;
      grams[h]![f] = i;
      fill[h] = f + 1;
    }

    final surahStarts = <int>{
      for (var i = 0; i < n; i++)
        if (ayah[i] == 1 || (surah[i] == 1 && ayah[i] == 2)) starts[i],
    };

    return QuranMatcher._(
      surah,
      ayah,
      starts,
      c,
      grams,
      _toCodes(ArabicNormalizer.key('بسم الله الرحمن الرحيم')),
      _toCodes(ArabicNormalizer.key('أعوذ بالله من الشيطان الرجيم')),
      fatiha,
      surahStarts,
    );
  }

  static Uint8List _toCodes(String key) {
    final out = Uint8List(key.length);
    for (var i = 0; i < key.length; i++) {
      out[i] = ArabicNormalizer.letterIndex(key.codeUnitAt(i));
    }
    return out;
  }

  static int _hash(Uint8List c, int i) =>
      ((c[i] * 27 + c[i + 1]) * 27 + c[i + 2]) * 27 + c[i + 3];

  /// رقم الآية (index بالقائمة) اللي فيها الموقع [pos] بالنص المتصل.
  int _ayahIndexAt(int pos) {
    var lo = 0, hi = _surah.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (_starts[mid] <= pos) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  /// موقع بداية/نهاية آية معينة بالنص المتصل (لتهيئة السياق يدوياً).
  int? corpusStartOf(int surah, int ayah) {
    for (var i = 0; i < _surah.length; i++) {
      if (_surah[i] == surah && _ayah[i] == ayah) return _starts[i];
    }
    return null;
  }

  int? corpusEndOf(int surah, int ayah) {
    for (var i = 0; i < _surah.length; i++) {
      if (_surah[i] == surah && _ayah[i] == ayah) return _starts[i + 1];
    }
    return null;
  }

  /// يطابق نص [asrText] (ناتج التعرف على الصوت لمقطع واحد) مع القرآن.
  ///
  /// [previousEnd]: `corpusEnd` تبع المقطع السابق بنفس التلاوة (اختياري).
  /// [expectSurahStart]: المقطع السابق كان بسملة لحالها → توقّع بداية سورة.
  /// بيرجّع null لو النص قصير جداً أو ما في أي تطابق معقول.
  ///
  /// لسلسلة مقاطع من نفس الفيديو، الأفضل [QuranSequenceMatcher] (بيختار
  /// أفضل تسلسل لكل المقاطع مع بعض بدل كل مقطع لحاله).
  QuranMatch? match(String asrText,
      {int? previousEnd, bool expectSurahStart = false, int topN = 8}) {
    final all = candidates(asrText,
        previousEnd: previousEnd,
        expectSurahStart: expectSurahStart,
        topN: topN,
        maxResults: 1);
    return all.isEmpty ? null : all.first;
  }

  /// مثل [match] بس بيرجّع لحد [maxResults] مطابقات بمواقع مختلفة
  /// بالقرآن (الأفضل أول)، كل وحدة مع تقسيمها على الآيات. بيستخدمها
  /// [QuranSequenceMatcher].
  ///
  /// [nextStart]: `corpusStart` تبع المقطع اللي بعده (سياق عكسي، اختياري):
  /// بيضمن نتحقق من الموقع اللي بيخلص بالضبط قبله.
  List<QuranMatch> candidates(String asrText,
      {int? previousEnd,
      int? nextStart,
      bool expectSurahStart = false,
      int topN = 8,
      int maxResults = 5}) {
    final query = ArabicNormalizer.keyWithMap(asrText);
    var q = _toCodes(query.key);
    if (q.length > maxQueryLetters) {
      q = Uint8List.sublistView(q, 0, maxQueryLetters);
    }

    // --- المقدمات: الاستعاذة ثم البسملة ببداية المقطع ---
    final preambles = <Preamble>[];
    var offset = 0;
    var preambleSimilarity = 1.0;
    for (final type in [PreambleType.istiadha, PreambleType.basmala]) {
      final p = type == PreambleType.istiadha ? _istiadha : _basmala;
      final hit = _prefixMatch(Uint8List.sublistView(q, offset), p);
      if (hit != null) {
        preambles.add(Preamble(type, offset, offset + hit.$1));
        preambleSimilarity = math.min(preambleSimilarity, hit.$2);
        offset += hit.$1;
      }
    }
    final body = Uint8List.sublistView(q, offset);

    if (body.length < minQueryLetters) {
      if (preambles.isEmpty) return const [];
      // المقطع كله استعاذة/بسملة. لو بسملة وبعدها الفاتحة، بتكون 1:1.
      final isFatihaStart = preambles.last.type == PreambleType.basmala &&
          _fatihaFirstIndex >= 0 &&
          previousEnd == null;
      return [
        QuranMatch(
          similarity: preambleSimilarity,
          confidence: preambleSimilarity * 0.9,
          isAmbiguous: false,
          continuesContext: false,
          corpusStart: previousEnd ?? 0,
          corpusEnd: previousEnd ?? 0,
          ayahs: const [],
          preambles: preambles,
          alternatives:
              isFatihaStart ? const [AlternativeMatch(1, 1, 1)] : const [],
          query: query,
        )
      ];
    }

    // البسملة غالباً بتنقرأ ببداية سورة → المرشح اللي ببداية سورة أولى.
    final afterBasmala = expectSurahStart ||
        (preambles.isNotEmpty && preambles.last.type == PreambleType.basmala);
    final cand = _verify(body, previousEnd, nextStart, topN, afterBasmala);
    if (cand.isEmpty) return const [];
    final m = body.length;

    // مواقع مختلفة بس (مرشحين متداخلين = نفس الموقع).
    final distinct = <_Candidate>[];
    for (final c in cand) {
      if (distinct.every((d) => (c.start - d.start).abs() > m ~/ 2)) {
        distinct.add(c);
      }
    }

    final out = <QuranMatch>[];
    for (var k = 0; k < distinct.length && k < maxResults; k++) {
      final c = distinct[k];
      _Candidate? rival;
      for (final d in distinct) {
        if (!identical(d, c)) {
          rival = d;
          break;
        }
      }
      final margin = c.similarity - (rival?.similarity ?? 0);
      final resolved = c.inContext || c.atSurahStart;
      final uniqueness =
          resolved ? 1.0 : (0.5 + margin / 0.3).clamp(0.5, 1.0);
      final confidence = c.similarity * lengthFactor(m, resolved) * uniqueness;

      final spans = _spans(body, c.start, c.end, offset);
      final pre = List<Preamble>.of(preambles);
      // لو انقرأت البسملة وبعدها مباشرة 1:2، فالبسملة هي الآية 1:1.
      if (pre.isNotEmpty &&
          pre.last.type == PreambleType.basmala &&
          spans.isNotEmpty &&
          spans.first.surah == 1 &&
          spans.first.ayah == 2) {
        final b = pre.removeLast();
        spans.insert(0, AyahSpan(1, 1, 1.0, b.queryStart, b.queryEnd));
      }

      final alternatives = <AlternativeMatch>[];
      for (final d in distinct) {
        if (identical(d, c)) continue;
        if (c.similarity - d.similarity > 0.15) continue;
        final ai = _ayahIndexAt(d.start);
        alternatives.add(AlternativeMatch(_surah[ai], _ayah[ai], d.similarity));
        if (alternatives.length >= 3) break;
      }

      out.add(QuranMatch(
        similarity: c.similarity,
        confidence: confidence,
        isAmbiguous: !resolved && margin < 0.1,
        continuesContext: c.inContext,
        corpusStart: c.start,
        corpusEnd: c.end,
        ayahs: spans,
        preambles: pre,
        alternatives: alternatives,
        query: query,
        letters: m,
      ));
    }
    return out;
  }

  /// عامل الطول: مقطع قصير (كم حرف) ممكن يكون موجود بأكثر من مكان، فثقته
  /// أقل. لو السياق حسم الموقع، بنتساهل أكثر (المقاطع القصيرة زي "الله
  /// الصمد" طبيعية بنص التلاوة).
  static double lengthFactor(int letters, bool resolvedByContext) =>
      math.min(1.0, letters / (resolvedByContext ? 10 : 24));

  // ---------------------------------------------------------------------

  /// هل [p] (مقدمة) موجودة ببداية [q]؟ بيرجّع (طولها بالاستعلام، تشابه).
  (int, double)? _prefixMatch(Uint8List q, Uint8List p) {
    if (q.length < p.length - 3) return null;
    final maxErr = math.max(2, (p.length * 0.15).floor());
    // edit distance بين p وكل بادئة من q بطول p±4.
    final maxLen = math.min(q.length, p.length + 4);
    var prev = List<int>.generate(maxLen + 1, (j) => j);
    for (var i = 1; i <= p.length; i++) {
      final cur = List<int>.filled(maxLen + 1, 0);
      cur[0] = i;
      for (var j = 1; j <= maxLen; j++) {
        final sub = prev[j - 1] + (p[i - 1] == q[j - 1] ? 0 : 1);
        cur[j] = math.min(sub, math.min(prev[j] + 1, cur[j - 1] + 1));
      }
      prev = cur;
    }
    var bestLen = -1, bestD = 1 << 30;
    for (var j = math.max(0, p.length - 4); j <= maxLen; j++) {
      if (prev[j] < bestD || (prev[j] == bestD && j > bestLen)) {
        bestD = prev[j];
        bestLen = j;
      }
    }
    if (bestLen < 0 || bestD > maxErr) return null;
    // لازم يكون في شي بعدها أو تكون هي كل المقطع.
    return (bestLen, 1 - bestD / p.length);
  }

  List<_Candidate> _verify(Uint8List q, int? previousEnd, int? nextStart,
      int topN, bool preferSurahStart) {
    final m = q.length;
    final votes = <int, double>{};
    if (m >= gramSize) {
      for (var i = 0; i + gramSize <= m; i++) {
        final occ = _grams[_hash(q, i)];
        if (occ == null || occ.length > _maxGramFrequency) continue;
        final w = 1.0 / math.log(2 + occ.length);
        for (final p in occ) {
          final b = (p - i) ~/ _bucket;
          votes[b] = (votes[b] ?? 0) + w;
        }
      }
    }
    if (previousEnd != null) {
      final b = previousEnd ~/ _bucket;
      votes[b] = (votes[b] ?? 0) + 1e9; // دايماً نتحقق من "يكمّل من السابق"
    }
    if (nextStart != null) {
      final b = math.max(0, nextStart - m) ~/ _bucket;
      votes[b] = (votes[b] ?? 0) + 1e9; // ... ومن "بيخلص قبل اللاحق"
    }
    if (votes.isEmpty) return const [];

    final ranked = votes.entries.toList()
      ..sort((a, b) {
        final c = b.value.compareTo(a.value);
        return c != 0 ? c : a.key.compareTo(b.key); // ترتيب ثابت عند التعادل
      });
    final seen = <int>[];
    final out = <_Candidate>[];
    for (final e in ranked.take(topN * 3)) {
      final d = e.key * _bucket;
      if (seen.any((s) => (d - s).abs() < m ~/ 2 + _bucket)) continue;
      seen.add(d);
      final lo = math.max(0, d - m ~/ 4 - 8);
      final hi = math.min(_codes.length, d + m + m ~/ 4 + 8);
      final r = _semiGlobal(q, lo, hi);
      final sim = 1 - r.$1 / m;
      final inCtx = (previousEnd != null &&
              r.$2 >= previousEnd - m ~/ 2 - 10 &&
              r.$2 <= previousEnd + 300) ||
          (nextStart != null &&
              r.$3 <= nextStart + m ~/ 2 + 10 &&
              r.$3 >= nextStart - 300);
      final atStart = preferSurahStart &&
          (_surahStarts.contains(r.$2) ||
              _surahStarts.contains(r.$2 - 1) ||
              _surahStarts.contains(r.$2 + 1));
      out.add(_Candidate(sim, r.$2, r.$3, inCtx, atStart));
      if (seen.length >= topN) break;
    }
    out.sort((a, b) => b.rank.compareTo(a.rank));
    return out;
  }

  /// أقل "تكلفة" محاذاة شبه-شاملة (بداية ونهاية حرة على طرف القرآن) بين q
  /// وأي جزء من corpus[lo:hi]. بيرجّع (التكلفة، البداية، النهاية) كمواقع
  /// مطلقة بالنص المتصل.
  ///
  /// حالتين لكل خلية: M (تطابق/استبدال، أو "حذف" حرف استعلام بتكلفة 1
  /// موحّدة — حرف زيادة بالتعرف، نادراً بيطوّل) و Dh (فجوة: حرف من القرآن
  /// ناقص بالاستعلام، بتكلفة affine عشان الفجوات الطويلة ما توقّف المحاذاة
  /// قبلها). نفس الفكرة بـ tool/proto/matcher.py (`semi_global`).
  (double, int, int) _semiGlobal(Uint8List q, int lo, int hi) {
    final n = hi - lo;
    final m = q.length;

    var prevM = Float64List(n + 1); // مبدئياً كل القيم 0 (بداية حرة)
    var prevMStart = Int32List(n + 1);
    for (var j = 0; j <= n; j++) {
      prevMStart[j] = j;
    }
    var prevDh = Float64List(n + 1)..fillRange(0, n + 1, double.infinity);
    var prevDhStart = Int32List(n + 1);

    var curM = Float64List(n + 1);
    var curMStart = Int32List(n + 1);
    var curDh = Float64List(n + 1);
    var curDhStart = Int32List(n + 1);

    for (var i = 1; i <= m; i++) {
      curM[0] = i.toDouble();
      curMStart[0] = 0;
      curDh[0] = double.infinity;
      curDhStart[0] = 0;
      final qi = q[i - 1];
      for (var j = 1; j <= n; j++) {
        final subCost = qi == _codes[lo + j - 1] ? 0.0 : 1.0;
        double subBase;
        int subStart;
        if (prevM[j - 1] <= prevDh[j - 1]) {
          subBase = prevM[j - 1];
          subStart = prevMStart[j - 1];
        } else {
          subBase = prevDh[j - 1];
          subStart = prevDhStart[j - 1];
        }
        final subVal = subBase + subCost;

        double delBase;
        int delStart;
        if (prevM[j] <= prevDh[j]) {
          delBase = prevM[j];
          delStart = prevMStart[j];
        } else {
          delBase = prevDh[j];
          delStart = prevDhStart[j];
        }
        final delVal = delBase + 1.0;

        if (subVal <= delVal) {
          curM[j] = subVal;
          curMStart[j] = subStart;
        } else {
          curM[j] = delVal;
          curMStart[j] = delStart;
        }

        final openVal = curM[j - 1] + _gapOpen;
        final extendVal = curDh[j - 1] + _gapExtend;
        if (openVal <= extendVal) {
          curDh[j] = openVal;
          curDhStart[j] = curMStart[j - 1];
        } else {
          curDh[j] = extendVal;
          curDhStart[j] = curDhStart[j - 1];
        }
      }
      final tm = prevM;
      prevM = curM;
      curM = tm;
      final tms = prevMStart;
      prevMStart = curMStart;
      curMStart = tms;
      final td = prevDh;
      prevDh = curDh;
      curDh = td;
      final tds = prevDhStart;
      prevDhStart = curDhStart;
      curDhStart = tds;
    }

    var bestJ = 0;
    var bestCost = prevM[0] <= prevDh[0] ? prevM[0] : prevDh[0];
    var bestStart = prevM[0] <= prevDh[0] ? prevMStart[0] : prevDhStart[0];
    for (var j = 1; j <= n; j++) {
      final c = prevM[j] <= prevDh[j] ? prevM[j] : prevDh[j];
      if (c <= bestCost) {
        // عند التعادل: الأطول
        bestCost = c;
        bestJ = j;
        bestStart = prevM[j] <= prevDh[j] ? prevMStart[j] : prevDhStart[j];
      }
    }
    return (bestCost, lo + bestStart, lo + bestJ);
  }

  /// محاذاة كاملة (مع traceback) بين q و corpus[start:end) وتقسيمها على
  /// الآيات. [queryOffset] = طول المقدمات المحذوفة من بداية الاستعلام.
  ///
  /// [start, end) ثابتين (جايين من [_semiGlobal]: أفضل بداية ونهاية)، فما
  /// في بداية/نهاية حرة هون — لازم كل حروف q وكل حروف النافذة ينحسبوا
  /// بمحاذاة واحدة كاملة، بنفس تكلفة affine gap تبع [_semiGlobal] (حالتين:
  /// M و Dh)، عشان الـ traceback (وتوقيت كل جزء من [qAt]) يطابق الاختيار
  /// اللي صار فوق بالضبط.
  List<AyahSpan> _spans(Uint8List q, int start, int end, int queryOffset) {
    final m = q.length, n = end - start;
    if (n <= 0) return [];
    final w = n + 1;
    final dm = Float32List((m + 1) * w);
    final dh = Float32List((m + 1) * w);
    for (var j = 0; j <= n; j++) {
      dh[j] = double.infinity;
    }
    dm[0] = 0;
    for (var j = 1; j <= n; j++) {
      dm[j] = double.infinity;
    }
    for (var j = 1; j <= n; j++) {
      final openVal = dm[j - 1] + _gapOpen;
      final extendVal = dh[j - 1] + _gapExtend;
      dh[j] = math.min(openVal, extendVal);
    }
    for (var i = 1; i <= m; i++) {
      dh[i * w] = double.infinity;
      dm[i * w] = i.toDouble(); // سلسلة "حذف" موحّدة بالعمود صفر
      final qi = q[i - 1];
      for (var j = 1; j <= n; j++) {
        final subCost = qi == _codes[start + j - 1] ? 0.0 : 1.0;
        final diagM = dm[(i - 1) * w + (j - 1)];
        final diagDh = dh[(i - 1) * w + (j - 1)];
        final subVal = (diagM <= diagDh ? diagM : diagDh) + subCost;
        final upM = dm[(i - 1) * w + j];
        final upDh = dh[(i - 1) * w + j];
        final delVal = (upM <= upDh ? upM : upDh) + 1.0;
        dm[i * w + j] = math.min(subVal, delVal);
        final openVal = dm[i * w + j - 1] + _gapOpen;
        final extendVal = dh[i * w + j - 1] + _gapExtend;
        dh[i * w + j] = math.min(openVal, extendVal);
      }
    }

    // qAt[j] = رقم حرف الاستعلام المقابل لحرف القرآن start+j.
    // matched[j] = حرف القرآن start+j انطابق فعلاً بحرف استعلام حقيقي
    // (مش بس "عبرناه" بفجوة Dh — آية كاملة أسقطها التعرف بنص المقطع ما
    // بتصير "مغطّاة" وهمياً، يوم 5).
    final qAt = Int32List(n);
    final matched = Uint8List(n);
    var i = m, j = n;
    var inM = dm[i * w + j] <= dh[i * w + j];
    while (j > 0) {
      if (inM) {
        final here = dm[i * w + j];
        final subCost = q[i - 1] == _codes[start + j - 1] ? 0.0 : 1.0;
        final diagM = dm[(i - 1) * w + (j - 1)];
        final diagDh = dh[(i - 1) * w + (j - 1)];
        final subVal = (diagM <= diagDh ? diagM : diagDh) + subCost;
        if ((subVal - here).abs() < 1e-3) {
          qAt[j - 1] = i - 1;
          matched[j - 1] = 1;
          final fromM = diagM <= diagDh;
          i--;
          j--;
          inM = fromM;
        } else {
          // "حذف": حرف استعلام زيادة بدون حرف قرآن مقابل — i بس بتنزل.
          i--;
          final upM = dm[i * w + j];
          final upDh = dh[i * w + j];
          inM = upM <= upDh;
        }
      } else {
        // بفجوة Dh: حرف قرآن ناقص من الاستعلام (أسقطه التعرف). ما
        // بنعلّمه matched، بس لازم قيمة qAt تقريبية (للتوقيت) بدون ما
        // تأثر على حساب التغطية.
        qAt[j - 1] = i > 0 ? i - 1 : 0;
        final leftM = dm[i * w + (j - 1)];
        final leftDh = dh[i * w + (j - 1)];
        final openVal = leftM + _gapOpen;
        final extendVal = leftDh + _gapExtend;
        j--;
        inM = openVal <= extendVal;
      }
    }

    final spans = <AyahSpan>[];
    var ai = _ayahIndexAt(start);
    while (ai < _surah.length && _starts[ai] < end) {
      final aStart = _starts[ai], aEnd = _starts[ai + 1];
      final s = math.max(aStart, start), e = math.min(aEnd, end);
      if (e > s) {
        final len = aEnd - aStart;
        var matchedCount = 0;
        var first = -1, last = -1;
        for (var p = s; p < e; p++) {
          if (matched[p - start] == 1) {
            matchedCount++;
            if (first < 0) first = p;
            last = p;
          }
        }
        // الأطراف من أول/آخر حرف انطابق فعلاً (مش من فجوة بالأطراف).
        final fs = first < 0 ? s : first, ls = last < 0 ? e - 1 : last;
        spans.add(AyahSpan(
          _surah[ai],
          _ayah[ai],
          len == 0 ? 1 : matchedCount / len,
          queryOffset + qAt[fs - start],
          queryOffset + qAt[ls - start] + 1,
          keyStart: fs - aStart,
          keyEnd: ls + 1 - aStart,
        ));
      }
      ai++;
    }
    // آيات بأطرافها مغطاة بحرف أو حرفين بس غالباً ضجيج محاذاة: نشيلها.
    spans.removeWhere((s) =>
        spans.length > 1 && s.coverage < 0.08 && (s.queryEnd - s.queryStart) < 3);
    return spans;
  }
}

class _Candidate {
  final double similarity;
  final int start;
  final int end;
  final bool inContext;
  final bool atSurahStart;
  const _Candidate(
      this.similarity, this.start, this.end, this.inContext, this.atSurahStart);
  double get rank =>
      similarity +
      (inContext ? QuranMatcher._contextBonus : 0) +
      (atSurahStart ? QuranMatcher._surahStartBonus : 0);
}
