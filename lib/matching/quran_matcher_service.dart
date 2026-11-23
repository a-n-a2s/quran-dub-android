import 'package:flutter/foundation.dart';

import '../data/quran_database.dart';
import 'quran_matcher.dart';

/// نسخة وحيدة من [QuranMatcher] مبنية من قاعدة البيانات المحلية (lazy).
/// البناء بياخد أجزاء من الثانية (فهرس ~270 ألف حرف) ومرة وحدة بس.
class QuranMatcherService {
  QuranMatcherService._();
  static final QuranMatcherService instance = QuranMatcherService._();

  Future<QuranMatcher>? _matcher;

  Future<QuranMatcher> get matcher => _matcher ??= _build();

  Future<QuranMatcher> _build() async {
    final ayahs = await QuranDatabase.instance.matchableAyahs();
    final sw = Stopwatch()..start();
    final m = QuranMatcher.build(ayahs);
    debugPrint('[QuranMatcher] built in ${sw.elapsedMilliseconds}ms '
        '(${m.ayahCount} ayahs, ${m.corpusLength} letters)');
    return m;
  }

  /// فحص ذاتي سريع بيطبع بالكونسول (يوم 3): نصوص "زي ناتج محرك التعرف"
  /// (إملاء عادي بدون تشكيل) → السورة/الآية + الثقة.
  Future<List<String>> selfCheck() async {
    final m = await matcher;
    const samples = [
      'قل هو الله أحد',
      'بسم الله الرحمن الرحيم الحمد لله رب العالمين الرحمن الرحيم',
      'الله لا اله الا هو الحي القيوم لا تاخذه سنه ولا نوم',
    ];
    final lines = <String>[];
    for (final s in samples) {
      final sw = Stopwatch()..start();
      final r = m.match(s);
      final where = r?.first == null
          ? '-'
          : '${r!.first!.surah}:${r.first!.ayah}'
              '${r.ayahs.length > 1 ? '→${r.last!.surah}:${r.last!.ayah}' : ''}';
      final line = '$where (ثقة ${((r?.confidence ?? 0) * 100).round()}%، '
          '${sw.elapsedMilliseconds}ms)';
      debugPrint('[QuranMatcher] "$s" → $r');
      lines.add(line);
    }
    return lines;
  }
}
