// الخط الزمني على موجة الصوت (يوم 10، المحرر 2): كل المقاطع على خط واحد زي
// برامج المونتاج، سحب بداية/نهاية كل مقطع، تكبير/تصغير، وتشغيل من مكان
// محدد. الواجهة هون "غبية" قصداً: كل منطق الحدود (ما يتخطى جاره، حد أدنى
// للطول) بالشاشة الأم ([lib/editor/timeline_geometry.dart]) — هاد بس بيرسم
// وبيبلّغ عن لمسات السحب بالثواني.
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

import '../../editor/timeline_geometry.dart';
import '../../editor/waveform.dart';
import '../../pipeline/recitation_segment.dart';

const Color _gold = Color(0xFFD9B55E);
const Color _greenLight = Color(0xFF17432F);

/// مقطع ظاهر بالخط الزمني (رقمه الأصلي بقائمة المقاطع + محتواه).
class TimelineSegment {
  final int index;
  final RecitationSegment segment;
  const TimelineSegment(this.index, this.segment);
}

class SegmentTimelineView extends StatefulWidget {
  final List<TimelineSegment> segments;
  final double duration;
  final WaveformPeaks peaks;

  /// موقع التشغيل الحالي (ثانية).
  final double playhead;

  /// المقطع المحدد هلأ (لو في)، لإبراز حدوده بلون مختلف.
  final int? selectedIndex;

  final void Function(double seconds) onSeek;
  final void Function(int index) onTapSegment;

  /// سحب حد مقطع: [isStart] يعني حد البداية، والقيمة الجديدة بالثواني
  /// **قبل** أي تحديد حدود (الشاشة الأم بتطبّق [clampSegmentDrag]).
  final void Function(int index, bool isStart, double newSeconds) onDragHandle;

  const SegmentTimelineView({
    super.key,
    required this.segments,
    required this.duration,
    required this.peaks,
    required this.playhead,
    required this.selectedIndex,
    required this.onSeek,
    required this.onTapSegment,
    required this.onDragHandle,
  });

  @override
  State<SegmentTimelineView> createState() => _SegmentTimelineViewState();
}

class _SegmentTimelineViewState extends State<SegmentTimelineView> {
  double _pixelsPerSecond = 80;
  final ScrollController _scroll = ScrollController();

  TimelineGeometry get _geo => TimelineGeometry(
      durationSeconds: widget.duration <= 0 ? 1 : widget.duration,
      pixelsPerSecond: _pixelsPerSecond);

  void _zoom(double factor) {
    setState(() => _pixelsPerSecond =
        _geo.zoomed(factor).pixelsPerSecond.toDouble());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final geo = _geo;
    final width = geo.totalWidth.clamp(200.0, 1e6).toDouble();
    const height = 92.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(child: Text('الخط الزمني', style: TextStyle(fontSize: 12))),
            IconButton(
              tooltip: 'تصغير',
              icon: const Icon(Icons.zoom_out, size: 20),
              onPressed: () => _zoom(1 / 1.5),
            ),
            IconButton(
              tooltip: 'تكبير',
              icon: const Icon(Icons.zoom_in, size: 20),
              onPressed: () => _zoom(1.5),
            ),
          ],
        ),
        SizedBox(
          height: height,
          child: SingleChildScrollView(
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: width,
              height: height,
              child: Stack(
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (d) => widget.onSeek(geo.secondsOfX(d.localPosition.dx)),
                    child: CustomPaint(
                      size: Size(width, height),
                      painter: _WaveformPainter(widget.peaks, geo),
                    ),
                  ),
                  for (final ts in widget.segments)
                    _SegmentBlock(
                      key: ValueKey('seg-${ts.index}'),
                      ts: ts,
                      geo: geo,
                      height: height,
                      selected: widget.selectedIndex == ts.index,
                      onTap: () => widget.onTapSegment(ts.index),
                      onDragStart: (secs) =>
                          widget.onDragHandle(ts.index, true, secs),
                      onDragEnd: (secs) =>
                          widget.onDragHandle(ts.index, false, secs),
                    ),
                  IgnorePointer(
                    child: CustomPaint(
                      size: Size(width, height),
                      painter: _PlayheadPainter(geo.xOfSeconds(widget.playhead)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SegmentBlock extends StatelessWidget {
  final TimelineSegment ts;
  final TimelineGeometry geo;
  final double height;
  final bool selected;
  final VoidCallback onTap;
  final void Function(double seconds) onDragStart;
  final void Function(double seconds) onDragEnd;

  const _SegmentBlock({
    super.key,
    required this.ts,
    required this.geo,
    required this.height,
    required this.selected,
    required this.onTap,
    required this.onDragStart,
    required this.onDragEnd,
  });

  static const double _handleWidth = 26;

  Color get _fill {
    final s = ts.segment;
    if (s.needsReview || s.inferred) return Colors.orange.withValues(alpha: 0.55);
    switch (s.kind) {
      case SegmentKind.fullAyah:
      case SegmentKind.partialAyah:
        return _gold.withValues(alpha: 0.55);
      case SegmentKind.basmala:
        return Colors.teal.withValues(alpha: 0.55);
      case SegmentKind.istiadha:
        return Colors.white24;
      case SegmentKind.nonQuran:
        return Colors.white30;
    }
  }

  @override
  Widget build(BuildContext context) {
    final left = geo.xOfSeconds(ts.segment.start);
    final w = (geo.xOfSeconds(ts.segment.end) - left).clamp(4.0, 1e6).toDouble();
    final label = _blockLabel(ts.segment);
    return Positioned(
      left: left,
      width: w,
      top: 4,
      height: height - 8,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: _fill,
            border: Border.all(
                color: selected ? Colors.white : _gold.withValues(alpha: 0.6),
                width: selected ? 2 : 1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: _handleWidth - 10),
                child: Align(
                  alignment: Alignment.center,
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    textDirection: TextDirection.rtl,
                    style: const TextStyle(fontSize: 11, color: Colors.white),
                  ),
                ),
              ),
              if (ts.segment.needsReview || ts.segment.inferred)
                const Positioned(
                  top: 1,
                  right: 1,
                  child: Icon(Icons.priority_high, size: 13, color: Colors.white),
                ),
              _handle(isStart: true),
              _handle(isStart: false),
            ],
          ),
        ),
      ),
    );
  }

  Widget _handle({required bool isStart}) => Positioned(
        left: isStart ? 0 : null,
        right: isStart ? null : 0,
        top: 0,
        bottom: 0,
        width: _handleWidth,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          dragStartBehavior: DragStartBehavior.down,
          onHorizontalDragUpdate: (d) {
            final seconds = geo.secondsOfX(
                geo.xOfSeconds(isStart ? ts.segment.start : ts.segment.end) +
                    d.delta.dx);
            isStart ? onDragStart(seconds) : onDragEnd(seconds);
          },
          child: Container(
            alignment: Alignment.center,
            child: Container(
              width: 4,
              margin: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      );

  String _blockLabel(RecitationSegment s) {
    if (s.kind == SegmentKind.nonQuran) {
      final t = (s.userText ?? '').trim();
      return t.isEmpty ? 'مش قرآن' : t;
    }
    if (s.kind == SegmentKind.basmala) return 'بسملة';
    if (s.ref == null) return s.kindLabel;
    return s.partCount > 1 ? '${s.ref} ج${s.part}' : s.ref!;
  }
}

class _WaveformPainter extends CustomPainter {
  final WaveformPeaks peaks;
  final TimelineGeometry geo;
  _WaveformPainter(this.peaks, this.geo);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = _greenLight);
    if (peaks.peaks.isEmpty || peaks.bucketSeconds <= 0) return;
    final mid = size.height / 2;
    final paint = Paint()..color = Colors.white54;
    final barWidth = (geo.pixelsPerSecond * peaks.bucketSeconds).clamp(1.0, 40.0);
    for (var i = 0; i < peaks.peaks.length; i++) {
      final t = i * peaks.bucketSeconds;
      final x = geo.xOfSeconds(t);
      if (x > size.width) break;
      final h = (peaks.peaks[i] * (size.height * 0.42)).clamp(1.0, size.height / 2);
      canvas.drawRect(
          Rect.fromLTWH(x, mid - h, barWidth.toDouble(), h * 2), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter old) =>
      old.peaks != peaks || old.geo.pixelsPerSecond != geo.pixelsPerSecond;
}

class _PlayheadPainter extends CustomPainter {
  final double x;
  _PlayheadPainter(this.x);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(Offset(x, 0), Offset(x, size.height),
        Paint()..color = Colors.redAccent..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(covariant _PlayheadPainter old) => old.x != x;
}
