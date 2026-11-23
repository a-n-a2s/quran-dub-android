// أداة سطر أوامر (نموذج أولي يوم 3): بتقرأ نواتج محرك التعرف على الصوت
// (من tool/asr_prototype/run_asr.py) وبتطابقها مع القرآن بـ QuranMatcher،
// وبتطبع رقم السورة/الآية ونسبة الثقة وتوقيت كل آية بالكونسول.
//
// usage: dart run tool/match_transcripts.dart transcripts.json [summary.md]
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:quran_dub/asr/asr_engine.dart';
import 'package:quran_dub/matching/quran_corpus_loader.dart';
import 'package:quran_dub/matching/quran_matcher.dart';
import 'package:quran_dub/matching/quran_sequence_matcher.dart';
import 'package:quran_dub/pipeline/quran_text_source.dart';
import 'package:quran_dub/pipeline/segment_builder.dart';

import 'pipeline_eval.dart';

void main(List<String> args) {
  final clips = json.decode(File(args[0]).readAsStringSync()) as List<dynamic>;
  final summaryPath = args.length > 1 ? args[1] : null;

  final sw = Stopwatch()..start();
  final matcher =
      QuranMatcher.build(loadSeedFile('assets/quran/quran_data.json.gz'));
  print('matcher ready in ${sw.elapsedMilliseconds}ms '
      '(${matcher.ayahCount} ayahs, ${matcher.corpusLength} letters)\n');

  final seqMatcher = QuranSequenceMatcher(matcher);
  final text = QuranTextSource.fromSeedFile('assets/quran/quran_data.json.gz');
  final evals = <(Map<String, dynamic>, ClipEval)>[];
  final md = StringBuffer()
    ..writeln('## نتيجة النموذج الأولي: تعرف على الصوت + مطابقة (يوم 3)\n')
    ..writeln('| المقطع | المتوقع | كامل: النتيجة | الثقة | VAD+تسلسل: آيات صح/متوقع | آيات غلط | (بدون تسلسل) | RTF |')
    ..writeln('|---|---|---|---|---|---|---|---|');

  var wholeOk = 0, vadOk = 0, greedyOk = 0, total = 0;
  var greedyFound = 0, greedyWrong = 0;
  var expectedAyahsTotal = 0, foundAyahsTotal = 0, wrongAyahsTotal = 0;

  for (final raw in clips) {
    final c = raw as Map<String, dynamic>;
    total++;
    final exp = _parseRange(c['expected'] as String);
    print('=== ${c['id']} (${c['reciter']}, ${c['duration']}s, '
        'expected ${c['expected']}${c['degraded'] == true ? ', phone-like noisy' : ''})');

    // 1) المقطع كامل
    final whole = c['whole'] as Map<String, dynamic>;
    final wText = whole['text'] as String;
    final ms = Stopwatch()..start();
    final w = matcher.match(wText);
    final wMs = ms.elapsedMilliseconds;
    final wGot = w?.first == null
        ? '-'
        : '${w!.first!.surah}:${w.first!.ayah}-${w.last!.surah}:${w.last!.ayah}';
    final isWholeOk = w != null &&
        w.first != null &&
        w.first!.surah == exp.$1 &&
        w.first!.ayah == exp.$2 &&
        w.last!.surah == exp.$1 &&
        w.last!.ayah == exp.$3;
    if (isWholeOk) wholeOk++;
    print('  ASR : $wText');
    print('  WHOLE → $wGot  confidence=${w?.confidence.toStringAsFixed(2)} '
        'similarity=${w?.similarity.toStringAsFixed(2)} (${wMs}ms) '
        '${isWholeOk ? "✅" : "❌"}');

    final segs = (c['segments'] as List<dynamic>).cast<Map<String, dynamic>>();

    // 2a) للمقارنة: كل مقطع لحاله (greedy) مع previousEnd بس.
    {
      final gFound = <String>{}, gWrong = <String>{};
      int? prevEnd;
      for (final s in segs) {
        final r = matcher.match(s['text'] as String, previousEnd: prevEnd);
        if (r == null) continue;
        if (r.ayahs.isNotEmpty && r.confidence >= 0.3) prevEnd = r.corpusEnd;
        if (r.confidence < 0.3) continue;
        for (final a in r.ayahs) {
          final inRange =
              a.surah == exp.$1 && a.ayah >= exp.$2 && a.ayah <= exp.$3;
          (inRange ? gFound : gWrong).add('${a.surah}:${a.ayah}');
        }
        if (r.ayahs.isEmpty && r.alternatives.any((x) => x.surah == 1 && x.ayah == 1)) {
          if (exp.$1 == 1 && exp.$2 == 1) gFound.add('1:1');
        }
      }
      greedyFound += gFound.length;
      greedyWrong += gWrong.length;
      if (gFound.length == exp.$3 - exp.$2 + 1 && gWrong.isEmpty) greedyOk++;
      c['_greedy'] = '${gFound.length}/${exp.$3 - exp.$2 + 1}, wrong ${gWrong.length}';
    }

    // 2b) مقاطع VAD مع مطابقة التسلسل (Viterbi) + توقيت الآيات
    final found = <String>{};
    final wrong = <String>{};
    final seqSw = Stopwatch()..start();
    final seqResults = seqMatcher.matchAll([for (final s in segs) s['text'] as String]);
    final seqMs = seqSw.elapsedMilliseconds;
    for (var si = 0; si < segs.length; si++) {
      final s = segs[si];
      final text = s['text'] as String;
      final times = (s['char_times'] as List<dynamic>).cast<num>();
      final r = seqResults[si];
      final head = '  [${s['start']}s–${s['end']}s] ';
      if (r == null) {
        print('$head(no match) "$text"');
        continue;
      }
      final pre = r.preambles.map((p) => p.type.name).join('+');
      final parts = <String>[];
      for (final a in r.ayahs) {
        String t(int keyIdx) {
          if (times.isEmpty || keyIdx >= r.query.sourceIndex.length) return '?';
          final src = r.query.sourceIndex[keyIdx];
          return src < times.length ? times[src].toStringAsFixed(2) : '?';
        }

        parts.add('${a.surah}:${a.ayah} '
            '[${t(a.queryStart)}s→${t(a.queryEnd - 1)}s, ${(a.coverage * 100).round()}%]');
        if (r.confidence >= 0.3) {
          final k = '${a.surah}:${a.ayah}';
          final inRange =
              a.surah == exp.$1 && a.ayah >= exp.$2 && a.ayah <= exp.$3;
          (inRange ? found : wrong).add(k);
        }
      }
      if (r.ayahs.isEmpty && r.alternatives.any((x) => x.surah == 1 && x.ayah == 1)) {
        if (exp.$1 == 1 && exp.$2 == 1) found.add('1:1');
      }
      print('$head${pre.isEmpty ? "" : "($pre) "}${parts.join(", ")} '
          'conf=${r.confidence.toStringAsFixed(2)}'
          '${r.continuesContext ? " ctx" : ""}${r.isAmbiguous ? " AMBIGUOUS" : ""}');
    }
    final expCount = exp.$3 - exp.$2 + 1;
    expectedAyahsTotal += expCount;
    foundAyahsTotal += found.length;
    wrongAyahsTotal += wrong.length;
    final isVadOk = found.length == expCount && wrong.isEmpty;
    if (isVadOk) vadOk++;
    print('  VAD+sequence → found ${found.length}/$expCount ayahs, wrong=${wrong.toList()} '
        '${isVadOk ? "✅" : "❌"} (${seqMs}ms for ${segs.length} segments; '
        'greedy was ${c['_greedy']})\n');

    // 3) يوم 5: خط الأنابيب كامل (نفس كود التطبيق) على نفس المقاطع.
    final asrSegs = [
      for (final s in segs)
        AsrSegment(
          start: (s['start'] as num).toDouble(),
          end: (s['end'] as num).toDouble(),
          text: s['text'] as String,
          charTimes: [for (final x in s['char_times'] as List<dynamic>) (x as num).toDouble()],
          tokens: const [],
          timestamps: const [],
        ),
    ];
    final pipe = buildRecitationSegments(matcher, text, asrSegs);
    final pe = evaluateClip(c, pipe);
    evals.add((c, pe));
    print('  PIPELINE → ${pe.good}/${pe.expected.length} ${pe.exact ? "✅" : "❌"}'
        '${pe.wrong.isEmpty ? "" : " wrong=${pe.wrong}"}'
        '${pe.inferred.isEmpty ? "" : " inferred=${pe.inferred}"}'
        '${pe.nonQuranHits.isEmpty ? "" : " over-non-quran=${pe.nonQuranHits}"}\n');

    md.writeln('| ${c['id']} | ${c['expected']} | $wGot ${isWholeOk ? "✅" : "❌"} '
        '| ${w?.confidence.toStringAsFixed(2) ?? "-"} '
        '| ${found.length}/$expCount ${isVadOk ? "✅" : "❌"} | ${wrong.length} '
        '| ${c['_greedy']} | ${c['rtf_vad']} |');
  }

  final line = 'SUMMARY: whole-clip exact $wholeOk/$total | '
      'VAD+sequence exact $vadOk/$total, ayah recall $foundAyahsTotal/$expectedAyahsTotal, '
      'wrong ayahs $wrongAyahsTotal | (greedy per-segment: exact $greedyOk/$total, '
      'recall $greedyFound/$expectedAyahsTotal, wrong $greedyWrong)';
  print(line);
  md
    ..writeln()
    ..writeln('**$line**');
  final pipeMd = evalMarkdown('خط الأنابيب كامل على نفس النواتج (يوم 5)', evals);
  print('\n$pipeMd');
  md
    ..writeln()
    ..writeln(pipeMd);
  if (summaryPath != null) File(summaryPath).writeAsStringSync(md.toString());

  // بوابة النموذج الأولي: نفشل لو الدقة واطية بشكل واضح.
  if (total == 0 || foundAyahsTotal / expectedAyahsTotal < 0.8) exitCode = 1;
}

(int, int, int) _parseRange(String r) {
  final parts = r.split('-');
  final a = parts[0].split(':').map(int.parse).toList();
  final b = parts[1].split(':').map(int.parse).toList();
  return (a[0], a[1], b[1]);
}
