// تقييم ناتج خط الأنابيب (يوم 5) مقابل "الحقيقة" اللي بيكتبها
// tool/asr_prototype/prepare_clips.py لكل مقطع: الآيات المتوقعة، وبداية
// ونهاية كلام كل آية (من ملفات everyayah)، وأماكن الكلام غير القرآني.
// بيستعمله tool/asr_engine_cli.dart (محرك Dart) و tool/match_transcripts.dart
// (ناتج Python).
import 'dart:math' as math;

import 'package:quran_dub/pipeline/recitation_segment.dart';
import 'package:quran_dub/pipeline/segment_builder.dart';

class ClipEval {
  final List<String> expected;
  final List<String> found;
  final List<String> wrong;
  final List<String> missing;
  final List<String> inferred;

  /// خطأ التوقيت بالثواني (الناتج − الحقيقة) لكل آية: [ref, start, end].
  final List<(String, double, double)> timing;

  /// مقاطع آيات انكتبت فوق كلام مش قرآن (مقدمة/دعاء).
  final List<String> nonQuranHits;

  ClipEval(this.expected, this.found, this.wrong, this.missing, this.inferred,
      this.timing, this.nonQuranHits);

  bool get exact => missing.isEmpty && wrong.isEmpty && nonQuranHits.isEmpty;
  int get good => found.where(expected.contains).length;
}

List<String> expectedRange(String s) {
  // "1:1-1:7"
  final parts = s.split('-');
  final a = parts[0].split(':');
  final b = parts[1].split(':');
  final surah = int.parse(a[0]);
  return [for (var i = int.parse(a[1]); i <= int.parse(b[1]); i++) '$surah:$i'];
}

ClipEval evaluateClip(Map<String, dynamic> clip, List<RecitationSegment> segs) {
  final exp = expectedRange(clip['expected'] as String);
  final found = pipelineAyahRefs(segs);
  final wrong = found.where((f) => !exp.contains(f)).toList();
  final missing = exp.where((e) => !found.contains(e)).toList();
  final inferred = [
    for (final s in segs)
      if (s.inferred) s.ref!,
  ];

  final timing = <(String, double, double)>[];
  final hits = <String>[];
  final truth = (clip['truth'] as List<dynamic>? ?? const [])
      .cast<Map<String, dynamic>>();
  final byRef = <String, (double, double)>{};
  for (final t in truth) {
    final ref = t['ref'] as String?;
    final s = (t['start'] as num).toDouble(), e = (t['end'] as num).toDouble();
    if (ref == null) {
      // كلام مش قرآن: أي آية مكتوبة فوق أكثر من نصّه غلط.
      for (final p in segs) {
        if (!p.isAyah && p.kind != SegmentKind.basmala) continue;
        final ov = math.min(e, p.end) - math.max(s, p.start);
        if (ov > 0.5 * (e - s) || ov > 0.5 * (p.end - p.start)) {
          hits.add('${p.ref ?? 'بسملة'}@${p.start.toStringAsFixed(1)}s');
        }
      }
      continue;
    }
    final old = byRef[ref];
    byRef[ref] = old == null ? (s, e) : (math.min(old.$1, s), math.max(old.$2, e));
  }
  for (final ref in exp) {
    final t = byRef[ref];
    final mine = segs.where((p) => p.ref == ref && p.isAyah).toList();
    if (t == null || mine.isEmpty) continue;
    final ps = mine.map((p) => p.start).reduce(math.min);
    final pe = mine.map((p) => p.end).reduce(math.max);
    timing.add((ref, ps - t.$1, pe - t.$2));
  }
  return ClipEval(exp, found, wrong, missing, inferred, timing, hits);
}

/// متوسط | وسيط | أقصى (قيمة مطلقة) بالثواني.
String errStats(Iterable<double> errs) {
  final a = errs.map((e) => e.abs()).toList()..sort();
  if (a.isEmpty) return '-';
  final mean = a.reduce((x, y) => x + y) / a.length;
  final med = a[a.length ~/ 2];
  return 'متوسط ${mean.toStringAsFixed(2)}s، وسيط ${med.toStringAsFixed(2)}s، '
      'أقصى ${a.last.toStringAsFixed(2)}s';
}

/// ملخص Markdown لكل المقاطع.
String evalMarkdown(String title, List<(Map<String, dynamic>, ClipEval)> rows) {
  final md = StringBuffer()
    ..writeln('## $title\n')
    ..writeln('| المقطع | المتوقع | آيات صح | غلط | مستنتجة | فوق كلام مش قرآن | خطأ البداية (أقصى) | خطأ النهاية (أقصى) |')
    ..writeln('|---|---|---|---|---|---|---|---|');
  var exact = 0, good = 0, total = 0, wrong = 0;
  final starts = <double>[], ends = <double>[];
  for (final (c, e) in rows) {
    if (e.exact) exact++;
    good += e.good;
    total += e.expected.length;
    wrong += e.wrong.length + e.nonQuranHits.length;
    starts.addAll(e.timing.map((t) => t.$2));
    ends.addAll(e.timing.map((t) => t.$3));
    String mx(Iterable<double> x) => x.isEmpty
        ? '-'
        : '${x.map((v) => v.abs()).reduce(math.max).toStringAsFixed(2)}s';
    md.writeln('| ${c['id']} | ${c['expected']} | ${e.good}/${e.expected.length} '
        '${e.exact ? '✅' : '❌'} | ${e.wrong.isEmpty ? 0 : e.wrong.join(' ')} '
        '| ${e.inferred.isEmpty ? '-' : e.inferred.join(' ')} '
        '| ${e.nonQuranHits.isEmpty ? '-' : e.nonQuranHits.join(' ')} '
        '| ${mx(e.timing.map((t) => t.$2))} | ${mx(e.timing.map((t) => t.$3))} |');
  }
  md
    ..writeln()
    ..writeln('**PIPELINE: exact ${rows.where((r) => r.$2.exact).length}/${rows.length}, '
        'ayah recall $good/$total, wrong $wrong**\n')
    ..writeln('- خطأ توقيت **البداية** (${starts.length} آية): ${errStats(starts)}')
    ..writeln('- خطأ توقيت **النهاية** (${ends.length} آية): ${errStats(ends)}')
    ..writeln('- (الخطأ = وقت الناتج − بداية/نهاية كلام الآية الحقيقي من ملف everyayah. '
        'موجب = متأخر.)');
  assert(exact >= 0 && wrong >= 0);
  return md.toString();
}
