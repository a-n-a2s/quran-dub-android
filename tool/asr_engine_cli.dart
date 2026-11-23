// أداة سطر أوامر (يوم 4، يوم 5): بتشغّل **نفس كود التطبيق** (lib/asr/ +
// lib/pipeline/) على Linux بالـ CI: مدير النموذج (تحميل من الـ Release +
// SHA256) ← قراءة WAV وتحويله لـ 16kHz ← VAD + sherpa-onnx (المحرك عايش
// طول التشغيل، بيتحمّل مرة وحدة) ← QuranSequenceMatcher ← قائمة المقاطع
// (خط الأنابيب). بتطبع لكل مقطع المقاطع والثقة والـ RTF، وبتقيس خطأ توقيت
// كل آية مقابل الحقيقة (prepare_clips.py)، وبتقارن خيطين مع 4 خيوط.
// كمان بتكتب JSON بنفس صيغة run_asr.py عشان tool/match_transcripts.dart.
//
// usage: dart run tool/asr_engine_cli.dart CLIPS_JSON OUT_JSON [MODEL_BASE_DIR] [SUMMARY_MD]
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:quran_dub/asr/asr_engine.dart';
import 'package:quran_dub/asr/asr_model_manager.dart';
import 'package:quran_dub/matching/quran_corpus_loader.dart';
import 'package:quran_dub/matching/quran_matcher.dart';
import 'package:quran_dub/pipeline/quran_text_source.dart';
import 'package:quran_dub/pipeline/segment_builder.dart';

import 'pipeline_eval.dart';

Future<void> main(List<String> args) async {
  final clips = json.decode(File(args[0]).readAsStringSync()) as List<dynamic>;
  final outPath = args[1];
  final mgr = AsrModelManager(Directory(args.length > 2 ? args[2] : 'build/asr/app_model'));
  final summaryPath = args.length > 3 ? args[3] : null;

  // 1) مدير النموذج: أول مرة بينزّل ويتحقق، تاني مرة offline.
  var lastPct = -10;
  final paths = await mgr.ensureReady(onProgress: (p) {
    final pct = (p.fraction * 100).floor();
    if (pct >= lastPct + 10) {
      lastPct = pct;
      print('  download $p');
    }
  });
  print('model ready: ${mgr.lastReport} → ${mgr.dir.path}');
  if (!await mgr.isReady()) {
    print('ERROR: isReady() false after ensureReady()');
    exit(1);
  }
  await mgr.ensureReady();
  print('second ensureReady (offline, no download): ${mgr.lastReport} ✅');
  final testClip = await mgr.ensureTestClip();
  print('test clip: $testClip (${File(testClip).lengthSync()} bytes, SHA256 ✅)\n');

  final sw = Stopwatch()..start();
  const seed = 'assets/quran/quran_data.json.gz';
  final matcher = QuranMatcher.build(loadSeedFile(seed));
  final text = QuranTextSource.fromSeedFile(seed);
  print('matcher + text source ready in ${sw.elapsedMilliseconds}ms\n');

  // المحرك عايش: بيتحمّل مرة وحدة لكل عدد خيوط.
  final rec2 = AsrRecognizer(paths, config: const AsrEngineConfig(numThreads: 2));
  final rec4 = AsrRecognizer(paths, config: const AsrEngineConfig(numThreads: 4));
  print('recognizer init: 2 threads ${rec2.initMs}ms, 4 threads ${rec4.initMs}ms '
      '(once per run, ${Platform.numberOfProcessors} cores)\n');

  // نفس الملف اللي بيجرّبه أنس على جواله (مقطع الاختبار بالـ Release).
  clips.add({
    'id': 'release_test_clip_fatiha',
    'reciter': 'Alafasy (asr-model-v1 test clip)',
    'expected': '1:1-1:7',
    'wav': testClip,
    'group': 'phone_clip',
  });

  final out = <Map<String, Object?>>[];
  final evals = <(Map<String, dynamic>, ClipEval)>[];
  var ok = 0, expectedTotal = 0, foundTotal = 0, wrongTotal = 0;
  var audio = 0.0, asr2 = 0, asr4 = 0, matchMs = 0;
  for (final raw in clips) {
    final c = raw as Map<String, dynamic>;
    final t = rec2.transcribeWavFile(c['wav'] as String);
    final t4 = rec4.transcribeWavFile(c['wav'] as String);
    audio += t.audioSeconds;
    asr2 += t.recognizeMs;
    asr4 += t4.recognizeMs;
    final ms = Stopwatch()..start();
    final segs = buildRecitationSegments(matcher, text, t.segments);
    matchMs += ms.elapsedMilliseconds;
    final e = evaluateClip(c, segs);
    evals.add((c, e));
    if (e.exact) ok++;
    expectedTotal += e.expected.length;
    foundTotal += e.good;
    wrongTotal += e.wrong.length + e.nonQuranHits.length;
    final same = t4.segments.map((s) => s.text).join('|') ==
        t.segments.map((s) => s.text).join('|');
    print('=== ${c['id']} (${t.audioSeconds.toStringAsFixed(1)}s) '
        'expected ${c['expected']}: ${e.exact ? "✅" : "❌"} ${e.good}/${e.expected.length}'
        '${e.wrong.isEmpty ? "" : " wrong=${e.wrong}"}'
        '${e.inferred.isEmpty ? "" : " inferred=${e.inferred}"}'
        '${e.nonQuranHits.isEmpty ? "" : " over-non-quran=${e.nonQuranHits}"}');
    print('  RTF 2 threads ${t.rtf.toStringAsFixed(3)} | 4 threads ${t4.rtf.toStringAsFixed(3)} '
        '(same text: $same) | pipeline ${ms.elapsedMilliseconds}ms');
    for (final s in segs) {
      print('  ${s.describe()}');
      if (s.text.isNotEmpty) print('     ${s.text}');
      if (s.partCount > 1 && s.tafsir.isNotEmpty) print('     تفسير: ${s.tafsir}');
    }
    if (e.timing.isNotEmpty) {
      print('  timing error (start/end): '
          '${e.timing.map((x) => '${x.$1} ${x.$2.toStringAsFixed(2)}/${x.$3.toStringAsFixed(2)}').join(', ')}');
    }
    out.add({
      ...c,
      'duration': double.parse(t.audioSeconds.toStringAsFixed(2)),
      'rtf_whole': 0,
      'rtf_vad': double.parse(t.rtf.toStringAsFixed(4)),
      'rtf_vad_4threads': double.parse(t4.rtf.toStringAsFixed(4)),
      // "whole" هون = المقاطع ورا بعض (الأداة الأصلية بتتعرف على الملف كامل).
      'whole': {
        'text': t.segments.map((s) => s.text.trim()).join(' '),
        'char_times': <double>[],
      },
      'segments': [for (final s in t.segments) s.toJson()],
      'pipeline': [for (final s in segs) s.toJson()],
    });
  }
  rec2.free();
  rec4.free();
  File(outPath).writeAsStringSync(const JsonEncoder.withIndent(' ').convert(out));

  final speed = 'السرعة (نفس المحرك عايش): ${audio.toStringAsFixed(0)} ثانية صوت، '
      'خيطين ${asr2}ms (RTF ${(asr2 / 1000 / audio).toStringAsFixed(3)})، '
      '4 خيوط ${asr4}ms (RTF ${(asr4 / 1000 / audio).toStringAsFixed(3)})، '
      'خط الأنابيب (مطابقة + تقسيم) ${matchMs}ms';
  final md = '${evalMarkdown('خط الأنابيب كامل (محرك التطبيق Dart، يوم 5)', evals)}\n- $speed\n';
  print('\n$md');
  if (summaryPath != null) File(summaryPath).writeAsStringSync(md);
  print('SUMMARY (Dart engine + pipeline, app code): exact $ok/${clips.length}, '
      'ayah recall $foundTotal/$expectedTotal, wrong $wrongTotal');
  if (expectedTotal == 0 || foundTotal / expectedTotal < 0.8) exitCode = 1;
}
