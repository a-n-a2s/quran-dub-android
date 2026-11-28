import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../asr/native_audio_decoder.dart';
import '../data/quran_database.dart';
import '../editor/project_edit_store.dart';
import '../editor/segment_edits.dart';
import '../editor/timeline_geometry.dart';
import '../editor/waveform.dart';
import '../export/export_request.dart';
import '../overlay/ayah_font.dart';
import '../overlay/overlay_frame.dart';
import '../overlay/overlay_layout.dart';
import '../overlay/overlay_style.dart';
import '../overlay/overlay_templates.dart';
import '../overlay/overlay_timeline.dart';
import '../overlay/playback_clock.dart';
import '../overlay/snap_guides.dart';
import '../pipeline/project_input.dart';
import '../pipeline/quran_text_source.dart';
import '../pipeline/recitation_pipeline.dart';
import '../pipeline/recitation_segment.dart';
import '../pipeline/segment_builder.dart' show ayahWords;
import '../pipeline/segment_factory.dart';
import '../platform/video_info.dart';
import 'export_screen.dart';
import 'widgets/ayah_picker_dialog.dart';
import 'widgets/segment_detail_panel.dart';
import 'widgets/editor_timeline.dart';
import '../ui/app_theme.dart';
import '../ui/ayah_widgets.dart';

// المحرر بالتصميم الجديد (طلب أنس 2026-11-28): زي CapCut — المعاينة فوق، تحتها
// سطر التشغيل (الوقت، تشغيل، تراجع/إعادة)، الخط الزمني بسهم ثابت بالنص، وشريط
// أدوات سفلي بيتغيّر حسب المحدد (آية محددة = أدوات الآية). الأدوات بتفتح لوحة
// مكان الخط الزمني (زي CapCut) وزر ✓ بيسكّرها. دايماً غامق.
const Color _gold = AyahColors.gold;
const Color _editorBg = Color(0xFF020E0A);
const Color _panelBg = Color(0xFF071A13);

ThemeData _editorTheme() {
  final base = buildAyahTheme(dark: true);
  return base.copyWith(
    scaffoldBackgroundColor: _editorBg,
    appBarTheme: base.appBarTheme.copyWith(backgroundColor: _editorBg),
  );
}

/// أدوات المحرر (كل وحدة بتفتح لوحة مكان الخط الزمني).
enum _Tool {
  elements('العناصر', Icons.layers_rounded),
  fonts('الخطوط والأحجام', Icons.text_fields_rounded),
  colors('الألوان والظل', Icons.palette_rounded),
  templates('القوالب', Icons.auto_awesome_mosaic_rounded),
  details('تفاصيل الآية', Icons.tune_rounded),
  split('تقسيم الآية', Icons.call_split_rounded);

  final String label;
  final IconData icon;
  const _Tool(this.label, this.icon);
}

/// لقطة للتراجع/الإعادة: المقاطع + الشكل.
class _Snapshot {
  final List<RecitationSegment> segments;
  final OverlayStyle style;
  const _Snapshot(this.segments, this.style);
}

/// المحرر 1 (يوم 9، مش التصميم النهائي يوم 22): معاينة الفيديو مع النص
/// المتزامن، **سحب العناصر بالإصبع** لأي مكان، وتبويبات: عناصر (تشغيل/إطفاء،
/// اسم القارئ) / خطوط (خط وحجم كل عنصر) / ألوان (أبيض أو أسود، شدة الظل،
/// خلفية شفافة) / قوالب (جاهزة + قوالبي). كل شي بيروح لـ [OverlayStyle] →
/// [AyahOverlayFrame] نفسه اللي بيرسم فيه التصدير، فالمعاينة = الناتج.
class OverlayEditorScreen extends StatefulWidget {
  final ProjectInput input;
  final List<RecitationSegment> segments;
  final TafsirMode initialTafsirMode;

  /// ملف الـ WAV اللي خط الأنابيب فكّه وقت التحليل (`PipelineResult.wavPath`)،
  /// لموجة الصوت بالخط الزمني بدون فك الصوت مرة ثانية. null = بنفكّه هون.
  final String? wavPath;

  /// الصلاحيات حسب الخطة (يوم 16–18 بيربطها). بالمجاني: قوالب جاهزة بس.
  final EditorCapabilities capabilities;

  const OverlayEditorScreen({
    super.key,
    required this.input,
    required this.segments,
    this.initialTafsirMode = TafsirMode.split,
    this.wavPath,
    this.capabilities = EditorCapabilities.full,
  });

  @override
  State<OverlayEditorScreen> createState() => _OverlayEditorScreenState();
}

class _OverlayEditorScreenState extends State<OverlayEditorScreen>
    with SingleTickerProviderStateMixin {
  VideoPlayerController? _video;

  /// ملف تلاوة منفصل (لو مفعّل): هو الساعة الرئيسية، وصوت الفيديو مكتوم.
  VideoPlayerController? _audio;
  VideoPlayerController? get _master => _audio ?? _video;

  final PlaybackClock _clock = PlaybackClock();
  final Stopwatch _wall = Stopwatch()..start();
  final ValueNotifier<double> _time = ValueNotifier<double>(0);
  late final Ticker _ticker;

  /// النص الظاهر هلأ (بيتغيّر بس لما المقطع أو الشفافية تتغيّر، مش كل إطار).
  final ValueNotifier<OverlayCue?> _cue = ValueNotifier<OverlayCue?>(null);
  final ValueNotifier<bool> _playing = ValueNotifier<bool>(false);

  /// المستخدم عم يسحب الخط الزمني: الساعة ما بتكتب فوق موقعه.
  bool _scrubbing = false;
  bool _wasPlayingBeforeScrub = false;

  /// seek واحد بس شغّال بنفس الوقت، والأحدث بيستنى (بدل طابور seeks بيعلّق).
  bool _seekBusy = false;
  double? _seekPending;

  /// موقع التشغيل قبل سحب مقبض (بنرجعله بعد السحب).
  double? _timeBeforeHandle;

  final List<_Snapshot> _undo = [];
  final List<_Snapshot> _redo = [];
  DateTime _lastStyleEdit = DateTime.fromMillisecondsSinceEpoch(0);

  List<ui.Image?> _thumbs = const [];

  /// مع آية محددة: true = الأدوات على كل الآيات (العام)، false = هالآية بس.
  bool _applyToAll = false;

  /// كلمات الآية المحددة (لأداة التقسيم).
  List<String> _splitWords = const [];

  Timer? _seekTimer;
  DateTime _lastNativeSeek = DateTime.fromMillisecondsSinceEpoch(0);
  double? _seekTarget;
  _Tool? _tool;
  final GlobalKey<EditorTimelineState> _timelineKey = GlobalKey<EditorTimelineState>();

  late OverlayTimeline _timeline;
  late OverlayStyle _style;

  /// (يوم 10، المحرر 2): نسخة قابلة للتعديل من المقاطع — تغيير آية، حذف،
  /// إضافة، وتحريك الحدود كلها بتعدّل هالقائمة، وبعدين `_rebuildTimeline`
  /// بيعيد بناء [_timeline] منها. القائمة لازم تضل مرتبة بالبداية (نفس ترتيب
  /// `widget.segments` الأصلي) عشان `index` بـ [TimelineSegment] يتطابق مع
  /// منطق الجيران بـ [clampSegmentDrag].
  late List<RecitationSegment> _segments;
  ProjectEditStore? _editStore;
  WaveformPeaks? _peaks;
  int? _selectedSegment;
  QuranTextSource? _textSource;
  Timer? _saveTimer;
  final Stopwatch _dragSeek = Stopwatch();

  /// في تعديلات يدوية بهالمشروع (لزر "رجوع للتحليل الأصلي").
  bool _hasEdits = false;

  /// بصمة نتيجة التحليل الأصلية (التعديلات المحفوظة مربوطة فيها).
  late final String _baseSignature = segmentsSignature(widget.segments);

  /// اللون اختاره المستخدم بإيده → ما بنغيّره تلقائياً.
  bool _colorTouched = false;
  String? _colorNote;
  double _lastShadow = OverlayStyle.defaultShadowStrength;

  Map<int, String> _surahNames = const {};
  TemplateStore _templates = TemplateStore.memory();
  String? _error;
  bool _ready = false;

  OverlayElement? _selected;

  // سحب العناصر: أبعاد الفيديو بالبكسل، ومفاتيح لقياس مكان كل عنصر.
  final GlobalKey _videoKey = GlobalKey(debugLabel: 'editor-video');
  final Map<OverlayElement, GlobalKey> _keys = {
    for (final e in OverlayElement.values) e: GlobalKey(debugLabel: e.name),
  };
  OverlayElement? _dragEl;
  Offset _dragStart = Offset.zero;
  double _baseCx = 0, _baseTop = 0;
  Size _dragSize = Size.zero;
  bool _pinching = false;
  Map<OverlayElement, double> _pinchBase = {};
  int? _pinchSeg;

  /// خطوط الإرشاد: بتبيّن بس وقت السحب أو التكبير بإصبعين.
  final ValueNotifier<List<SnapGuide>> _guides = ValueNotifier(const []);

  /// true = تكبير/تصغير كل العناصر مع بعض بنفس النسبة، false = العنصر المختار بس.
  bool _linkSizes = false;

  /// true = الحجم لمقطع واحد بس (اللي ظاهر هلأ)، false = كل المقاطع مع بعض.
  bool _perSegment = false;

  /// رقم المقطع الظاهر هلأ (بيتحدّث مع التشغيل، لتحديث أزرار الحجم).
  final ValueNotifier<int?> _segIdx = ValueNotifier(null);

  final TextEditingController _reciterCtl = TextEditingController();

  double get _wallSeconds => _wall.elapsedMicroseconds / 1e6;
  int get _w => widget.input.videoInfo.rotatedWidth;
  int get _h => widget.input.videoInfo.rotatedHeight;
  bool get _can => widget.capabilities.canCustomize;

  @override
  void initState() {
    super.initState();
    _style = OverlayStyle(tafsirMode: widget.initialTafsirMode);
    _segments = [...widget.segments];
    _rebuildTimeline();
    _ticker = createTicker((_) {
      if (!_scrubbing) _time.value = _clock.now(_wallSeconds);
      _updateCue();
    })..start();
    _init();
    _autoPickColor();
    _loadSurahNames();
    _openTemplates();
    _openEditStore();
    _loadWaveform();
    _loadThumbs();
    RecitationPipeline.instance.textSource.then((t) {
      if (mounted) _textSource = t;
    }).catchError((_) {});
  }

  /// إعادة بناء [_timeline] من [_segments] الحالية (بعد أي تعديل يدوي).
  void _rebuildTimeline() {
    final info = widget.input.videoInfo;
    _timeline = OverlayTimeline.build(_segments,
        videoDuration: info.durationMs > 0 ? info.durationSeconds : null);
    _cueKey = null; // نجبر تحديث النص الظاهر.
  }

  String? _cueKey;

  /// تحديث [_cue] بس لما يتغيّر فعلاً (سرعة: النص العربي تقيل بالرسم).
  void _updateCue() {
    final c = _timeline.cueAt(_time.value);
    final key = c == null ? '' : '${c.item.index}|${(c.opacity * 64).round()}';
    if (key != _cueKey) {
      _cueKey = key;
      _cue.value = c;
    }
    final cur = c?.item.index;
    if (cur != _segIdx.value) _segIdx.value = cur;
  }

  /// فتح مخزن تعديلات هالمشروع، وتحميل آخر نسخة محفوظة منه لو موجودة
  /// (يوم 10، القسم 6: "التعديلات اليدوية ما تنمسح لما ترجع للمحرر"). الملف
  /// مربوط ببصمة نتيجة التحليل ([segmentsSignature]): لو المستخدم عاد التحليل
  /// وطلعت نتيجة ثانية، ما بنركّب التعديلات القديمة فوقها.
  Future<void> _openEditStore() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final store = ProjectEditStore(
          File('${dir.path}/${projectEditFileName(widget.input.videoPath)}'));
      _editStore = store;
      final saved = await store.loadEdits(base: _baseSignature);
      if (saved != null && saved.segments.isNotEmpty && mounted) {
        setState(() {
          _segments = saved.segments;
          _style = _style.copyWith(
              segmentScales: saved.segmentScales, segmentStyles: saved.segmentStyles);
          _hasEdits = true;
          _rebuildTimeline();
        });
      }
    } catch (_) {
      // بدون تخزين: التعديلات بتضل بالذاكرة بس لهالجلسة.
    }
  }

  /// حفظ (مؤجّل شوي عشان السحب ما يكتب ملف بكل إطار).
  void _saveEdits({bool now = false}) {
    _hasEdits = true;
    _saveTimer?.cancel();
    void write() {
      final store = _editStore;
      if (store == null) return;
      store
          .save(_segments,
              base: _baseSignature,
              segmentScales: _style.segmentScales,
              segmentStyles: _style.segmentStyles)
          .catchError((_) {});
    }

    if (now) {
      write();
    } else {
      _saveTimer = Timer(const Duration(milliseconds: 600), write);
    }
  }

  /// استخراج موجة الصوت من نفس ملف الـ WAV اللي خط الأنابيب فكّه
  /// ([OverlayEditorScreen.wavPath])، أو فكّه هلأ لو مش موجود، بـ isolate عشان
  /// ما يجمّد الواجهة. الصوت = مصدر التعرف (ملف التلاوة المنفصل لو مفعّل)،
  /// لأنه هو اللي التوقيت محسوب عليه.
  Future<void> _loadWaveform() async {
    try {
      var wav = widget.wavPath;
      if (wav == null || !File(wav).existsSync()) {
        final tempDir = await getTemporaryDirectory();
        wav = await NativeAudioDecoder.ensureWav(
            widget.input.recognitionSourcePath, Directory('${tempDir.path}/wave'));
      }
      final peaks = await extractPeaksFromWavFile(wav);
      if (mounted) setState(() => _peaks = peaks);
    } catch (_) {
      // بدون موجة: الخط الزمني بيطلع بخلفية فاضية (السحب والتعديل لسا شغالين).
      if (mounted) setState(() => _peaks = WaveformPeaks.empty);
    }
  }

  /// أسماء السور من جدول `surahs` (للعنصر "اسم السورة ورقم الآية").
  Future<void> _loadSurahNames() async {
    try {
      final all = await QuranDatabase.instance.allSurahs();
      if (!mounted) return;
      setState(() => _surahNames = {for (final s in all) s.number: s.nameArabic});
    } catch (_) {
      // بدون أسماء: بيطلع "سورة 50".
    }
  }

  Future<void> _openTemplates() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final store = await TemplateStore.open(
          TemplateStorage(File('${dir.path}/overlay_templates.json')));
      if (!mounted) return;
      setState(() => _templates = store);
    } catch (_) {
      // بدون تخزين: القوالب بالذاكرة بس لهالجلسة.
    }
  }

  /// لون النص الأوضح حسب سطوع الفيديو بمنطقة النص (أسود فوق خلفية فاتحة).
  Future<void> _autoPickColor() async {
    final b = await VideoInfoReader.textBandBrightness(
        widget.input.videoInfo, widget.input.videoPath);
    if (b == null || !mounted || _colorTouched) return;
    final pick = OverlayTextColor.forBackground(b.luma, b.brightFraction);
    setState(() {
      _style = _style.copyWith(color: pick);
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
    // بس أيقونة التشغيل (بدل setState للشاشة كلها مع كل تبليغ من المشغّل).
    _playing.value = v.isPlaying;
    // انتهى: وقّف وانتظر "تشغيل" ليرجع من البداية.
    if (v.isCompleted && _video!.value.isPlaying) {
      _video!.pause();
    }
    // seek لسا معلّق: موقع المشغّل قديم، ما نصدّقه.
    if (_seekTimer != null || _seekTarget != null) return;
    // وقت التحميل (buffering) الصورة واقفة: الساعة ما لازم تمشي لحالها.
    _clock.report(
      position: v.position.inMicroseconds / 1e6,
      wall: _wallSeconds,
      playing: v.isPlaying && !v.isBuffering,
    );
  }

  Future<void> _togglePlay() async {
    final m = _master!;
    final all = [_video!, if (_audio != null) _audio!];
    if (m.value.isPlaying) {
      await Future.wait([for (final c in all) c.pause()]);
    } else {
      final dur = m.value.duration;
      if (m.value.position >= dur - const Duration(milliseconds: 100) ||
          _time.value >= _duration - 0.1) {
        await _seekTo(0, now: true);
      } else if (_seekTimer != null ||
          _seekTarget != null ||
          (m.value.position.inMicroseconds / 1e6 - _time.value).abs() > 0.25) {
        // بعد سحب: المشغّل لازم يكون بنفس مكان الخط قبل ما يبلّش.
        await _seekTo(_time.value, now: true);
      }
      await Future.wait([for (final c in all) c.play()]);
    }
  }

  Future<void> _seek(Duration to) => _seekTo(to.inMicroseconds / 1e6, now: true);

  /// seek مضبوط: النص والخط الزمني بيتحدّثوا فوراً، والمشغّل بياخد **آخر** موقع
  /// مطلوب بس، وبحد أقصى seek كل 150ms (وقت السحب). `seekTo` تبع video_player
  /// بيرجع قبل ما ExoPlayer يخلّص، فطابور seeks سريع كان بيعلّق الصورة لثواني
  /// بعد "تشغيل" (بلاغ أنس 2026-11-28: الخط بيمشي والفيديو واقف).
  Future<void> _seekTo(double seconds, {bool now = false}) async {
    final t = seconds.clamp(0.0, _duration).toDouble();
    _time.value = t;
    _updateCue();
    if (_video == null) return;
    _seekTarget = t;
    final since = DateTime.now().difference(_lastNativeSeek).inMilliseconds;
    if (!now && since < 150) {
      _seekTimer ??= Timer(Duration(milliseconds: 150 - since), _flushSeek);
      return;
    }
    await _flushSeek();
  }

  Future<void> _flushSeek() async {
    _seekTimer?.cancel();
    _seekTimer = null;
    final t = _seekTarget;
    if (t == null || _video == null) return;
    _seekTarget = null;
    _lastNativeSeek = DateTime.now();
    try {
      final d = Duration(microseconds: (t * 1e6).round());
      await Future.wait([for (final c in [_video!, if (_audio != null) _audio!]) c.seekTo(d)]);
    } catch (_) {
      // المشغّل انسكّر.
    }
    if (!mounted || _master == null) return;
    _clock.report(position: t, wall: _wallSeconds, playing: false);
  }

  // ------------------------ السحب على الخط الزمني ------------------------

  void _onScrubStart() {
    _scrubbing = true;
    _wasPlayingBeforeScrub = _master?.value.isPlaying ?? false;
    if (_wasPlayingBeforeScrub) {
      for (final c in [_video!, if (_audio != null) _audio!]) {
        c.pause();
      }
    }
  }

  void _onScrub(double t) => _seekTo(t);

  void _onScrubEnd() {
    _scrubbing = false;
    // seek أخير بالمكان بالضبط (بدل ما يضل طلب معلّق).
    _seekTo(_time.value, now: true);
  }

  // --------------------------- تراجع / إعادة ---------------------------

  _Snapshot get _snap => _Snapshot(List.of(_segments), _style);

  void _checkpoint() {
    _undo.add(_snap);
    if (_undo.length > 60) _undo.removeAt(0);
    _redo.clear();
  }

  void _restore(_Snapshot s) {
    setState(() {
      _segments = List.of(s.segments);
      _style = s.style;
      if (_selectedSegment != null && _selectedSegment! >= _segments.length) {
        _selectedSegment = null;
      }
      _rebuildTimeline();
    });
    _updateCue();
    _saveEdits();
  }

  void _doUndo() {
    if (_undo.isEmpty) return;
    HapticFeedback.selectionClick();
    _redo.add(_snap);
    _restore(_undo.removeLast());
  }

  void _doRedo() {
    if (_redo.isEmpty) return;
    HapticFeedback.selectionClick();
    _undo.add(_snap);
    _restore(_redo.removeLast());
  }

  /// الصور المصغّرة لمسار الفيديو (بالخلفية، بعد ما المحرر يفتح).
  Future<void> _loadThumbs() async {
    try {
      final info = widget.input.videoInfo;
      final dur = info.durationSeconds > 0 ? info.durationSeconds : _duration;
      final count = dur.isFinite ? dur.round().clamp(4, 40) : 12;
      final bytes = await VideoInfoReader.thumbnails(widget.input.videoPath,
          durationMs: info.durationMs, count: count, height: 112,
          portrait: info.rotatedHeight > info.rotatedWidth);
      final out = <ui.Image?>[];
      for (final b in bytes) {
        if (b.isEmpty) {
          out.add(null);
          continue;
        }
        try {
          final codec = await ui.instantiateImageCodec(b);
          final f = await codec.getNextFrame();
          out.add(f.image);
        } catch (_) {
          out.add(null);
        }
      }
      if (mounted && out.any((e) => e != null)) {
        setState(() => _thumbs = out);
      } else {
        for (final i in out) {
          i?.dispose();
        }
      }
    } catch (_) {
      // بدون صور: شريط فيلم بسيط.
    }
  }

  Future<void> _openExport() async {
    final all = [_video!, if (_audio != null) _audio!];
    await Future.wait([for (final c in all) c.pause()]);
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ExportScreen(
        request: ExportRequest(
          input: widget.input,
          segments: _segments,
          style: _style,
          surahNames: _surahNames,
        ),
      ),
    ));
  }

  @override
  void dispose() {
    if (_saveTimer?.isActive ?? false) {
      _saveTimer!.cancel();
      _editStore
          ?.save(_segments, base: _baseSignature,
              segmentScales: _style.segmentScales,
              segmentStyles: _style.segmentStyles)
          .catchError((_) {});
    }
    _seekTimer?.cancel();
    _ticker.dispose();
    _master?.removeListener(_onPlayerUpdate);
    _video?.dispose();
    _audio?.dispose();
    _time.dispose();
    _cue.dispose();
    _playing.dispose();
    for (final i in _thumbs) {
      i?.dispose();
    }
    _guides.dispose();
    _segIdx.dispose();
    _reciterCtl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // تعديل الشكل
  // ---------------------------------------------------------------------

  /// الآية اللي التعديلات بتنطبّق عليها لحالها (null = الشكل العام لكل الآيات).
  /// لما تكون آية محددة، كل الأدوات (وسحب العناصر بالمعاينة) بتشتغل عليها هي
  /// بس، إلا لو المستخدم اختار "كل الآيات".
  int? get _scopeSeg {
    final sel = _selectedSegment;
    if (sel == null || _applyToAll || sel >= _segments.length) return null;
    return _segments[sel].isVisible ? sel : null;
  }

  /// الشكل اللي عم يتعدّل هلأ (العام، أو شكل الآية المحددة).
  OverlayStyle get _es {
    final seg = _scopeSeg;
    return seg == null ? _style : _style.forSegment(seg);
  }

  /// كل مقاطع نفس الآية (الأجزاء) اللي المقطع [i] منها.
  List<int> _groupOf(int i) {
    final (from, to) = readingGroupAt(_segments, i);
    return [for (var k = from; k <= to; k++) k];
  }

  void _setStyle(OverlayStyle s) {
    // تغييرات متتالية (سلايدر، سحب) = خطوة تراجع وحدة.
    final now = DateTime.now();
    if (now.difference(_lastStyleEdit).inMilliseconds > 700) _checkpoint();
    _lastStyleEdit = now;
    final seg = _scopeSeg;
    if (seg == null) {
      setState(() => _style = s);
      return;
    }
    // شكل خاص بهالآية (كل أجزائها)، والحجم الخاص القديم بينطوي جواه.
    final own = s.copyWith(
        reciterName: '', segmentScales: const {}, segmentStyles: const {});
    final styles = {..._style.segmentStyles};
    final scales = {..._style.segmentScales};
    for (final i in _groupOf(seg)) {
      styles[i] = own;
      scales.remove(i);
    }
    setState(() => _style = _style.copyWith(segmentStyles: styles, segmentScales: scales));
    _saveEdits();
  }

  /// رجّع الآية المحددة للشكل العام.
  void _resetAyahStyle() {
    final sel = _selectedSegment;
    if (sel == null) return;
    _checkpoint();
    final styles = {..._style.segmentStyles};
    final scales = {..._style.segmentScales};
    for (final i in _groupOf(sel)) {
      styles.remove(i);
      scales.remove(i);
    }
    setState(() => _style = _style.copyWith(segmentStyles: styles, segmentScales: scales));
    _saveEdits();
  }

  void _setPlacement(OverlayElement e, ElementPlacement Function(ElementPlacement) f) =>
      _setStyle(_es.copyWith(layout: _es.layout.update(e, f)));

  String? _surahLookup(int n) => _surahNames[n];

  // ---------------------------------------------------------------------
  // سحب العناصر بالإصبع: بنقيس مكان كل عنصر ظاهر بإحداثيات الفيديو
  // (بكسلات الفيديو الحقيقية، مهما كان تصغير الشاشة)، وبنخزّن الموقع نسبي.
  // ---------------------------------------------------------------------

  Offset? _toVideo(Offset global) {
    final ro = _videoKey.currentContext?.findRenderObject();
    if (ro is! RenderBox || !ro.attached || !ro.hasSize) return null;
    return ro.globalToLocal(global);
  }

  /// مكان العنصر الظاهر حالياً بإحداثيات الفيديو، أو null لو مش ظاهر.
  Rect? _rectOf(OverlayElement e) {
    final frame = _videoKey.currentContext?.findRenderObject();
    final el = _keys[e]!.currentContext?.findRenderObject();
    if (frame is! RenderBox ||
        el is! RenderBox ||
        !frame.attached ||
        !el.attached ||
        !el.hasSize) {
      return null;
    }
    final a = frame.globalToLocal(el.localToGlobal(Offset.zero));
    final b = frame.globalToLocal(el.localToGlobal(el.size.bottomRight(Offset.zero)));
    return Rect.fromPoints(a, b);
  }

  OverlayElement? _hit(Offset p) {
    final unit = (_w < _h ? _w : _h).toDouble();
    final slop = unit * 0.02;
    // المنسحب فوق الباقي (بينرسم آخر)، وبعدين بترتيب عكسي.
    final order = [
      ..._es.layout.detached.reversed,
      ...OverlayElement.values.reversed,
    ];
    for (final e in order) {
      if (!_es.layout.isEnabled(e)) continue;
      final r = _rectOf(e);
      if (r != null && r.inflate(slop).contains(p)) return e;
    }
    return null;
  }

  /// زي ستوري إنستغرام: الضغطة الواضحة بس بتحدد عنصر (أو بتلغي التحديد لو
  /// ضغطت مكان فاضي). بعد التحديد، السحب من أي مكان بالشاشة بيحرّك العنصر
  /// المحدد، والإصبعين بيكبّروه/بيصغّروه، بدون ما تلمس العنصر نفسه.
  void _onTapUp(TapUpDetails d) {
    final p = _toVideo(d.globalPosition);
    setState(() => _selected = p == null ? null : _hit(p));
  }

  List<OverlayElement> get _sizable => [
        for (final e in OverlayElement.values)
          if (_es.layout.isEnabled(e) && e.available) e
      ];

  /// المقطع اللي بيتعدّل حجمه: null = كل المقاطع (الحجم العام)، أو رقم المقطع
  /// الظاهر هلأ لما "كل مقطع لحاله" شغّال. [_noSegment] = لحاله بس ما في مقطع ظاهر.
  int? get _targetSeg => _perSegment && _scopeSeg == null ? _segIdx.value : null;
  bool get _noSegment => _perSegment && _scopeSeg == null && _segIdx.value == null;

  double _scaleOf(OverlayElement e, int? seg) =>
      seg == null ? _es.layout[e].scale : _es.forSegment(seg).layout[e].scale;

  void _applyScales(Map<OverlayElement, double> scales, {int? seg}) {
    if (seg == null) {
      var l = _es.layout;
      scales.forEach((e, v) => l = l.update(e, (p) => p.copyWith(scale: clampScale(v))));
      _setStyle(_es.copyWith(layout: l));
      return;
    }
    final mine = {...?_style.segmentScales[seg]};
    scales.forEach((e, v) => mine[e] = clampScale(v));
    _setStyle(_style.copyWith(segmentScales: {..._style.segmentScales, seg: mine}));
    _saveEdits(); // أحجام كل مقطع بتنحفظ مع تعديلات المقاطع (يوم 10)
  }

  /// رجّع حجم المقطع [seg] للحجم العام.
  void _resetSegment(int seg) {
    final m = {..._style.segmentScales}..remove(seg);
    _setStyle(_style.copyWith(segmentScales: m));
    _saveEdits();
  }

  /// تغيير حجم [e] لـ [v] (للمقطع الظاهر لو "كل مقطع لحاله"): لو "الكل مع بعض"
  /// كل العناصر بتتضرب بنفس النسبة.
  void _scaleTo(OverlayElement e, double v) {
    if (_noSegment) return;
    final seg = _targetSeg;
    final old = _scaleOf(e, seg);
    if (!_linkSizes || old <= 0) {
      _applyScales({e: v}, seg: seg);
      return;
    }
    final f = v / old;
    _applyScales({for (final x in _sizable) x: _scaleOf(x, seg) * f}, seg: seg);
  }

  void _setGuides(List<SnapGuide> g) {
    if (g.isNotEmpty && g.length != _guides.value.length) {
      HapticFeedback.selectionClick();
    }
    _guides.value = g;
  }

  double get _snapThreshold => (_w < _h ? _w : _h) * 0.018;

  void _onScaleStart(ScaleStartDetails d) {
    final e = _selected;
    if (!_can || e == null || !_es.layout.isEnabled(e)) return;
    final p = _toVideo(d.focalPoint);
    final r = _rectOf(e);
    if (p == null || r == null) return;
    final a = _es.layout[e].anchor;
    _dragEl = e;
    _dragStart = p;
    _dragSize = r.size;
    _baseCx = a != null ? a.cx * _w : r.center.dx;
    _baseTop = a != null ? a.top * _h : r.top;
    _pinching = false;
    _pinchSeg = _targetSeg;
    _pinchBase = {for (final x in _sizable) x: _scaleOf(x, _pinchSeg)};
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    final e = _dragEl;
    final p = _toVideo(d.focalPoint);
    if (e == null || p == null) return;
    final video = Size(_w.toDouble(), _h.toDouble());
    List<Rect> others() => [
          for (final x in OverlayElement.values)
            if (x != e && _es.layout.isEnabled(x))
              if (_rectOf(x) case final r?) r
        ];
    if (d.pointerCount >= 2) {
      _pinching = true;
      final f = d.scale;
      if (_perSegment && _pinchSeg == null) {
        // ما في مقطع ظاهر: ما في شي نكبّره لحاله.
      } else if (_linkSizes) {
        _applyScales({for (final x in _pinchBase.keys) x: _pinchBase[x]! * f},
            seg: _pinchSeg);
      } else if (_pinchBase.containsKey(e)) {
        _applyScales({e: _pinchBase[e]! * f}, seg: _pinchSeg);
      }
      final r = _rectOf(e);
      if (r != null) {
        _setGuides(snapRect(r,
                video: video, others: others(), threshold: _snapThreshold, snap: false)
            .guides);
      }
      return;
    }
    if (_pinching) return; // رفع إصبع وسط التكبير: ما نحرّك فجأة.
    final cx = _baseCx + (p.dx - _dragStart.dx);
    final top = _baseTop + (p.dy - _dragStart.dy);
    final raw = Rect.fromLTWH(cx - _dragSize.width / 2, top, _dragSize.width, _dragSize.height);
    final s = snapRect(raw, video: video, others: others(), threshold: _snapThreshold);
    _setGuides(s.guides);
    final anchor = anchorFromPixels(s.rect.center.dx, s.rect.top, _w, _h);
    _setPlacement(e, (pl) => pl.copyWith(anchor: anchor));
  }

  void _onScaleEnd([Object? _]) {
    _dragEl = null;
    _pinching = false;
    _guides.value = const [];
  }

  // ---------------------------------------------------------------------
  // تعديل المقاطع يدوياً (يوم 10، المحرر 2: التصحيح اليدوي). كل العمليات
  // بـ `lib/editor/segment_edits.dart` (صافية ومختبرة)؛ هون بس منطبّقها على
  // الحالة، ومنعيد ربط `segmentScales` لما العدد أو الترتيب يتغيّر.
  // ---------------------------------------------------------------------

  double get _duration {
    final d = widget.input.videoInfo.durationSeconds;
    if (d > 0) return d;
    final m = _master?.value.duration.inMilliseconds ?? 0;
    if (m > 0) return m / 1000;
    return _segments.isEmpty ? 1 : _segments.last.end + 1;
  }

  Future<QuranTextSource> _text() async =>
      _textSource ??= await RecitationPipeline.instance.textSource;

  void _applyEdit(SegmentEdit e,
      {bool select = true, bool saveNow = false, bool continuous = false}) {
    if (!continuous) _checkpoint();
    setState(() {
      _segments = e.segments;
      _style = _style.copyWith(
          segmentScales: e.remapScales(_style.segmentScales),
          segmentStyles: e.remapMap(_style.segmentStyles));
      if (select) {
        _selectedSegment = e.focus;
      } else if (_selectedSegment != null) {
        final m = _selectedSegment! < e.mapping.length
            ? e.mapping[_selectedSegment!]
            : null;
        _selectedSegment = m;
      }
      _rebuildTimeline();
    });
    _saveEdits(now: saveNow);
  }

  void _selectSegment(int? i) {
    FocusScope.of(context).unfocus();
    setState(() {
      if (i != _selectedSegment) _applyToAll = false;
      _selectedSegment = i;
      if (i == null && _tool == _Tool.split) _tool = null;
    });
    if (i != null && i < _segments.length) {
      final s = _segments[i];
      final t = _time.value;
      // المقطع برا اللي ظاهر هلأ → روح لأوله (عشان المعاينة تعرضه).
      if (t < s.start || t >= s.end) {
        _seek(Duration(milliseconds: (s.start * 1000).round() + 30));
      }
    }
  }

  void _onHandleStart(int index, bool isStart) {
    _checkpoint();
    _timeBeforeHandle = _time.value;
    if (_master?.value.isPlaying ?? false) {
      for (final c in [_video!, if (_audio != null) _audio!]) {
        c.pause();
      }
    }
  }

  void _onDragHandle(int index, bool isStart, double v) {
    if (index < 0 || index >= _segments.length) return;
    final s = _segments[index];
    _applyEdit(
        setBounds(_segments, index, isStart ? v : s.start, isStart ? s.end : v,
            duration: _duration),
        select: false,
        continuous: true);
    // المعاينة بتوريك أول/آخر الآية وانت بتسحب (seek مضبوط، آخر طلب بس).
    final seg = _segments[index];
    _seekTo(isStart ? seg.start + 0.03 : seg.end - 0.05);
  }

  void _onHandleEnd() {
    _saveEdits(now: true);
    final back = _timeBeforeHandle;
    _timeBeforeHandle = null;
    if (back != null) _seekTo(back);
  }

  void _onBounds(int index, double start, double end) {
    if (index < 0 || index >= _segments.length) return;
    _applyEdit(setBounds(_segments, index, start, end, duration: _duration), select: false);
  }

  Future<void> _changeAyahFlow(int index) async {
    final s = _segments[index];
    final initial = s.surah != null && s.ayah != null
        ? (s.surah!, s.ayah!)
        : parseRef(s.suggestedRef);
    final picked = await showAyahPicker(context,
        initial: initial, title: s.isAyah ? 'تغيير الآية' : 'شو الآية بهالمقطع؟');
    if (picked == null || !mounted) return;
    final text = await _text();
    if (!mounted || index >= _segments.length) return;
    _applyEdit(changeAyah(text, _segments, index, picked.$1, picked.$2), saveNow: true);
  }

  Future<void> _convertToNonQuran(int index) async {
    final text = await _text();
    if (!mounted || index >= _segments.length) return;
    _applyEdit(convertToNonQuran(text, _segments, index), saveNow: true);
  }

  void _onUserText(int index, String value) {
    if (index < 0 || index >= _segments.length) return;
    _applyEdit(setUserText(_segments, index, value), select: false);
  }

  void _confirm(int index) {
    _applyEdit(confirmSegment(_segments, index), select: false, saveNow: true);
    // على المقطع الجاي اللي بده مراجعة (لو في).
    final next = nextNeedingReview(_segments, after: index);
    if (next != null && next != index) _selectSegment(next);
  }

  Future<void> _delete(int index) async {
    final text = await _text().catchError((_) => QuranTextSource.fromRows(const []));
    if (!mounted || index >= _segments.length) return;
    _applyEdit(deleteSegment(text, _segments, index), select: false, saveNow: true);
    setState(() => _selectedSegment = null);
  }

  Map<OverlayElement, double> _segmentScalesFor(int index) => {
        for (final e in OverlayElement.values)
          if (e.available && _style.layout.isEnabled(e))
            e: _style.forSegment(index).layout[e].scale,
      };

  void _setSegmentScale(int index, OverlayElement e, double v) {
    final mine = {...?_style.segmentScales[index]};
    mine[e] = clampScale(v);
    setState(() => _style =
        _style.copyWith(segmentScales: {..._style.segmentScales, index: mine}));
    _saveEdits();
  }

  void _resetSegmentScales(int index) {
    final m = {..._style.segmentScales}..remove(index);
    setState(() => _style = _style.copyWith(segmentScales: m));
    _saveEdits();
  }

  Future<void> _playSegment(int index) async {
    final s = _segments[index];
    await _seek(Duration(milliseconds: (s.start * 1000).round()));
    final all = [_video!, if (_audio != null) _audio!];
    await Future.wait([for (final c in all) c.play()]);
  }

  /// إضافة مقطع يدوياً: نوعه (آية أو نص غير قرآني) + نطاق وقت (مقترح: من
  /// موقع التشغيل لأول فراغ، والمستخدم بيعدّله بلوحة التفاصيل بعدين).
  Future<void> _addSegmentFlow() async {
    final after = _time.value;
    final ranges = [for (final s in _segments) (s.start, s.end)];
    final free = nextFreeRange(ranges, afterSeconds: after, duration: _duration) ??
        nextFreeRange(ranges, afterSeconds: 0, duration: _duration) ??
        nextFreeRange(ranges,
            afterSeconds: after, duration: _duration, length: minSegmentSeconds * 2) ??
        nextFreeRange(ranges,
            afterSeconds: 0, duration: _duration, length: minSegmentSeconds * 2);
    if (free == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('ما في وقت فاضي بالفيديو. صغّر أو احذف مقطع أول.')));
      return;
    }
    final kind = await showDialog<String>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: SimpleDialog(
          title: Text('إضافة مقطع من ${formatClock(free.$1)} لـ ${formatClock(free.$2)}'),
          children: [
            SimpleDialogOption(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              onPressed: () => Navigator.pop(ctx, 'ayah'),
              child: const Text('آية', style: TextStyle(fontSize: 16)),
            ),
            SimpleDialogOption(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              onPressed: () => Navigator.pop(ctx, 'text'),
              child: const Text('نص خاص (مقدمة، دعاء…)', style: TextStyle(fontSize: 16)),
            ),
          ],
        ),
      ),
    );
    if (kind == null || !mounted) return;
    RecitationSegment seg;
    if (kind == 'ayah') {
      final last = _segments.lastWhere((s) => s.isAyah && s.start <= after,
          orElse: () => const RecitationSegment(start: 0, end: 0, kind: SegmentKind.nonQuran, confidence: 0));
      final picked = await showAyahPicker(context,
          initial: last.surah == null ? null : (last.surah!, (last.ayah ?? 0) + 1),
          title: 'آية المقطع الجديد');
      if (picked == null || !mounted) return;
      final text = await _text();
      seg = buildWholeAyahSegment(
          text: text, surah: picked.$1, ayah: picked.$2, start: free.$1, end: free.$2);
    } else {
      seg = buildUserTextSegment(start: free.$1, end: free.$2);
    }
    if (!mounted) return;
    final e = insertSegment(_segments, seg);
    if (e == null) return;
    _applyEdit(e, saveNow: true);
    _selectSegment(e.focus);
  }

  /// رجوع لنتيجة التحليل الأصلية (بيمسح كل التعديلات اليدوية لهالمشروع).
  Future<void> _resetEdits() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('رجوع للتحليل الأصلي؟'),
          content: const Text('كل تعديلات التوقيت والآيات والنصوص بهالمشروع رح تنمسح.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('رجوع')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    _saveTimer?.cancel();
    await _editStore?.clear();
    if (!mounted) return;
    setState(() {
      _segments = [...widget.segments];
      _style = _style.copyWith(segmentScales: const {}, segmentStyles: const {});
      _selectedSegment = null;
      _hasEdits = false;
      _rebuildTimeline();
    });
  }

  // ---------------------------------------------------------------------
  // البناء (تصميم زي CapCut)
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: _editorTheme(),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle.light.copyWith(
              systemNavigationBarColor: _panelBg, statusBarColor: Colors.transparent),
          child: Scaffold(
            backgroundColor: _editorBg,
            body: SafeArea(
              child: _error != null
                  ? _errorView()
                  : !_ready
                      ? const Center(child: GoldLoader(size: 70))
                      : _buildBody(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _errorView() => Column(
        children: [
          _topBar(),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!, textAlign: TextAlign.center),
              ),
            ),
          ),
        ],
      );

  Widget _topBar() {
    final q = math.min(_w, _h);
    final res = q >= 2000 ? '4K' : '${q}P';
    return SizedBox(
      height: 54,
      child: Row(
        children: [
          IconButton(
            tooltip: 'رجوع',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.close_rounded, size: 28, color: Colors.white),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: const Color(0x1AFFFFFF),
            ),
            child: Text(res,
                textDirection: TextDirection.ltr,
                style: const TextStyle(
                    fontFamily: kUiFont, fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white70)),
          ),
          const SizedBox(width: 10),
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 12),
            child: GoldButton(
              label: 'تصدير',
              icon: Icons.file_upload_outlined,
              height: 38,
              fontSize: 15,
              expand: false,
              onPressed: _ready ? _openExport : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final w = _w, h = _h;
    final unit = (w < h ? w : h).toDouble();
    return Column(
      children: [
        _topBar(),
        // ------------------------------ المعاينة ------------------------------
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: _onTapUp,
            onScaleStart: (d) {
              if (_selected != null) _checkpoint();
              _onScaleStart(d);
            },
            onScaleUpdate: _onScaleUpdate,
            onScaleEnd: _onScaleEnd,
            child: Container(
              color: Colors.black,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(vertical: 6),
              // مساحة الفيديو الحقيقية بالبكسل (نفس التصدير) مصغّرة بالـ FittedBox.
              child: FittedBox(
                fit: BoxFit.contain,
                child: SizedBox(
                  key: _videoKey,
                  width: w.toDouble(),
                  height: h.toDouble(),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      RepaintBoundary(child: VideoPlayer(_video!)),
                      RepaintBoundary(
                        child: ValueListenableBuilder<OverlayCue?>(
                          valueListenable: _cue,
                          builder: (_, cue, __) => _overlayFor(cue),
                        ),
                      ),
                      IgnorePointer(
                        child: CustomPaint(
                          painter: _GuidesPainter(guides: _guides, unit: unit),
                        ),
                      ),
                      IgnorePointer(
                        child: CustomPaint(
                          painter: _SelectionPainter(
                            repaint: _cue,
                            unit: unit,
                            rect: () => _selected == null ? null : _rectOf(_selected!),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        _controlsRow(),
        // اللوحة (أداة مفتوحة) بتاخد مكان الخط الزمني والشريط، زي CapCut.
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOutCubic,
          transitionBuilder: (child, anim) => SizeTransition(
            sizeFactor: anim,
            axisAlignment: -1,
            child: FadeTransition(opacity: anim, child: child),
          ),
          child: _tool != null
              ? KeyedSubtree(key: ValueKey(_tool), child: _toolPanel(_tool!))
              : Column(
                  key: const ValueKey('timeline'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _timelineArea(),
                    _toolbar(),
                  ],
                ),
        ),
      ],
    );
  }

  // كاش لويدجت النص: نفس المدخلات = نفس الويدجت (Flutter ما بيعيد بناءه).
  Widget? _overlayCache;
  OverlayCue? _overlayCue;
  OverlayStyle? _overlayStyle;
  Map<int, String>? _overlayNames;

  Widget _overlayFor(OverlayCue? cue) {
    if (_overlayCache != null &&
        identical(cue, _overlayCue) &&
        identical(_style, _overlayStyle) &&
        identical(_surahNames, _overlayNames)) {
      return _overlayCache!;
    }
    _overlayCue = cue;
    _overlayStyle = _style;
    _overlayNames = _surahNames;
    return _overlayCache = AyahOverlayFrame(
      videoWidth: _w,
      videoHeight: _h,
      cue: cue,
      style: _style,
      surahName: _surahLookup,
      elementKeys: _keys,
    );
  }

  String _clockText(double t) {
    final ms = (t * 1000).round();
    final m = ms ~/ 60000, sec = (ms ~/ 1000) % 60;
    return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  /// سطر التشغيل: الوقت | تشغيل | تراجع/إعادة (زي CapCut).
  Widget _controlsRow() {
    final total = _clockText(_duration);
    return Container(
      height: 52,
      color: _editorBg,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          children: [
            ValueListenableBuilder<double>(
              valueListenable: _time,
              builder: (_, t, __) => RichText(
                text: TextSpan(
                  style: const TextStyle(fontFamily: kUiFont, fontSize: 13),
                  children: [
                    TextSpan(text: _clockText(t), style: const TextStyle(color: Colors.white)),
                    TextSpan(text: ' / $total', style: const TextStyle(color: Colors.white54)),
                  ],
                ),
              ),
            ),
            const Spacer(),
            ValueListenableBuilder<bool>(
              valueListenable: _playing,
              builder: (_, playing, __) => GestureDetector(
                onTap: _togglePlay,
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0x14FFFFFF)),
                  child: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      size: 34, color: Colors.white),
                ),
              ),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'تراجع',
              onPressed: _undo.isEmpty ? null : _doUndo,
              icon: const Icon(Icons.undo_rounded),
              color: Colors.white,
              disabledColor: Colors.white24,
            ),
            IconButton(
              tooltip: 'إعادة',
              onPressed: _redo.isEmpty ? null : _doRedo,
              icon: const Icon(Icons.redo_rounded),
              color: Colors.white,
              disabledColor: Colors.white24,
            ),
          ],
        ),
      ),
    );
  }

  Widget _timelineArea() {
    return Container(
      color: _panelBg,
      padding: const EdgeInsets.only(top: 6),
      child: Stack(
        children: [
          Directionality(
            textDirection: TextDirection.ltr,
            child: EditorTimeline(
              key: _timelineKey,
              segments: _segments,
              duration: _duration,
              peaks: _peaks,
              thumbs: _thumbs,
              playhead: _time,
              selectedIndex: _selectedSegment,
              onScrubStart: _onScrubStart,
              onScrub: _onScrub,
              onScrubEnd: _onScrubEnd,
              onSelect: _selectSegment,
              onHandleStart: _onHandleStart,
              onDragHandle: _onDragHandle,
              onHandleEnd: _onHandleEnd,
              onAdd: _addSegmentFlow,
            ),
          ),
          // زر "+" ثابت عطرف مسار الآيات (زي زر الإضافة بـ CapCut).
          Positioned(
            right: 8,
            top: 6 + TimelineMetrics.ayahTop + (TimelineMetrics.ayahH - 36) / 2,
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(9),
              elevation: 3,
              child: InkWell(
                borderRadius: BorderRadius.circular(9),
                onTap: _addSegmentFlow,
                child: const SizedBox(
                  width: 36,
                  height: 36,
                  child: Icon(Icons.add_rounded, color: Colors.black, size: 26),
                ),
              ),
            ),
          ),
          if (_peaks == null)
            const Positioned(
              left: 10,
              top: 6 + TimelineMetrics.audioTop + 6,
              child: SizedBox(
                  width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
        ],
      ),
    );
  }

  int get _reviewCount => [
        for (final s in _segments)
          if ((s.needsReview || s.inferred) && s.kind != SegmentKind.istiadha) s
      ].length;

  /// شريط الأدوات السفلي: أدوات عامة، أو أدوات الآية المحددة (زي CapCut).
  Widget _toolbar() {
    final sel = _selectedSegment;
    final hasSel = sel != null && sel < _segments.length;
    final items = <Widget>[];
    if (hasSel) {
      final s = _segments[sel];
      items.addAll([
        _ToolButton(
          icon: Icons.chevron_right_rounded,
          label: 'رجوع',
          onTap: () => _selectSegment(null),
          dim: true,
        ),
        _ToolButton(icon: Icons.swap_horiz_rounded, label: 'تغيير الآية', onTap: () => _changeAyahFlow(sel)),
        if (s.isAyah)
          _ToolButton(icon: Icons.call_split_rounded, label: 'تقسيم', onTap: _openSplit),
        _ToolButton(icon: Icons.tune_rounded, label: 'التوقيت', onTap: () => _openTool(_Tool.details)),
        if (s.isVisible) ...[
          _ToolButton(icon: _Tool.fonts.icon, label: 'خطها وحجمها', onTap: () => _openTool(_Tool.fonts)),
          _ToolButton(icon: _Tool.colors.icon, label: 'ألوانها', onTap: () => _openTool(_Tool.colors)),
          _ToolButton(icon: _Tool.elements.icon, label: 'عناصرها', onTap: () => _openTool(_Tool.elements)),
          _ToolButton(icon: _Tool.templates.icon, label: 'قالب لها', onTap: () => _openTool(_Tool.templates)),
          if (_style.segmentStyles.containsKey(sel))
            _ToolButton(
                icon: Icons.format_color_reset_rounded,
                label: 'شكل عام',
                dim: true,
                onTap: _resetAyahStyle),
        ],
        _ToolButton(icon: Icons.play_circle_outline_rounded, label: 'تشغيلها', onTap: () => _playSegment(sel)),
        if (s.needsReview || s.inferred)
          _ToolButton(
              icon: Icons.check_circle_outline_rounded,
              label: 'صح ✓',
              color: AyahColors.review,
              onTap: () => _confirm(sel)),
        if (s.kind == SegmentKind.nonQuran)
          _ToolButton(icon: Icons.edit_note_rounded, label: 'النص', onTap: () => _openTool(_Tool.details))
        else
          _ToolButton(
              icon: Icons.text_snippet_outlined, label: 'نص خاص', onTap: () => _convertToNonQuran(sel)),
        _ToolButton(icon: Icons.skip_previous_rounded, label: 'السابقة', onTap: () => _step(-1)),
        _ToolButton(icon: Icons.skip_next_rounded, label: 'التالية', onTap: () => _step(1)),
        _ToolButton(
            icon: Icons.delete_outline_rounded,
            label: 'حذف',
            color: AyahColors.danger,
            onTap: () => _confirmDelete(sel)),
      ]);
    } else {
      final review = _reviewCount;
      items.addAll([
        _ToolButton(icon: Icons.add_box_outlined, label: 'إضافة', onTap: _addSegmentFlow),
        _ToolButton(icon: _Tool.elements.icon, label: 'العناصر', onTap: () => _openTool(_Tool.elements)),
        _ToolButton(icon: _Tool.fonts.icon, label: 'الخطوط', onTap: () => _openTool(_Tool.fonts)),
        _ToolButton(icon: _Tool.colors.icon, label: 'الألوان', onTap: () => _openTool(_Tool.colors)),
        _ToolButton(icon: _Tool.templates.icon, label: 'القوالب', onTap: () => _openTool(_Tool.templates)),
        if (review > 0)
          _ToolButton(
            icon: Icons.priority_high_rounded,
            label: 'مراجعة',
            badge: review,
            color: AyahColors.review,
            onTap: () => _selectSegment(nextNeedingReview(_segments, after: -1)),
          ),
        _ToolButton(icon: Icons.zoom_in_rounded, label: 'تكبير', onTap: () => _timelineKey.currentState?.zoomBy(1.6)),
        _ToolButton(icon: Icons.zoom_out_rounded, label: 'تصغير', onTap: () => _timelineKey.currentState?.zoomBy(1 / 1.6)),
        if (_hasEdits)
          _ToolButton(icon: Icons.restore_rounded, label: 'الأصل', onTap: _resetEdits, dim: true),
      ]);
    }
    return Container(
      height: 78,
      decoration: const BoxDecoration(
        color: _editorBg,
        border: Border(top: BorderSide(color: Color(0x14FFFFFF))),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        children: items,
      ),
    );
  }

  void _step(int d) {
    final sel = _selectedSegment;
    if (sel == null) return;
    _selectSegment((sel + d).clamp(0, _segments.length - 1));
  }

  Future<void> _confirmDelete(int index) async {
    final ok = await showAyahDialog<bool>(
      context,
      (ctx) => AlertDialog(
        title: const Text('حذف المقطع؟'),
        content: const Text('بتقدر ترجعه بزر التراجع.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AyahColors.danger, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok == true) await _delete(index);
  }

  void _openTool(_Tool t) {
    HapticFeedback.selectionClick();
    setState(() => _tool = t);
  }

  void _closeTool() => setState(() => _tool = null);

  /// اختيار: التعديل على الآية المحددة بس، أو على كل الآيات (الشكل العام).
  Widget _scopeBar() {
    final sel = _selectedSegment!;
    final s = _segments[sel];
    final name = s.isAyah
        ? '${_surahLookup(s.surah ?? 0) ?? 'سورة ${s.surah}'} • ${s.ayah ?? ''}'
        : 'هالمقطع';
    final own = _style.segmentStyles.containsKey(sel);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                    value: false,
                    label: Text('هالآية بس ($name)', maxLines: 1, overflow: TextOverflow.ellipsis)),
                const ButtonSegment(value: true, label: Text('كل الآيات')),
              ],
              selected: {_applyToAll},
              onSelectionChanged: (v) => setState(() => _applyToAll = v.first),
            ),
          ),
          if (own && !_applyToAll)
            IconButton(
              tooltip: 'رجّعها للشكل العام',
              onPressed: _resetAyahStyle,
              icon: const Icon(Icons.format_color_reset_rounded, color: _gold),
            ),
        ],
      ),
    );
  }

  /// فتح أداة التقسيم: بنجيب كلمات الآية المحددة.
  Future<void> _openSplit() async {
    final sel = _selectedSegment;
    if (sel == null || sel >= _segments.length) return;
    final s = _segments[sel];
    if (!s.isAyah || s.surah == null || s.ayah == null) return;
    final text = await _text();
    if (!mounted) return;
    setState(() {
      _splitWords = ayahWords(text, s.surah!, s.ayah!);
      _tool = _Tool.split;
    });
  }

  /// تطبيق حدود التقسيم (عدد الكلمات قبل كل حد) على آية المقطع المحدد.
  Future<void> _applyCuts(List<int> cuts) async {
    final sel = _selectedSegment;
    if (sel == null || sel >= _segments.length) return;
    final text = await _text();
    if (!mounted || sel >= _segments.length) return;
    final hadStyle = _groupOf(sel).map((i) => _style.segmentStyles[i]).whereType<OverlayStyle>().firstOrNull;
    final e = splitAyahAtWords(text, _segments, sel, cuts);
    _applyEdit(e, saveNow: true);
    // الشكل الخاص بالآية بيشمل كل أجزائها الجديدة.
    if (hadStyle != null && _selectedSegment != null) {
      final styles = {..._style.segmentStyles};
      for (final i in _groupOf(_selectedSegment!)) {
        styles[i] = hadStyle;
      }
      setState(() => _style = _style.copyWith(segmentStyles: styles));
      _saveEdits();
    }
    HapticFeedback.selectionClick();
  }

  /// لوحة التقسيم: كلمات الآية، وبينها فواصل بتنكبس لتقسم السطر هون.
  Widget _splitPanel() {
    final sel = _selectedSegment;
    if (sel == null || sel >= _segments.length || !_segments[sel].isAyah) {
      return const _Note('اختار آية من الخط الزمني أول.');
    }
    final words = _splitWords;
    if (words.isEmpty) return const Center(child: GoldLoader());
    final cuts = wordCutsAt(_segments, sel).toSet();
    final parts = cuts.length + 1;
    // رقم الجزء (من 0) لكل كلمة، عشان نلوّن الأجزاء.
    int partOf(int w) => cuts.where((c) => c <= w).length;
    const partColors = [Color(0xFFDDB45C), Color(0xFF52C7B8), Color(0xFFE8A0BF), Color(0xFF9DB7F5)];
    void toggle(int c) {
      final next = {...cuts};
      if (!next.remove(c)) next.add(c);
      _applyCuts(next.toList()..sort());
    }

    void every(int n) => _applyCuts([for (var c = n; c < words.length; c += n) c]);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: GoldOutlineButton(
                label: 'الآية كاملة',
                icon: Icons.notes_rounded,
                height: 44,
                onPressed: cuts.isEmpty ? null : () => _applyCuts(const []),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: _gold.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Text(parts == 1 ? 'سطر واحد' : '$parts أسطر',
                  style: const TextStyle(fontFamily: kUiFont, color: _gold, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        const _Note('اكبس على الفاصل بين كلمتين لتبلّش سطر جديد من هون (وكبسة ثانية بتشيله). '
            'كل سطر بيصير مقطع لحاله على الخط الزمني، وبتظبط وقته بالمقبضين.'),
        const SizedBox(height: 6),
        Wrap(
          textDirection: TextDirection.rtl,
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: 10,
          children: [
            for (var w = 0; w < words.length; w++) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: partColors[partOf(w) % partColors.length].withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: partColors[partOf(w) % partColors.length].withValues(alpha: 0.6)),
                ),
                child: Text(words[w],
                    style: const TextStyle(
                        fontFamily: 'Amiri Quran', fontSize: 19, height: 1.9, color: Colors.white)),
              ),
              if (w < words.length - 1)
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => toggle(w + 1),
                  child: SizedBox(
                    width: 26,
                    height: 44,
                    child: Center(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        width: cuts.contains(w + 1) ? 5 : 2,
                        height: cuts.contains(w + 1) ? 36 : 20,
                        decoration: BoxDecoration(
                          color: cuts.contains(w + 1) ? _gold : Colors.white24,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ],
        ),
        const SizedBox(height: 14),
        const Text('تقسيم سريع', style: TextStyle(fontFamily: kUiFont, color: Colors.white70)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final n in [2, 3, 4, 5, 6])
              if (n < words.length)
                ActionChip(label: Text('كل $n كلمات'), onPressed: () => every(n)),
          ],
        ),
      ],
    );
  }

  /// لوحة الأداة (مكان الخط الزمني) بعنوان وزر ✓.
  Widget _toolPanel(_Tool t) {
    final maxH = MediaQuery.sizeOf(context).height * 0.42;
    Widget body;
    switch (t) {
      case _Tool.elements:
        body = _elementsTab();
      case _Tool.fonts:
        body = _fontsTab();
      case _Tool.colors:
        body = _colorsTab();
      case _Tool.templates:
        body = _templatesTab();
      case _Tool.split:
        body = _splitPanel();
      case _Tool.details:
        final sel = _selectedSegment;
        body = sel == null || sel >= _segments.length
            ? const _Note('اختار آية من الخط الزمني أول.')
            : SegmentDetailPanel(
                segment: _segments[sel],
                index: sel,
                count: _segments.length,
                playhead: _time,
                surahName: (n) => _surahLookup(n) ?? 'سورة $n',
                scales: _can ? _segmentScalesFor(sel) : const {},
                hasOwnScales: _style.segmentScales.containsKey(sel),
                onBounds: (a, b) => _onBounds(sel, a, b),
                onChangeAyah: () => _changeAyahFlow(sel),
                onConvertToNonQuran: () => _convertToNonQuran(sel),
                onUserText: (x) => _onUserText(sel, x),
                onConfirm: () => _confirm(sel),
                onDelete: () => _confirmDelete(sel),
                onScale: (e, v) => _setSegmentScale(sel, e, v),
                onResetScales: () => _resetSegmentScales(sel),
                onPlay: () => _playSegment(sel),
                onStep: (d) => _step(d),
                onClose: _closeTool,
              );
    }
    return Container(
      constraints: BoxConstraints(maxHeight: maxH, minHeight: 200),
      decoration: const BoxDecoration(
        color: _panelBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        border: Border(top: BorderSide(color: Color(0x40DDB45C))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 50,
            child: Row(
              children: [
                const SizedBox(width: 16),
                Icon(t.icon, color: _gold, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(t.label,
                      style: const TextStyle(
                          fontFamily: kUiFont, fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
                ),
                IconButton(
                  tooltip: 'تم',
                  onPressed: _closeTool,
                  icon: Container(
                    width: 34,
                    height: 34,
                    decoration: const BoxDecoration(shape: BoxShape.circle, gradient: AyahColors.goldVertical),
                    child: const Icon(Icons.check_rounded, color: AyahColors.ink, size: 22),
                  ),
                ),
                const SizedBox(width: 6),
              ],
            ),
          ),
          if (_selectedSegment != null &&
              _selectedSegment! < _segments.length &&
              _segments[_selectedSegment!].isVisible &&
              t != _Tool.details &&
              t != _Tool.split)
            _scopeBar(),
          if (!_can && t != _Tool.templates && t != _Tool.details && t != _Tool.split)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: _Note('التخصيص (العناصر والخطوط والألوان) بالخطط المدفوعة. بالمجاني: القوالب الجاهزة.'),
            ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: body,
            ),
          ),
        ],
      ),
    );
  }

  // --------------------------- تبويب العناصر ---------------------------

  Widget _elementsTab() {
    final layout = _es.layout;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Note('اسحب أي عنصر بإصبعك على الفيديو لمكان تاني (وقّف على نص ظاهر). '
            'المكان نسبي، فنفس التصميم بيطلع على عمودي وأفقي ومربّع.'),
        for (final e in OverlayElement.values) ...[
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            value: layout.isEnabled(e),
            onChanged: _can && e.available
                ? (v) => _setPlacement(e, (p) => p.copyWith(enabled: v))
                : null,
            title: Text(e.label),
            subtitle: e.available
                ? (layout[e].isDetached ? const Text('بمكان مخصّص') : null)
                : const Text('الترجمة بتتفعّل يوم 12 (المصدر والنص لسا)'),
            secondary: layout[e].isDetached && layout.isEnabled(e)
                ? IconButton(
                    tooltip: 'رجّع للمكان الافتراضي',
                    icon: const Icon(Icons.restart_alt, color: _gold),
                    onPressed: _can
                        ? () => _setPlacement(e, (p) => p.copyWith(clearAnchor: true))
                        : null,
                  )
                : null,
          ),
          if (e == OverlayElement.reciter && layout.isEnabled(e))
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: TextField(
                controller: _reciterCtl,
                enabled: _can,
                textDirection: TextDirection.rtl,
                decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    labelText: 'اسم القارئ (بتكتبه إنت)'),
                onChanged: (v) => setState(() => _style = _style.copyWith(reciterName: v)),
              ),
            ),
        ],
        if (layout.detached.isNotEmpty)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: _can
                  ? () => _setStyle(_es.copyWith(
                      layout: OverlayLayout.of({
                        for (final e in OverlayElement.values)
                          e: layout[e].copyWith(clearAnchor: true),
                      })))
                  : null,
              icon: const Icon(Icons.restart_alt),
              label: const Text('رجّع كل العناصر لأماكنها'),
            ),
          ),
      ],
    );
  }

  // ---------------------------- تبويب الخطوط ----------------------------

  Widget _fontsTab() {
    final layout = _es.layout;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('خط الآية'),
        SegmentedButton<AyahFont>(
          showSelectedIcon: false,
          segments: [
            for (final f in AyahFont.values) ButtonSegment(value: f, label: Text(f.label)),
          ],
          selected: {_es.font},
          onSelectionChanged: _can ? (s) => _setStyle(_es.copyWith(font: s.first)) : null,
        ),
        const SizedBox(height: 8),
        const Text('خط التفسير والعناصر النصية'),
        SegmentedButton<TafsirFont>(
          showSelectedIcon: false,
          segments: [
            for (final f in TafsirFont.values) ButtonSegment(value: f, label: Text(f.label)),
          ],
          selected: {_es.tafsirFont},
          onSelectionChanged:
              _can ? (s) => _setStyle(_es.copyWith(tafsirFont: s.first)) : null,
        ),
        const SizedBox(height: 8),
        const Text('عرض التفسير للآية المقسومة'),
        SegmentedButton<TafsirMode>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: TafsirMode.split, label: Text('مقسوم')),
            ButtonSegment(value: TafsirMode.fullUnderEachPart, label: Text('كامل تحت كل جزء')),
          ],
          selected: {_es.tafsirMode},
          onSelectionChanged:
              _can ? (s) => _setStyle(_es.copyWith(tafsirMode: s.first)) : null,
        ),
        const SizedBox(height: 8),
        ValueListenableBuilder<int?>(
          valueListenable: _segIdx,
          builder: (_, __, ___) => _sizesSection(),
        ),
      ],
    );
  }

  /// قسم الأحجام: زرين: (1) المقاطع: كل المقاطع مع بعض / المقطع الظاهر لحاله،
  /// (2) العناصر: كل العناصر مع بعض / العنصر لحاله.
  Widget _sizesSection() {
    final seg = _targetSeg;
    final idx = _segIdx.value;
    final cur = idx == null
        ? null
        : _timeline.items.where((i) => i.index == idx).firstOrNull?.segment;
    final curName = cur == null
        ? 'ما في نص ظاهر هلأ'
        : '${_surahLookup(cur.surah ?? 0) ?? 'سورة ${cur.surah}'} • ${cur.ayah ?? ''}'
            '${cur.partCount > 1 ? ' (جزء ${cur.part}/${cur.partCount})' : ''}';
    final hasOverride = seg != null && _style.segmentScales.containsKey(seg);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(child: Text('الأحجام')),
            if (_scopeSeg == null)
            FilterChip(
              avatar: Icon(_perSegment ? Icons.looks_one_outlined : Icons.layers, size: 18),
              label: Text(_perSegment ? 'كل مقطع لحاله' : 'كل المقاطع مع بعض'),
              selected: _perSegment,
              onSelected: _can ? (v) => setState(() => _perSegment = v) : null,
            ),
            const SizedBox(width: 6),
            FilterChip(
              avatar: Icon(_linkSizes ? Icons.link : Icons.link_off, size: 18),
              label: Text(_linkSizes ? 'كل العناصر مع بعض' : 'عنصر لحاله'),
              selected: _linkSizes,
              onSelected: _can ? (v) => setState(() => _linkSizes = v) : null,
            ),
          ],
        ),
        if (_perSegment && _scopeSeg == null)
          Row(
            children: [
              Expanded(
                child: Text('المقطع الظاهر: $curName',
                    style: const TextStyle(fontSize: 12, color: _gold)),
              ),
              if (hasOverride)
                TextButton(
                  onPressed: () => _resetSegment(seg),
                  child: const Text('رجّعه للحجم العام'),
                ),
            ],
          ),
        _Note(_scopeSeg != null
            ? 'الحجم هون لهالآية بس. بدك الكل؟ اختار "كل الآيات" فوق.'
            : _perSegment
            ? 'الحجم هون بيتغيّر للمقطع الظاهر بس (شغّل أو حرّك الفيديو لمقطع ثاني '
                'لتغيّر حجمه). المقاطع الباقية بتضل بحجمها.'
            : 'الحجم هون بيطبّق على كل المقاطع (كل الآيات، كل التفاسير...) مع بعض.'),
        const _Note('اضغط على عنصر بالفيديو لتحديده، وبعدين اسحب من أي مكان لتحريكه '
            'أو استعمل إصبعين لتكبيره وتصغيره.'),
        for (final e in OverlayElement.values)
          if (_es.layout.isEnabled(e) && e.available)
            Row(
              children: [
                SizedBox(width: 92, child: Text(e.label, style: const TextStyle(fontSize: 12))),
                Expanded(
                  child: Slider(
                    value: _scaleOf(e, seg),
                    min: ElementPlacement.minScale,
                    max: ElementPlacement.maxScale,
                    divisions: 20,
                    label: '${(_scaleOf(e, seg) * 100).round()}٪',
                    onChanged: _can && !_noSegment ? (v) => _scaleTo(e, v) : null,
                  ),
                ),
                SizedBox(
                    width: 40,
                    child: Text('${(_scaleOf(e, seg) * 100).round()}٪',
                        style: const TextStyle(fontSize: 12))),
              ],
            ),
      ],
    );
  }

  // ----------------------------- تبويب الألوان -----------------------------

  Widget _colorsTab() {
    final bg = _es.background;
    final shadowOn = _es.shadowStrength > 0;
    final opposite = _es.color == OverlayTextColor.white ? 'أسود' : 'أبيض';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // لون النص: أبيض أو أسود بس (قرار أنس).
        SegmentedButton<OverlayTextColor>(
          showSelectedIcon: false,
          segments: [
            for (final c in OverlayTextColor.values)
              ButtonSegment(
                value: c,
                icon: Icon(Icons.circle, color: c.text, shadows: const [
                  Shadow(color: Colors.grey, blurRadius: 2),
                ]),
                label: Text('نص ${c.label}'),
              ),
          ],
          selected: {_es.color},
          onSelectionChanged: _can
              ? (s) {
                  _setStyle(_es.copyWith(color: s.first));
                  setState(() {
                    _colorTouched = true;
                    _colorNote = null;
                  });
                }
              : null,
        ),
        if (_colorNote != null) _Note(_colorNote!),
        const SizedBox(height: 4),
        const _Note('الألوان: أبيض أو أسود بس هلأ. الظل والخلفية بلون عكس النص.'),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          value: shadowOn,
          onChanged: _can
              ? (v) => _setStyle(_es.copyWith(shadowStrength: v ? _lastShadow : 0))
              : null,
          title: Text('ظل $opposite للنص'),
        ),
        Row(
          children: [
            const SizedBox(width: 74, child: Text('شدة الظل', style: TextStyle(fontSize: 12))),
            Expanded(
              child: Slider(
                value: _es.shadowStrength,
                divisions: 20,
                label: '${(_es.shadowStrength * 100).round()}٪',
                onChanged: _can
                    ? (v) {
                        if (v > 0) _lastShadow = v;
                        _setStyle(_es.copyWith(shadowStrength: v));
                      }
                    : null,
              ),
            ),
            SizedBox(
                width: 44,
                child: Text('${(_es.shadowStrength * 100).round()}٪',
                    style: const TextStyle(fontSize: 12))),
          ],
        ),
        const _Note('0٪ = بدون ظل. ملاحظة: الظل بلون عكس النص، فالظل الأبيض '
            'ما بيبيّن فوق خلفية بيضا (والأسود فوق خلفية سودا).'),
        const SizedBox(height: 4),
        const Text('خلفية شفافة ورا النص'),
        SegmentedButton<OverlayBackgroundMode>(
          showSelectedIcon: false,
          segments: [
            for (final m in OverlayBackgroundMode.values)
              ButtonSegment(value: m, label: Text(m.label)),
          ],
          selected: {bg.mode},
          onSelectionChanged:
              _can ? (s) => _setStyle(_es.copyWith(background: bg.copyWith(mode: s.first))) : null,
        ),
        if (bg.mode != OverlayBackgroundMode.none)
          Row(
            children: [
              const SizedBox(width: 74, child: Text('الشفافية', style: TextStyle(fontSize: 12))),
              Expanded(
                child: Slider(
                  value: bg.opacity,
                  max: OverlayBackground.maxOpacity,
                  divisions: 18,
                  label: '${(bg.opacity * 100).round()}٪',
                  onChanged: _can
                      ? (v) => _setStyle(_es.copyWith(background: bg.copyWith(opacity: v)))
                      : null,
                ),
              ),
              SizedBox(
                  width: 44,
                  child: Text('${(bg.opacity * 100).round()}٪',
                      style: const TextStyle(fontSize: 12))),
            ],
          ),
      ],
    );
  }

  // ---------------------------- تبويب القوالب ----------------------------

  Widget _templatesTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('قوالب جاهزة'),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final t in builtInTemplates)
              ActionChip(
                label: Text(t.name),
                onPressed: () => _apply(t),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            const Expanded(child: Text('قوالبي')),
            TextButton.icon(
              onPressed: _can ? _saveCurrent : null,
              icon: const Icon(Icons.add),
              label: const Text('حفظ الشكل الحالي'),
            ),
          ],
        ),
        if (!_can)
          const _Note('حفظ قوالبك بالخطط المدفوعة.')
        else if (_templates.userTemplates.isEmpty)
          const _Note('ما عندك قوالب محفوظة بعد.'),
        for (final t in _templates.userTemplates)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(t.name),
            onTap: _can ? () => _apply(t) : null,
            trailing: Wrap(
              children: [
                IconButton(
                  tooltip: 'تحديث بالشكل الحالي',
                  icon: const Icon(Icons.save_as, size: 20),
                  onPressed: _can ? () => _updateTemplate(t) : null,
                ),
                IconButton(
                  tooltip: 'تعديل الاسم',
                  icon: const Icon(Icons.edit, size: 20),
                  onPressed: _can ? () => _renameTemplate(t) : null,
                ),
                IconButton(
                  tooltip: 'حذف',
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: _can ? () => _deleteTemplate(t) : null,
                ),
              ],
            ),
          ),
      ],
    );
  }

  void _apply(OverlayTemplate t) {
    if (_scopeSeg != null) {
      _setStyle(t.applyTo(_es));
      setState(() => _selected = null);
      return;
    }
    _checkpoint();
    setState(() {
      _style = t.applyTo(_style).copyWith(segmentStyles: _style.segmentStyles);
      // قالب المستخدم بيرجّع لونه؛ والجاهز بيحافظ على اللون الحالي.
      if (!t.builtIn) _colorTouched = true;
      if (_es.shadowStrength > 0) _lastShadow = _es.shadowStrength;
      _colorNote = null;
      _selected = null;
    });
    // القالب بيمسح أحجام كل مقطع (قرار يوم 9): الملف المحفوظ لازم يتبعه.
    if (_hasEdits) _saveEdits();
  }

  Future<String?> _askName(String title, {String initial = ''}) async {
    final c = TextEditingController(text: initial);
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text(title),
          content: TextField(
            controller: c,
            autofocus: true,
            textDirection: TextDirection.rtl,
            decoration: const InputDecoration(hintText: 'اسم القالب'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, c.text), child: const Text('حفظ')),
          ],
        ),
      ),
    );
    c.dispose();
    return r;
  }

  Future<void> _saveCurrent() async {
    final name = await _askName('حفظ كقالب');
    if (name == null || !mounted) return;
    await _templates.add(name, _es);
    if (mounted) setState(() {});
  }

  Future<void> _updateTemplate(OverlayTemplate t) async {
    await _templates.updateStyle(t.id, _es);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('تحدّث القالب "${t.name}"')));
  }

  Future<void> _renameTemplate(OverlayTemplate t) async {
    final name = await _askName('تعديل الاسم', initial: t.name);
    if (name == null || !mounted) return;
    await _templates.rename(t.id, name);
    if (mounted) setState(() {});
  }

  Future<void> _deleteTemplate(OverlayTemplate t) async {
    await _templates.delete(t.id);
    if (mounted) setState(() {});
  }
}

/// زر بشريط الأدوات السفلي (أيقونة + اسم)، زي CapCut.
class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  final int? badge;
  final bool dim;

  const _ToolButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
    this.badge,
    this.dim = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? (dim ? Colors.white60 : Colors.white);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: SizedBox(
        width: 70,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(icon, color: c, size: 26),
                if (badge != null)
                  Positioned(
                    top: -6,
                    left: -10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                          color: AyahColors.review, borderRadius: BorderRadius.circular(10)),
                      child: Text('$badge',
                          style: const TextStyle(
                              fontFamily: kUiFont, fontSize: 10, fontWeight: FontWeight.w700, color: Colors.black)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontFamily: kUiFont, fontSize: 11.5, color: c)),
          ],
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  final String text;
  const _Note(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(text, style: const TextStyle(fontSize: 11, color: Colors.white60)),
      );
}

/// إطار ذهبي حوالين العنصر المختار (بإحداثيات الفيديو).
class _SelectionPainter extends CustomPainter {
  final Rect? Function() rect;
  final double unit;

  _SelectionPainter({required Listenable repaint, required this.rect, required this.unit})
      : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    final r = rect();
    if (r == null) return;
    final paint = Paint()
      ..color = _gold
      ..style = PaintingStyle.stroke
      ..strokeWidth = unit * 0.004 < 2 ? 2 : unit * 0.004;
    canvas.drawRRect(
        RRect.fromRectAndRadius(r.inflate(unit * 0.01), Radius.circular(unit * 0.012)),
        paint);
  }

  @override
  bool shouldRepaint(covariant _SelectionPainter old) => true;
}

/// خطوط الإرشاد: وسط الفيديو بالذهبي، والمحاذاة مع عناصر ثانية بالسماوي.
class _GuidesPainter extends CustomPainter {
  final ValueListenable<List<SnapGuide>> guides;
  final double unit;

  _GuidesPainter({required this.guides, required this.unit}) : super(repaint: guides);

  @override
  void paint(Canvas canvas, Size size) {
    final w = unit * 0.003 < 1.5 ? 1.5 : unit * 0.003;
    for (final g in guides.value) {
      final paint = Paint()
        ..color = g.kind == GuideKind.center ? _gold : Colors.cyanAccent
        ..strokeWidth = w;
      if (g.axis == GuideAxis.vertical) {
        canvas.drawLine(Offset(g.position, 0), Offset(g.position, size.height), paint);
      } else {
        canvas.drawLine(Offset(0, g.position), Offset(size.width, g.position), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GuidesPainter old) => true;
}
