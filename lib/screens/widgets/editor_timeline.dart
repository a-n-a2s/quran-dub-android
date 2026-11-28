// الخط الزمني الجديد زي CapCut (طلب أنس 2026-11-28):
//
// - **السهم (الخط الأبيض) ثابت بالنص**، والخط الزمني هو اللي بيتحرّك تحته: السحب
//   يمين/شمال = تنقّل بالفيديو (scrub)، والرمية بتكمّل بقصور ذاتي.
// - **قرصة بإصبعين** = تكبير/تصغير (السهم بيضل على نفس اللحظة).
// - **مسارات** تحت بعض: الفيديو (صور مصغّرة)، الآيات (كتل بأسمائها)، وموجة الصوت.
//   حتى لو ما في ولا آية، الخط الزمني والمسارات موجودين.
// - **كبسة على آية** بتحددها: بيطلع حواليها إطار أبيض ومقبضين كبار عالطرفين
//   بينسحبوا لتعديل البداية والنهاية (مع التصاق بالجار وبالسهم).
//
// الرسم كله بـ CustomPainter واحد بيرسم الجزء الظاهر بس، وبيعيد الرسم من
// ValueNotifiers (بدون setState) — هيك السحب والتشغيل سلسين حتى بفيديو طويل.
// الوقت دايماً من الشمال لليمين (زي كل برامج المونتاج) حتى بواجهة عربية.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../../editor/timeline_geometry.dart';
import '../../editor/waveform.dart';
import '../../pipeline/recitation_segment.dart';
import '../../ui/app_theme.dart';
import 'segment_timeline_view.dart' show segmentBlockLabel, segmentBlockStyle;

/// مقاسات المسارات (بكسلات منطقية).
class TimelineMetrics {
  static const double ruler = 24;
  static const double videoTop = 30;
  static const double videoH = 48;
  static const double ayahTop = videoTop + videoH + 8;
  static const double ayahH = 44;
  static const double audioTop = ayahTop + ayahH + 8;
  static const double audioH = 30;
  static const double height = audioTop + audioH + 8;
  static const double handleTouch = 44;
}

/// حساب درجات المسطرة: خطوة التسمية (ثواني) حسب التكبير، بحيث يكون بين
/// التسميات ≥ [minGapPx] بكسل.
double rulerStep(double pixelsPerSecond, {double minGapPx = 64}) {
  const steps = [0.5, 1.0, 2.0, 5.0, 10.0, 15.0, 30.0, 60.0, 120.0, 300.0];
  for (final s in steps) {
    if (s * pixelsPerSecond >= minGapPx) return s;
  }
  return steps.last;
}

/// "00:05" (أو "1:02:05" فوق الساعة).
String rulerLabel(double seconds) {
  final t = seconds.round();
  final h = t ~/ 3600, m = (t % 3600) ~/ 60, s = t % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}

class EditorTimeline extends StatefulWidget {
  final List<RecitationSegment> segments;
  final double duration;
  final WaveformPeaks? peaks;

  /// صور مصغّرة موزّعة بالتساوي على المدة (null = لسا ما جهزت).
  final List<ui.Image?> thumbs;
  final ValueListenable<double> playhead;
  final int? selectedIndex;

  final VoidCallback onScrubStart;
  final ValueChanged<double> onScrub;
  final VoidCallback onScrubEnd;
  final ValueChanged<int?> onSelect;
  final void Function(int index, bool isStart) onHandleStart;
  final void Function(int index, bool isStart, double seconds) onDragHandle;
  final VoidCallback onHandleEnd;
  final VoidCallback onAdd;

  const EditorTimeline({
    super.key,
    required this.segments,
    required this.duration,
    required this.peaks,
    required this.thumbs,
    required this.playhead,
    required this.selectedIndex,
    required this.onScrubStart,
    required this.onScrub,
    required this.onScrubEnd,
    required this.onSelect,
    required this.onHandleStart,
    required this.onDragHandle,
    required this.onHandleEnd,
    required this.onAdd,
  });

  @override
  State<EditorTimeline> createState() => EditorTimelineState();
}

class EditorTimelineState extends State<EditorTimeline> with SingleTickerProviderStateMixin {
  /// اللحظة اللي بنص الشاشة (تحت السهم).
  late final ValueNotifier<double> _view = ValueNotifier(widget.playhead.value);
  final ValueNotifier<double> _zoom = ValueNotifier(60);
  late final AnimationController _fling = AnimationController.unbounded(vsync: this)
    ..addListener(_onFlingTick)
    ..addStatusListener(_onFlingStatus);
  final Map<String, TextPainter> _labels = {};

  bool _frozen = false; // وقت سحب مقبض: الخط ما بيلحق السهم.
  bool _scrubbing = false;
  bool _zoomedThisGesture = false;
  bool _zoomInit = false;
  double _gStartT = 0, _gStartPps = 60, _gStartX = 0;
  double _width = 360;

  // سحب المقبض.
  int? _hIndex;
  bool _hIsStart = true;
  double _hStartSec = 0, _hStartX = 0;
  int? _lastSnap;

  double get _minPps => math.max(2.0, math.min(TimelineGeometry.minPixelsPerSecond,
      _width * 0.8 / math.max(0.5, widget.duration)));
  static const double _maxPps = 400;

  @override
  void initState() {
    super.initState();
    widget.playhead.addListener(_follow);
  }

  @override
  void didUpdateWidget(covariant EditorTimeline old) {
    super.didUpdateWidget(old);
    if (old.playhead != widget.playhead) {
      old.playhead.removeListener(_follow);
      widget.playhead.addListener(_follow);
    }
    if (old.segments != widget.segments) _labels.clear();
  }

  @override
  void dispose() {
    widget.playhead.removeListener(_follow);
    _fling.dispose();
    _view.dispose();
    _zoom.dispose();
    for (final t in _labels.values) {
      t.dispose();
    }
    super.dispose();
  }

  void _follow() {
    if (_frozen || _scrubbing) return;
    _view.value = widget.playhead.value;
  }

  /// تكبير/تصغير بالأزرار (من الشاشة الأم).
  void zoomBy(double f) {
    _zoom.value = (_zoom.value * f).clamp(_minPps, _maxPps).toDouble();
  }

  double _clampT(double t) => t.clamp(0.0, math.max(0.0, widget.duration)).toDouble();

  // ------------------------- السحب (scrub) والتكبير -------------------------

  void _stopFling() {
    if (_fling.isAnimating) {
      _fling.stop();
      _endScrub();
    }
  }

  void _beginScrub() {
    if (_scrubbing) return;
    _scrubbing = true;
    widget.onScrubStart();
  }

  void _endScrub() {
    if (!_scrubbing) return;
    _scrubbing = false;
    widget.onScrubEnd();
  }

  void _onScaleStart(ScaleStartDetails d) {
    _stopFling();
    _gStartT = _view.value;
    _gStartPps = _zoom.value;
    _gStartX = d.localFocalPoint.dx;
    _zoomedThisGesture = false;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (d.pointerCount >= 2) {
      _zoomedThisGesture = true;
      _zoom.value = (_gStartPps * d.scale).clamp(_minPps, _maxPps).toDouble();
      return;
    }
    if (_zoomedThisGesture) return;
    final dx = d.localFocalPoint.dx - _gStartX;
    if (!_scrubbing && dx.abs() < 2) return;
    _beginScrub();
    final t = _clampT(_gStartT - dx / _zoom.value);
    _view.value = t;
    widget.onScrub(t);
  }

  void _onScaleEnd(ScaleEndDetails d) {
    if (!_scrubbing) return;
    final vx = d.velocity.pixelsPerSecond.dx;
    if (vx.abs() < 250) {
      _endScrub();
      return;
    }
    final sim = FrictionSimulation(0.12, _view.value, -vx / _zoom.value);
    _fling.value = _view.value;
    _fling.animateWith(sim);
  }

  void _onFlingTick() {
    if (!_fling.isAnimating) return;
    final raw = _fling.value;
    final t = _clampT(raw);
    _view.value = t;
    widget.onScrub(t);
    if (raw != t) {
      _fling.stop();
      _endScrub();
    }
  }

  void _onFlingStatus(AnimationStatus s) {
    if (s == AnimationStatus.completed || s == AnimationStatus.dismissed) _endScrub();
  }

  double _xOf(double t) => _width / 2 + (t - _view.value) * _zoom.value;
  double _tOf(double x) => _view.value + (x - _width / 2) / _zoom.value;

  void _onTapUp(TapUpDetails d) {
    final p = d.localPosition;
    final t = _tOf(p.dx);
    if (p.dy >= TimelineMetrics.ayahTop - 4 &&
        p.dy <= TimelineMetrics.ayahTop + TimelineMetrics.ayahH + 4) {
      for (var i = 0; i < widget.segments.length; i++) {
        final s = widget.segments[i];
        if (t >= s.start && t < s.end) {
          HapticFeedback.selectionClick();
          widget.onSelect(i == widget.selectedIndex ? null : i);
          return;
        }
      }
    }
    if (p.dy < TimelineMetrics.videoTop) {
      // كبسة عالمسطرة = روح لهاللحظة.
      final tt = _clampT(t);
      widget.onScrubStart();
      widget.onScrub(tt);
      widget.onScrubEnd();
      return;
    }
    widget.onSelect(null);
  }

  // ------------------------------- المقابض -------------------------------

  void _hStart(int index, bool isStart, DragStartDetails d) {
    _stopFling();
    final s = widget.segments[index];
    _hIndex = index;
    _hIsStart = isStart;
    _hStartSec = isStart ? s.start : s.end;
    _hStartX = d.globalPosition.dx;
    _frozen = true;
    _lastSnap = null;
    HapticFeedback.selectionClick();
    widget.onHandleStart(index, isStart);
  }

  void _hUpdate(DragUpdateDetails d) {
    final i = _hIndex;
    if (i == null || i >= widget.segments.length) return;
    var sec = _hStartSec + (d.globalPosition.dx - _hStartX) / _zoom.value;
    final cands = <double>[
      if (i > 0) widget.segments[i - 1].end,
      if (i < widget.segments.length - 1) widget.segments[i + 1].start,
      _view.value,
    ];
    final (snapped, which) = snapSeconds(sec, cands, threshold: 10 / _zoom.value);
    if (which != null && which != _lastSnap) HapticFeedback.selectionClick();
    _lastSnap = which;
    sec = snapped;
    widget.onDragHandle(i, _hIsStart, _clampT(sec));
  }

  void _hEnd([Object? _]) {
    _hIndex = null;
    _frozen = false;
    widget.onHandleEnd();
  }

  TextPainter _label(String text) {
    final cached = _labels[text];
    if (cached != null) return cached;
    if (_labels.length > 300) {
      for (final t in _labels.values) {
        t.dispose();
      }
      _labels.clear();
    }
    final tp = TextPainter(
      text: TextSpan(
          text: text,
          style: const TextStyle(
              fontFamily: kUiFont, fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
      textDirection: TextDirection.rtl,
      maxLines: 1,
    )..layout();
    return _labels[text] = tp;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      _width = c.maxWidth;
      if (!_zoomInit && _width > 0) {
        _zoomInit = true;
        // البداية: ~7 ثواني ظاهرين (زي CapCut)، والفيديو القصير كله.
        _zoom.value = (_width / math.min(7.0, math.max(1.0, widget.duration)) * 0.9)
            .clamp(_minPps, _maxPps)
            .toDouble();
      }
      final sel = widget.selectedIndex;
      return SizedBox(
        height: TimelineMetrics.height,
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: _onTapUp,
                onScaleStart: _onScaleStart,
                onScaleUpdate: _onScaleUpdate,
                onScaleEnd: _onScaleEnd,
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _TimelinePainter(
                      segments: widget.segments,
                      duration: widget.duration,
                      peaks: widget.peaks,
                      thumbs: widget.thumbs,
                      view: _view,
                      zoom: _zoom,
                      playhead: widget.playhead,
                      selected: sel,
                      label: _label,
                    ),
                  ),
                ),
              ),
            ),
            if (sel != null && sel < widget.segments.length)
              AnimatedBuilder(
                animation: Listenable.merge([_view, _zoom]),
                builder: (_, __) {
                  final s = widget.segments[sel];
                  Widget handle(bool isStart) {
                    final x = _xOf(isStart ? s.start : s.end);
                    return Positioned(
                      left: x - TimelineMetrics.handleTouch / 2 + (isStart ? -6 : 6),
                      top: TimelineMetrics.ayahTop - 10,
                      width: TimelineMetrics.handleTouch,
                      height: TimelineMetrics.ayahH + 20,
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onHorizontalDragStart: (d) => _hStart(sel, isStart, d),
                        onHorizontalDragUpdate: _hUpdate,
                        onHorizontalDragEnd: _hEnd,
                        onHorizontalDragCancel: _hEnd,
                      ),
                    );
                  }

                  return Stack(children: [handle(true), handle(false)]);
                },
              ),
          ],
        ),
      );
    });
  }
}

class _TimelinePainter extends CustomPainter {
  final List<RecitationSegment> segments;
  final double duration;
  final WaveformPeaks? peaks;
  final List<ui.Image?> thumbs;
  final ValueListenable<double> view;
  final ValueListenable<double> zoom;
  final ValueListenable<double> playhead;
  final int? selected;
  final TextPainter Function(String) label;

  _TimelinePainter({
    required this.segments,
    required this.duration,
    required this.peaks,
    required this.thumbs,
    required this.view,
    required this.zoom,
    required this.playhead,
    required this.selected,
    required this.label,
  }) : super(repaint: Listenable.merge([view, zoom, playhead]));

  static final Paint _fill = Paint();
  static final Paint _stroke = Paint()..style = PaintingStyle.stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final pps = zoom.value;
    final c = view.value;
    final cx = size.width / 2;
    double xOf(double t) => cx + (t - c) * pps;
    final t0 = c - cx / pps, t1 = c + cx / pps;
    final x0 = xOf(0), xEnd = xOf(duration);

    _ruler(canvas, size, pps, t0, t1, xOf);
    _videoTrack(canvas, size, x0, xEnd, pps, c, cx);
    _ayahTrack(canvas, size, t0, t1, xOf, x0, xEnd);
    _audioTrack(canvas, size, x0, xEnd, pps, c, cx);

    // السهم: خط أبيض بالنص (أو عند موقع التشغيل لو مختلف وقت سحب مقبض).
    final px = xOf(playhead.value);
    _fill
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(px - 1.25, TimelineMetrics.ruler - 2, 2.5, size.height - TimelineMetrics.ruler),
            const Radius.circular(2)),
        _fill);
    final tri = Path()
      ..moveTo(px - 6, TimelineMetrics.ruler - 8)
      ..lineTo(px + 6, TimelineMetrics.ruler - 8)
      ..lineTo(px, TimelineMetrics.ruler)
      ..close();
    canvas.drawPath(tri, _fill);
  }

  void _ruler(Canvas canvas, Size size, double pps, double t0, double t1,
      double Function(double) xOf) {
    final step = rulerStep(pps);
    final start = (math.max(0, t0) / step).floor() * step;
    final end = math.min(duration, t1);
    _fill.color = const Color(0x99FFFFFF);
    for (var t = start; t <= end + 1e-6; t += step) {
      final x = xOf(t);
      final tp = label(rulerLabel(t));
      // تسمية المسطرة بخط أصغر: بنصغّرها بالرسم.
      canvas.save();
      canvas.translate(x - tp.width * 0.42, 2);
      canvas.scale(0.84);
      tp.paint(canvas, Offset.zero);
      canvas.restore();
      // نقطة بنص المسافة.
      final mid = t + step / 2;
      if (mid <= end) canvas.drawCircle(Offset(xOf(mid), 11), 1.6, _fill);
    }
  }

  void _videoTrack(Canvas canvas, Size size, double x0, double xEnd, double pps, double c, double cx) {
    final top = TimelineMetrics.videoTop, h = TimelineMetrics.videoH;
    final l = math.max(x0, -10.0), r = math.min(xEnd, size.width + 10);
    if (r <= l) return;
    final rr = RRect.fromLTRBR(x0, top, xEnd, top + h, const Radius.circular(8));
    canvas.save();
    canvas.clipRRect(rr);
    _fill.color = const Color(0xFF16352B);
    canvas.drawRect(Rect.fromLTRB(l, top, r, top + h), _fill);
    final imgs = thumbs;
    ui.Image? any;
    for (final i in imgs) {
      if (i != null) {
        any = i;
        break;
      }
    }
    if (any != null && duration > 0) {
      final aspect = any.width / any.height;
      final tileW = h * aspect;
      final first = ((l - x0) / tileW).floor();
      final last = ((r - x0) / tileW).ceil();
      final paint = Paint()..filterQuality = FilterQuality.low;
      for (var k = math.max(0, first); k <= last; k++) {
        final tx = x0 + k * tileW;
        final tMid = (k * tileW + tileW / 2) / pps;
        if (tMid > duration + tileW / pps) break;
        final idx = (tMid / duration * imgs.length).floor().clamp(0, imgs.length - 1);
        final img = imgs[idx] ?? any;
        canvas.drawImageRect(
            img,
            Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
            Rect.fromLTWH(tx, top, tileW + 0.5, h),
            paint);
      }
    } else {
      // لسا ما في صور: شريط فيلم بسيط.
      _fill.color = const Color(0x22FFFFFF);
      for (var x = l - ((l - x0) % 14); x < r; x += 14) {
        canvas.drawRRect(RRect.fromLTRBR(x + 3, top + 4, x + 9, top + 9, const Radius.circular(1.5)), _fill);
        canvas.drawRRect(
            RRect.fromLTRBR(x + 3, top + h - 9, x + 9, top + h - 4, const Radius.circular(1.5)), _fill);
      }
    }
    canvas.restore();
    _stroke
      ..color = const Color(0x33FFFFFF)
      ..strokeWidth = 1;
    canvas.drawRRect(rr, _stroke);
  }

  void _ayahTrack(Canvas canvas, Size size, double t0, double t1, double Function(double) xOf,
      double x0, double xEnd) {
    final top = TimelineMetrics.ayahTop, h = TimelineMetrics.ayahH;
    // خلفية المسار (حتى لو فاضي).
    _fill.color = const Color(0x0FFFFFFF);
    canvas.drawRRect(RRect.fromLTRBR(x0, top, xEnd, top + h, const Radius.circular(8)), _fill);
    if (segments.isEmpty) {
      final tp = label('اكبس + لتضيف آية');
      tp.paint(canvas, Offset(size.width / 2 - tp.width / 2, top + (h - tp.height) / 2));
    }
    RRect? selRect;
    for (var i = 0; i < segments.length; i++) {
      final s = segments[i];
      if (s.end < t0 - 1 || s.start > t1 + 1) continue;
      final l = xOf(s.start) + 1, r = xOf(s.end) - 1;
      if (r - l < 1) continue;
      final rr = RRect.fromLTRBR(l, top, r, top + h, const Radius.circular(7));
      final st = segmentBlockStyle(s);
      _fill.color = st.fill;
      canvas.drawRRect(rr, _fill);
      _stroke
        ..color = st.border
        ..strokeWidth = 1.2;
      canvas.drawRRect(rr.deflate(0.6), _stroke);
      // التسمية بأول الجزء الظاهر من الكتلة.
      final text = segmentBlockLabel(s);
      final tp = label(text);
      final vl = math.max(l, 0.0) + 7, vr = math.min(r, size.width) - 7;
      if (vr - vl > 14) {
        canvas.save();
        canvas.clipRect(Rect.fromLTRB(vl, top, vr, top + h));
        final x = math.max(vl, vr - tp.width); // عربي: من اليمين
        tp.paint(canvas, Offset(x, top + (h - tp.height) / 2));
        canvas.restore();
      }
      if (i == selected) selRect = rr;
    }
    if (selRect != null) {
      // إطار أبيض + مقبضين (زي CapCut).
      _stroke
        ..color = Colors.white
        ..strokeWidth = 2.4;
      canvas.drawRRect(selRect.inflate(1.2), _stroke);
      _fill.color = Colors.white;
      final hl = RRect.fromLTRBR(selRect.left - 14, top - 3, selRect.left, top + h + 3,
          const Radius.circular(5));
      final hr = RRect.fromLTRBR(selRect.right, top - 3, selRect.right + 14, top + h + 3,
          const Radius.circular(5));
      canvas.drawRRect(hl, _fill);
      canvas.drawRRect(hr, _fill);
      _fill.color = const Color(0xFF1B1B1B);
      for (final hh in [hl, hr]) {
        final mx = hh.center.dx;
        canvas.drawRRect(
            RRect.fromLTRBR(mx - 1.2, top + h / 2 - 8, mx + 1.2, top + h / 2 + 8, const Radius.circular(1)),
            _fill);
      }
    }
  }

  void _audioTrack(Canvas canvas, Size size, double x0, double xEnd, double pps, double c, double cx) {
    final top = TimelineMetrics.audioTop, h = TimelineMetrics.audioH;
    final l = math.max(x0, 0.0), r = math.min(xEnd, size.width);
    _fill.color = const Color(0x3317694F);
    canvas.drawRRect(RRect.fromLTRBR(x0, top, xEnd, top + h, const Radius.circular(6)), _fill);
    final pk = peaks;
    if (pk == null || pk.peaks.isEmpty || r <= l) return;
    _fill.color = AyahColors.teal.withValues(alpha: 0.85);
    final mid = top + h / 2;
    for (var x = l; x < r; x += 3) {
      final t = c + (x - cx) / pps;
      final v = pk.at(t).clamp(0.0, 1.0);
      final bh = math.max(1.5, v * (h - 6));
      canvas.drawRect(Rect.fromLTWH(x, mid - bh / 2, 2, bh), _fill);
    }
  }

  @override
  bool shouldRepaint(covariant _TimelinePainter old) =>
      old.segments != segments ||
      old.selected != selected ||
      old.peaks != peaks ||
      old.thumbs != thumbs ||
      old.duration != duration;
}
