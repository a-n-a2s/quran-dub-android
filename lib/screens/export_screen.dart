import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../export/export_plan.dart';
import '../export/export_request.dart';
import '../export/export_settings.dart';
import '../export/export_status.dart';
import '../export/overlay_renderer.dart';
import '../overlay/overlay_metrics.dart';
import '../platform/video_exporter.dart';

/// شاشة التصدير (يوم 8، بسيطة، مش التصميم النهائي): ملخص → تجهيز النص (صور
/// بـ AyahOverlayFrame) → تصدير بالخلفية (إشعار) → نجاح (مشاركة/فتح/حفظ) أو
/// خطأ بالعربي. بتنفتح من شاشة المعاينة بنفس اختيارات المستخدم هناك.
class ExportScreen extends StatefulWidget {
  final ExportRequest request;

  /// للتجربة (integration test): بيبلّش لحاله.
  final bool autoStart;

  /// بينادى لما التصدير يخلص (نجاح/خطأ/إلغاء) — للتجربة.
  final void Function(ExportStatus status, ExportPlan? plan, String? workDir)?
      onFinished;

  const ExportScreen({
    super.key,
    required this.request,
    this.autoStart = false,
    this.onFinished,
  });

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  final OverlayRenderController _renderer = OverlayRenderController();
  ExportStatus _status = ExportStatus.idle;
  ExportPlan? _plan;

  /// التصدير اللي الشاشة بتتابعه (الحالي، أو واحد شغّال من قبل ما تنفتح:
  /// المستخدم طلع من الشاشة ورجع).
  String? _activeId;
  String? _workDir;
  StreamSubscription<ExportStatus>? _sub;
  bool _cancelRequested = false;
  bool _otherExportRunning = false;
  bool _notificationsOff = false;
  bool _finishedReported = false;
  final Stopwatch _prepareWatch = Stopwatch();
  int? _prepareMs;

  @override
  void initState() {
    super.initState();
    _sub = VideoExporter.statusStream.listen(_onStatus, onError: (_) {});
    VideoExporter.status().then((s) {
      if (!mounted || _activeId != null) return;
      // تصدير لسا شغّال بالخلفية (طلعنا من الشاشة ورجعنا): بنكمّل نتابعه.
      if (s.phase.isRunning && s.id != null) {
        setState(() {
          _activeId = s.id;
          _status = s;
        });
      }
    }).catchError((_) {});
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _start());
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _onStatus(ExportStatus s) {
    if (!mounted) return;
    final id = _activeId;
    if (id == null) {
      // تصدير ثاني (من قبل) لسا شغّال؟
      if (s.phase.isRunning != _otherExportRunning) {
        setState(() => _otherExportRunning = s.phase.isRunning);
      }
      return;
    }
    if (s.id != id) return;
    if (s.phase == ExportPhase.idle) return;
    setState(() => _status = s);
    if (s.phase.isFinished) _reportFinished(s);
  }

  void _reportFinished(ExportStatus s) {
    if (_finishedReported) return;
    _finishedReported = true;
    widget.onFinished?.call(s, _plan, _workDir);
  }

  void _fail(ExportErrorKind kind, String detail) {
    final s = ExportStatus(
        id: _activeId,
        phase: ExportPhase.failed,
        error: kind,
        errorDetail: detail);
    setState(() => _status = s);
    _reportFinished(s);
  }

  Future<void> _start() async {
    if (_status.phase.isRunning) return;
    setState(() {
      _status = const ExportStatus(phase: ExportPhase.preparing);
      _cancelRequested = false;
      _finishedReported = false;
      _plan = null;
      _activeId = null;
      _prepareMs = null;
    });
    _prepareWatch
      ..reset()
      ..start();
    try {
      // صلاحيات وقت الحاجة بس: الإشعارات (13+)، والتخزين (7–9 بس).
      final notif = await VideoExporter.requestNotificationPermission();
      await VideoExporter.requestStoragePermission();
      if (mounted) setState(() => _notificationsOff = !notif);

      final tmp = await getTemporaryDirectory();
      final now = DateTime.now();
      final id = 'exp${now.millisecondsSinceEpoch}';
      final workDir = '${tmp.path}/export/$id';
      await Directory('$workDir/overlays').create(recursive: true);
      _workDir = workDir;
      final req = widget.request;
      final plan = planForRequest(req, id: id, workDir: workDir, now: now);

      final free = await VideoExporter.freeBytes(workDir);
      final needed = plan.estimatedBytes * 2 + 50 * 1024 * 1024;
      if (free >= 0 && free < needed) {
        _fail(ExportErrorKind.noSpace,
            'متاح ${formatBytes(free)}، محتاجين ~${formatBytes(needed)}');
        return;
      }

      // صور النص: نفس AyahOverlayFrame ونفس الخط الزمني تبع المعاينة.
      final tl = req.timeline;
      final metrics = OverlayMetrics.forSize(plan.size.width, plan.size.height);
      assert(overlayBandFor(metrics).top == plan.band.top);
      for (var i = 0; i < tl.items.length; i++) {
        if (_cancelRequested || !mounted) {
          await _cleanup(workDir);
          if (mounted) {
            setState(() => _status = const ExportStatus(phase: ExportPhase.cancelled));
          }
          return;
        }
        final png = await _renderer.renderPng(OverlayRenderJob(
          width: plan.size.width,
          height: plan.size.height,
          band: plan.band,
          item: tl.items[i],
          style: req.style,
        ));
        await File(plan.cues[i].png).writeAsBytes(png, flush: false);
        if (mounted) {
          setState(() => _status = ExportStatus(
              phase: ExportPhase.preparing,
              fraction: (i + 1) / tl.items.length));
        }
      }
      _prepareMs = _prepareWatch.elapsedMilliseconds;

      final json = plan.toJson()
        ..['keepWorkFiles'] = req.keepWorkFiles
        ..['style'] = req.style.toJson();
      final planPath = '$workDir/plan.json';
      await File(planPath).writeAsString(jsonEncode(json));
      if (_cancelRequested || !mounted) {
        await _cleanup(workDir);
        if (mounted) {
          setState(() => _status = const ExportStatus(phase: ExportPhase.cancelled));
        }
        return;
      }
      _plan = plan;
      _activeId = plan.id;
      setState(() => _status = ExportStatus(id: plan.id, phase: ExportPhase.encoding));
      await VideoExporter.start(planPath);
    } on PlatformException catch (e) {
      _fail(ExportErrorKind.unknown, '${e.code}: ${e.message}');
    } catch (e) {
      _fail(ExportErrorKind.overlay, e.toString());
    }
  }

  Future<void> _cleanup(String workDir) async {
    try {
      await Directory(workDir).delete(recursive: true);
    } catch (_) {}
  }

  Future<void> _cancel() async {
    if (_status.phase == ExportPhase.preparing) {
      setState(() => _cancelRequested = true);
    } else {
      await VideoExporter.cancel();
    }
  }

  Future<void> _call(Future<void> Function() f, String failMsg) async {
    try {
      await f();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$failMsg ($e)')));
    }
  }

  String _report() {
    final s = _status;
    final p = _plan;
    final req = widget.request;
    final b = StringBuffer()
      ..writeln('تقرير التصدير (آية ستوديو)')
      ..writeln('الحالة: ${s.phase.name}${s.error != null ? ' (${s.error!.name})' : ''}')
      ..writeln('الأصل: ${req.input.videoInfo}')
      ..writeln('الشكل: ${req.style}');
    if (p != null) {
      b
        ..writeln('الناتج المطلوب: ${p.size}، ${(p.videoBitrate / 1e6).toStringAsFixed(1)}Mbps، '
            '${p.fps.toStringAsFixed(2)}fps، صوت ${p.audio.kind}')
        ..writeln('شريط النص: ${p.band}، صور النص: ${p.cues.length}')
        ..writeln('الملف: ${p.fileName}');
    }
    if (_prepareMs != null) b.writeln('تجهيز النص: ${_prepareMs}ms');
    if (s.phase == ExportPhase.done) {
      b
        ..writeln('الناتج الفعلي: ${s.width}×${s.height}، '
            '${s.fileSizeBytes != null ? formatBytes(s.fileSizeBytes!) : '?'}، '
            '${((s.averageVideoBitrate ?? 0) / 1e6).toStringAsFixed(1)}Mbps')
        ..writeln('المدة: ${((s.durationMs ?? 0) / 1000).toStringAsFixed(2)}s، '
            'وقت التصدير: ${((s.elapsedMs ?? 0) / 1000).toStringAsFixed(1)}s')
        ..writeln('المرمّز: ${s.videoEncoder}')
        ..writeln(s.savedToGallery ? 'بالمعرض: ${s.galleryPath}' : 'مش محفوظ بالمعرض');
    }
    if (s.errorDetail != null) b.writeln('تفاصيل: ${s.errorDetail}');
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تصدير الفيديو')),
      body: Stack(
        children: [
          Positioned.fill(child: _body()),
          // مكان رسم صور النص (مخفي، حجمه صفر).
          Positioned(left: 0, top: 0, child: OverlayRenderHost(controller: _renderer)),
        ],
      ),
    );
  }

  Widget _body() {
    final s = _status;
    final req = widget.request;
    final size = req.size;
    final info = req.input.videoInfo;
    final audio = ExportAudio.forInput(req.input);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('الفيديو: ${size.width}×${size.height}'
            '${size.width != info.rotatedWidth || size.height != info.rotatedHeight ? ' (الأصل ${info.rotatedWidth}×${info.rotatedHeight})' : ''}'
            '، ${info.durationSeconds.toStringAsFixed(1)} ثانية'),
        Text('الشكل: ${req.style}'),
        Text(switch (audio) {
          ExternalAudio() => 'الصوت: ملف التلاوة المنفصل (صوت الفيديو مكتوم).',
          NoAudio() => 'الفيديو بدون صوت.',
          OriginalAudio() => 'الصوت: صوت الفيديو الأصلي.',
        }),
        const SizedBox(height: 16),
        if (_otherExportRunning && !s.phase.isRunning)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text('في تصدير ثاني شغّال هلأ. استنى لحد ما يخلص.'),
          ),
        if (s.phase == ExportPhase.idle ||
            s.phase == ExportPhase.failed ||
            s.phase == ExportPhase.cancelled) ...[
          if (s.phase != ExportPhase.idle)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(s.label,
                  style: TextStyle(
                      color: s.phase == ExportPhase.failed
                          ? Theme.of(context).colorScheme.error
                          : null)),
            ),
          FilledButton.icon(
            onPressed: _otherExportRunning ? null : _start,
            icon: const Icon(Icons.movie_creation_outlined),
            label: Text(s.phase == ExportPhase.idle ? 'ابدأ التصدير' : 'جرّب كمان مرة'),
          ),
        ],
        if (s.phase.isRunning) ...[
          Text(s.label),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: s.progress),
          const SizedBox(height: 4),
          Text('${(s.progress * 100).toStringAsFixed(0)}٪'),
          const SizedBox(height: 8),
          Text(
            s.phase == ExportPhase.preparing
                ? 'خليك بالتطبيق لحد ما يجهز النص (ثواني)، وبعدها بتقدر تطلع والتصدير بيكمّل بالخلفية.'
                : 'بتقدر تطلع من التطبيق: التصدير بيكمّل بالخلفية'
                    '${_notificationsOff ? ' (الإشعارات مطفية، فارجع للتطبيق تشوف النتيجة).' : ' ورح يوصلك إشعار لما يخلص.'}',
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _cancelRequested ? null : _cancel,
            icon: const Icon(Icons.close),
            label: const Text('إلغاء'),
          ),
        ],
        if (s.phase == ExportPhase.done) ...[
          Text(s.label, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
              '${s.width}×${s.height}، ${s.fileSizeBytes != null ? formatBytes(s.fileSizeBytes!) : ''}'
              '، خلص بـ ${((s.elapsedMs ?? 0) / 1000).toStringAsFixed(0)} ثانية'),
          Text(s.savedToGallery
              ? 'محفوظ بالمعرض: ${s.galleryPath}'
              : 'لسا مش محفوظ بالمعرض.'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: () => _call(VideoExporter.share, 'ما انفتحت المشاركة'),
                icon: const Icon(Icons.share),
                label: const Text('مشاركة'),
              ),
              OutlinedButton.icon(
                onPressed: () => _call(VideoExporter.open, 'ما في تطبيق يفتح الفيديو'),
                icon: const Icon(Icons.play_circle_outline),
                label: const Text('فتح'),
              ),
              if (!s.savedToGallery)
                OutlinedButton.icon(
                  onPressed: () => _call(() async {
                    await VideoExporter.requestStoragePermission();
                    await VideoExporter.saveToGallery();
                  }, 'ما انحفظ'),
                  icon: const Icon(Icons.save_alt),
                  label: const Text('حفظ بالمعرض'),
                ),
            ],
          ),
        ],
        if (s.phase != ExportPhase.idle && !s.phase.isRunning) ...[
          const SizedBox(height: 20),
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _report()));
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('انتسخ تقرير التصدير')));
            },
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('نسخ تقرير التصدير'),
          ),
        ],
      ],
    );
  }
}
