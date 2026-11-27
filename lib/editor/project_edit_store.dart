// حفظ تعديلات المحرر اليدوية على المقاطع (يوم 10، القسم 6): "التعديلات
// اليدوية ما تنمسح لما المستخدم يرجع للمحرر". نفس نمط التخزين الآمن تبع
// `overlay_templates.dart` (ملف مؤقت ثم rename؛ ملف تالف أو مفقود = ما في
// تعديلات محفوظة، بدون ما يوقّع التطبيق). جزء صافي (dart:io بس).
import 'dart:convert';
import 'dart:io';

import '../pipeline/recitation_segment.dart';

/// تعديلات مشروع واحد: قائمة المقاطع بعد كل التصحيحات اليدوية (تغيير آية،
/// حذف، إضافة، تعديل توقيت، نص مستخدم). القوالب والشكل العام ([OverlayStyle]
/// بدون `segmentScales`) محفوظين لحالهم ([TemplateStore])، فهون المقاطع بس.
class ProjectEditStore {
  final File file;
  const ProjectEditStore(this.file);

  static const int _version = 1;

  /// null = ما في تعديلات محفوظة (أول فتح، أو ملف تالف/مفقود) — المتصل
  /// بيبلّش من مقاطع التحليل الأصلية.
  Future<List<RecitationSegment>?> load() async {
    try {
      if (!await file.exists()) return null;
      final j = jsonDecode(await file.readAsString());
      if (j is! Map || j['segments'] is! List) return null;
      final out = <RecitationSegment>[];
      for (final s in j['segments'] as List) {
        final seg = RecitationSegment.fromJson(s);
        if (seg == null) return null; // عنصر تالف: ما نثق بباقي الملف.
        out.add(seg);
      }
      return out;
    } catch (_) {
      return null;
    }
  }

  Future<void> save(List<RecitationSegment> segments) async {
    final tmp = File('${file.path}.tmp');
    await file.parent.create(recursive: true);
    await tmp.writeAsString(
      jsonEncode({
        'version': _version,
        'segments': [for (final s in segments) s.toJson()],
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
