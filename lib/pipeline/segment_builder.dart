import 'dart:math' as math;

import '../asr/asr_engine.dart';
import '../matching/arabic_normalizer.dart';
import '../matching/quran_matcher.dart';
import '../matching/quran_sequence_matcher.dart';
import 'quran_text_source.dart';
import 'recitation_segment.dart';
import 'text_splitter.dart';

class PipelineOptions {
  final TafsirMode tafsirMode;

  /// مقطع انطابق بثقة أقل من هيك → مش قرآن (مكان لنص المستخدم) مع اقتراح.
  final double nonQuranBelow;

  /// ومقطع تشابهه مع القرآن أقل من هيك وما بيكمّل من/لـ جيرانه → مش قرآن
  /// (كلام عادي زي "السلام عليكم..." بيطلع تشابهه ~0.45–0.55 مع أقرب آية،
  /// والتلاوة الحقيقية حتى بتسجيل جوال فوق ~0.7).
  final double minQuranSimilarity;

  /// ثقة أقل من هيك (أو موقع مش محسوم) → "بده مراجعة".
  final double reviewBelow;

  /// التفسير بينقسم بس لما يكون "طويل": على الأقل هالعدد من الحروف لكل
  /// جزء، وإلا بيطلع كامل تحت كل جزء.
  final int minTafsirCharsPerPart;

  /// آيات ناقصة بين آيتين انطابقوا (التعرف أسقطها): نكتبها "مستنتجة" لو
  /// عددها لحد هيك، والوقت بينهم على الأقل [inferMinSecondsPerAyah] لكل آية
  /// **و** على الأقل [inferMinPaceFraction] من الوقت المتوقع لقراءتها بسرعة
  /// القارئ نفسه بهالمقطع (من الآيات اللي انطابقت)، والآيتين حواليهم ثقتهم
  /// ≥ [inferMinConfidence].
  ///
  /// (يوم 7، بعد تجربة أنس: كانت 3 آيات بحد أقصى وثقة ≥ 0.5 بس، فآيات كتير
  /// بتسجيل جوال كانت بتضيع. فحص السرعة بيمنع نستنتج آيات ما في وقت يكفيها.)
  final int inferMaxMissing;
  final double inferMinSecondsPerAyah;
  final double inferMinPaceFraction;
  final double inferMinConfidence;

  /// النص المعروض = **الآية كاملة** (مقسومة على أجزاءها لو انقسمت)، حتى لو
  /// التعرف ما طلّع أول أو آخر كلماتها. بيضل الجزء اللي انسمع بس لما القارئ
  /// يوقف بنص الآية ويرجع يعيدها (أو لما التلاوة إعادة من النص). (يوم 7:
  /// كانت الكلمات اللي التعرف ما طلّعها بتنشال من الشاشة، زي "بِظَلَّٰمٖ
  /// لِّلۡعَبِيدِ" بـ 50:29 بتجربة أنس.)
  final bool showWholeAyah;

  /// لو أكثر من هالنسبة من الآية ما انسمعت وانضافت للعرض → "بده مراجعة".
  final double reviewIfAddedAbove;

  const PipelineOptions({
    this.tafsirMode = TafsirMode.split,
    this.nonQuranBelow = 0.3,
    this.minQuranSimilarity = 0.6,
    this.reviewBelow = 0.6,
    this.minTafsirCharsPerPart = 60,
    this.inferMaxMissing = 8,
    this.inferMinSecondsPerAyah = 0.8,
    this.inferMinPaceFraction = 0.35,
    this.inferMinConfidence = 0.35,
    this.showWholeAyah = true,
    this.reviewIfAddedAbove = 0.5,
  });
}

/// كل مقاطع VAD → [QuranSequenceMatcher] → قائمة [RecitationSegment]
/// بتوقيتها (Dart صافي: نفس الكود بالتطبيق وبالـ CI والاختبارات).
List<RecitationSegment> buildRecitationSegments(
  QuranMatcher matcher,
  QuranTextSource text,
  List<AsrSegment> segments, {
  PipelineOptions options = const PipelineOptions(),
}) {
  final matches = QuranSequenceMatcher(matcher)
      .matchAll([for (final s in segments) s.text]);
  return segmentsFromMatches(text, segments, matches, options: options);
}

class _AyahItem {
  final int surah, ayah;
  int ks, ke; // بمفتاح الآية
  double start, end;
  final double confidence;
  final bool review;
  final String asr;
  final bool inferred;

  /// وقت آخر حرف فعلاً (قبل ما نمدّ النهاية لبداية الآية الجاية).
  double rawEnd;
  _AyahItem(this.surah, this.ayah, this.ks, this.ke, this.start, this.end,
      this.confidence, this.review, this.asr,
      {this.inferred = false, double? rawEnd})
      : rawEnd = rawEnd ?? end;
}

/// مقطع انطابق بس ضعيف (ثقة واطية، أو تشابه قليل وما بيكمّل من جيرانه):
/// افتراضياً "مش قرآن" ([placeholder])، إلا لو طلع **محصور** بين آيتين
/// انطابقوا ومتّسق معهم (نفس السورة وبالترتيب) → بيرجع آيات ([items])
/// "بده مراجعة". (يوم 7: قبل هيك كان دايماً بيختفي.)
class _Weak {
  final RecitationSegment placeholder;
  final List<_AyahItem> items;
  _Weak(this.placeholder, this.items);
}

List<RecitationSegment> segmentsFromMatches(
  QuranTextSource text,
  List<AsrSegment> segments,
  List<QuranMatch?> matches, {
  PipelineOptions options = const PipelineOptions(),
}) {
  final events = <Object>[]; // RecitationSegment أو _AyahItem بالترتيب
  final basmalaText = text.ayah(1, 1)?.uthmani ?? 'بِسۡمِ ٱللَّهِ ٱلرَّحۡمَٰنِ ٱلرَّحِيمِ';

  for (var i = 0; i < segments.length; i++) {
    final s = segments[i];
    final r = matches[i];
    final asr = s.text.trim();
    if (r == null || (r.ayahs.isEmpty && r.preambles.isEmpty)) {
      events.add(RecitationSegment(
          start: s.start,
          end: s.end,
          kind: SegmentKind.nonQuran,
          confidence: 0,
          asrText: asr));
      continue;
    }
    // بيكمّل من المقطع اللي قبله أو بيوصل للي بعده؟ (مقطع تعرّفه ضعيف بنص
    // تلاوة متصلة غالباً قرآن، مش كلام عادي.)
    QuranMatch? nextReal;
    for (var j = i + 1; j < segments.length; j++) {
      final n = matches[j];
      if (n != null && n.ayahs.isNotEmpty) {
        nextReal = n;
        break;
      }
    }
    final linked = r.continuesContext ||
        (nextReal != null &&
            nextReal.continuesContext &&
            (nextReal.corpusStart - r.corpusEnd).abs() <= 25);
    final weak = r.ayahs.isNotEmpty &&
        (r.confidence < options.nonQuranBelow ||
            (r.similarity < options.minQuranSimilarity && !linked));
    if (weak) {
      events.add(_Weak(
        RecitationSegment(
            start: s.start,
            end: s.end,
            kind: SegmentKind.nonQuran,
            confidence: r.confidence,
            needsReview: true,
            suggestedRef: '${r.ayahs.first.surah}:${r.ayahs.first.ayah}',
            asrText: asr),
        r.preambles.isEmpty
            ? _ayahItems(s, r, asr, review: true).toList()
            : const [],
      ));
      continue;
    }
    events.addAll(_preambleSegments(s, r, asr, basmalaText, options));
    events.addAll(_ayahItems(s, r, asr,
        review: r.confidence < options.reviewBelow || r.isAmbiguous));
  }

  _promoteSandwiched(events);
  for (var i = 0; i < events.length; i++) {
    final e = events[i];
    if (e is _Weak) events[i] = e.placeholder;
  }
  _rescueShortSegments(text, events);
  _inferMissingAyahs(text, events, options);

  // تجميع الأجزاء المتتالية لنفس الآية: كل مجموعة = تلاوة وحدة للآية.
  final groups = <Object>[]; // List<_AyahItem> أو RecitationSegment
  var group = <_AyahItem>[];
  void flush() {
    if (group.isNotEmpty) groups.add(group);
    group = [];
  }

  for (final e in events) {
    if (e is _AyahItem) {
      // آية ثانية، أو نفس الآية بس القارئ رجع عادها (بلّش قبل وين وقف):
      // تلاوة جديدة للآية بأجزائها وتفسيرها، مش "جزء" من الأولى.
      if (group.isNotEmpty &&
          (group.last.surah != e.surah ||
              group.last.ayah != e.ayah ||
              (e.ks >= 0 && group.last.ke >= 0 && e.ks < group.last.ke - 3))) {
        flush();
      }
      group.add(e);
    } else {
      flush();
      groups.add(e as RecitationSegment);
    }
  }
  flush();

  // المجموعة اللي قبل/بعد (بتتخطى المقاطع غير القرآنية بس): لو هي نفس
  // الآية، فهاي إعادة → بنعرض اللي انقرأ بس من جهتها.
  List<_AyahItem>? neighbour(int idx, int dir) {
    for (var j = idx + dir; j >= 0 && j < groups.length; j += dir) {
      final g = groups[j];
      if (g is List<_AyahItem>) return g;
      if ((g as RecitationSegment).kind != SegmentKind.nonQuran) return null;
    }
    return null;
  }

  bool sameAyah(List<_AyahItem>? g, _AyahItem x) =>
      g != null && g.first.surah == x.surah && g.first.ayah == x.ayah;

  final out = <RecitationSegment>[];
  for (var gi = 0; gi < groups.length; gi++) {
    final g = groups[gi];
    if (g is RecitationSegment) {
      out.add(g);
      continue;
    }
    final items = g as List<_AyahItem>;
    out.addAll(_buildGroup(text, items, options,
        rereading: sameAyah(neighbour(gi, -1), items.first),
        readAgainAfter: sameAyah(neighbour(gi, 1), items.first)));
  }
  return out;
}

/// المقدمات (استعاذة/بسملة) بمقطع VAD واحد، بتوقيتها.
Iterable<RecitationSegment> _preambleSegments(AsrSegment s, QuranMatch r,
    String asr, String basmalaText, PipelineOptions options) sync* {
  final review = r.confidence < options.reviewBelow || r.isAmbiguous;
  final onlyPreambles = r.ayahs.isEmpty;
  for (final p in r.preambles) {
    final t0 = onlyPreambles && p == r.preambles.first
        ? s.start
        : _timeAt(s, r, p.queryStart, s.start);
    final t1 = onlyPreambles && p == r.preambles.last
        ? s.end
        : _timeAt(s, r, p.queryEnd - 1, s.end);
    final isBasmala = p.type == PreambleType.basmala;
    yield RecitationSegment(
      start: t0,
      end: t1 < t0 ? t0 : t1,
      kind: isBasmala ? SegmentKind.basmala : SegmentKind.istiadha,
      text: isBasmala ? basmalaText : '',
      confidence: r.confidence,
      needsReview: review,
      asrText: asr,
    );
  }
}

/// وقت حرف رقم [keyIdx] بمفتاح الاستعلام المطبّع (من توقيت حروف التعرف).
double _timeAt(AsrSegment s, QuranMatch r, int keyIdx, double fallback) {
  if (s.charTimes.isEmpty || keyIdx < 0 || keyIdx >= r.query.sourceIndex.length) {
    return fallback;
  }
  final src = r.query.sourceIndex[keyIdx];
  return src < s.charTimes.length ? s.charTimes[src] : fallback;
}

/// الآيات بمقطع VAD واحد بتوقيتها.
///
/// التوقيت: حدود مقطع VAD (بداية/نهاية الكلام) أدق من توقيت أول/آخر حرف
/// (محرك CTC بيطلّع الحرف ببداية صوته، والمد بآخر الآية بيطوّل بعده).
/// فأول آية بالمقطع بتبلّش مع المقطع (لو ما في مقدمات)، وآخر آية بتخلص
/// معه، والحد بين آيتين جوا المقطع = قبل أول حرف من الآية الجاية بشوي.
Iterable<_AyahItem> _ayahItems(AsrSegment s, QuranMatch r, String asr,
    {required bool review}) sync* {
  final t0s = [for (final a in r.ayahs) _timeAt(s, r, a.queryStart, s.start)];
  final t1s = [for (final a in r.ayahs) _timeAt(s, r, a.queryEnd - 1, s.end)];
  for (var k = 0; k < r.ayahs.length; k++) {
    final a = r.ayahs[k];
    var t0 = t0s[k], t1 = t1s[k];
    if (k == 0 && r.preambles.isEmpty && t0 - s.start < _snapSeconds) {
      t0 = s.start;
    }
    if (k == r.ayahs.length - 1) {
      if (s.end - t1 < _snapSeconds) t1 = s.end;
    } else {
      t1 = math.max(t1, t0s[k + 1] - 0.2);
    }
    yield _AyahItem(a.surah, a.ayah, a.keyStart, a.keyEnd, t0,
        t1 < t0 ? t0 : t1, r.confidence, review, asr,
        rawEnd: k == r.ayahs.length - 1 ? null : math.max(t0, t1s[k]));
  }
}

/// مقطع ضعيف ([_Weak]) محصور بين آيتين انطابقوا (ممكن مع مقاطع غير قرآنية
/// بالنص)، ومن نفس السورة، وآياته بالترتيب بينهم (بيكمّل الآية اللي قبله أو
/// اللي بعدها، أو بيعبّي آيات ناقصة بينهم) → آيات "بده مراجعة" بتوقيتها
/// الحقيقي بدل ما يختفي. الكلام العادي (مقدمة، دعاء) ما بيكون محصور ومتّسق
/// هيك، فبيضل "مش قرآن".
void _promoteSandwiched(List<Object> events) {
  _AyahItem? find(int from, int dir) {
    for (var j = from + dir, hops = 0;
        j >= 0 && j < events.length && hops < 4;
        j += dir, hops++) {
      final e = events[j];
      if (e is _AyahItem) return e;
      final skippable = e is _Weak ||
          (e is RecitationSegment && e.kind == SegmentKind.nonQuran);
      if (!skippable) return null;
    }
    return null;
  }

  for (var i = 0; i < events.length; i++) {
    final w = events[i];
    if (w is! _Weak || w.items.isEmpty) continue;
    final prev = find(i, -1), next = find(i, 1);
    if (prev == null || next == null) continue;
    final f = w.items.first, l = w.items.last;
    final sameSurah = prev.surah == f.surah &&
        f.surah == l.surah &&
        l.surah == next.surah;
    if (!sameSurah) continue;
    final ordered = prev.ayah <= f.ayah &&
        f.ayah <= prev.ayah + 2 &&
        f.ayah <= l.ayah &&
        l.ayah <= next.ayah &&
        l.ayah >= next.ayah - 2;
    final close = w.placeholder.start - prev.end < 20 &&
        next.start - w.placeholder.end < 20;
    if (!ordered || !close) continue;
    events.replaceRange(i, i + 1, w.items);
    i += w.items.length - 1;
  }
}

/// سرعة القارئ بهالمقطع: ثواني لكل حرف من مفتاح الآية (الوسيط من الآيات
/// اللي انطابقت فعلاً)، لتقدير وقت الآيات الناقصة.
double _secondsPerKeyChar(List<Object> events) {
  final rates = <double>[];
  for (final e in events) {
    if (e is! _AyahItem || e.inferred || e.ke < 0) continue;
    final chars = e.ke - e.ks;
    final d = e.rawEnd - e.start;
    if (chars >= 8 && d > 0.3) rates.add(d / chars);
  }
  if (rates.isEmpty) return 0.1;
  rates.sort();
  return rates[rates.length ~/ 2].clamp(0.03, 0.5).toDouble();
}

/// [rereading]: المجموعة اللي قبلها نفس الآية (هاي إعادة، ممكن من نص الآية).
/// [readAgainAfter]: المجموعة اللي بعدها نفس الآية (القارئ وقف هون ورجع).
List<RecitationSegment> _buildGroup(
    QuranTextSource text, List<_AyahItem> items, PipelineOptions options,
    {bool rereading = false, bool readAgainAfter = false}) {
  final first = items.first;
  final content = text.ayah(first.surah, first.ayah);
  final uthmani = content?.uthmani ?? '';
  final tafsirFull = content?.tafsir ?? '';
  final cutter = AyahTextCutter(uthmani);
  final len = cutter.keyLength;
  final p = items.length;

  // نطاقات الأجزاء بمفتاح الآية، مع حدود مشتركة للأجزاء المتتالية.
  for (final it in items) {
    it.ke = it.ke < 0 ? len : it.ke.clamp(0, len);
    it.ks = it.ks.clamp(0, it.ke);
  }
  // الآية كاملة على الشاشة (أول الجزء الأول = أول الآية، وآخر الجزء الأخير =
  // آخرها)، إلا من جهة إعادة: إعادة من نص الآية بتبلّش من وين بلّش القارئ،
  // وتلاوة وقف فيها القارئ ورجع بتخلص وين وقف.
  final heardFrom = items.first.ks, heardTo = items.last.ke;
  if (items.first.ks <= 2 || (options.showWholeAyah && !rereading)) {
    items.first.ks = 0;
  }
  if (items.last.ke >= len - 2 || (options.showWholeAyah && !readAgainAfter)) {
    items.last.ke = len;
  }
  final added = (heardFrom - items.first.ks) + (items.last.ke - heardTo);
  final mostlyUnheard =
      len > 0 && !first.inferred && added > options.reviewIfAddedAbove * len;
  for (var k = 0; k + 1 < p; k++) {
    final cur = items[k], next = items[k + 1];
    if (next.ks >= cur.ke - 3) {
      // بيكمّل (مش إعادة): حد واحد بالنص بين آخر حرف وأول حرف.
      final b = ((cur.ke + next.ks) / 2).round().clamp(0, len);
      cur.ke = b;
      next.ks = b;
    }
  }

  // نمط التقسيم بيتحسب دايماً ([RecitationSegment.tafsirSplit]) عشان المعاينة
  // تبدّل بين النمطين بدون إعادة تحليل؛ و[RecitationSegment.tafsir] بتتبع
  // [PipelineOptions.tafsirMode].
  final splitWanted =
      p > 1 && tafsirFull.length >= options.minTafsirCharsPerPart * p;
  final split = splitWanted && len > 0
      ? TafsirSplitter.split(
          tafsirFull, [for (final it in items) (it.ks / len, it.ke / len)])
      : null;
  final splitTafsirs = split ?? List.filled(p, tafsirFull);
  final tafsirs = options.tafsirMode == TafsirMode.split
      ? splitTafsirs
      : List.filled(p, tafsirFull);

  final out = <RecitationSegment>[];
  for (var k = 0; k < p; k++) {
    final it = items[k];
    var partText =
        cutter.slice(cutter.boundaryAt(it.ks), cutter.boundaryAt(it.ke));
    if (partText.isEmpty) partText = cutter.wordsCovering(it.ks, it.ke);
    final whole = p == 1 && it.ks == 0 && it.ke == len;
    out.add(RecitationSegment(
      start: it.start,
      end: it.end,
      kind: whole ? SegmentKind.fullAyah : SegmentKind.partialAyah,
      surah: it.surah,
      ayah: it.ayah,
      part: k + 1,
      partCount: p,
      text: partText,
      showAyahNumber: k == p - 1 && it.ke == len,
      tafsir: tafsirs[k],
      tafsirFull: tafsirFull,
      tafsirSplit: splitTafsirs[k],
      confidence: it.confidence,
      needsReview: it.review || mostlyUnheard,
      asrText: it.asr,
      inferred: it.inferred,
    ));
  }
  return out;
}

const double _snapSeconds = 4.0;

int _editDistance(String a, String b) {
  var prev = List<int>.generate(b.length + 1, (j) => j);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
    for (var j = 1; j <= b.length; j++) {
      cur[j] = math.min(
          prev[j - 1] + (a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1),
          math.min(prev[j] + 1, cur[j - 1] + 1));
    }
    prev = cur;
  }
  return prev[b.length];
}

bool _close(String a, String b) =>
    a.isNotEmpty &&
    b.isNotEmpty &&
    _editDistance(a, b) <= math.max(1, (b.length * 0.34).floor());

/// مقاطع VAD قصيرة كتير (كلمة وحدة) ما بتنطابق لحالها (أقل من 6 حروف):
/// مثلاً 55:1 "الرحمن"، أو "الله" ببداية آية الكرسي لما القارئ يوقف بعدها.
/// لو جنبها آية انطابقت ونصها بيطابق اللي ناقص منها (أو الآية اللي قبلها/
/// بعدها كاملة)، منرجّعها لمكانها.
void _rescueShortSegments(QuranTextSource text, List<Object> events) {
  String keyOf(int s, int a) =>
      ArabicNormalizer.key(text.ayah(s, a)?.uthmani ?? '');
  bool shortUnmatched(Object e) =>
      e is RecitationSegment &&
      e.kind == SegmentKind.nonQuran &&
      e.suggestedRef == null &&
      ArabicNormalizer.key(e.asrText).length <= 12;

  for (var i = 0; i < events.length; i++) {
    final e = events[i];
    if (!shortUnmatched(e)) continue;
    final seg = e as RecitationSegment;
    final k = ArabicNormalizer.key(seg.asrText);
    if (k.isEmpty) continue;
    final next = i + 1 < events.length ? events[i + 1] : null;
    final prev = i > 0 ? events[i - 1] : null;
    if (next is _AyahItem && next.start - seg.end < 3) {
      final ayahKey = keyOf(next.surah, next.ayah);
      if (next.ks > 0 && _close(k, ayahKey.substring(0, next.ks.clamp(0, ayahKey.length)))) {
        // أول الآية انقرأ لحاله قبل وقفة.
        next
          ..ks = 0
          ..start = seg.start;
        events.removeAt(i--);
        continue;
      }
      if (next.ks <= 2 && next.ayah > 1 && _close(k, keyOf(next.surah, next.ayah - 1))) {
        events[i] = _AyahItem(next.surah, next.ayah - 1, 0, -1, seg.start,
            seg.end, next.confidence * 0.8, true, seg.asrText);
        continue;
      }
    }
    if (prev is _AyahItem && seg.start - prev.end < 3) {
      final ayahKey = keyOf(prev.surah, prev.ayah);
      final ke = prev.ke < 0 ? ayahKey.length : prev.ke;
      if (ke < ayahKey.length && _close(k, ayahKey.substring(ke))) {
        prev
          ..ke = ayahKey.length
          ..end = seg.end;
        events.removeAt(i--);
        continue;
      }
      if (ke >= ayahKey.length - 2 &&
          text.ayah(prev.surah, prev.ayah + 1) != null &&
          _close(k, keyOf(prev.surah, prev.ayah + 1))) {
        events[i] = _AyahItem(prev.surah, prev.ayah + 1, 0, -1, seg.start,
            seg.end, prev.confidence * 0.8, true, seg.asrText);
      }
    }
  }
}

/// بين آيتين متتاليتين بالقائمة (بدون بسملة/كلام بينهم) من نفس السورة، لو
/// في آية أو كم آية ناقصة والوقت بينهم بيكفّي، منضيفها "مستنتجة": الوقت
/// بينهم بينقسم بنسبة طول كل آية.
void _inferMissingAyahs(
    QuranTextSource text, List<Object> events, PipelineOptions options) {
  if (options.inferMaxMissing <= 0) return;
  final secPerChar = _secondsPerKeyChar(events);
  int keyLen(int s, int a) =>
      ArabicNormalizer.key(text.ayah(s, a)?.uthmani ?? '').length.clamp(1, 1 << 20);
  for (var i = 0; i + 1 < events.length; i++) {
    final a = events[i];
    if (a is! _AyahItem) continue;
    // الآية الجاية، مع السماح بمقاطع "مش قرآن" بينهم (كلام التعرف خرّبه،
    // غالباً هو الآيات الناقصة نفسها، زي الضجيج القوي).
    var j = i + 1;
    while (j < events.length &&
        events[j] is RecitationSegment &&
        (events[j] as RecitationSegment).kind == SegmentKind.nonQuran) {
      j++;
    }
    if (j >= events.length) continue;
    final b = events[j];
    if (b is! _AyahItem) continue;
    final missing = b.ayah - a.ayah - 1;
    if (a.surah != b.surah || missing < 1 || missing > options.inferMaxMissing) {
      continue;
    }
    if (math.min(a.confidence, b.confidence) < options.inferMinConfidence) {
      continue;
    }
    final gap = b.start - a.rawEnd;
    final lens = [
      for (var k = 1; k <= missing; k++) keyLen(a.surah, a.ayah + k),
    ];
    final total = lens.fold<int>(0, (x, y) => x + y);
    // كمان الجزء اللي ما انسمع من آخر a وأول b بياخد من نفس الوقت.
    final aRest = a.ke < 0 ? 0 : math.max(0, keyLen(a.surah, a.ayah) - a.ke);
    final bRest = math.max(0, b.ks);
    final expected = (total + aRest + bRest) * secPerChar;
    if (gap < options.inferMinSecondsPerAyah * missing ||
        gap < options.inferMinPaceFraction * expected) {
      continue;
    }
    a.end = a.rawEnd;
    var t = a.rawEnd;
    final add = <_AyahItem>[];
    for (var k = 0; k < missing; k++) {
      final d = gap * lens[k] / total;
      add.add(_AyahItem(a.surah, a.ayah + k + 1, 0, -1, t, t + d,
          math.min(a.confidence, b.confidence) * 0.5, true, '',
          inferred: true));
      t += d;
    }
    events
      ..removeRange(i + 1, j)
      ..insertAll(i + 1, add);
    i += add.length;
  }
}

/// تلاوة وحدة لآية [surah]:[ayah] مقسومة على أوقات [partTimes] (جزء لكل
/// نطاق، بالترتيب) — للمحرر (يوم 10: تغيير الآية، إضافة مقطع يدوي، وإعادة
/// بناء أجزاء آية بعد حذف جزء منها). **نفس [_buildGroup] تبع خط الأنابيب
/// بالضبط** (قص النص على حدود الكلمات، رقم الآية مع آخر جزء، تقسيم التفسير
/// بـ [TafsirSplitter] وحد [PipelineOptions.minTafsirCharsPerPart])، فما في
/// نسخة ثانية من المنطق. الفرق الوحيد: ما في توقيت حروف من التعرف، فحدود
/// الأجزاء بمفتاح الآية بتتوزّع **بنسبة مدة كل جزء**.
///
/// آية مش موجودة بالمصدر → مقاطع "مش قرآن" فاضية "بدها مراجعة" (باقتراح
/// الرقم اللي انطلب) بنفس الأوقات، بدل استثناء.
List<RecitationSegment> buildAyahReading(
  QuranTextSource text,
  int surah,
  int ayah,
  List<(double, double)> partTimes, {
  PipelineOptions options = const PipelineOptions(),
  double confidence = 1.0,
  bool needsReview = false,
  String asrText = '',
  bool inferred = false,
}) {
  if (partTimes.isEmpty) return const [];
  final times = [
    for (final (s, e) in partTimes) (s, e < s ? s : e),
  ];
  final content = text.ayah(surah, ayah);
  if (content == null) {
    return [
      for (final (s, e) in times)
        RecitationSegment(
          start: s,
          end: e,
          kind: SegmentKind.nonQuran,
          confidence: confidence,
          needsReview: true,
          suggestedRef: '$surah:$ayah',
          asrText: asrText,
        ),
    ];
  }
  final len = AyahTextCutter(content.uthmani).keyLength;
  final durations = [for (final (s, e) in times) e - s];
  final total = durations.fold<double>(0, (a, b) => a + b);
  final items = <_AyahItem>[];
  var acc = 0.0;
  var prevKe = 0;
  for (var k = 0; k < times.length; k++) {
    acc += total > 0 ? durations[k] : 1;
    final frac = acc / (total > 0 ? total : times.length);
    final ke = k == times.length - 1 ? len : (len * frac).round().clamp(prevKe, len);
    items.add(_AyahItem(surah, ayah, prevKe, ke, times[k].$1, times[k].$2,
        confidence, needsReview, asrText,
        inferred: inferred));
    prevKe = ke;
  }
  return _buildGroup(text, items, options);
}

/// الآيات اللي انكتبت (بالترتيب، بدون تكرار).
List<String> pipelineAyahRefs(List<RecitationSegment> segs) {
  final seen = <String>{};
  return [
    for (final s in segs)
      if (s.isAyah && seen.add(s.ref!)) s.ref!,
  ];
}

/// كلمات الآية (مقسومة على المسافات) للتقسيم اليدوي بالمحرر.
List<String> ayahWords(QuranTextSource text, int surah, int ayah) {
  final c = text.ayah(surah, ayah);
  if (c == null) return const [];
  return [for (final m in RegExp(r'\S+').allMatches(c.uthmani)) m.group(0)!];
}

/// تلاوة آية **مقسومة يدوياً على حدود كلمات** (طلب أنس 2026-11-28: "تقسم الآية
/// لسطر فيه كم كلمة"). [cuts] = عدد الكلمات قبل كل حد (بين 1 وعدد الكلمات−1)؛
/// فاضية = الآية كاملة بجزء واحد. الأوقات: [partTimes] لو بنفس عدد الأجزاء،
/// وإلا [start]–[end] بتتوزّع بنسبة طول كل جزء. الباقي (القص، الرقم مع آخر جزء،
/// تقسيم التفسير) بنفس [_buildGroup] تبع خط الأنابيب.
List<RecitationSegment> buildAyahReadingAtWords(
  QuranTextSource text,
  int surah,
  int ayah,
  List<int> cuts, {
  required double start,
  required double end,
  List<(double, double)>? partTimes,
  PipelineOptions options = const PipelineOptions(),
  double confidence = 1.0,
}) {
  final content = text.ayah(surah, ayah);
  if (content == null) {
    return buildAyahReading(text, surah, ayah, [(start, end)],
        options: options, confidence: confidence);
  }
  final uthmani = content.uthmani;
  final words = RegExp(r'\S+').allMatches(uthmani).toList();
  final norm = ArabicNormalizer.keyWithMap(uthmani);
  final len = norm.key.length;
  int keyAt(int pos) {
    // عدد حروف المفتاح اللي موقعها بالنص قبل [pos].
    var lo = 0, hi = norm.sourceIndex.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (norm.sourceIndex[mid] < pos) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  final ks = <int>[];
  for (final c in ({...cuts}.toList()..sort())) {
    if (c < 1 || c >= words.length) continue;
    final k = keyAt(words[c].start);
    if (k <= 0 || k >= len) continue;
    if (ks.isNotEmpty && k <= ks.last) continue;
    ks.add(k);
  }
  final bounds = [0, ...ks, len];
  final p = bounds.length - 1;
  final e = end < start ? start : end;
  final List<(double, double)> times;
  if (partTimes != null && partTimes.length == p) {
    times = partTimes;
  } else {
    final total = e - start;
    final t = <(double, double)>[];
    var acc = start;
    for (var k = 0; k < p; k++) {
      final frac = len > 0 ? (bounds[k + 1] - bounds[k]) / len : 1 / p;
      final next = k == p - 1 ? e : acc + total * frac;
      t.add((acc, next));
      acc = next;
    }
    times = t;
  }
  final items = <_AyahItem>[
    for (var k = 0; k < p; k++)
      _AyahItem(surah, ayah, bounds[k], bounds[k + 1], times[k].$1, times[k].$2,
          confidence, false, ''),
  ];
  return _buildGroup(text, items, options);
}
