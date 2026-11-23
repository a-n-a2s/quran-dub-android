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
  /// عددها لحد هيك، والوقت بينهم على الأقل [inferMinSecondsPerAyah] لكل آية.
  final int inferMaxMissing;
  final double inferMinSecondsPerAyah;

  const PipelineOptions({
    this.tafsirMode = TafsirMode.split,
    this.nonQuranBelow = 0.3,
    this.minQuranSimilarity = 0.6,
    this.reviewBelow = 0.6,
    this.minTafsirCharsPerPart = 60,
    this.inferMaxMissing = 3,
    this.inferMinSecondsPerAyah = 0.8,
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
    if (r.ayahs.isNotEmpty &&
        (r.confidence < options.nonQuranBelow ||
            (r.similarity < options.minQuranSimilarity && !linked))) {
      events.add(RecitationSegment(
          start: s.start,
          end: s.end,
          kind: SegmentKind.nonQuran,
          confidence: r.confidence,
          needsReview: true,
          suggestedRef: '${r.ayahs.first.surah}:${r.ayahs.first.ayah}',
          asrText: asr));
      continue;
    }

    double timeAt(int keyIdx, double fallback) {
      if (s.charTimes.isEmpty ||
          keyIdx < 0 ||
          keyIdx >= r.query.sourceIndex.length) {
        return fallback;
      }
      final src = r.query.sourceIndex[keyIdx];
      return src < s.charTimes.length ? s.charTimes[src] : fallback;
    }

    final review = r.confidence < options.reviewBelow || r.isAmbiguous;
    final onlyPreambles = r.ayahs.isEmpty;
    for (final p in r.preambles) {
      final t0 = onlyPreambles && p == r.preambles.first
          ? s.start
          : timeAt(p.queryStart, s.start);
      final t1 = onlyPreambles && p == r.preambles.last
          ? s.end
          : timeAt(p.queryEnd - 1, s.end);
      final isBasmala = p.type == PreambleType.basmala;
      events.add(RecitationSegment(
        start: t0,
        end: t1 < t0 ? t0 : t1,
        kind: isBasmala ? SegmentKind.basmala : SegmentKind.istiadha,
        text: isBasmala ? basmalaText : '',
        confidence: r.confidence,
        needsReview: review,
        asrText: asr,
      ));
    }
    // التوقيت: حدود مقطع VAD (بداية/نهاية الكلام) أدق من توقيت أول/آخر حرف
    // (محرك CTC بيطلّع الحرف ببداية صوته، والمد بآخر الآية بيطوّل بعده).
    // فأول آية بالمقطع بتبلّش مع المقطع (لو ما في مقدمات)، وآخر آية بتخلص
    // معه، والحد بين آيتين جوا المقطع = قبل أول حرف من الآية الجاية بشوي.
    final t0s = [for (final a in r.ayahs) timeAt(a.queryStart, s.start)];
    final t1s = [for (final a in r.ayahs) timeAt(a.queryEnd - 1, s.end)];
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
      events.add(_AyahItem(a.surah, a.ayah, a.keyStart, a.keyEnd, t0,
          t1 < t0 ? t0 : t1, r.confidence, review, asr,
          rawEnd: k == r.ayahs.length - 1 ? null : math.max(t0, t1s[k])));
    }
  }

  _rescueShortSegments(text, events);
  _inferMissingAyahs(text, events, options);

  // تجميع الأجزاء المتتالية لنفس الآية.
  final out = <RecitationSegment>[];
  var group = <_AyahItem>[];
  void flush() {
    if (group.isNotEmpty) out.addAll(_buildGroup(text, group, options));
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
      out.add(e as RecitationSegment);
    }
  }
  flush();
  return out;
}

List<RecitationSegment> _buildGroup(
    QuranTextSource text, List<_AyahItem> items, PipelineOptions options) {
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
  if (items.first.ks <= 2) items.first.ks = 0;
  if (items.last.ke >= len - 2) items.last.ke = len;
  for (var k = 0; k + 1 < p; k++) {
    final cur = items[k], next = items[k + 1];
    if (next.ks >= cur.ke - 3) {
      // بيكمّل (مش إعادة): حد واحد بالنص بين آخر حرف وأول حرف.
      final b = ((cur.ke + next.ks) / 2).round().clamp(0, len);
      cur.ke = b;
      next.ks = b;
    }
  }

  List<String> tafsirs;
  final splitWanted = options.tafsirMode == TafsirMode.split &&
      p > 1 &&
      tafsirFull.length >= options.minTafsirCharsPerPart * p;
  final split = splitWanted && len > 0
      ? TafsirSplitter.split(
          tafsirFull, [for (final it in items) (it.ks / len, it.ke / len)])
      : null;
  tafsirs = split ?? List.filled(p, tafsirFull);

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
      confidence: it.confidence,
      needsReview: it.review,
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
    if (math.min(a.confidence, b.confidence) < 0.5) continue;
    final gap = b.start - a.rawEnd;
    if (gap < options.inferMinSecondsPerAyah * missing) continue;
    a.end = a.rawEnd;
    final lens = [
      for (var k = 1; k <= missing; k++)
        ArabicNormalizer.key(text.ayah(a.surah, a.ayah + k)?.uthmani ?? '')
            .length
            .clamp(1, 1 << 20),
    ];
    final total = lens.fold<int>(0, (x, y) => x + y);
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

/// الآيات اللي انكتبت (بالترتيب، بدون تكرار).
List<String> pipelineAyahRefs(List<RecitationSegment> segs) {
  final seen = <String>{};
  return [
    for (final s in segs)
      if (s.isAyah && seen.add(s.ref!)) s.ref!,
  ];
}
