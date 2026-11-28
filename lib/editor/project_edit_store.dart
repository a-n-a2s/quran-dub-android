// حفظ تعديلات المحرر اليدوية على المقاطع (يوم 10، القسم 6): "التعديلات
// اليدوية ما تنمسح لما المستخدم يرجع للمحرر". نفس نمط التخزين الآمن تبع
// `overlay_templates.dart` (ملف مؤقت ثم rename؛ ملف تالف أو مفقود = ما في
// تعديلات محفوظة، بدون ما يوقّع التطبيق). جزء صافي (dart:io بس).
import 'dart:convert';
import 'dart:io';

import '../overlay/overlay_layout.dart';
import '../overlay/overlay_style.dart';
import '../pipeline/recitation_segment.dart';

/// تعديلات مشروع محفوظة: المقاطع وأحجام كل مقطع.
class ProjectEdits {
  final List<RecitationSegment> segments;
  final Map<int, Map<OverlayElement, double>> segmentScales;

  /// الشكل الخاص بكل آية (`OverlayStyle.segmentStyles`).
  final Map<int, OverlayStyle> segmentStyles;
  const ProjectEdits(this.segments, this.segmentScales, [this.segmentStyles = const {}]);
}

/// تعديلات مشروع واحد: قائمة المقاطع بعد كل التصحيحات اليدوية (تغيير آية،
/// حذف، إضافة، تعديل توقيت، نص مستخدم). القوالب والشكل العام ([OverlayStyle]
/// بدون `segmentScales`) محفوظين لحالهم ([TemplateStore])، فهون المقاطع بس.
class ProjectEditStore {
  final File file;
  const ProjectEditStore(this.file);

  static const int _version = 2;

  /// null = ما في تعديلات محفوظة (أول فتح، أو ملف تالف/مفقود) — المتصل
  /// بيبلّش من مقاطع التحليل الأصلية.
  Future<List<RecitationSegment>?> load() async => (await loadEdits())?.segments;

  /// المقاطع + أحجام كل مقطع (`segmentScales`، مفاتيحها index بنفس القائمة
  /// المحفوظة). [base]: بصمة التحليل اللي المتصل فاتحه (`segmentsSignature`):
  /// لو الملف انحفظ فوق تحليل ثاني (المستخدم عاد التحليل) → null، عشان ما
  /// نركّب تعديلات قديمة على نتيجة جديدة.
  Future<ProjectEdits?> loadEdits({String? base}) async {
    try {
      if (!await file.exists()) return null;
      final j = jsonDecode(await file.readAsString());
      if (j is! Map || j['segments'] is! List) return null;
      if (base != null && j['base'] is String && j['base'] != base) return null;
      final out = <RecitationSegment>[];
      for (final s in j['segments'] as List) {
        final seg = RecitationSegment.fromJson(s);
        if (seg == null) return null; // عنصر تالف: ما نثق بباقي الملف.
        out.add(seg);
      }
      final scales = <int, Map<OverlayElement, double>>{};
      final raw = j['segmentScales'];
      if (raw is Map) {
        raw.forEach((k, v) {
          final idx = int.tryParse('$k');
          if (idx == null || idx < 0 || idx >= out.length || v is! Map) return;
          final m = <OverlayElement, double>{
            for (final e in OverlayElement.values)
              if (v[e.name] is num) e: clampScale((v[e.name] as num).toDouble()),
          };
          if (m.isNotEmpty) scales[idx] = m;
        });
      }
      final styles = <int, OverlayStyle>{};
      final rawStyles = j['segmentStyles'];
      if (rawStyles is Map) {
        rawStyles.forEach((k, v) {
          final idx = int.tryParse('$k');
          if (idx == null || idx < 0 || idx >= out.length || v is! Map) return;
          styles[idx] = OverlayStyle.fromJson(v);
        });
      }
      return ProjectEdits(out, scales, styles);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(List<RecitationSegment> segments,
      {String? base,
      Map<int, Map<OverlayElement, double>> segmentScales = const {},
      Map<int, OverlayStyle> segmentStyles = const {}}) async {
    final tmp = File('${file.path}.tmp');
    await file.parent.create(recursive: true);
    await tmp.writeAsString(
      jsonEncode({
        'version': _version,
        if (base != null) 'base': base,
        'segments': [for (final s in segments) s.toJson()],
        'segmentScales': {
          for (final k in segmentScales.keys)
            '$k': {
              for (final e in segmentScales[k]!.keys) e.name: segmentScales[k]![e]
            }
        },
        if (segmentStyles.isNotEmpty)
          'segmentStyles': {
            for (final k in segmentStyles.keys) '$k': segmentStyles[k]!.toJson(forTemplate: true)
          },
      }),
      flush: true,
    );
    await tmp.rename(file.path);
  }

  Future<void> clear() async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // ما في فرق لو ما قدرنا نحذفه: فتحة جاية بتحاول تحمّل وتفشل بهدوء.
    }
  }
}

/// اسم ملف ثابت ومميّز لمشروع واحد (حسب مسار الفيديو، عشان كل مشروع إله
/// ملف تعديلاته الخاص بنفس مجلد دعم التطبيق).
String projectEditFileName(String videoPath) {
  // بصمة بسيطة ومستقرة (بدون اعتماد على مكتبة خارجية): مجموع أحرف المسار.
  var hash = 0;
  for (final unit in videoPath.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return 'project_edits_${hash.toRadixString(16)}.json';
}
