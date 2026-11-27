// اختيار آية (يوم 10): بحث بنص الآية، أو اختيار سورة + رقم آية. نفس النافذة
// لتغيير آية مقطع ولإضافة مقطع يدوي. بتقرأ من جداول `surahs`/`ayahs`
// (`QuranDatabase`، يوم 2/3).
import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/models/ayah.dart';
import '../../data/models/surah.dart';
import '../../data/quran_database.dart';

const Color _gold = Color(0xFFD9B55E);

/// بيرجّع (سورة، آية) أو null لو المستخدم لغى. [initial] = اقتراح (مثلاً من
/// `RecitationSegment.suggestedRef` أو الآية الحالية).
Future<(int, int)?> showAyahPicker(BuildContext context,
    {(int, int)? initial, String title = 'اختيار الآية'}) {
  return showDialog<(int, int)>(
    context: context,
    builder: (_) => Directionality(
      textDirection: TextDirection.rtl,
      child: _AyahPickerDialog(initial: initial, title: title),
    ),
  );
}

/// "50:27" → (50, 27).
(int, int)? parseRef(String? ref) {
  if (ref == null) return null;
  final m = RegExp(r'^\s*(\d{1,3})\s*[:：]\s*(\d{1,3})\s*$').firstMatch(ref);
  if (m == null) return null;
  return (int.parse(m.group(1)!), int.parse(m.group(2)!));
}

class _AyahPickerDialog extends StatefulWidget {
  final (int, int)? initial;
  final String title;
  const _AyahPickerDialog({required this.initial, required this.title});

  @override
  State<_AyahPickerDialog> createState() => _AyahPickerDialogState();
}

class _AyahPickerDialogState extends State<_AyahPickerDialog> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<Ayah> _results = const [];
  List<Surah> _surahs = const [];
  Surah? _surah;
  int _ayah = 1;
  Ayah? _preview;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final all = await QuranDatabase.instance.allSurahs();
      if (!mounted) return;
      final init = widget.initial;
      Surah? s;
      if (init != null) {
        for (final x in all) {
          if (x.number == init.$1) s = x;
        }
      }
      setState(() {
        _surahs = all;
        _surah = s ?? (all.isEmpty ? null : all.first);
        _ayah = s != null && init != null
            ? init.$2.clamp(1, s.ayahCount)
            : 1;
      });
      _loadPreview();
    } catch (e) {
      if (mounted) setState(() => _error = 'ما قدرنا نقرأ السور: $e');
    }
  }

  Future<void> _loadPreview() async {
    final s = _surah;
    if (s == null) return;
    final a = await QuranDatabase.instance.ayahAt(s.number, _ayah);
    if (mounted) setState(() => _preview = a);
  }

  void _onSearch(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      final t = q.trim();
      if (t.isEmpty) {
        if (mounted) setState(() => _results = const []);
        return;
      }
      // "50:27" مكتوب بالبحث = رقم مباشر (بيعبّي الاختيار تحت، بدون ما يسكّر
      // لحاله: ممكن المستخدم لسا عم يكتب "50:2…").
      final ref = parseRef(t);
      if (ref != null) {
        Surah? s;
        for (final x in _surahs) {
          if (x.number == ref.$1) s = x;
        }
        if (s != null && mounted) {
          setState(() {
            _surah = s;
            _ayah = ref.$2.clamp(1, s!.ayahCount);
            _results = const [];
          });
          _loadPreview();
        }
        return;
      }
      try {
        final r = await QuranDatabase.instance.searchAyahText(t);
        if (mounted) setState(() => _results = r);
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  String _surahName(int n) {
    for (final s in _surahs) {
      if (s.number == n) return s.nameArabic;
    }
    return 'سورة $n';
  }

  @override
  Widget build(BuildContext context) {
    final s = _surah;
    return AlertDialog(
      title: Text(widget.title),
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null)
                Text(_error!, style: const TextStyle(color: Colors.orange)),
              TextField(
                controller: _search,
                autofocus: false,
                textDirection: TextDirection.rtl,
                style: const TextStyle(fontSize: 16),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'ابحث بنص الآية، أو اكتب 50:27',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: _onSearch,
              ),
              for (final a in _results.take(8))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  minVerticalPadding: 10,
                  title: Text(a.textUthmani,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textDirection: TextDirection.rtl,
                      style: const TextStyle(fontSize: 15)),
                  subtitle: Text('${_surahName(a.surahNumber)} • ${a.ayahNumber}'),
                  onTap: () =>
                      Navigator.of(context).pop((a.surahNumber, a.ayahNumber)),
                ),
              const Divider(height: 24),
              const Text('أو اختار السورة والآية:',
                  style: TextStyle(fontSize: 13, color: Colors.white70)),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: DropdownButton<Surah>(
                      isExpanded: true,
                      value: s,
                      items: [
                        for (final x in _surahs)
                          DropdownMenuItem(
                              value: x, child: Text('${x.number}. ${x.nameArabic}')),
                      ],
                      onChanged: (x) {
                        if (x == null) return;
                        setState(() {
                          _surah = x;
                          _ayah = 1;
                        });
                        _loadPreview();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                    icon: const Icon(Icons.remove),
                    onPressed: s == null || _ayah <= 1
                        ? null
                        : () {
                            setState(() => _ayah--);
                            _loadPreview();
                          },
                  ),
                  Text('آية $_ayah', style: const TextStyle(fontSize: 15)),
                  IconButton(
                    constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                    icon: const Icon(Icons.add),
                    onPressed: s == null || _ayah >= s.ayahCount
                        ? null
                        : () {
                            setState(() => _ayah++);
                            _loadPreview();
                          },
                  ),
                ],
              ),
              if (s != null)
                Slider(
                  value: _ayah.toDouble(),
                  min: 1,
                  max: s.ayahCount.toDouble() < 2 ? 2 : s.ayahCount.toDouble(),
                  divisions: s.ayahCount > 1 ? s.ayahCount - 1 : 1,
                  activeColor: _gold,
                  label: '$_ayah',
                  onChanged: (v) => setState(() => _ayah = v.round().clamp(1, s.ayahCount)),
                  onChangeEnd: (_) => _loadPreview(),
                ),
              if (_preview != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(_preview!.textUthmani,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      textDirection: TextDirection.rtl,
                      style: const TextStyle(fontSize: 15, color: _gold)),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(), child: const Text('إلغاء')),
        FilledButton(
          onPressed: s == null ? null : () => Navigator.of(context).pop((s.number, _ayah)),
          child: Text(s == null ? 'اختيار' : 'اختيار ${s.number}:$_ayah'),
        ),
      ],
    );
  }
}
