import 'dart:convert';
import 'dart:io';

import 'quran_matcher.dart';

/// يقرأ ملف الأصول المضغوط (assets/quran/quran_data.json.gz) مباشرة ويحوّله
/// لقائمة آيات للـ matcher. Dart صافي (بدون Flutter/sqflite)، عشان
/// الاختبارات وأدوات سطر الأوامر (tool/) والـ isolates.
List<MatchableAyah> parseSeedBundle(List<int> gzipBytes) {
  final jsonString = utf8.decode(GZipCodec().decode(gzipBytes));
  final bundle = json.decode(jsonString) as Map<String, dynamic>;
  final ayahs = bundle['ayahs'] as List<dynamic>;
  return [
    for (final raw in ayahs)
      MatchableAyah(
        (raw as Map<String, dynamic>)['s'] as int,
        raw['a'] as int,
        raw['t'] as String,
      ),
  ];
}

List<MatchableAyah> loadSeedFile(String path) =>
    parseSeedBundle(File(path).readAsBytesSync());
