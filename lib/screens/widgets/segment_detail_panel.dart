// لوحة تفاصيل المقطع (يوم 10، طلب أنس صريح): لوحة خاصة غير تبويبات
// التخصيص، بتطلع تحت الخط الزمني لما يكبس المستخدم على مقطع. فيها:
//
// - **ثانية البداية والنهاية** بطريقتين مع بعض ومتزامنتين: كتابة (حقول بدقة
//   0.01، وأزرار ±0.1 كبيرة) **و** سحب مقابض المقطع على الخط الزمني فوقها —
//   اللوحة مش نافذة منبثقة، فالسحب بيحدّث الحقول فوراً والعكس.
// - "من هون" / "لهون": البداية أو النهاية = موقع التشغيل (أسرع طريقة للدقة:
//   شغّل، وقّف عند بداية الآية، اكبس).
// - تغيير الآية، تحويل لنص غير قرآني، نص المستخدم، تأكيد "بده مراجعة"، حذف،
//   وأحجام هالمقطع (`OverlayStyle.segmentScales`).
//
// اللوحة "غبية": كل تعديل بيروح للشاشة الأم (`segment_edits.dart` بيطبّق
// الحدود)، وهي بترجع ترسم القيم المقصوصة.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../editor/timeline_geometry.dart';
import '../../overlay/overlay_layout.dart';
import '../../pipeline/recitation_segment.dart';

const Color _gold = Color(0xFFD9B55E);
const Color _review = Color(0xFFE8892B);

class SegmentDetailPanel extends StatefulWidget {
  final RecitationSegment segment;
  final int index;
  final int count;
  final ValueListenable<double> playhead;
  final String Function(int surah) surahName;

  /// العناصر اللي إلها حجم بهالمقطع (الظاهرة)، والحجم الحالي لكل واحد.
  final Map<OverlayElement, double> scales;
  final bool hasOwnScales;

  final void Function(double start, double end) onBounds;
  final VoidCallback onChangeAyah;
  final VoidCallback onConvertToNonQuran;
  final void Function(String text) onUserText;
  final VoidCallback onConfirm;
  final VoidCallback onDelete;
  final void Function(OverlayElement e, double v) onScale;
  final VoidCallback onResetScales;
  final VoidCallback onPlay;
  final void Function(int delta) onStep;
  final VoidCallback onClose;

  const SegmentDetailPanel({
    super.key,
    required this.segment,
    required this.index,
    required this.count,
    required this.playhead,
    required this.surahName,
    required this.scales,
    required this.hasOwnScales,
    required this.onBounds,
    required this.onChangeAyah,
    required this.onConvertToNonQuran,
    required this.onUserText,
    required this.onConfirm,
    required this.onDelete,
    required this.onScale,
    required this.onResetScales,
    required this.onPlay,
    required this.onStep,
    required this.onClose,
  });

  @override
  State<SegmentDetailPanel> createState() => _SegmentDetailPanelState();
}

class _SegmentDetailPanelState extends State<SegmentDetailPanel> {
  final _startCtl = TextEditingController();
  final _endCtl = TextEditingController();
  final _startFocus = FocusNode();
  final _endFocus = FocusNode();
  final _userCtl = TextEditingController();
  final _userFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _sync(force: true);
    _startFocus.addListener(() {
      if (!_startFocus.hasFocus) _submit(true);
    });
    _endFocus.addListener(() {
      if (!_endFocus.hasFocus) _submit(false);
    });
  }

  @override
  void didUpdateWidget(covariant SegmentDetailPanel old) {
    super.didUpdateWidget(old);
    _sync(force: old.index != widget.index);
  }

  /// الحقول بتتبع القيمة الحالية (سحب، ±، أو قصّ الجيران) إلا الحقل اللي
  /// المستخدم عم يكتب فيه.
  void _sync({bool force = false}) {
    final s = widget.segment;
    if (force || !_startFocus.hasFocus) _startCtl.text = formatSecondsInput(s.start);
    if (force || !_endFocus.hasFocus) _endCtl.text = formatSecondsInput(s.end);
    if (force || !_userFocus.hasFocus) {
      final t = s.userText ?? '';
      if (_userCtl.text != t) _userCtl.text = t;
    }
  }

  void _submit(bool isStart) {
    final ctl = isStart ? _startCtl : _endCtl;
    final v = parseSecondsInput(ctl.text);
    final s = widget.segment;
    if (v == null) {
      ctl.text = formatSecondsInput(isStart ? s.start : s.end);
      return;
    }
    if (isStart) {
      widget.onBounds(v, s.end);
    } else {
      widget.onBounds(s.start, v);
    }
  }

  void _nudge(bool isStart, double d) {
    final s = widget.segment;
    if (isStart) {
      widget.onBounds(s.start + d, s.end);
    } else {
      widget.onBounds(s.start, s.end + d);
    }
  }

  void _toPlayhead(bool isStart) {
    final t = widget.playhead.value;
    final s = widget.segment;
    if (isStart) {
      widget.onBounds(t, s.end);
    } else {
      widget.onBounds(s.start, t);
    }
  }

  @override
  void dispose() {
    _startCtl.dispose();
    _endCtl.dispose();
    _startFocus.dispose();
    _endFocus.dispose();
    _userCtl.dispose();
    _userFocus.dispose();
    super.dispose();
  }

  String get _title {
    final s = widget.segment;
    switch (s.kind) {
      case SegmentKind.fullAyah:
      case SegmentKind.partialAyah:
        final part = s.partCount > 1 ? ' — جزء ${s.part} من ${s.partCount}' : '';
        return '${widget.surahName(s.surah ?? 0)} • آية ${s.ayah}$part';
      case SegmentKind.basmala:
        return 'بسملة';
      case SegmentKind.istiadha:
        return 'استعاذة (ما بتنكتب)';
      case SegmentKind.nonQuran:
        return 'كلام غير قرآني';
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.segment;
    final review = (s.needsReview || s.inferred) && s.kind != SegmentKind.istiadha;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0E2F24),
        border: Border.all(color: review ? _review : _gold, width: 1.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _big(Icons.chevron_right, 'المقطع اللي قبله',
                  widget.index > 0 ? () => widget.onStep(-1) : null),
              Expanded(
                child: Text(
                  _title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold, color: _gold),
                ),
              ),
              _big(Icons.chevron_left, 'المقطع اللي بعده',
                  widget.index + 1 < widget.count ? () => widget.onStep(1) : null),
              _big(Icons.close, 'سكّر اللوحة', widget.onClose),
            ],
          ),
          if (s.text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(s.text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, color: Colors.white)),
            ),
          if (review)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                  color: _review.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(6)),
              child: Row(
                children: [
                  const Icon(Icons.priority_high, color: _review),
                  Expanded(
                    child: Text(
                      s.inferred
                          ? 'التعرف ما سمع هالآية، وتوقيتها تقديري. تأكد منها.'
                          : (s.suggestedRef != null && s.kind == SegmentKind.nonQuran
                              ? 'شكلها آية (${s.suggestedRef}) بس مش أكيد.'
                              : 'التطبيق مش متأكد من هالمقطع.'),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                        minimumSize: const Size(72, 44), backgroundColor: _review),
                    onPressed: widget.onConfirm,
                    child: const Text('صح ✓'),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          _timeRow('البداية', true),
          const SizedBox(height: 6),
          _timeRow('النهاية', false),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'المدة ${(s.end - s.start).toStringAsFixed(2)} ثانية'
              ' • اسحب المقبضين الذهبيين فوق كمان',
              style: const TextStyle(fontSize: 12, color: Colors.white60),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _action(Icons.play_arrow, 'شغّل المقطع', widget.onPlay),
              if (s.kind != SegmentKind.istiadha)
                _action(Icons.menu_book, s.isAyah ? 'تغيير الآية' : 'خليها آية',
                    widget.onChangeAyah),
              if (s.isAyah || s.kind == SegmentKind.basmala)
                _action(Icons.text_fields, 'مش آية (نص خاص)', widget.onConvertToNonQuran),
              _action(Icons.delete_outline, 'حذف المقطع', () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => Directionality(
                    textDirection: TextDirection.rtl,
                    child: AlertDialog(
                      title: const Text('حذف المقطع؟'),
                      content: const Text(
                          'بيختفي من الخط الزمني ومن الفيديو. بتقدر ترجّع كل التعديلات بزر "رجوع للتحليل الأصلي".'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('إلغاء')),
                        FilledButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('حذف')),
                      ],
                    ),
                  ),
                );
                if (ok == true) widget.onDelete();
              }, danger: true),
            ],
          ),
          if (s.kind == SegmentKind.nonQuran) ...[
            const SizedBox(height: 10),
            const Text('النص اللي بيطلع بهالجزء (مقدمة، دعاء…). فاضي = الشاشة نظيفة.',
                style: TextStyle(fontSize: 12, color: Colors.white70)),
            const SizedBox(height: 4),
            TextField(
              controller: _userCtl,
              focusNode: _userFocus,
              textDirection: TextDirection.rtl,
              minLines: 1,
              maxLines: 3,
              style: const TextStyle(fontSize: 16),
              decoration: const InputDecoration(
                  border: OutlineInputBorder(), hintText: 'اكتب النص هون'),
              onChanged: widget.onUserText,
            ),
          ],
          if (widget.scales.isNotEmpty && s.isVisible) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Expanded(
                  child: Text('أحجام هالمقطع بس',
                      style: TextStyle(fontSize: 13, color: Colors.white)),
                ),
                if (widget.hasOwnScales)
                  TextButton(
                      onPressed: widget.onResetScales,
                      child: const Text('رجّع للحجم العام')),
              ],
            ),
            for (final e in widget.scales.keys)
              Row(
                children: [
                  SizedBox(
                      width: 92,
                      child: Text(e.label, style: const TextStyle(fontSize: 12))),
                  Expanded(
                    child: Slider(
                      value: widget.scales[e]!
                          .clamp(ElementPlacement.minScale, ElementPlacement.maxScale)
                          .toDouble(),
                      min: ElementPlacement.minScale,
                      max: ElementPlacement.maxScale,
                      divisions: 20,
                      activeColor: _gold,
                      label: '${(widget.scales[e]! * 100).round()}٪',
                      onChanged: (v) => widget.onScale(e, v),
                    ),
                  ),
                  SizedBox(
                      width: 44,
                      child: Text('${(widget.scales[e]! * 100).round()}٪',
                          style: const TextStyle(fontSize: 12))),
                ],
              ),
          ],
        ],
      ),
    );
  }

  Widget _big(IconData icon, String tip, VoidCallback? onTap) => IconButton(
        tooltip: tip,
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        icon: Icon(icon),
        onPressed: onTap,
      );

  Widget _action(IconData icon, String label, VoidCallback onTap,
          {bool danger = false}) =>
      OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 44),
          foregroundColor: danger ? Colors.redAccent : _gold,
          side: BorderSide(color: danger ? Colors.redAccent : _gold),
        ),
        onPressed: onTap,
        icon: Icon(icon, size: 20),
        label: Text(label, style: const TextStyle(fontSize: 13)),
      );

  /// سطر: [−0.1] [حقل] [+0.1] [من موقع التشغيل].
  Widget _timeRow(String label, bool isStart) {
    final ctl = isStart ? _startCtl : _endCtl;
    final focus = isStart ? _startFocus : _endFocus;
    return Row(
      children: [
        SizedBox(width: 54, child: Text(label, style: const TextStyle(fontSize: 13))),
        _stepButton('−0.1', () => _nudge(isStart, -0.1)),
        const SizedBox(width: 4),
        Expanded(
          child: TextField(
            key: ValueKey('time-${isStart ? 'start' : 'end'}'),
            controller: ctl,
            focusNode: focus,
            textAlign: TextAlign.center,
            textDirection: TextDirection.ltr,
            style: const TextStyle(fontSize: 18, fontFeatures: [FontFeature.tabularFigures()]),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
              suffixText: 'ث',
              contentPadding: EdgeInsets.symmetric(vertical: 12, horizontal: 6),
            ),
            onSubmitted: (_) => _submit(isStart),
            onTapOutside: (_) => focus.unfocus(),
          ),
        ),
        const SizedBox(width: 4),
        _stepButton('+0.1', () => _nudge(isStart, 0.1)),
        const SizedBox(width: 4),
        Tooltip(
          message: isStart
              ? 'البداية = موقع التشغيل الحالي'
              : 'النهاية = موقع التشغيل الحالي',
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
                minimumSize: const Size(56, 44),
                padding: const EdgeInsets.symmetric(horizontal: 6)),
            onPressed: () => _toPlayhead(isStart),
            child: Text(isStart ? 'من هون' : 'لهون',
                style: const TextStyle(fontSize: 12)),
          ),
        ),
      ],
    );
  }

  Widget _stepButton(String label, VoidCallback onTap) => SizedBox(
        width: 54,
        height: 44,
        child: FilledButton.tonal(
          style: FilledButton.styleFrom(padding: EdgeInsets.zero),
          onPressed: onTap,
          child: Text(label,
              textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 13)),
        ),
      );
}
