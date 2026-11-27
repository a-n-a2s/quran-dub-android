// الخط الزمني على موجة الصوت (يوم 10، المحرر 2): كل المقاطع على خط واحد زي
// برامج المونتاج (كل مقطع كتلة بالنص إلها بداية ونهاية)، فوق موجة الصوت.
//
// - **كبسة على كتلة** بتحددها (وبتفتح لوحة تفاصيلها بالشاشة الأم)، وبيطلع
//   على حدودها **مقبضين كبار** (أهداف لمس 44px) بينسحبوا بالإصبع.
// - السحب **بيلتصق** بحد المقطع الجار (هزّة خفيفة)، زي خطوط الإرشاد
//   بسحب العناصر (يوم 9).
// - **المسطرة فوق**: كبسة أو سحب = تشغيل من هالمكان (scrub).
// - **تكبير/تصغير**: أزرار، أو قرصة بإصبعين فوق الخط.
// - موقع التشغيل (خط أحمر) بيضل ظاهر وقت التشغيل (الخط بيتمرّر لحاله).
//
// الوقت دايماً **من الشمال لليمين** (زي كل برامج المونتاج) حتى بواجهة عربية.
// كل الحدود (ما يتخطى جاره، حد أدنى) بالشاشة الأم (`segment_edits.dart`):
// هون رسم + لمس + التصاق بس.
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../editor/timeline_geometry.dart';
import '../../editor/waveform.dart';
import '../../pipeline/recitation_segment.dart';

const Color _gold = Color(0xFFD9B55E);
const Color _track = Color(0xFF0B271D);
const Color _review = Color(0xFFE8892B);

class SegmentTimelineView extends StatefulWidget {
  final List<RecitationSegment> segments;
  final double duration;
  final WaveformPeaks? peaks;
  final ValueListenable<double> playhead;
  final int? selectedIndex;

  final void Function(double seconds) onSeek;
  final void Function(int? index) onSelect;

  /// سحب حد المقطع [index] ([isStart] = البداية) لـ [seconds] (بعد الالتصاق،
  /// قبل حدود الجيران — الشاشة الأم بتطبّقها).
  final void Function(int index, bool isStart, double seconds) onDragHandle;

  /// خلص السحب (للحفظ).
  final VoidCallback? onDragFinished;

  const SegmentTimelineView({
    super.key,
    required this.segments,
    required this.duration,
    required this.peaks,
    required this.playhead,
    required this.selectedIndex,
    required this.onSeek,
    required this.onSelect,
    required this.onDragHandle,
    this.onDragFinished,
  });

  static const double rulerHeight = 26;
  static const double trackHeight = 84;
  static const double handleWidth = 44;

  @override
  State<SegmentTimelineView> createState() => _SegmentTimelineViewState();
}

class _SegmentTimelineViewState extends State<SegmentTimelineView> {
  double _pps = 60; // بكسل لكل ثانية (مستوى التكبير)
  final ScrollController _scroll = ScrollController();
  double _viewport = 300;

  // قرصة بإصبعين (Listener بدون ما ندخل بمنافسة الإيماءات مع التمرير).
  final Map<int, Offset> _pointers = {};
  double? _pinchStartDist;
  double _pinchStartPps = 60;

  // السحب: القيمة وقت ما بلّش + مجموع الحركة (بدل ما نجمع على قيمة مقصوصة).
  double _dragBase = 0, _dragDx = 0;
  int? _lastSnap;

  TimelineGeometry get _geo => TimelineGeometry(
      durationSeconds: widget.duration <= 0 ? 1 : widget.duration,
      pixelsPerSecond: _pps);

  @override
  void initState() {
    super.initState();
    widget.playhead.addListener(_follow);
  }

  @override
  void didUpdateWidget(covariant SegmentTimelineView old) {
    super.didUpdateWidget(old);
    if (old.playhead != widget.playhead) {
      old.playhead.removeListener(_follow);
      widget.playhead.addListener(_follow);
    }
  }

  @override
  void dispose() {
    widget.playhead.removeListener(_follow);
    _scroll.dispose();
    super.dispose();
  }

  /// موقع التشغيل طلع برا الشاشة (وقت التشغيل) → منمرّر الخط.
  void _follow() {
    if (!_scroll.hasClients || _pointers.isNotEmpty) return;
    final x = _geo.xOfSeconds(widget.playhead.value);
    final off = _scroll.offset;
    if (x < off || x > off + _viewport - 24) {
      final to = (x - _viewport * 0.25)
          .clamp(0.0, _scroll.position.maxScrollExtent)
          .toDouble();
      _scroll.jumpTo(to);
    }
  }

  void _zoomBy(double f, {double? focusX}) {
    final old = _pps;
    final next = (old * f)
        .clamp(TimelineGeometry.minPixelsPerSecond, 400.0)
        .toDouble();
    if (next == old) return;
    // نخلي النقطة تحت الإصبعين (أو نص الشاشة) بمكانها.
    final fx = focusX ?? _viewport / 2;
    final secondsAtFocus =
        _scroll.hasClients ? (_scroll.offset + fx) / old : 0.0;
    setState(() => _pps = next);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final to = (secondsAtFocus * next - fx)
          .clamp(0.0, _scroll.position.maxScrollExtent)
          .toDouble();
      _scroll.jumpTo(to);
    });
  }

  void _onPointerDown(PointerDownEvent e) {
    _pointers[e.pointer] = e.localPosition;
    if (_pointers.length == 2) {
      final p = _pointers.values.toList();
      _pinchStartDist = (p[0] - p[1]).distance;
      _pinchStartPps = _pps;
    }
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.localPosition;
    final d0 = _pinchStartDist;
    if (_pointers.length == 2 && d0 != null && d0 > 10) {
      final p = _pointers.values.toList();
      final d = (p[0] - p[1]).distance;
      final target = _pinchStartPps * d / d0;
      _zoomBy(target / _pps, focusX: (p[0].dx + p[1].dx) / 2);
    }
  }

  void _onPointerUp(PointerEvent e) {
    _pointers.remove(e.pointer);
    if (_pointers.length < 2) _pinchStartDist = null;
  }

  // ------------------------------ المقابض ------------------------------

  void _handleStart(int index, bool isStart) {
    final s = widget.segments[index];
    _dragBase = isStart ? s.start : s.end;
    _dragDx = 0;
    _lastSnap = null;
  }

  void _handleUpdate(int index, bool isStart, double dx) {
    _dragDx += dx;
    final raw = _dragBase + _dragDx / _pps;
    final segs = widget.segments;
    final candidates = <double>[
      if (index > 0) segs[index - 1].end,
      if (index + 1 < segs.length) segs[index + 1].start,
      // موقع التشغيل مش منهم: المعاينة بتلحق الحد وقت السحب، فكان رح يعلق فيه.
      // (لـ "البداية = موقع التشغيل" في زر "من هون" بلوحة التفاصيل.)
    ];
    final (v, which) =
        snapSeconds(raw, candidates, threshold: 10 / _pps);
    if (which != null && which != _lastSnap) HapticFeedback.selectionClick();
    _lastSnap = which;
    widget.onDragHandle(index, isStart, v < 0 ? 0 : v);
  }

  @override
  Widget build(BuildContext context) {
    final geo = _geo;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _zoomButton(Icons.zoom_out, 'تصغير الخط', () => _zoomBy(1 / 1.6)),
              _zoomButton(Icons.zoom_in, 'تكبير الخط', () => _zoomBy(1.6)),
              const Spacer(),
              ValueListenableBuilder<double>(
                valueListenable: widget.playhead,
                builder: (_, t, __) => Text(
                  '${formatClock(t)} / ${formatClock(widget.duration)}',
                  style: const TextStyle(
                      fontSize: 13, fontFeatures: [FontFeature.tabularFigures()]),
                ),
              ),
            ],
          ),
          LayoutBuilder(builder: (context, c) {
            _viewport = c.maxWidth;
            final width = geo.totalWidth < c.maxWidth ? c.maxWidth : geo.totalWidth;
            const h = SegmentTimelineView.rulerHeight + SegmentTimelineView.trackHeight;
            return Listener(
              onPointerDown: _onPointerDown,
              onPointerMove: _onPointerMove,
              onPointerUp: _onPointerUp,
              onPointerCancel: _onPointerUp,
              child: SizedBox(
                height: h,
                child: SingleChildScrollView(
                  controller: _scroll,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: width,
                    height: h,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        // المسطرة: كبسة أو سحب = تشغيل من هون.
                        Positioned(
                          left: 0,
                          top: 0,
                          width: width,
                          height: SegmentTimelineView.rulerHeight,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTapUp: (d) => widget.onSeek(geo.secondsOfX(d.localPosition.dx)),
                            onHorizontalDragUpdate: (d) =>
                                widget.onSeek(geo.secondsOfX(d.localPosition.dx)),
                            child: CustomPaint(painter: _RulerPainter(geo)),
                          ),
                        ),
                        // الموجة (كبسة على الفاضي = إلغاء التحديد + تشغيل من هون).
                        Positioned(
                          left: 0,
                          top: SegmentTimelineView.rulerHeight,
                          width: width,
                          height: SegmentTimelineView.trackHeight,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTapUp: (d) {
                              widget.onSelect(null);
                              widget.onSeek(geo.secondsOfX(d.localPosition.dx));
                            },
                            child: RepaintBoundary(
                              child: CustomPaint(
                                  painter: _WaveformPainter(widget.peaks, geo)),
                            ),
                          ),
                        ),
                        for (var i = 0; i < widget.segments.length; i++)
                          _block(i, geo),
                        if (widget.selectedIndex != null &&
                            widget.selectedIndex! < widget.segments.length) ...[
                          _handle(widget.selectedIndex!, true, geo),
                          _handle(widget.selectedIndex!, false, geo),
                        ],
                        // موقع التشغيل.
                        Positioned.fill(
                          child: IgnorePointer(
                            child: CustomPaint(
                              painter: _PlayheadPainter(widget.playhead, geo),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
          const SizedBox(height: 4),
          const _Legend(),
        ],
      ),
    );
  }

  Widget _zoomButton(IconData icon, String tip, VoidCallback onTap) => IconButton(
        tooltip: tip,
        iconSize: 26,
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        icon: Icon(icon),
        onPressed: onTap,
      );

  Widget _block(int i, TimelineGeometry geo) {
    final s = widget.segments[i];
    final left = geo.xOfSeconds(s.start);
    final w = (geo.xOfSeconds(s.end) - left).clamp(3.0, 1e7).toDouble();
    final selected = widget.selectedIndex == i;
    final review = (s.needsReview || s.inferred) && s.kind != SegmentKind.istiadha;
    final style = segmentBlockStyle(s);
    return Positioned(
      left: left,
      width: w,
      top: SegmentTimelineView.rulerHeight + 6,
      height: SegmentTimelineView.trackHeight - 12,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onSelect(i),
        child: Container(
          decoration: BoxDecoration(
            color: style.fill,
            border: Border.all(
              color: selected ? Colors.white : (review ? _review : style.border),
              width: selected ? 3 : (review ? 2 : 1),
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: w < 22
              ? null
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      segmentBlockLabel(s),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textDirection: TextDirection.rtl,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.white),
                    ),
                    if (review && w > 40)
                      const Text('بده مراجعة',
                          maxLines: 1,
                          textDirection: TextDirection.rtl,
                          style: TextStyle(fontSize: 10, color: Colors.white)),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _handle(int i, bool isStart, TimelineGeometry geo) {
    final s = widget.segments[i];
    final x = geo.xOfSeconds(isStart ? s.start : s.end);
    const hw = SegmentTimelineView.handleWidth;
    return Positioned(
      // المقبض نصه جوا المقطع ونصه برا، عشان المقطع القصير يضل إله مقبضين.
      left: isStart ? x - hw * 0.75 : x - hw * 0.25,
      width: hw,
      top: SegmentTimelineView.rulerHeight,
      height: SegmentTimelineView.trackHeight,
      child: GestureDetector(
        key: ValueKey('handle-$i-${isStart ? 's' : 'e'}'),
        behavior: HitTestBehavior.opaque,
        dragStartBehavior: DragStartBehavior.down,
        onHorizontalDragStart: (_) => _handleStart(i, isStart),
        onHorizontalDragUpdate: (d) => _handleUpdate(i, isStart, d.delta.dx),
        onHorizontalDragEnd: (_) => widget.onDragFinished?.call(),
        child: Align(
          alignment: isStart ? const Alignment(0.5, 0) : const Alignment(-0.5, 0),
          child: Container(
            width: 14,
            height: SegmentTimelineView.trackHeight - 8,
            decoration: BoxDecoration(
              color: _gold,
              borderRadius: BorderRadius.circular(5),
              boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 3)],
            ),
            child: const Icon(Icons.drag_indicator, size: 14, color: Colors.black87),
          ),
        ),
      ),
    );
  }
}

/// لون وحد كتلة المقطع حسب نوعه (الآيات ذهبي، البسملة فيروزي، نص المستخدم
/// أزرق، الفاضي والاستعاذة رمادي؛ "بده مراجعة" برتقالي فوق أي نوع).
({Color fill, Color border}) segmentBlockStyle(RecitationSegment s) {
  final review = (s.needsReview || s.inferred) && s.kind != SegmentKind.istiadha;
  if (review) {
    return (fill: _review.withValues(alpha: 0.55), border: _review);
  }
  return switch (s.kind) {
    SegmentKind.fullAyah ||
    SegmentKind.partialAyah =>
      (fill: _gold.withValues(alpha: 0.45), border: _gold),
    SegmentKind.basmala => (fill: Colors.teal.withValues(alpha: 0.5), border: Colors.teal),
    SegmentKind.istiadha => (fill: Colors.white10, border: Colors.white24),
    SegmentKind.nonQuran => (s.userText ?? '').trim().isEmpty
        ? (fill: Colors.white10, border: Colors.white38)
        : (fill: Colors.blue.withValues(alpha: 0.45), border: Colors.lightBlueAccent),
  };
}

/// نص الكتلة بالخط الزمني.
String segmentBlockLabel(RecitationSegment s) {
  switch (s.kind) {
    case SegmentKind.nonQuran:
      final t = (s.userText ?? '').trim();
      return t.isEmpty ? 'فاضي' : t;
    case SegmentKind.basmala:
      return 'بسملة';
    case SegmentKind.istiadha:
      return 'استعاذة';
    case SegmentKind.fullAyah:
    case SegmentKind.partialAyah:
      final r = '${s.surah}:${s.ayah}';
      return s.partCount > 1 ? '$r (${s.part}/${s.partCount})' : r;
  }
}

class _Legend extends StatelessWidget {
  const _Legend();
  @override
  Widget build(BuildContext context) {
    Widget dot(Color c, String t) => Padding(
          padding: const EdgeInsets.only(right: 10),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 12, height: 12, color: c),
            const SizedBox(width: 4),
            Text(t, style: const TextStyle(fontSize: 11, color: Colors.white70)),
          ]),
        );
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Wrap(children: [
        dot(_gold, 'آية'),
        dot(_review, 'بده مراجعة'),
        dot(Colors.teal, 'بسملة'),
        dot(Colors.lightBlueAccent, 'نص المستخدم'),
        dot(Colors.white38, 'فاضي / استعاذة'),
      ]),
    );
  }
}

class _RulerPainter extends CustomPainter {
  final TimelineGeometry geo;
  _RulerPainter(this.geo);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF123A2B));
    // تدريج حسب التكبير: علامة كل 1/5/10 ثواني ورقم كل 5/10/30.
    final pps = geo.pixelsPerSecond;
    final step = pps >= 60 ? 1.0 : (pps >= 15 ? 5.0 : 10.0);
    final labelEvery = pps >= 60 ? 5.0 : (pps >= 15 ? 10.0 : 30.0);
    final tick = Paint()..color = Colors.white54..strokeWidth = 1;
    final tp = TextPainter(textDirection: TextDirection.ltr);
    for (var t = 0.0; t <= geo.durationSeconds + 1e-6; t += step) {
      final x = geo.xOfSeconds(t);
      final major = (t % labelEvery).abs() < 1e-6;
      canvas.drawLine(Offset(x, size.height), Offset(x, size.height - (major ? 12 : 6)), tick);
      if (major) {
        tp.text = TextSpan(
            text: formatClock(t).replaceAll('.0', ''),
            style: const TextStyle(fontSize: 10, color: Colors.white70));
        tp.layout();
        tp.paint(canvas, Offset(x + 3, 1));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RulerPainter old) =>
      old.geo.pixelsPerSecond != geo.pixelsPerSecond ||
      old.geo.durationSeconds != geo.durationSeconds;
}

class _WaveformPainter extends CustomPainter {
  final WaveformPeaks? peaks;
  final TimelineGeometry geo;
  _WaveformPainter(this.peaks, this.geo);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = _track);
    final p = peaks;
    if (p == null || p.peaks.isEmpty || p.bucketSeconds <= 0) return;
    final mid = size.height / 2;
    final paint = Paint()..color = Colors.white38;
    // عمود لكل ~2px (مش لكل جزء) عشان الرسم يضل خفيف حتى بفيديو طويل.
    const px = 2.0;
    for (var x = 0.0; x < size.width; x += px) {
      final t0 = geo.secondsOfX(x), t1 = geo.secondsOfX(x + px);
      var v = 0.0;
      final i0 = (t0 / p.bucketSeconds).floor();
      final i1 = (t1 / p.bucketSeconds).ceil();
      for (var i = i0; i <= i1 && i < p.peaks.length; i++) {
        if (i >= 0 && p.peaks[i] > v) v = p.peaks[i];
      }
      final h = (v * size.height * 0.46).clamp(0.5, size.height / 2).toDouble();
      canvas.drawRect(Rect.fromLTWH(x, mid - h, px - 0.5, h * 2), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter old) =>
      !identical(old.peaks, peaks) || old.geo.pixelsPerSecond != geo.pixelsPerSecond;
}

class _PlayheadPainter extends CustomPainter {
  final ValueListenable<double> t;
  final TimelineGeometry geo;
  _PlayheadPainter(this.t, this.geo) : super(repaint: t);

  @override
  void paint(Canvas canvas, Size size) {
    final x = geo.xOfSeconds(t.value);
    final p = Paint()
      ..color = Colors.redAccent
      ..strokeWidth = 2;
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    final path = Path()
      ..moveTo(x - 6, 0)
      ..lineTo(x + 6, 0)
      ..lineTo(x, 8)
      ..close();
    canvas.drawPath(path, Paint()..color = Colors.redAccent);
  }

  @override
  bool shouldRepaint(covariant _PlayheadPainter old) =>
      old.geo.pixelsPerSecond != geo.pixelsPerSecond || old.t != t;
}
