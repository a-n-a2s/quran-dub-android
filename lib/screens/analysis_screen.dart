import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../asr/file_downloader.dart';
import '../data/quran_database.dart';
import '../editor/waveform.dart';
import '../pipeline/project_input.dart';
import '../pipeline/recitation_pipeline.dart';
import '../pipeline/recitation_segment.dart';
import '../platform/media_picker.dart';
import '../projects/recent_projects.dart';
import '../ui/app_settings.dart';
import '../ui/app_theme.dart';
import '../ui/ayah_widgets.dart';
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
      _rememberProject(result);
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

  /// المشروع بيتسجّل بـ "مشاريع القرآن الأخيرة" مع نتيجة التحليل (عشان يرجع
  /// يفتح المحرر بدون تحليل جديد) وموجة مصغّرة للبطاقة.
  Future<void> _rememberProject(PipelineResult r) async {
    try {
      Map<int, String> names = const {};
      try {
        final all = await QuranDatabase.instance.allSurahs();
        names = {for (final s in all) s.number: s.nameArabic};
      } catch (_) {}
      final d = describeProject(r.segments, (n) => names[n]);
      List<double> wave = const [];
      try {
        final peaks = await extractPeaksFromWavFile(r.wavPath);
        wave = downsampleWave(peaks.peaks);
      } catch (_) {}
      final v = _input.videoInfo;
      final store = await AppSettings.projects();
      await store.upsert(
        RecentProject(
          id: recentProjectId(_input.videoPath),
          videoPath: _input.videoPath,
          externalAudioPath: _input.externalAudioPath,
          useExternalAudio: _input.useExternalAudio,
          title: d.title,
          subtitle: d.subtitle,
          ayahCount: d.ayahs,
          durationSeconds: v.durationSeconds,
          width: v.width,
          height: v.height,
          rotation: v.rotationDegrees,
          fps: v.fps,
          hasAudioTrack: v.hasAudioTrack,
          updatedAt: DateTime.now(),
          wave: wave,
        ),
        analysis: r.segments,
      );
      AppSettings.projectsChanged();
    } catch (_) {
      // القائمة مش ضرورية للتحليل نفسه.
    }
  }

  void _openEditor() {
    final r = _result;
    if (r == null) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => OverlayEditorScreen(
        input: _input,
        segments: r.segments,
        wavPath: r.wavPath,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final p = AyahPalette.of(context);
    final busy = _state == _AnalysisState.analyzing || _state == _AnalysisState.validating;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(title: const Text('تحليل المقطع')),
      body: AyahBackground(
        child: SafeArea(
          child: ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
            children: [
              _VideoInfoCard(input: _input),
              const SizedBox(height: 12),
              GlassCard(
                padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
                child: Row(
                  children: [
                    Icon(Icons.graphic_eq_rounded, color: p.accentText),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_input.hasExternalAudio ? 'ملف تلاوة منفصل' : 'صوت التلاوة',
                              style: Theme.of(context).textTheme.titleSmall),
                          Text(
                            _input.hasExternalAudio
                                ? _input.externalAudioPath!.split('/').last
                                : 'من صوت الفيديو نفسه (أو أضف ملف منفصل)',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    if (_input.hasExternalAudio)
                      Switch(
                        value: _input.useExternalAudio,
                        onChanged: busy
                            ? null
                            : (v) {
                                setState(() => _input = _input.withUseExternalAudio(v));
                                _validateAndRun();
                              },
                      ),
                    IconButton(
                      tooltip: _input.hasExternalAudio ? 'تغيير الملف' : 'إضافة ملف تلاوة',
                      onPressed: busy ? null : _pickExternalAudio,
                      icon: Icon(_input.hasExternalAudio ? Icons.swap_horiz_rounded : Icons.add_rounded),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: KeyedSubtree(key: ValueKey(_state), child: _buildBody()),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    final p = AyahPalette.of(context);
    final tt = Theme.of(context).textTheme;
    switch (_state) {
      case _AnalysisState.validating:
      case _AnalysisState.analyzing:
        final pct = _progress == null ? null : (_progress! * 100).round();
        return GlassCard(
          padding: const EdgeInsets.fromLTRB(22, 34, 22, 26),
          child: Column(
            children: [
              const GoldLoader(size: 96),
              const SizedBox(height: 22),
              Text(_stageLabel.isEmpty ? 'عم نجهّز…' : _stageLabel,
                  textAlign: TextAlign.center, style: tt.titleMedium),
              const SizedBox(height: 6),
              Text(pct == null ? 'لحظات…' : '$pct٪',
                  style: TextStyle(
                      fontFamily: kUiFont, fontSize: 28, fontWeight: FontWeight.w700, color: p.accentText)),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(value: _progress, minHeight: 8),
              ),
              const SizedBox(height: 16),
              Text('التعرف بيصير على جوالك نفسه، بدون ما يطلع الصوت لأي سيرفر.',
                  textAlign: TextAlign.center, style: tt.bodySmall),
            ],
          ),
        );
      case _AnalysisState.error:
        return GlassCard(
          borderColor: AyahColors.danger.withValues(alpha: 0.7),
          padding: const EdgeInsets.all(22),
          child: Column(
            children: [
              const Icon(Icons.error_outline_rounded, size: 54, color: AyahColors.danger),
              const SizedBox(height: 12),
              Text(_errorMessage ?? 'خطأ غير معروف',
                  textAlign: TextAlign.center, style: tt.bodyLarge),
              const SizedBox(height: 18),
              GoldButton(label: 'جرّب كمان مرة', icon: Icons.refresh_rounded, onPressed: _validateAndRun),
            ],
          ),
        );
      case _AnalysisState.done:
        final r = _result!;
        final refs = r.ayahRefs;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GlassCard(
              highlight: true,
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
              child: Column(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: const BoxDecoration(
                        shape: BoxShape.circle, gradient: AyahColors.goldVertical),
                    child: const Icon(Icons.check_rounded, size: 38, color: AyahColors.ink),
                  ),
                  const SizedBox(height: 14),
                  Text('لقينا ${toArabicDigits('${refs.length}')} آية',
                      style: tt.headlineSmall),
                  const SizedBox(height: 4),
                  Text('بتقدر تعدّل أي شي بالمحرر: التوقيت، الآية، الشكل.',
                      textAlign: TextAlign.center, style: tt.bodySmall),
                  const SizedBox(height: 16),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final ref in refs.take(24)) AyahTag(toArabicDigits(ref)),
                      if (refs.length > 24) AyahTag('+${toArabicDigits('${refs.length - 24}')}', gold: false),
                    ],
                  ),
                  const SizedBox(height: 22),
                  GoldButton(
                    label: 'افتح المحرر',
                    icon: Icons.movie_creation_rounded,
                    onPressed: _openEditor,
                  ),
                  const SizedBox(height: 10),
                  // يوم 7: تقرير كامل (كل المقاطع حتى المخفية + ناتج التعرف الخام).
                  TextButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: analysisReport(_input, r)));
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('انتسخ التقرير. الصقه بالمحادثة.')));
                    },
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: const Text('نسخ تقرير التحليل'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: GlassCard(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: ExpansionTile(
                  iconColor: p.accentText,
                  collapsedIconColor: p.textMuted,
                  title: Text('تفاصيل المقاطع (${toArabicDigits('${r.segments.length}')})',
                      style: tt.titleSmall),
                  childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
                  children: [for (final s in r.segments) _SegmentTile(segment: s)],
                ),
              ),
            ),
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
    final p = AyahPalette.of(context);
    final v = input.videoInfo;
    final orientationLabel = switch (v.orientation) {
      VideoOrientation.portrait => 'عمودي',
      VideoOrientation.landscape => 'أفقي',
      VideoOrientation.square => 'مربع',
    };
    Widget chip(IconData i, String t) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: AyahColors.gold.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(i, size: 14, color: p.accentText),
            const SizedBox(width: 5),
            Text(t, style: TextStyle(fontFamily: kUiFont, fontSize: 12, color: p.text)),
          ]),
        );
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: const BoxDecoration(
                    shape: BoxShape.circle, gradient: AyahColors.goldVertical),
                child: Icon(
                    input.source == VideoSource.camera
                        ? Icons.videocam_rounded
                        : Icons.movie_rounded,
                    color: AyahColors.ink),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(input.videoPath.split('/').last,
                    style: Theme.of(context).textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              chip(Icons.aspect_ratio_rounded, '${v.rotatedWidth}×${v.rotatedHeight} • $orientationLabel'),
              chip(Icons.timer_outlined, '${v.durationSeconds.toStringAsFixed(1)} ث'),
              if (v.fps > 0) chip(Icons.speed_rounded, '${v.fps.toStringAsFixed(0)}fps'),
              chip(v.hasAudioTrack ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                  v.hasAudioTrack ? 'فيه صوت' : 'بدون صوت'),
            ],
          ),
        ],
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
    final p = AyahPalette.of(context);
    final hidden = !segment.isVisible;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: p.dark ? const Color(0x12FFFFFF) : const Color(0x0D000000),
        border: Border.all(
            color: segment.needsReview
                ? AyahColors.review.withValues(alpha: 0.7)
                : p.cardBorder.withValues(alpha: 0.25)),
      ),
      child: Opacity(
        opacity: hidden ? 0.5 : 1,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(segment.describe(), style: Theme.of(context).textTheme.bodySmall),
            if (!hidden && segment.text.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(segment.text,
                  style: TextStyle(fontFamily: 'Amiri Quran', fontSize: 19, height: 1.9, color: p.text),
                  textDirection: TextDirection.rtl),
            ],
            if (!hidden && segment.tafsir.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(segment.tafsir,
                  style: TextStyle(fontFamily: 'Amiri', fontSize: 14, color: p.textMuted)),
            ],
            if (hidden && segment.asrText.isNotEmpty)
              Text('التعرف: ${segment.asrText}',
                  style: Theme.of(context).textTheme.bodySmall, textDirection: TextDirection.rtl),
          ],
        ),
      ),
    );
  }
}
