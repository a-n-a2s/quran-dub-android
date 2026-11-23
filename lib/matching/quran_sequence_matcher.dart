import 'dart:math' as math;

import 'quran_matcher.dart';

/// مطابقة سلسلة مقاطع (من نفس الفيديو، مقطّعة على الوقفات بـ VAD) مع
/// القرآن **مع بعض** بدل كل مقطع لحاله.
///
/// ليش؟ مقطع قصير زي "الحمد لله رب العالمين" أو "الله لا إله إلا هو الحي
/// القيوم" موجود بأكثر من مكان بالقرآن. لحاله ما بنعرف وين، بس المقطع
/// اللي بعده بيحسم. فبنعمل Viterbi:
/// - كل مقطع إله لحد 5 مرشحين (مواقع مختلفة) من [QuranMatcher.candidates].
/// - نقاط المرشح = التشابه × عامل الطول.
/// - نقاط الانتقال بين مرشحين متتاليين: متصل (بيكمّل من وين وقف السابق)
///   = أعلى نقاط، إعادة لجزء (القارئ رجع كرر) = أقل، قفزة صغيرة لقدام =
///   أقل كمان، أي إشي ثاني = صفر. وبعد بسملة: بداية سورة = نقاط.
/// - بنختار المسار اللي مجموع نقاطه أعلى، وبنحسب ثقة كل مقطع من الفرق بين
///   أحسن مسار بيمر بالمرشح المختار وأحسن مسار بيمر بموقع ثاني
///   (max-marginals: forward + backward).
class QuranSequenceMatcher {
  final QuranMatcher matcher;
  final int maxCandidates;
  final double minSimilarity;

  const QuranSequenceMatcher(this.matcher,
      {this.maxCandidates = 5, this.minSimilarity = 0.45});

  static const double _contiguous = 0.6;
  static const double _repeat = 0.3;
  static const double _smallSkip = 0.15;
  static const double _surahStartAfterBasmala = 0.4;

  /// النتيجة بنفس ترتيب [segments] (null = مقطع ما انطابق: صمت/ضجيج).
  List<QuranMatch?> matchAll(List<String> segments) {
    final n = segments.length;
    final result = List<QuranMatch?>.filled(n, null);

    // 1) مرشحين لكل مقطع.
    final cands = List<List<QuranMatch>>.filled(n, const []);
    final basmalaBefore = List<bool>.filled(n, false);
    var pendingBasmala = false;
    for (var i = 0; i < n; i++) {
      final all = matcher.candidates(segments[i],
          expectSurahStart: pendingBasmala, maxResults: maxCandidates);
      if (all.length == 1 && all.first.isPreambleOnly) {
        result[i] = all.first;
        if (all.first.preambles.last.type == PreambleType.basmala) {
          pendingBasmala = true;
        }
        continue;
      }
      final good = all.where((c) => c.similarity >= minSimilarity).toList();
      if (good.isEmpty) continue;
      basmalaBefore[i] = pendingBasmala ||
          good.first.preambles.any((p) => p.type == PreambleType.basmala);
      pendingBasmala = false;
      cands[i] = good;
    }

    final real = [for (var i = 0; i < n; i++) if (cands[i].isNotEmpty) i];
    if (real.isEmpty) return result;

    // جولتين: الثانية بتضيف لكل مقطع مرشحين "إجباريين" بيكمّلوا من/لـ
    // المسار المختار بالجولة الأولى (عشان آية مكررة 31 مرة ما يضيع موقعها
    // الصح من أول 5 مرشحين).
    var chosen = _decode(real, cands, basmalaBefore).$1;
    for (var k = 0; k < real.length; k++) {
      final i = real[k];
      final prev = k > 0 ? cands[real[k - 1]][chosen[k - 1]] : null;
      final next = k + 1 < real.length ? cands[real[k + 1]][chosen[k + 1]] : null;
      final extra = matcher.candidates(segments[i],
          previousEnd: prev?.corpusEnd,
          nextStart: next?.corpusStart,
          expectSurahStart: basmalaBefore[i],
          maxResults: 2);
      final merged = List<QuranMatch>.of(cands[i]);
      for (final e in extra) {
        if (e.similarity < minSimilarity) continue;
        if (merged.every((c) => (c.corpusStart - e.corpusStart).abs() > 4)) {
          merged.add(e);
        }
      }
      cands[i] = merged;
    }
    final decoded = _decode(real, cands, basmalaBefore);
    chosen = decoded.$1;
    final alpha = decoded.$2, beta = decoded.$3;
    final r = real.length;

    // 4) ثقة كل مقطع من الـ max-marginals.
    for (var k = 0; k < r; k++) {
      final i = real[k];
      final cs = cands[i];
      final c = chosen[k];
      final mine = alpha[k][c] + beta[k][c];
      var rival = double.negativeInfinity;
      for (var x = 0; x < cs.length; x++) {
        if (x != c) rival = math.max(rival, alpha[k][x] + beta[k][x]);
      }
      final margin = rival.isInfinite ? 1.0 : mine - rival;
      final linkedIn = k > 0 &&
          _trans(cands[real[k - 1]][chosen[k - 1]], cs[c], basmalaBefore[i]) >=
              _repeat;
      final linkedOut = k + 1 < r &&
          _trans(cs[c], cands[real[k + 1]][chosen[k + 1]],
                  basmalaBefore[real[k + 1]]) >=
              _repeat;
      final linked = linkedIn || linkedOut || _init(basmalaBefore[i], cs[c]) > 0;
      final uniqueness = (0.5 + margin / 0.4).clamp(0.5, 1.0);
      final conf = cs[c].similarity *
          QuranMatcher.lengthFactor(cs[c].letters, linked) *
          uniqueness;
      result[i] = cs[c].copyWith(
        confidence: conf,
        isAmbiguous: margin < 0.1,
        continuesContext: linkedIn,
      );
    }

    // 5) بسملة لحالها وبعدها الفاتحة 1:2 → البسملة هي الآية 1:1.
    for (var i = 0; i + 1 < n; i++) {
      final b = result[i];
      if (b == null || !b.isPreambleOnly) continue;
      if (b.preambles.last.type != PreambleType.basmala) continue;
      QuranMatch? next;
      for (var j = i + 1; j < n; j++) {
        if (result[j] != null) {
          next = result[j];
          break;
        }
      }
      final f = next?.first;
      if (f != null && f.surah == 1 && f.ayah == 2) {
        final p = b.preambles.last;
        result[i] = b.copyWith(
          ayahs: [AyahSpan(1, 1, 1.0, p.queryStart, p.queryEnd)],
          preambles: b.preambles.sublist(0, b.preambles.length - 1),
        );
      }
    }
    return result;
  }

  static double _emit(QuranMatch c) =>
      c.similarity * math.min(1.0, c.letters / 12);

  static bool _atSurahStart(QuranMatch c) {
    final f = c.first;
    if (f == null) return false;
    return (f.ayah == 1 || (f.surah == 1 && f.ayah <= 2)) && f.coverage > 0.5;
  }

  static double _trans(QuranMatch p, QuranMatch c, bool basmalaBetween) {
    if (basmalaBetween) return _atSurahStart(c) ? _surahStartAfterBasmala : 0;
    final gap = c.corpusStart - p.corpusEnd;
    if (gap.abs() <= 25) return _contiguous;
    if (c.corpusStart >= p.corpusStart - 10 && c.corpusStart < p.corpusEnd) {
      return _repeat;
    }
    if (gap > 25 && gap <= 600) return _smallSkip;
    return 0;
  }

  static double _init(bool basmalaBefore, QuranMatch c) =>
      basmalaBefore && _atSurahStart(c) ? _surahStartAfterBasmala : 0;

  /// Viterbi: بيرجّع (المسار المختار، alpha، beta).
  (List<int>, List<List<double>>, List<List<double>>) _decode(
      List<int> real, List<List<QuranMatch>> cands, List<bool> basmalaBefore) {
    final r = real.length;
    // forward (alpha) + backward (beta) max-sum.
    final alpha = [for (final i in real) List<double>.filled(cands[i].length, 0)];
    final back = [for (final i in real) List<int>.filled(cands[i].length, -1)];
    for (var k = 0; k < r; k++) {
      final cs = cands[real[k]];
      for (var c = 0; c < cs.length; c++) {
        var best = _init(basmalaBefore[real[k]], cs[c]);
        var arg = -1;
        if (k > 0) {
          final ps = cands[real[k - 1]];
          for (var p = 0; p < ps.length; p++) {
            final v = alpha[k - 1][p] +
                _trans(ps[p], cs[c], basmalaBefore[real[k]]);
            if (arg == -1 || v > best) {
              best = v;
              arg = p;
            }
          }
        }
        alpha[k][c] = best + _emit(cs[c]);
        back[k][c] = arg;
      }
    }
    final beta = [for (final i in real) List<double>.filled(cands[i].length, 0)];
    for (var k = r - 2; k >= 0; k--) {
      final cs = cands[real[k]], ns = cands[real[k + 1]];
      for (var c = 0; c < cs.length; c++) {
        var best = double.negativeInfinity;
        for (var x = 0; x < ns.length; x++) {
          final v = _trans(cs[c], ns[x], basmalaBefore[real[k + 1]]) +
              _emit(ns[x]) +
              beta[k + 1][x];
          if (v > best) best = v;
        }
        beta[k][c] = best;
      }
    }

    // أحسن مسار (traceback).
    final chosen = List<int>.filled(r, 0);
    var last = 0;
    for (var c = 1; c < alpha[r - 1].length; c++) {
      if (alpha[r - 1][c] > alpha[r - 1][last]) last = c;
    }
    chosen[r - 1] = last;
    for (var k = r - 1; k > 0; k--) {
      chosen[k - 1] = math.max(0, back[k][chosen[k]]);
    }

    return (chosen, alpha, beta);
  }
}
