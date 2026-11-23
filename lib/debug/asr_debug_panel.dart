import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../asr/asr_engine.dart';
import '../asr/asr_model_manager.dart';
import '../asr/native_audio_decoder.dart';
import '../asr/recitation_matcher.dart';
import '../matching/quran_matcher_service.dart';

/// زر debug (يوم 4): "تجربة التعرف على الصوت" على الجوال نفسه.
/// بينزّل النموذج (مرة وحدة) ومقطع الفاتحة، بيشغّل VAD + التعرف بـ isolate،
/// بعدين QuranSequenceMatcher، وبيطبع لكل مقطع: الوقت، السورة:الآية، الثقة،
/// وبيقيس الوقت والـ RTF. المتوقع: الفاتحة 1:1–1:7.
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

  Future<AsrModelManager> _manager() async {
    final support = await getApplicationSupportDirectory();
    return AsrModelManager(Directory('${support.path}/asr'));
  }

  Future<void> _run() async {
    setState(() {
      _running = true;
      _lines.clear();
      _passed = null;
    });
    final total = Stopwatch()..start();
    try {
      final mgr = await _manager();
      final wasReady = await mgr.isReady();
      final dl = Stopwatch()..start();
      final paths = await mgr.ensureReady(
          onProgress: (p) => _setStep('تحميل النموذج: $p', p.fraction));
      _log(wasReady
          ? 'النموذج موجود ومتحقق منه (offline)'
          : 'نزل النموذج وتحقق SHA256 ✅ (${(AsrModelManager.totalBytes / 1e6).toStringAsFixed(1)}MB '
              'بـ ${(dl.elapsedMilliseconds / 1000).toStringAsFixed(1)} ثانية)');

      final clip = await mgr.ensureTestClip(
          onProgress: (r, t) => _setStep('تحميل مقطع الاختبار', t == null ? null : r / t));

      _setStep('التعرف على الصوت (VAD + sherpa-onnx)...');
      final tmp = await getTemporaryDirectory();
      final wav = await NativeAudioDecoder.ensureWav(clip, tmp);
      final t = await AsrEngine.transcribeWavFile(paths, wav);

      _setStep('المطابقة مع القرآن...');
      final matcher = await QuranMatcherService.instance.matcher;
      final ms = Stopwatch()..start();
      final matches = matchTranscript(matcher, t);
      final matchMs = ms.elapsedMilliseconds;

      _log('— المقاطع (${t.segments.length}) —');
      for (var i = 0; i < matches.length; i++) {
        _log(describeMatches([matches[i]]).first);
        debugPrint('[AsrDebug]    نص: ${matches[i].segment.text}');
      }
      final found = foundAyahs(matches);
      final missing = _expected.where((e) => !found.contains(e)).toList();
      final wrong = found.where((f) => !_expected.contains(f)).toList();
      _passed = missing.isEmpty && wrong.isEmpty;

      _log('— النتيجة —');
      _log('الآيات: ${found.join('، ')}');
      _log(_passed!
          ? '✅ مطابق: الفاتحة 1:1–1:7 كاملة'
          : '❌ ناقص: ${missing.join('، ')}${wrong.isEmpty ? '' : ' | غلط: ${wrong.join('، ')}'}');
      _log('— السرعة —');
      _log('طول الصوت: ${t.audioSeconds.toStringAsFixed(1)} ثانية '
          '(${t.sourceSampleRate}Hz)');
      _log('قراءة الصوت: ${t.loadAudioMs}ms | تحميل النموذج: ${t.initMs}ms');
      _log('VAD + تعرف: ${t.recognizeMs}ms → RTF = ${t.rtf.toStringAsFixed(3)} '
          '(${t.numThreads} threads، الجوال فيه ${Platform.numberOfProcessors} أنوية)');
      _log('المطابقة: ${matchMs}ms | RTF الكلي: ${t.rtfTotal.toStringAsFixed(3)}');

      // فحص الفك الأصلي (MediaCodec) على نفس الملف.
      try {
        final d = await NativeAudioDecoder.decodeToMonoWav(clip, '${tmp.path}/native_check.wav');
        final ok = (d.seconds - t.audioSeconds).abs() < 0.2;
        _log('فك MediaCodec: ${d.mime}، ${d.sampleRate}Hz، '
            '${d.seconds.toStringAsFixed(2)} ثانية بـ ${d.elapsedMs}ms ${ok ? '✅' : '❌'}');
      } catch (e) {
        _log('فك MediaCodec: ❌ $e');
      }
      _log('الجوال: Android ${Platform.operatingSystemVersion}');
      _log('الوقت الكلي للتجربة: ${(total.elapsedMilliseconds / 1000).toStringAsFixed(1)} ثانية');
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
    final mgr = await _manager();
    if (await mgr.dir.exists()) await mgr.dir.delete(recursive: true);
    _log('انمسحت ملفات النموذج. الضغطة الجاية بتنزّلها من جديد.');
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('أداة تطوير (يوم 4)',
                style: TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _running ? null : _run,
              icon: const Icon(Icons.graphic_eq),
              label: const Text('تجربة التعرف على الصوت'),
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
