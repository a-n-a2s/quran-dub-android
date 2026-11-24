import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../data/quran_database.dart';
import '../export/export_request.dart';
import '../overlay/ayah_font.dart';
import '../overlay/overlay_frame.dart';
import '../overlay/overlay_layout.dart';
import '../overlay/overlay_style.dart';
import '../overlay/overlay_templates.dart';
import '../overlay/overlay_timeline.dart';
import '../overlay/playback_clock.dart';
import '../pipeline/project_input.dart';
import '../pipeline/recitation_segment.dart';
import '../platform/video_info.dart';
import 'export_screen.dart';

// هوية التطبيق (أخضر غامق + ذهبي): بشكل مبسّط لحد يوم 22 (تلميع الواجهات).
const Color _green = Color(0xFF0E2F24);
const Color _greenLight = Color(0xFF17432F);
const Color _gold = Color(0xFFD9B55E);

ThemeData _editorTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: _green,
    colorScheme: base.colorScheme.copyWith(
      primary: _gold,
      onPrimary: Colors.black,
      secondary: _gold,
      surface: _greenLight,
      secondaryContainer: const Color(0xFF2B5A43),
      onSecondaryContainer: Colors.white,
    ),
    appBarTheme: const AppBarTheme(
        backgroundColor: _green, foregroundColor: Colors.white, elevation: 0),
    sliderTheme: base.sliderTheme.copyWith(
        activeTrackColor: _gold, thumbColor: _gold, inactiveTrackColor: Colors.white24),
  );
}

enum _Tab {
  elements('عناصر'),
  fonts('خطوط'),
  colors('ألوان'),
  templates('قوالب');

  final String label;
  const _Tab(this.label);
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

  /// الصلاحيات حسب الخطة (يوم 16–18 بيربطها). بالمجاني: قوالب جاهزة بس.
  final EditorCapabilities capabilities;

  const OverlayEditorScreen({
    super.key,
    required this.input,
    required this.segments,
    this.initialTafsirMode = TafsirMode.split,
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

  late OverlayTimeline _timeline;
  late OverlayStyle _style;

  /// اللون اختاره المستخدم بإيده → ما بنغيّره تلقائياً.
  bool _colorTouched = false;
  String? _colorNote;
  double _lastShadow = OverlayStyle.defaultShadowStrength;

  Map<int, String> _surahNames = const {};
  TemplateStore _templates = TemplateStore.memory();
  String? _error;
  bool _ready = false;

  _Tab _tab = _Tab.elements;
  OverlayElement? _selected;

  // سحب العناصر: أبعاد الفيديو بالبكسل، ومفاتيح لقياس مكان كل عنصر.
  final GlobalKey _videoKey = GlobalKey(debugLabel: 'editor-video');
  final Map<OverlayElement, GlobalKey> _keys = {
    for (final e in OverlayElement.values) e: GlobalKey(debugLabel: e.name),
  };
  OverlayElement? _dragEl;
  Offset _dragStart = Offset.zero;
  double _baseCx = 0, _baseTop = 0;

  final TextEditingController _reciterCtl = TextEditingController();

  double get _wallSeconds => _wall.elapsedMicroseconds / 1e6;
  int get _w => widget.input.videoInfo.rotatedWidth;
  int get _h => widget.input.videoInfo.rotatedHeight;
  bool get _can => widget.capabilities.canCustomize;

  @override
  void initState() {
    super.initState();
    _style = OverlayStyle(tafsirMode: widget.initialTafsirMode);
    final info = widget.input.videoInfo;
    _timeline = OverlayTimeline.build(widget.segments,
        videoDuration: info.durationMs > 0 ? info.durationSeconds : null);
    _ticker = createTicker((_) {
      _time.value = _clock.now(_wallSeconds);
    })..start();
    _init();
    _autoPickColor();
    _loadSurahNames();
    _openTemplates();
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

  Future<void> _openExport() async {
    final all = [_video!, if (_audio != null) _audio!];
    await Future.wait([for (final c in all) c.pause()]);
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ExportScreen(
        request: ExportRequest(
          input: widget.input,
          segments: widget.segments,
          style: _style,
          surahNames: _surahNames,
        ),
      ),
    ));
  }

  @override
  void dispose() {
    _ticker.dispose();
    _master?.removeListener(_onPlayerUpdate);
    _video?.dispose();
    _audio?.dispose();
    _time.dispose();
    _reciterCtl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // تعديل الشكل
  // ---------------------------------------------------------------------

  void _setStyle(OverlayStyle s) => setState(() => _style = s);

  void _setPlacement(OverlayElement e, ElementPlacement Function(ElementPlacement) f) =>
      _setStyle(_style.copyWith(layout: _style.layout.update(e, f)));

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
      ..._style.layout.detached.reversed,
      ...OverlayElement.values.reversed,
    ];
    for (final e in order) {
      if (!_style.layout.isEnabled(e)) continue;
      final r = _rectOf(e);
      if (r != null && r.inflate(slop).contains(p)) return e;
    }
    return null;
  }

  void _onTapUp(TapUpDetails d) {
    final p = _toVideo(d.globalPosition);
    setState(() => _selected = p == null ? null : _hit(p));
  }

  void _onPanStart(DragStartDetails d) {
    if (!_can) return;
    final p = _toVideo(d.globalPosition);
    if (p == null) return;
    final hit = _hit(p);
    if (hit == null) return;
    final r = _rectOf(hit);
    if (r == null) return;
    final a = _style.layout[hit].anchor;
    _dragEl = hit;
    _dragStart = p;
    _baseCx = a != null ? a.cx * _w : r.center.dx;
    _baseTop = a != null ? a.top * _h : r.top;
    setState(() => _selected = hit);
  }

  void _onPanUpdate(DragUpdateDetails d) {
    final e = _dragEl;
    final p = _toVideo(d.globalPosition);
    if (e == null || p == null) return;
    final anchor = anchorFromPixels(
        _baseCx + (p.dx - _dragStart.dx), _baseTop + (p.dy - _dragStart.dy), _w, _h);
    _setPlacement(e, (pl) => pl.copyWith(anchor: anchor));
  }

  void _onPanEnd([Object? _]) => _dragEl = null;

  // ---------------------------------------------------------------------
  // البناء
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: _editorTheme(),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('المحرر'),
            actions: [
              // التصدير بنفس الشكل بالمعاينة (OverlayStyle كامل).
              TextButton.icon(
                onPressed: _ready ? _openExport : null,
                icon: const Icon(Icons.ios_share, color: _gold),
                label: const Text('تصدير', style: TextStyle(color: _gold)),
              ),
            ],
          ),
          body: _error != null
              ? Padding(padding: const EdgeInsets.all(16), child: Text(_error!))
              : !_ready
                  ? const Center(child: CircularProgressIndicator())
                  : _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    final w = _w, h = _h;
    final unit = (w < h ? w : h).toDouble();
    final master = _master!;
    return Column(
      children: [
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: _onTapUp,
            onPanStart: _onPanStart,
            onPanUpdate: _onPanUpdate,
            onPanEnd: _onPanEnd,
            onPanCancel: _onPanEnd,
            child: Container(
              color: Colors.black,
              alignment: Alignment.center,
              // مساحة الفيديو الحقيقية بالبكسل (نفس تصدير يوم 8) مصغّرة
              // بالـ FittedBox: النص بيطلع بنفس النسب على كل الأبعاد.
              child: FittedBox(
                fit: BoxFit.contain,
                child: SizedBox(
                  key: _videoKey,
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
                          style: _style,
                          surahName: _surahLookup,
                          elementKeys: _keys,
                        ),
                      ),
                      // إطار ذهبي حوالين العنصر المختار.
                      IgnorePointer(
                        child: CustomPaint(
                          painter: _SelectionPainter(
                            repaint: _time,
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
        // اللوحة بتاخد لحد 48% من الشاشة وبتنسحب (الجوالات الصغيرة).
        ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.48),
          child: _panel(master),
        ),
      ],
    );
  }

  Widget _panel(VideoPlayerController master) {
    final dur = master.value.duration;
    final pos = master.value.position;
    final maxMs = dur.inMilliseconds.toDouble();
    return Material(
      color: _greenLight,
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconButton.filled(
                    onPressed: _togglePlay,
                    icon: Icon(master.value.isPlaying ? Icons.pause : Icons.play_arrow),
                  ),
                  Expanded(
                    child: Slider(
                      value: pos.inMilliseconds.toDouble().clamp(0, maxMs > 0 ? maxMs : 1),
                      max: maxMs > 0 ? maxMs : 1,
                      onChanged: (v) => _seek(Duration(milliseconds: v.round())),
                    ),
                  ),
                  Text('${_fmt(pos)} / ${_fmt(dur)}',
                      style: const TextStyle(fontSize: 12)),
                ],
              ),
              _cueLabel(),
              if (_audio != null)
                const Text('الصوت من ملف التلاوة المنفصل (صوت الفيديو مكتوم).',
                    style: TextStyle(fontSize: 11, color: Colors.white60)),
              const SizedBox(height: 6),
              SegmentedButton<_Tab>(
                showSelectedIcon: false,
                segments: [
                  for (final t in _Tab.values)
                    ButtonSegment(value: t, label: Text(t.label)),
                ],
                selected: {_tab},
                onSelectionChanged: (s) => setState(() => _tab = s.first),
              ),
              const SizedBox(height: 8),
              if (!_can && _tab != _Tab.templates)
                const _Note('التخصيص (العناصر والخطوط والألوان) بالخطط المدفوعة. '
                    'بالمجاني: القوالب الجاهزة.'),
              switch (_tab) {
                _Tab.elements => _elementsTab(),
                _Tab.fonts => _fontsTab(),
                _Tab.colors => _colorsTab(),
                _Tab.templates => _templatesTab(),
              },
            ],
          ),
        ),
      ),
    );
  }

  String _fmt(Duration d) {
    final s = d.inSeconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  Widget _cueLabel() => ValueListenableBuilder<double>(
        valueListenable: _time,
        builder: (_, t, __) {
          final c = _timeline.cueAt(t);
          final label = c == null ? 'ما في نص ظاهر هلأ' : c.item.segment.describe();
          return Text(label,
              style: const TextStyle(fontSize: 11, color: Colors.white60),
              maxLines: 1,
              overflow: TextOverflow.ellipsis);
        },
      );

  // --------------------------- تبويب العناصر ---------------------------

  Widget _elementsTab() {
    final layout = _style.layout;
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
                onChanged: (v) => _setStyle(_style.copyWith(reciterName: v)),
              ),
            ),
        ],
        if (layout.detached.isNotEmpty)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: _can
                  ? () => _setStyle(_style.copyWith(
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
    final layout = _style.layout;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('خط الآية'),
        SegmentedButton<AyahFont>(
          showSelectedIcon: false,
          segments: [
            for (final f in AyahFont.values) ButtonSegment(value: f, label: Text(f.label)),
          ],
          selected: {_style.font},
          onSelectionChanged: _can ? (s) => _setStyle(_style.copyWith(font: s.first)) : null,
        ),
        const SizedBox(height: 8),
        const Text('خط التفسير والعناصر النصية'),
        SegmentedButton<TafsirFont>(
          showSelectedIcon: false,
          segments: [
            for (final f in TafsirFont.values) ButtonSegment(value: f, label: Text(f.label)),
          ],
          selected: {_style.tafsirFont},
          onSelectionChanged:
              _can ? (s) => _setStyle(_style.copyWith(tafsirFont: s.first)) : null,
        ),
        const SizedBox(height: 8),
        const Text('عرض التفسير للآية المقسومة'),
        SegmentedButton<TafsirMode>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: TafsirMode.split, label: Text('مقسوم')),
            ButtonSegment(value: TafsirMode.fullUnderEachPart, label: Text('كامل تحت كل جزء')),
          ],
          selected: {_style.tafsirMode},
          onSelectionChanged:
              _can ? (s) => _setStyle(_style.copyWith(tafsirMode: s.first)) : null,
        ),
        const SizedBox(height: 8),
        const Text('الأحجام (كل عنصر لحاله)'),
        for (final e in OverlayElement.values)
          if (layout.isEnabled(e) && e.available)
            Row(
              children: [
                SizedBox(width: 92, child: Text(e.label, style: const TextStyle(fontSize: 12))),
                Expanded(
                  child: Slider(
                    value: layout[e].scale,
                    min: ElementPlacement.minScale,
                    max: ElementPlacement.maxScale,
                    divisions: 20,
                    label: '${(layout[e].scale * 100).round()}٪',
                    onChanged: _can ? (v) => _setPlacement(e, (p) => p.copyWith(scale: v)) : null,
                  ),
                ),
                SizedBox(
                    width: 40,
                    child: Text('${(layout[e].scale * 100).round()}٪',
                        style: const TextStyle(fontSize: 12))),
              ],
            ),
      ],
    );
  }

  // ----------------------------- تبويب الألوان -----------------------------

  Widget _colorsTab() {
    final bg = _style.background;
    final shadowOn = _style.shadowStrength > 0;
    final opposite = _style.color == OverlayTextColor.white ? 'أسود' : 'أبيض';
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
          selected: {_style.color},
          onSelectionChanged: _can
              ? (s) => setState(() {
                    _style = _style.copyWith(color: s.first);
                    _colorTouched = true;
                    _colorNote = null;
                  })
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
              ? (v) => _setStyle(_style.copyWith(shadowStrength: v ? _lastShadow : 0))
              : null,
          title: Text('ظل $opposite للنص'),
        ),
        Row(
          children: [
            const SizedBox(width: 74, child: Text('شدة الظل', style: TextStyle(fontSize: 12))),
            Expanded(
              child: Slider(
                value: _style.shadowStrength,
                divisions: 20,
                label: '${(_style.shadowStrength * 100).round()}٪',
                onChanged: _can
                    ? (v) {
                        if (v > 0) _lastShadow = v;
                        _setStyle(_style.copyWith(shadowStrength: v));
                      }
                    : null,
              ),
            ),
            SizedBox(
                width: 44,
                child: Text('${(_style.shadowStrength * 100).round()}٪',
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
              _can ? (s) => _setStyle(_style.copyWith(background: bg.copyWith(mode: s.first))) : null,
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
                      ? (v) => _setStyle(_style.copyWith(background: bg.copyWith(opacity: v)))
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
    setState(() {
      _style = t.applyTo(_style);
      // قالب المستخدم بيرجّع لونه؛ والجاهز بيحافظ على اللون الحالي.
      if (!t.builtIn) _colorTouched = true;
      if (_style.shadowStrength > 0) _lastShadow = _style.shadowStrength;
      _colorNote = null;
      _selected = null;
    });
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
    await _templates.add(name, _style);
    if (mounted) setState(() {});
  }

  Future<void> _updateTemplate(OverlayTemplate t) async {
    await _templates.updateStyle(t.id, _style);
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
