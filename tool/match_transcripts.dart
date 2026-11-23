// أداة سطر أوامر (نموذج أولي يوم 3): بتقرأ نواتج محرك التعرف على الصوت
// (من tool/asr_prototype/run_asr.py) وبتطابقها مع القرآن بـ QuranMatcher،
// وبتطبع رقم السورة/الآية ونسبة الثقة وتوقيت كل آية بالكونسول.
//
// usage: dart run tool/match_transcripts.dart transcripts.json [summary.md]
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:quran_dub/matching/quran_corpus_loader.dart';
import 'package:quran_dub/matching/quran_matcher.dart';

void main(List<String> args) {
  final clips = json.decode(File(args[0]).readAsStringSync()) as List<dynamic>;
  final summaryPath = args.length > 1 ? args[1] : null;

  final sw = Stopwatch()..start();
  final matcher =
      QuranMatcher.build(loadSeedFile('assets/quran/quran_data.json.gz'));
  print('matcher ready in ${sw.elapsedMilliseconds}ms '
      '(${matcher.ayahCount} ayahs, ${matcher.corpusLength} letters)\n');

  final md = StringBuffer()
    ..writeln('## نتيجة النموذج الأولي: تعرف على الصوت + مطابقة (يوم 3)\n')
    ..writeln('| المقطع | المتوقع | كامل: النتيجة | الثقة | VAD: آيات صح/متوقع | آيات غلط | RTF |')
    ..writeln('|---|---|---|---|---|---|---|');

  var wholeOk = 0, vadOk = 0, total = 0;
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

    // 2) مقاطع VAD متسلسلة مع السياق + توقيت الآيات
    final found = <String>{};
    final wrong = <String>{};
    int? prevEnd;
    for (final sraw in (c['segments'] as List<dynamic>)) {
      final s = sraw as Map<String, dynamic>;
      final text = s['text'] as String;
      final times = (s['char_times'] as List<dynamic>).cast<num>();
      final r = matcher.match(text, previousEnd: prevEnd);
      final head = '  [${s['start']}s–${s['end']}s] ';
      if (r == null) {
        print('$head(no match) "$text"');
        continue;
      }
      if (r.ayahs.isNotEmpty && r.confidence >= 0.3) prevEnd = r.corpusEnd;
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
    print('  VAD → found ${found.length}/$expCount ayahs, wrong=${wrong.toList()} '
        '${isVadOk ? "✅" : "❌"}\n');

    md.writeln('| ${c['id']} | ${c['expected']} | $wGot ${isWholeOk ? "✅" : "❌"} '
        '| ${w?.confidence.toStringAsFixed(2) ?? "-"} '
        '| ${found.length}/$expCount ${isVadOk ? "✅" : "❌"} | ${wrong.length} '
        '| ${c['rtf_vad']} |');
  }

  final line = 'SUMMARY: whole-clip exact $wholeOk/$total, '
      'VAD-segmented exact $vadOk/$total, '
      'ayah recall $foundAyahsTotal/$expectedAyahsTotal, wrong ayahs $wrongAyahsTotal';
  print(line);
  md
    ..writeln()
    ..writeln('**$line**');
  if (summaryPath != null) File(summaryPath).writeAsStringSync(md.toString());

  // بوابة النموذج الأولي: نفشل لو الدقة واطية بشكل واضح.
  if (total == 0 || wholeOk / total < 0.6) exitCode = 1;
}

(int, int, int) _parseRange(String r) {
  final parts = r.split('-');
  final a = parts[0].split(':').map(int.parse).toList();
  final b = parts[1].split(':').map(int.parse).toList();
  return (a[0], a[1], b[1]);
}
