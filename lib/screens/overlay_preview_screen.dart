import 'dart:io';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:video_player/video_player.dart';

import '../overlay/ayah_font.dart';
import '../overlay/overlay_frame.dart';
import '../overlay/overlay_timeline.dart';
import '../overlay/playback_clock.dart';
import '../pipeline/project_input.dart';
import '../pipeline/recitation_segment.dart';
import '../platform/video_info.dart';

/// معاينة الفيديو مع النص المتزامن (يوم 7). الفيديو (أو الفيديو + ملف تلاوة
/// منفصل) بيشتغل، والنص بيتبدّل حسب توقيت كل مقطع بنفس المقاسات اللي رح
/// يتصدّر فيها (يوم 8). فيها تبديل نمط التفسير وخط الآية ولون النص (أبيض أو
/// أسود، وبيتختار تلقائياً حسب سطوع الفيديو تحت النص). مش التصميم النهائي
/// (الهوية الخضراء/الذهبية بأيام الواجهات).
class OverlayPreviewScreen extends StatefulWidget {
  final ProjectInput input;
  final List<RecitationSegment> segments;
  final TafsirMode initialTafsirMode;

  const OverlayPreviewScreen({
    super.key,
    required this.input,
    required this.segments,
    this.initialTafsirMode = TafsirMode.split,
  });

  @override
  State<OverlayPreviewScreen> createState() => _OverlayPreviewScreenState();
}

class _OverlayPreviewScreenState extends State<OverlayPreviewScreen>
    with SingleTickerProviderStateMixin {
  VideoPlayerController? _video;

  /// ملف تلاوة منفصل (لو مفعّل): هو الساعة الرئيسية، وصوت الفيديو مكتوم.
  VideoPlayerController? _audio;
  VideoPlayerController? get _master => _audio ?? _video;

  final PlaybackClock _clock = PlaybackClock();
  final Stopwatch _wall = Stopwatch()..start();
  final ValueNotifier<double> _time = ValueNotifier<double>(0);
  late final Ticker _ticker;

  late OverlayTimeline _timeline;
  late TafsirMode _tafsirMode;
  AyahFont _font = AyahFont.defaultFont;
  OverlayTextColor _color = OverlayTextColor.defaultColor;

  /// اللون اختاره المستخدم بإيده → ما بنغيّره تلقائياً.
  bool _colorTouched = false;

  /// ملاحظة قصيرة لما اللون انختار تلقائياً.
  String? _colorNote;
  String? _error;
  bool _ready = false;

  double get _wallSeconds => _wall.elapsedMicroseconds / 1e6;

  @override
  void initState() {
    super.initState();
    _tafsirMode = widget.initialTafsirMode;
    final info = widget.input.videoInfo;
    _timeline = OverlayTimeline.build(widget.segments,
        videoDuration: info.durationMs > 0 ? info.durationSeconds : null);
    _ticker = createTicker((_) {
      _time.value = _clock.now(_wallSeconds);
    })..start();
    _init();
    _autoPickColor();
  }

  /// لون النص الأوضح حسب سطوع الفيديو بمنطقة النص (أسود فوق خلفية فاتحة).
  Future<void> _autoPickColor() async {
    final b = await VideoInfoReader.textBandBrightness(
        widget.input.videoInfo, widget.input.videoPath);
    if (b == null || !mounted || _colorTouched) return;
    final pick = OverlayTextColor.forBackground(b.luma, b.brightFraction);
    setState(() {
      _color = pick;
      _colorNote = pick == OverlayTextColor.black
          ? 'الخلفية فاتحة، فاخترنا نص أسود (بتقدر تغيّره).'
          : null;
    });
  }

  Future<void> _init() async {
    try {
      final input = widget.input;
      final video = VideoPlayerController.file(File(input.videoPath));
      _video = video;
      await video.initialize();
      if (input.useExternalAudio && input.externalAudioPath != null) {
        final audio = VideoPlayerController.file(File(input.externalAudioPath!));
        _audio = audio;
        await audio.initialize();
        await video.setVolume(0);
      }
      _master!.addListener(_onPlayerUpdate);
      if (!mounted) return;
      setState(() => _ready = true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'ما قدرنا نفتح الفيديو للمعاينة: $e');
    }
  }

  void _onPlayerUpdate() {
    final v = _master!.value;
    _clock.report(
      position: v.position.inMicroseconds / 1e6,
      wall: _wallSeconds,
      playing: v.isPlaying,
    );
    // انتهى: وقّف وانتظر "تشغيل" ليرجع من البداية.
    if (v.isCompleted && _video!.value.isPlaying) {
      _video!.pause();
    }
    if (mounted) setState(() {}); // أيقونة التشغيل/الشريط
  }

  Future<void> _togglePlay() async {
    final m = _master!;
    final all = [_video!, if (_audio != null) _audio!];
    if (m.value.isPlaying) {
      await Future.wait([for (final c in all) c.pause()]);
    } else {
      final dur = m.value.duration;
      if (m.value.position >= dur - const Duration(milliseconds: 100)) {
        await _seek(Duration.zero);
      }
      await Future.wait([for (final c in all) c.play()]);
    }
  }

  Future<void> _seek(Duration to) async {
    final all = [_video!, if (_audio != null) _audio!];
    await Future.wait([for (final c in all) c.seekTo(to)]);
    _clock.report(
      position: to.inMicroseconds / 1e6,
      wall: _wallSeconds,
      playing: _master!.value.isPlaying,
    );
    _time.value = to.inMicroseconds / 1e6;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _master?.removeListener(_onPlayerUpdate);
    _video?.dispose();
    _audio?.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('معاينة النص فوق الفيديو')),
      body: _error != null
          ? Padding(padding: const EdgeInsets.all(16), child: Text(_error!))
          : !_ready
              ? const Center(child: CircularProgressIndicator())
              : _buildPreview(),
    );
  }

  Widget _buildPreview() {
    final info = widget.input.videoInfo;
    final w = info.rotatedWidth, h = info.rotatedHeight;
    final master = _master!;
    final dur = master.value.duration;
    final pos = master.value.position;
    return Column(
      children: [
        Expanded(
          child: Container(
            color: Colors.black,
            alignment: Alignment.center,
            // مساحة الفيديو الحقيقية بالبكسل (نفس تصدير يوم 8) مصغّرة
            // بالـ FittedBox: النص بيطلع بنفس النسب على كل الأبعاد.
            child: FittedBox(
              fit: BoxFit.contain,
              child: SizedBox(
                width: w.toDouble(),
                height: h.toDouble(),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    VideoPlayer(_video!),
                    ValueListenableBuilder<double>(
                      valueListenable: _time,
                      builder: (_, t, __) => AyahOverlayFrame(
                        videoWidth: w,
                        videoHeight: h,
                        cue: _timeline.cueAt(t),
                        tafsirMode: _tafsirMode,
                        font: _font,
                        color: _color,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        _Controls(
          playing: master.value.isPlaying,
          position: pos,
          duration: dur,
          onToggle: _togglePlay,
          onSeek: (d) => _seek(d),
          tafsirMode: _tafsirMode,
          onTafsirMode: (m) => setState(() => _tafsirMode = m),
          font: _font,
          onFont: (f) => setState(() => _font = f),
          color: _color,
          colorNote: _colorNote,
          onColor: (c) => setState(() {
            _color = c;
            _colorTouched = true;
            _colorNote = null;
          }),
          usingExternalAudio: _audio != null,
          timeListenable: _time,
          timeline: _timeline,
        ),
      ],
    );
  }
}

class _Controls extends StatelessWidget {
  final bool playing;
  final Duration position;
  final Duration duration;
  final VoidCallback onToggle;
  final ValueChanged<Duration> onSeek;
  final TafsirMode tafsirMode;
  final ValueChanged<TafsirMode> onTafsirMode;
  final AyahFont font;
  final ValueChanged<AyahFont> onFont;
  final OverlayTextColor color;
  final String? colorNote;
  final ValueChanged<OverlayTextColor> onColor;
  final bool usingExternalAudio;
  final ValueListenable<double> timeListenable;
  final OverlayTimeline timeline;

  const _Controls({
    required this.playing,
    required this.position,
    required this.duration,
    required this.onToggle,
    required this.onSeek,
    required this.tafsirMode,
    required this.onTafsirMode,
    required this.font,
    required this.onFont,
    required this.color,
    required this.colorNote,
    required this.onColor,
    required this.usingExternalAudio,
    required this.timeListenable,
    required this.timeline,
  });

  String _fmt(Duration d) {
    final s = d.inSeconds;
    final m = s ~/ 60;
    return '$m:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final maxMs = duration.inMilliseconds.toDouble();
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton.filled(
                  onPressed: onToggle,
                  icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                ),
                Expanded(
                  child: Slider(
                    value: position.inMilliseconds
                        .toDouble()
                        .clamp(0, maxMs > 0 ? maxMs : 1),
                    max: maxMs > 0 ? maxMs : 1,
                    onChanged: (v) => onSeek(Duration(milliseconds: v.round())),
                  ),
                ),
                Text('${_fmt(position)} / ${_fmt(duration)}',
                    style: const TextStyle(fontSize: 12)),
              ],
            ),
            ValueListenableBuilder<double>(
              valueListenable: timeListenable,
              builder: (_, t, __) {
                final c = timeline.cueAt(t);
                final label = c == null
                    ? 'ما في نص ظاهر هلأ'
                    : c.item.segment.describe();
                return Text(label,
                    style: const TextStyle(fontSize: 11, color: Colors.black54),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis);
              },
            ),
            if (usingExternalAudio)
              const Text('الصوت من ملف التلاوة المنفصل (صوت الفيديو مكتوم).',
                  style: TextStyle(fontSize: 11, color: Colors.black54)),
            const SizedBox(height: 6),
            SegmentedButton<TafsirMode>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                    value: TafsirMode.split, label: Text('التفسير مقسوم')),
                ButtonSegment(
                    value: TafsirMode.fullUnderEachPart,
                    label: Text('كامل تحت كل جزء')),
              ],
              selected: {tafsirMode},
              onSelectionChanged: (s) => onTafsirMode(s.first),
            ),
            const SizedBox(height: 6),
            SegmentedButton<AyahFont>(
              showSelectedIcon: false,
              segments: [
                for (final f in AyahFont.values)
                  ButtonSegment(value: f, label: Text(f.label)),
              ],
              selected: {font},
              onSelectionChanged: (s) => onFont(s.first),
            ),
            const SizedBox(height: 6),
            // لون النص: أبيض أو أسود بس (طلب أنس).
            SegmentedButton<OverlayTextColor>(
              showSelectedIcon: false,
              segments: [
                for (final c in OverlayTextColor.values)
                  ButtonSegment(
                    value: c,
                    icon: Icon(Icons.circle,
                        color: c.text,
                        shadows: const [
                          Shadow(color: Colors.grey, blurRadius: 2),
                        ]),
                    label: Text('نص ${c.label}'),
                  ),
              ],
              selected: {color},
              onSelectionChanged: (s) => onColor(s.first),
            ),
            if (colorNote != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(colorNote!,
                    style: const TextStyle(fontSize: 11, color: Colors.black54)),
              ),
          ],
        ),
      ),
    );
  }
}
