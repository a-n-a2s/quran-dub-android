import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../asr/asr_engine.dart';
import '../matching/quran_matcher_service.dart';
import '../pipeline/recitation_pipeline.dart';
import '../platform/media_picker.dart';

/// أداة تطوير (يوم 4 → يوم 5): خط الأنابيب كامل على الجوال نفسه.
/// - "تجربة على مقطع الفاتحة": بينزّل النموذج ومقطع الاختبار (مرة وحدة)،
///   بيشغّل خط الأنابيب بخيطين، وبعدين التعرف بـ 4 خيوط للمقارنة، وبيطبع وقت
///   كل خطوة + قائمة المقاطع (النص العثماني + التفسير المقسوم).
/// - "اختيار ملف": نفس الشي على أي ملف صوت/فيديو من الجوال.
/// المحرك عايش بـ isolate طول الجلسة، فالضغطة الثانية ما بتحمّل النموذج.
class AsrDebugPanel extends StatefulWidget {
  const AsrDebugPanel({super.key});

  @override
  State<AsrDebugPanel> createState() => _AsrDebugPanelState();
}

class _AsrDebugPanelState extends State<AsrDebugPanel> {
  bool _running = false;
  String _step = '';
  double? _progress;
  final List<String> _lines = [];
  bool? _passed;

  /// جلسة لكل عدد خيوط (عشان المقارنة ما تبني المحرك من جديد كل مرة).
  static final Map<int, Future<AsrSession>> _sessions = {};
  static Future<AsrSession> _session(int threads) =>
      _sessions[threads] ??= threads == 2 ? AsrSession.shared() : AsrSession.start();

  static const _expected = ['1:1', '1:2', '1:3', '1:4', '1:5', '1:6', '1:7'];

  void _log(String s) {
    debugPrint('[AsrDebug] $s');
    setState(() => _lines.add(s));
  }

  void _setStep(String s, [double? p]) {
    final pct = p == null ? null : (p * 100).floor();
    final old = _progress == null ? null : (_progress! * 100).floor();
    if (s == _step && pct == old) return;
    setState(() {
      _step = s;
      _progress = p;
    });
  }

  String _sec(int ms) => '${(ms / 1000).toStringAsFixed(ms < 10000 ? 2 : 1)}s';

  Future<void> _run({bool pickFile = false}) async {
    setState(() {
      _running = true;
      _lines.clear();
      _passed = null;
    });
    final total = Stopwatch()..start();
    try {
      String input;
      String label;
      if (pickFile) {
        _setStep('اختيار ملف...');
        final picked = await MediaPicker.pick();
        if (picked == null) {
          _log('ما انختار ملف.');
          return;
        }
        input = picked.path;
        label = '${picked.name} (${(picked.bytes / 1e6).toStringAsFixed(1)}MB)';
        total.reset();
      } else {
        input = '';
        label = 'مقطع الفاتحة (العفاسي، 46 ثانية)';
      }
      _log('— الملف: $label —');

      // 0) قاعدة البيانات والـ matcher (بيبلّشوا من فتح التطبيق).
      final dbSw = Stopwatch()..start();
      var matcherMs = -1, textMs = -1;
      QuranMatcherService.instance.matcher
          .then((_) => matcherMs = dbSw.elapsedMilliseconds);
      RecitationPipeline.instance.textSource
          .then((_) => textMs = dbSw.elapsedMilliseconds);

      final pipe = RecitationPipeline.instance;
      final mgr = await pipe.modelManager();

      // 1) مقطع الاختبار (لو مش ملف من المستخدم).
      if (!pickFile) {
        final clipSw = Stopwatch()..start();
        final had = await File('${mgr.dir.path}/test_fatiha_alafasy_16k.wav').exists();
        input = await mgr.ensureTestClip(
            onProgress: (r, t) =>
                _setStep('تحميل مقطع الاختبار', t == null ? null : r / t));
        _log('مقطع الاختبار: ${had ? 'موجود' : 'نزل وتحقق SHA256'} '
            '(${_sec(clipSw.elapsedMilliseconds)})');
      }

      // 2) خط الأنابيب كامل (خيطين).
      final r = await pipe.analyze(
        input,
        config: const AsrEngineConfig(numThreads: 2),
        session: await _session(2),
        onStage: (s, p) => _setStep(
            s == PipelineStage.preparingModel && p != null
                ? '${s.label} ${(p * 100).round()}%'
                : '${s.label}...',
            p),
      );
      final t = r.transcript;

      _log('— المقاطع (${r.segments.length}) —');
      for (final s in r.segments) {
        _log(s.describe());
        if (s.text.isNotEmpty) _log('   ${s.text}');
        if (s.tafsir.isNotEmpty) _log('   تفسير: ${s.tafsir}');
        debugPrint('[AsrDebug]    نص التعرف: ${s.asrText}');
      }
      final found = r.ayahRefs;
      _log('— النتيجة —');
      _log('الآيات: ${found.join('، ')}');
      final review = r.segments.where((s) => s.needsReview).length;
      if (review > 0) _log('بدها مراجعة: $review مقاطع');
      if (!pickFile) {
        final missing = _expected.where((e) => !found.contains(e)).toList();
        final wrong = found.where((f) => !_expected.contains(f)).toList();
        _passed = missing.isEmpty && wrong.isEmpty;
        _log(_passed!
            ? '✅ مطابق: الفاتحة 1:1–1:7 كاملة'
            : '❌ ناقص: ${missing.join('، ')}${wrong.isEmpty ? '' : ' | غلط: ${wrong.join('، ')}'}');
      } else {
        _passed = true;
      }

      // 3) أوقات كل خطوة.
      _log('— وقت كل خطوة —');
      _log('قاعدة البيانات + QuranMatcher: '
          '${matcherMs <= 5 ? 'كانوا جاهزين' : 'جهزوا بعد ${_sec(matcherMs)}'}'
          '، نص الآيات والتفسير: ${textMs <= 5 ? 'جاهز' : _sec(textMs)}');
      _log('النموذج: ${r.modelReport}');
      _log('فك الصوت: ${_sec(r.timings['decode'] ?? 0)} | '
          'انتظار القرآن: ${_sec(r.timings['quran_wait'] ?? 0)} | '
          'المطابقة + التقسيم: ${r.timings['match']}ms');
      _log('طول الصوت: ${t.audioSeconds.toStringAsFixed(1)} ثانية (${t.sourceSampleRate}Hz)');
      _log('خيطين: تحميل المحرك ${t.initMs == 0 ? '0ms (عايش من قبل)' : '${t.initMs}ms'} | '
          'VAD + تعرف ${t.recognizeMs}ms → RTF ${t.rtf.toStringAsFixed(3)}');

      // 4) نفس الملف بـ 4 خيوط (المقارنة).
      _setStep('مقارنة: التعرف بـ 4 خيوط...');
      final paths = await mgr.ensureReady();
      final t4 = await (await _session(4)).transcribeWavFile(paths, r.wavPath,
          config: const AsrEngineConfig(numThreads: 4));
      final same = t4.segments.length == t.segments.length &&
          [for (var i = 0; i < t.segments.length; i++) t4.segments[i].text == t.segments[i].text]
              .every((e) => e);
      _log('4 خيوط: تحميل المحرك ${t4.initMs == 0 ? '0ms (عايش من قبل)' : '${t4.initMs}ms'} | '
          'VAD + تعرف ${t4.recognizeMs}ms → RTF ${t4.rtf.toStringAsFixed(3)} '
          '(${t.recognizeMs == 0 ? '' : '${(t.recognizeMs / t4.recognizeMs).toStringAsFixed(2)}× '}'
          'مقارنة بخيطين، النص ${same ? 'نفسه ✅' : 'اختلف ⚠️'})');
      _log('الجوال: ${Platform.numberOfProcessors} أنوية، Android ${Platform.operatingSystemVersion}');
      _log('الوقت الكلي للتجربة: ${_sec(total.elapsedMilliseconds)}');
    } catch (e, st) {
      _passed = false;
      _log('❌ خطأ: $e');
      debugPrint('$st');
    } finally {
      if (mounted) {
        setState(() {
          _running = false;
          _step = '';
          _progress = null;
        });
      }
    }
  }

  Future<void> _deleteModel() async {
    final mgr = await RecitationPipeline.instance.modelManager();
    if (await mgr.dir.exists()) await mgr.dir.delete(recursive: true);
    _log('انمسحت ملفات النموذج. الضغطة الجاية بتنزّلها من جديد '
        '(المحرك اللي بالذاكرة بيضل لحد ما تسكّر التطبيق).');
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('أداة تطوير (يوم 5): خط الأنابيب كامل',
                style: TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _running ? null : () => _run(),
              icon: const Icon(Icons.graphic_eq),
              label: const Text('تجربة على مقطع الفاتحة'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _running ? null : () => _run(pickFile: true),
              icon: const Icon(Icons.folder_open),
              label: const Text('اختيار ملف صوت أو فيديو وتجربته'),
            ),
            if (_running) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(value: _progress),
              const SizedBox(height: 6),
              Text(_step, style: const TextStyle(fontSize: 13)),
            ],
            if (_lines.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _passed == null
                      ? Colors.grey.shade100
                      : (_passed! ? Colors.green.shade50 : Colors.red.shade50),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(_lines.join('\n'),
                    style: const TextStyle(fontSize: 13, height: 1.5)),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: _lines.join('\n')));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('انتسخت النتيجة')));
                        }
                      },
                      icon: const Icon(Icons.copy),
                      label: const Text('نسخ النتيجة'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _running ? null : _deleteModel,
                    child: const Text('مسح النموذج'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
