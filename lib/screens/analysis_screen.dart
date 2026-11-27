import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../asr/file_downloader.dart';
import '../pipeline/project_input.dart';
import '../pipeline/recitation_pipeline.dart';
import '../pipeline/recitation_segment.dart';
import '../platform/media_picker.dart';
import 'overlay_editor_screen.dart';

enum _AnalysisState { validating, analyzing, done, error }

/// شاشة تحليل بسيطة (يوم 6، **مش التصميم النهائي**): بتعرض المقطع المختار
/// ومعلوماته، وبعدها تقدّم التحليل بمراحل [PipelineStage]، وبالآخر قائمة
/// المقاطع (النص والتفسير). حالات الخطأ: ما في صوت، المقطع قصير، ما انلقط
/// قرآن، والنت مقطوع أول مرة (تحميل محرك التعرف).
class AnalysisScreen extends StatefulWidget {
  final ProjectInput input;
  const AnalysisScreen({super.key, required this.input});

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen> {
  late ProjectInput _input;
  _AnalysisState _state = _AnalysisState.validating;
  String _stageLabel = '';
  double? _progress;
  PipelineResult? _result;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _input = widget.input;
    _validateAndRun();
  }

  Future<void> _validateAndRun() async {
    setState(() {
      _state = _AnalysisState.validating;
      _errorMessage = null;
    });
    final info = _input.videoInfo;
    if (info.tooShort) {
      setState(() {
        _state = _AnalysisState.error;
        _errorMessage = 'المقطع قصير جداً '
            '(${info.durationSeconds.toStringAsFixed(1)} ثانية). لازم يكون فيه '
            'تلاوة واضحة.';
      });
      return;
    }
    if (!info.hasAudioTrack && !_input.useExternalAudio) {
      setState(() {
        _state = _AnalysisState.error;
        _errorMessage =
            'ما في صوت بهالفيديو. اختار ملف تلاوة منفصل عشان يتركّب عليه.';
      });
      return;
    }
    await _run();
  }

  Future<void> _run() async {
    setState(() {
      _state = _AnalysisState.analyzing;
      _stageLabel = '';
      _progress = null;
    });
    try {
      final result = await RecitationPipeline.instance.analyze(
        _input.recognitionSourcePath,
        onStage: (stage, progress) {
          if (!mounted) return;
          setState(() {
            _stageLabel = stage.label;
            _progress = progress;
          });
        },
      );
      if (!mounted) return;
      final anyAyah = result.segments.any((s) => s.isAyah);
      if (!anyAyah) {
        setState(() {
          _state = _AnalysisState.error;
          _errorMessage = 'ما انلقط قرآن بهالمقطع. جرّب مقطع فيه تلاوة أوضح، '
              'أو اختار ملف تلاوة منفصل.';
        });
        return;
      }
      setState(() {
        _result = result;
        _state = _AnalysisState.done;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _AnalysisState.error;
        _errorMessage = _describeError(e);
      });
    }
  }

  String _describeError(Object e) {
    if (e is DownloadException) {
      return 'ما قدرنا ننزّل محرك التعرف (~20MB، أول استخدام بس). تأكد من '
          'النت وجرّب كمان مرة.\n${e.message}';
    }
    if (e is SocketException || e is HttpException) {
      return 'النت مقطوع. محرك التعرف محتاج تنزيل مرة وحدة بس (~20MB)، '
          'وبعدها بيشتغل بدون نت أبداً.';
    }
    return 'حصل خطأ: $e';
  }

  Future<void> _pickExternalAudio() async {
    final picked = await MediaPicker.pick();
    if (picked == null) return;
    setState(() => _input = _input.withExternalAudio(picked.path));
    await _validateAndRun();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تحليل المقطع')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _VideoInfoCard(input: _input),
            const SizedBox(height: 16),
            if (_input.hasExternalAudio)
              SwitchListTile(
                title: const Text('التعرف على ملف التلاوة المنفصل'),
                subtitle: Text(_input.externalAudioPath!.split('/').last),
                value: _input.useExternalAudio,
                onChanged: (v) {
                  setState(() => _input = _input.withUseExternalAudio(v));
                  _validateAndRun();
                },
              ),
            OutlinedButton.icon(
              onPressed:
                  _state == _AnalysisState.analyzing ? null : _pickExternalAudio,
              icon: const Icon(Icons.audiotrack),
              label: Text(_input.hasExternalAudio
                  ? 'تغيير ملف التلاوة المنفصل'
                  : 'إضافة ملف تلاوة منفصل (اختياري)'),
            ),
            const SizedBox(height: 16),
            _buildBody(),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (_state) {
      case _AnalysisState.validating:
        return const Center(child: CircularProgressIndicator());
      case _AnalysisState.analyzing:
        return Column(
          children: [
            LinearProgressIndicator(value: _progress),
            const SizedBox(height: 8),
            Text(_progress == null
                ? '$_stageLabel...'
                : '$_stageLabel ${(_progress! * 100).round()}%'),
          ],
        );
      case _AnalysisState.error:
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_errorMessage ?? 'خطأ غير معروف'),
              const SizedBox(height: 8),
              OutlinedButton(
                  onPressed: _validateAndRun, child: const Text('إعادة المحاولة')),
            ],
          ),
        );
      case _AnalysisState.done:
        final r = _result!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('الآيات: ${r.ayahRefs.join('، ')}',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            // يوم 9: المحرر (معاينة + سحب العناصر + تخصيص + قوالب). من يوم 7: النص المتزامن (نمط التفسير وخط الآية
            // بتتبدّل جوا شاشة المعاينة).
            FilledButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => OverlayEditorScreen(
                  input: _input,
                  segments: r.segments,
                  wavPath: r.wavPath,
                ),
              )),
              icon: const Icon(Icons.play_circle_outline),
              label: const Text('معاينة النص فوق الفيديو'),
            ),
            const SizedBox(height: 8),
            // يوم 7: تقرير كامل (كل المقاطع حتى المخفية + ناتج التعرف الخام)
            // عشان أنس يبعته لما آية أو كلمة تنقص، ونعرف السبب بالضبط.
            OutlinedButton.icon(
              onPressed: () async {
                await Clipboard.setData(
                    ClipboardData(text: analysisReport(_input, r)));
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('انتسخ التقرير. الصقه بالمحادثة.')));
              },
              icon: const Icon(Icons.copy),
              label: const Text('نسخ تقرير التحليل'),
            ),
            const SizedBox(height: 12),
            // كل المقاطع (المخفية باهتة: استعاذة، أو مش قرآن مع نص التعرف).
            for (final s in r.segments) _SegmentTile(segment: s),
          ],
        );
    }
  }
}

class _VideoInfoCard extends StatelessWidget {
  final ProjectInput input;
  const _VideoInfoCard({required this.input});

  @override
  Widget build(BuildContext context) {
    final v = input.videoInfo;
    final orientationLabel = switch (v.orientation) {
      VideoOrientation.portrait => 'عمودي',
      VideoOrientation.landscape => 'أفقي',
      VideoOrientation.square => 'مربع',
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(input.source == VideoSource.camera
                    ? Icons.videocam
                    : Icons.photo_library),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(input.videoPath.split('/').last,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${v.rotatedWidth}×${v.rotatedHeight} ($orientationLabel) • '
              '${v.durationSeconds.toStringAsFixed(1)} ثانية'
              '${v.fps > 0 ? ' • ${v.fps.toStringAsFixed(0)}fps' : ''} • '
              '${v.hasAudioTrack ? 'فيه صوت' : 'بدون صوت'}',
              style: const TextStyle(color: Colors.black54, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

/// تقرير نصي للتحليل (للنسخ): معلومات الملف، الآيات، وقت كل مرحلة، كل
/// المقاطع (حتى المخفية) مع نص التعرف، وناتج التعرف الخام لكل مقطع VAD.
String analysisReport(ProjectInput input, PipelineResult r) {
  final v = input.videoInfo;
  final b = StringBuffer()
    ..writeln('آية ستوديو – تقرير التحليل')
    ..writeln('الملف: ${input.videoPath.split('/').last} • '
        '${v.rotatedWidth}×${v.rotatedHeight} • '
        '${v.durationSeconds.toStringAsFixed(1)}s'
        '${input.useExternalAudio && input.externalAudioPath != null ? ' • تلاوة منفصلة: ${input.externalAudioPath!.split('/').last}' : ''}')
    ..writeln('الآيات: ${r.ayahRefs.join('، ')}')
    ..writeln('الوقت (ms): ${r.timings.entries.map((e) => '${e.key} ${e.value}').join('، ')}')
    ..writeln()
    ..writeln('— المقاطع —');
  for (final s in r.segments) {
    b.writeln(s.describe());
    if (s.text.isNotEmpty) b.writeln('  النص: ${s.text}');
    if (s.asrText.isNotEmpty) b.writeln('  التعرف: ${s.asrText}');
  }
  b
    ..writeln()
    ..writeln('— ناتج التعرف الخام (${r.transcript.segments.length} مقطع) —');
  for (final a in r.transcript.segments) {
    b.writeln('[${a.start.toStringAsFixed(2)}–${a.end.toStringAsFixed(2)}s] ${a.text.trim()}');
  }
  return b.toString();
}

class _SegmentTile extends StatelessWidget {
  final RecitationSegment segment;
  const _SegmentTile({required this.segment});

  @override
  Widget build(BuildContext context) {
    if (!segment.isVisible) {
      return Card(
        color: Colors.grey.shade100,
        margin: const EdgeInsets.only(bottom: 8),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(segment.describe(),
                  style: const TextStyle(fontSize: 12, color: Colors.black45)),
              if (segment.asrText.isNotEmpty)
                Text('التعرف: ${segment.asrText}',
                    style: const TextStyle(fontSize: 12, color: Colors.black45),
                    textDirection: TextDirection.rtl),
            ],
          ),
        ),
      );
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(segment.describe(),
                style: const TextStyle(fontSize: 12, color: Colors.black54)),
            if (segment.text.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(segment.text,
                  style: const TextStyle(fontSize: 18), textDirection: TextDirection.rtl),
            ],
            if (segment.tafsir.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(segment.tafsir,
                  style: const TextStyle(fontSize: 13, color: Colors.black87)),
            ],
          ],
        ),
      ),
    );
  }
}
