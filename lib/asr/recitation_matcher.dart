import '../matching/quran_matcher.dart';
import '../matching/quran_sequence_matcher.dart';
import 'asr_engine.dart';

/// آية (أو جزء منها) جوا مقطع، مع توقيتها من توقيت الحروف.
class AyahTiming {
  final int surah;
  final int ayah;
  final double start;
  final double end;
  final double coverage;
  const AyahTiming(this.surah, this.ayah, this.start, this.end, this.coverage);
  String get ref => '$surah:$ayah';
}

/// نتيجة مقطع VAD واحد بعد المطابقة.
class SegmentMatch {
  final AsrSegment segment;
  final QuranMatch? match;
  final List<AyahTiming> ayahs;

  /// استعاذة/بسملة ببداية المقطع.
  final List<PreambleType> preambles;

  /// المقطع بسملة بس قبل الفاتحة 1:2 (يعني هي الآية 1:1).
  final bool isFatihaBasmala;

  const SegmentMatch(this.segment, this.match, this.ayahs, this.preambles,
      this.isFatihaBasmala);

  double get confidence => match?.confidence ?? 0;

  String describe() {
    final where = ayahs.isNotEmpty
        ? ayahs.map((a) => a.ref).join('، ')
        : (isFatihaBasmala
            ? '1:1 (بسملة)'
            : (preambles.isNotEmpty
                ? preambles.map((p) => p == PreambleType.basmala ? 'بسملة' : 'استعاذة').join('+')
                : 'مش قرآن / ما انطابق'));
    return where;
  }
}

/// يطابق كل مقاطع التفريغ مع بعض بـ [QuranSequenceMatcher] (Viterbi)،
/// وبيحسب توقيت كل آية من توقيت الحروف. (يوم 5 رح يكمّل: تقسيم التفسير،
/// والبسملة، وأماكن النص غير القرآني.)
List<SegmentMatch> matchTranscript(QuranMatcher matcher, AsrTranscript t) {
  final segs = t.segments;
  final results =
      QuranSequenceMatcher(matcher).matchAll([for (final s in segs) s.text]);
  final out = <SegmentMatch>[];
  for (var i = 0; i < segs.length; i++) {
    final s = segs[i];
    final r = results[i];
    if (r == null) {
      out.add(SegmentMatch(s, null, const [], const [], false));
      continue;
    }
    double timeAt(int keyIdx, double fallback) {
      if (s.charTimes.isEmpty || keyIdx < 0 || keyIdx >= r.query.sourceIndex.length) {
        return fallback;
      }
      final src = r.query.sourceIndex[keyIdx];
      return src < s.charTimes.length ? s.charTimes[src] : fallback;
    }

    final ayahs = [
      for (final a in r.ayahs)
        AyahTiming(a.surah, a.ayah, timeAt(a.queryStart, s.start),
            timeAt(a.queryEnd - 1, s.end), a.coverage),
    ];
    // بسملة لحالها والمقطع اللي بعده بيبلّش من 1:2 → هي 1:1.
    var fatihaBasmala = false;
    if (r.ayahs.isEmpty &&
        r.preambles.isNotEmpty &&
        r.preambles.last.type == PreambleType.basmala) {
      for (var j = i + 1; j < segs.length; j++) {
        final n = results[j];
        if (n == null || n.ayahs.isEmpty) continue;
        fatihaBasmala = n.ayahs.first.surah == 1 && n.ayahs.first.ayah == 2;
        break;
      }
    }
    out.add(SegmentMatch(s, r, ayahs,
        [for (final p in r.preambles) p.type], fatihaBasmala));
  }
  return out;
}

/// ملخص سطر لكل مقطع: الوقت، السورة:الآية، الثقة.
List<String> describeMatches(List<SegmentMatch> matches) => [
      for (final m in matches)
        '[${m.segment.start.toStringAsFixed(2)}s–${m.segment.end.toStringAsFixed(2)}s] '
            '${m.describe()}  ثقة ${(m.confidence * 100).round()}%',
    ];

/// الآيات اللي انلقطت (بثقة ≥ [minConfidence]) بالترتيب بدون تكرار.
List<String> foundAyahs(List<SegmentMatch> matches, {double minConfidence = 0.3}) {
  final seen = <String>{};
  final out = <String>[];
  for (final m in matches) {
    if (m.isFatihaBasmala && seen.add('1:1')) out.add('1:1');
    if (m.confidence < minConfidence) continue;
    for (final a in m.ayahs) {
      if (seen.add(a.ref)) out.add(a.ref);
    }
  }
  return out;
}
