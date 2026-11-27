// لوحة تفاصيل المقطع (يوم 10، طلب أنس صريح): لوحة خاصة غير تبويبات
// التخصيص، بتفتح لما يكبس المستخدم على مقطع (آية) بالخط الزمني. فيها: ثانية
// البداية والنهاية بطريقتين متزامنتين (كتابة بدقة 0.1 ثانية مع أزرار ±،
// وسحب على الخط الزمني — السحب نفسه بالخط الزمني مش هون، بس هالحقول بتتبع
// نفس القيمة)، تغيير الآية (بحث أو سورة+آية)، حذف المقطع، وأحجام هالمقطع
// الخاصة (`OverlayStyle.segmentScales`).
import 'package:flutter/material.dart';

import '../../data/models/ayah.dart';
import '../../data/models/surah.dart';
import '../../data/quran_database.dart';
import '../../overlay/overlay_layout.dart';
import '../../pipeline/recitation_segment.dart';

const Color _gold = Color(0xFFD9B55E);

/// نتيجة فتح اللوحة: بترجع فالسالب أو true لو انحذف المقطع (الشاشة الأم
/// لازم تشيله من القائمة لو رجعت true).
Future<void> showSegmentDetailSheet(
  BuildContext context, {
  required RecitationSegment segment,
  required int index,
  required double duration,
  required String Function(int surah) surahName,
  required double Function(OverlayElement) scaleOf,
  required void Function(OverlayElement element, double scale) onScaleChanged,
  required void Function(double start, double end) onBoundsChanged,
  required void Function(int surah, int ayah) onChangeAyah,
  required void Function(String text) onUserTextChanged,
  required VoidCallback onDelete,
  required VoidCallback onConfirmReview,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF17432F),
    builder: (ctx) => Directionality(
      textDirection: TextDirection.rtl,
      child: DraggableScrollableSheet(
        initialChildSize: 0.65,
        minChildSize: 0.35,
        maxChildSize: 0.92,
        expand: false,
        builder: (ctx2, scrollCtl) => _SegmentDetailSheetBody(
          scrollController: scrollCtl,
          segment: segment,
          index: index,
          duration: duration,
          surahName: surahName,
          scaleOf: scaleOf,
          onScaleChanged: onScaleChanged,
          onBoundsChanged: onBoundsChanged,
          onChangeAyah: onChangeAyah,
          onUserTextChanged: onUserTextChanged,
          onDelete: onDelete,
          onConfirmReview: onConfirmReview,
        ),
      ),
    ),
  );
}

class _SegmentDetailSheetBody extends StatefulWidget {
  final ScrollController scrollController;
  final RecitationSegment segment;
  final int index;
  final double duration;
  final String Function(int surah) surahName;
  final double Function(OverlayElement) scaleOf;
  final void Function(OverlayElement element, double scale) onScaleChanged;
  final void Function(double start, double end) onBoundsChanged;
  final void Function(int surah, int ayah) onChangeAyah;
  final void Function(String text) onUserTextChanged;
  final VoidCallback onDelete;
  final VoidCallback onConfirmReview;

  const _SegmentDetailSheetBody({
    required this.scrollController,
    required this.segment,
    required this.index,
    required this.duration,
    required this.surahName,
    required this.scaleOf,
    required this.onScaleChanged,
    required this.onBoundsChanged,
    required this.onChangeAyah,
    required this.onUserTextChanged,
    required this.onDelete,
    required this.onConfirmReview,
  });

  @override
  State<_SegmentDetailSheetBody> createState() => _SegmentDetailSheetBodyState();
}

class _SegmentDetailSheetBodyState extends State<_SegmentDetailSheetBody> {
  late double _start = widget.segment.start;
  late double _end = widget.segment.end;
  late final TextEditingController _startCtl =
      TextEditingController(text: _fmt(_start));
  late final TextEditingController _endCtl =
      TextEditingController(text: _fmt(_end));
  late final TextEditingController _userTextCtl =
      TextEditingController(text: widget.segment.userText ?? '');
  final TextEditingController _searchCtl = TextEditingController();
  List<Ayah> _searchResults = const [];
  bool _changingAyah = false;

  static String _fmt(double v) => v.toStringAsFixed(1);

  @override
  void initState() {
    super.initState();
    if ((widget.segment.suggestedRef ?? '').isNotEmpty) {
      _searchCtl.text = widget.segment.suggestedRef!;
    }
  }

  @override
  void dispose() {
    _startCtl.dispose();
    _endCtl.dispose();
    _userTextCtl.dispose();
    _searchCtl.dispose();
    super.dispose();
  }

  void _applyBounds() {
    var s = _start, e = _end;
    if (e <= s) e = s + 0.1;
    if (s < 0) s = 0;
    if (e > widget.duration && widget.duration > 0) e = widget.duration;
    setState(() {
      _start = s;
      _end = e;
      _startCtl.text = _fmt(s);
      _endCtl.text = _fmt(e);
    });
    widget.onBoundsChanged(s, e);
  }

  void _nudge(bool isStart, double delta) {
    setState(() {
      if (isStart) {
        _start = (_start + delta).clamp(0.0, widget.duration > 0 ? widget.duration : 1e9);
      } else {
        _end = (_end + delta).clamp(0.0, widget.duration > 0 ? widget.duration : 1e9);
      }
    });
    _applyBounds();
  }

  void _onFieldSubmit(bool isStart, String value) {
    final v = double.tryParse(value.trim());
    if (v == null) return;
    setState(() {
      if (isStart) {
        _start = v;
      } else {
        _end = v;
      }
    });
    _applyBounds();
  }

  Future<void> _search(String q) async {
    if (q.trim().isEmpty) {
      setState(() => _searchResults = const []);
      return;
    }
    try {
      final results = await QuranDatabase.instance.searchAyahText(q.trim());
      if (!mounted) return;
      setState(() => _searchResults = results);
    } catch (_) {
      // بدون نت ولا قاعدة بيانات: البحث ببساطة ما بيرجّع شي.
    }
  }

  Future<void> _pickBySurahAyah() async {
    final surahs = await QuranDatabase.instance.allSurahs();
    if (!mounted) return;
    Surah? selectedSurah =
        surahs.where((s) => s.number == widget.segment.surah).firstOrNull ??
            (surahs.isEmpty ? null : surahs.first);
    List<Ayah> ayahs =
        selectedSurah == null ? const [] : await QuranDatabase.instance.ayahsOfSurah(selectedSurah.number);
    Ayah? selectedAyah =
        ayahs.where((a) => a.ayahNumber == widget.segment.ayah).firstOrNull ??
            (ayahs.isEmpty ? null : ayahs.first);
    if (!mounted) return;
    final result = await showDialog<(int, int)>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(builder: (ctx, setD) {
          return AlertDialog(
            title: const Text('اختيار سورة وآية'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButton<Surah>(
                  isExpanded: true,
                  value: selectedSurah,
                  items: [
                    for (final s in surahs)
                      DropdownMenuItem(value: s, child: Text('${s.number}. ${s.nameArabic}')),
                  ],
                  onChanged: (s) async {
                    if (s == null) return;
                    final a = await QuranDatabase.instance.ayahsOfSurah(s.number);
                    setD(() {
                      selectedSurah = s;
                      ayahs = a;
                      selectedAyah = a.isEmpty ? null : a.first;
                    });
                  },
                ),
                const SizedBox(height: 8),
                DropdownButton<Ayah>(
                  isExpanded: true,
                  value: selectedAyah,
                  items: [
                    for (final a in ayahs)
                      DropdownMenuItem(value: a, child: Text('آية ${a.ayahNumber}')),
                  ],
                  onChanged: (a) => setD(() => selectedAyah = a),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
              FilledButton(
                onPressed: selectedSurah == null || selectedAyah == null
                    ? null
                    : () => Navigator.pop(ctx, (selectedSurah!.number, selectedAyah!.ayahNumber)),
                child: const Text('اختيار'),
              ),
            ],
          );
        }),
      ),
    );
    if (result != null) {
      widget.onChangeAyah(result.$1, result.$2);
      if (mounted) setState(() => _changingAyah = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.segment;
    final isAyah = s.isAyah;
    final isNonQuran = s.kind == SegmentKind.nonQuran;
    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
      children: [
        Center(
          child: Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
                color: Colors.white38, borderRadius: BorderRadius.circular(4)),
          ),
        ),
        Text(
          isAyah
              ? '${widget.surahName(s.surah ?? 0)} • آية ${s.ayah}'
                  '${s.partCount > 1 ? ' (جزء ${s.part}/${s.partCount})' : ''}'
              : (s.kind == SegmentKind.basmala ? 'بسملة' : 'لوحة تفاصيل المقطع'),
          style: const TextStyle(
              fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        if (s.needsReview || s.inferred)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: [
                const Icon(Icons.priority_high, color: Colors.orange, size: 18),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    s.inferred
                        ? 'مقطع مستنتج: التعرف ما طلّعها، التوقيت تقديري.'
                        : 'بده مراجعة.',
                    style: const TextStyle(fontSize: 12, color: Colors.orange),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    widget.onConfirmReview();
                    Navigator.of(context).maybePop();
                  },
                  child: const Text('تأكيد'),
                ),
              ],
            ),
          ),
        const SizedBox(height: 14),
        const Text('البداية والنهاية (ثانية)',
            style: TextStyle(color: Colors.white70, fontSize: 12)),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(child: _timeField('البداية', _startCtl, isStart: true)),
            const SizedBox(width: 10),
            Expanded(child: _timeField('النهاية', _endCtl, isStart: false)),
          ],
        ),
        const SizedBox(height: 4),
        Text('المدة: ${(_end - _start).toStringAsFixed(1)}ث',
            style: const TextStyle(fontSize: 11, color: Colors.white54)),
        const SizedBox(height: 16),
        if (isAyah) ...[
          const Divider(color: Colors.white24),
          Row(
            children: [
              const Expanded(child: Text('تغيير الآية', style: TextStyle(color: Colors.white))),
              TextButton.icon(
                onPressed: () => setState(() => _changingAyah = !_changingAyah),
                icon: Icon(_changingAyah ? Icons.close : Icons.edit, size: 18),
                label: Text(_changingAyah ? 'إلغاء' : 'تغيير'),
              ),
            ],
          ),
          if (_changingAyah) ...[
            TextField(
              controller: _searchCtl,
              textDirection: TextDirection.rtl,
              decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                  hintText: 'ابحث بنص الآية (مثلاً: الحمد لله)',
                  suffixIcon: Icon(Icons.search)),
              onChanged: _search,
            ),
            const SizedBox(height: 6),
            for (final a in _searchResults.take(8))
              ListTile(
                dense: true,
                title: Text(a.textUthmani,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    textDirection: TextDirection.rtl),
                subtitle: Text('${a.surahNumber}:${a.ayahNumber}'),
                onTap: () {
                  widget.onChangeAyah(a.surahNumber, a.ayahNumber);
                  setState(() => _changingAyah = false);
                },
              ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: _pickBySurahAyah,
                icon: const Icon(Icons.list_alt, size: 18),
                label: const Text('أو اختيار سورة وآية من قائمة'),
              ),
            ),
          ],
          const SizedBox(height: 10),
          const Divider(color: Colors.white24),
          const Text('أحجام هالمقطع بس', style: TextStyle(color: Colors.white)),
          for (final e in flowElements)
            if (e.available)
            Row(
              children: [
                SizedBox(width: 80, child: Text(e.label, style: const TextStyle(fontSize: 12))),
                Expanded(
                  child: Slider(
                    value: widget.scaleOf(e),
                    min: ElementPlacement.minScale,
                    max: ElementPlacement.maxScale,
                    divisions: 20,
                    activeColor: _gold,
                    label: '${(widget.scaleOf(e) * 100).round()}٪',
                    onChanged: (v) => setState(() => widget.onScaleChanged(e, v)),
                  ),
                ),
              ],
            ),
        ],
        if (isNonQuran) ...[
          const Divider(color: Colors.white24),
          const Text('نص المستخدم (كلام غير قرآني)', style: TextStyle(color: Colors.white)),
          const SizedBox(height: 6),
          TextField(
            controller: _userTextCtl,
            textDirection: TextDirection.rtl,
            maxLines: 3,
            decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                hintText: 'مثلاً: بسم الله، أو دعاء...'),
            onChanged: widget.onUserTextChanged,
          ),
        ],
        const SizedBox(height: 20),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent),
          onPressed: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (ctx) => Directionality(
                textDirection: TextDirection.rtl,
                child: AlertDialog(
                  title: const Text('حذف المقطع؟'),
                  content: const Text('ما في تراجع بعد الحذف.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
                    FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف')),
                  ],
                ),
              ),
            );
            if (ok == true) {
              widget.onDelete();
              if (context.mounted) Navigator.of(context).maybePop();
            }
          },
          icon: const Icon(Icons.delete_outline),
          label: const Text('حذف هالمقطع'),
        ),
      ],
    );
  }

  Widget _timeField(String label, TextEditingController ctl, {required bool isStart}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.white54)),
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.remove_circle_outline, size: 20),
              onPressed: () => _nudge(isStart, -0.1),
            ),
            Expanded(
              child: TextField(
                controller: ctl,
                textAlign: TextAlign.center,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                onSubmitted: (v) => _onFieldSubmit(isStart, v),
                onTapOutside: (_) => _onFieldSubmit(isStart, ctl.text),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline, size: 20),
              onPressed: () => _nudge(isStart, 0.1),
            ),
          ],
        ),
      ],
    );
  }
}
