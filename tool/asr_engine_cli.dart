// أداة سطر أوامر (يوم 4): بتشغّل **نفس كود التطبيق** (lib/asr/) على Linux
// بالـ CI: مدير النموذج (تحميل من الـ Release + SHA256) ← قراءة WAV وتحويله
// لـ 16kHz ← VAD + sherpa-onnx (باكج Dart الرسمي) ← QuranSequenceMatcher.
// بتطبع لكل مقطع: الوقت، السورة:الآية، الثقة، والـ RTF، وبتكتب JSON بنفس
// صيغة run_asr.py عشان tool/match_transcripts.dart يقارن مع Python.
//
// usage: dart run tool/asr_engine_cli.dart CLIPS_JSON OUT_JSON [MODEL_BASE_DIR]
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:quran_dub/asr/asr_engine.dart';
import 'package:quran_dub/asr/asr_model_manager.dart';
import 'package:quran_dub/asr/recitation_matcher.dart';
import 'package:quran_dub/matching/quran_corpus_loader.dart';
import 'package:quran_dub/matching/quran_matcher.dart';

Future<void> main(List<String> args) async {
  final clips = json.decode(File(args[0]).readAsStringSync()) as List<dynamic>;
  final outPath = args[1];
  final mgr = AsrModelManager(Directory(args.length > 2 ? args[2] : 'build/asr/app_model'));

  // 1) مدير النموذج: أول مرة بينزّل ويتحقق، تاني مرة offline.
  final sw = Stopwatch()..start();
  var lastPct = -10;
  final paths = await mgr.ensureReady(onProgress: (p) {
    final pct = (p.fraction * 100).floor();
    if (pct >= lastPct + 10) {
      lastPct = pct;
      print('  download $p');
    }
  });
  print('model ready in ${sw.elapsedMilliseconds}ms → ${mgr.dir.path}');
  if (!await mgr.isReady()) {
    print('ERROR: isReady() false after ensureReady()');
    exit(1);
  }
  sw.reset();
  await mgr.ensureReady();
  print('second ensureReady (offline, no download): ${sw.elapsedMilliseconds}ms ✅');
  final testClip = await mgr.ensureTestClip();
  print('test clip: $testClip (${File(testClip).lengthSync()} bytes, SHA256 ✅)\n');

  final matcher = QuranMatcher.build(loadSeedFile('assets/quran/quran_data.json.gz'));

  final out = <Map<String, Object?>>[];
  var ok = 0, expectedTotal = 0, foundTotal = 0, wrongTotal = 0;
  for (final raw in clips) {
    final c = raw as Map<String, dynamic>;
    final t = AsrEngine.transcribeWavFileSync(paths, c['wav'] as String);
    final matches = matchTranscript(matcher, t);
    final exp = _range(c['expected'] as String);
    final found = foundAyahs(matches);
    final good = found.where(exp.contains).length;
    final wrong = found.where((f) => !exp.contains(f)).toList();
    final pass = good == exp.length && wrong.isEmpty;
    if (pass) ok++;
    expectedTotal += exp.length;
    foundTotal += good;
    wrongTotal += wrong.length;
    print('=== ${c['id']} (${t.audioSeconds.toStringAsFixed(1)}s) '
        'expected ${c['expected']}: ${pass ? "✅" : "❌"} $good/${exp.length}'
        '${wrong.isEmpty ? "" : " wrong=$wrong"}');
    print('  init ${t.initMs}ms | VAD+ASR ${t.recognizeMs}ms | RTF ${t.rtf.toStringAsFixed(3)}');
    for (final line in describeMatches(matches)) {
      print('  $line');
    }
    out.add({
      ...c,
      'duration': double.parse(t.audioSeconds.toStringAsFixed(2)),
      'rtf_whole': 0,
      'rtf_vad': double.parse(t.rtf.toStringAsFixed(4)),
      // "whole" هون = المقاطع ورا بعض (الأداة الأصلية بتتعرف على الملف كامل).
      'whole': {
        'text': t.segments.map((s) => s.text.trim()).join(' '),
        'char_times': <double>[],
      },
      'segments': [for (final s in t.segments) s.toJson()],
    });
  }
  File(outPath).writeAsStringSync(const JsonEncoder.withIndent(' ').convert(out));
  print('\nSUMMARY (Dart engine, app code): exact $ok/${clips.length}, '
      'ayah recall $foundTotal/$expectedTotal, wrong $wrongTotal');
}

List<String> _range(String s) {
  // "1:1-1:7"
  final parts = s.split('-');
  final a = parts[0].split(':');
  final b = parts[1].split(':');
  final surah = int.parse(a[0]);
  return [for (var i = int.parse(a[1]); i <= int.parse(b[1]); i++) '$surah:$i'];
}
