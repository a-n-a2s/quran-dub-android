// "مشاريع القرآن الأخيرة" بالشاشة الرئيسية (الواجهة الجديدة). كل مشروع = فيديو
// انحلّل: مساره، معلوماته، عنوانه (السورة والآيات)، موجة مصغّرة للبطاقة، ونتيجة
// التحليل الأصلية (ملف لحاله) عشان يرجع يفتح المحرر **بدون تحليل جديد**. تعديلات
// المحرر نفسها بـ `ProjectEditStore` (يوم 10) ومربوطة ببصمة نفس المقاطع.
//
// جزء صافي (dart:io بس)، والتخزين JSON بكتابة آمنة (ملف مؤقت + rename) زي
// القوالب وتعديلات المحرر. ملف تالف = قائمة فاضية بدون انهيار.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import '../editor/project_edit_store.dart';
import '../pipeline/project_input.dart';
import '../pipeline/recitation_segment.dart';

class RecentProject {
  final String id;
  final String videoPath;
  final String? externalAudioPath;
  final bool useExternalAudio;
  final String title;
  final String subtitle;
  final int ayahCount;
  final double durationSeconds;
  final int width;
  final int height;
  final int rotation;
  final double fps;
  final bool hasAudioTrack;
  final DateTime updatedAt;

  /// موجة مصغّرة (0..1) للبطاقة.
  final List<double> wave;

  /// معلومات الفيديو ([width]/[height] الخام قبل الدوران، زي [VideoInfo]).
  VideoInfo get videoInfo => VideoInfo(
        width: width,
        height: height,
        rotationDegrees: rotation,
        durationMs: (durationSeconds * 1000).round(),
        fps: fps,
        hasAudioTrack: hasAudioTrack,
      );

  ProjectInput get input => ProjectInput(
        videoPath: videoPath,
        source: VideoSource.gallery,
        videoInfo: videoInfo,
        externalAudioPath: externalAudioPath,
        useExternalAudio: useExternalAudio && externalAudioPath != null,
      );

  const RecentProject({
    required this.id,
    required this.videoPath,
    this.externalAudioPath,
    this.useExternalAudio = false,
    required this.title,
    required this.subtitle,
    required this.ayahCount,
    required this.durationSeconds,
    required this.width,
    required this.height,
    this.rotation = 0,
    this.fps = 0,
    this.hasAudioTrack = true,
    required this.updatedAt,
    this.wave = const [],
  });

  Map<String, Object?> toJson() => {
        'id': id,
        'video': videoPath,
        if (externalAudioPath != null) 'audio': externalAudioPath,
        'use_audio': useExternalAudio,
        'title': title,
        'subtitle': subtitle,
        'ayahs': ayahCount,
        'duration': durationSeconds,
        'w': width,
        'h': height,
        'rot': rotation,
        'fps': fps,
        'has_audio': hasAudioTrack,
        'updated': updatedAt.millisecondsSinceEpoch,
        'wave': [for (final v in wave) (v * 100).round()],
      };

  static RecentProject? fromJson(Object? j) {
    if (j is! Map) return null;
    try {
      return RecentProject(
        id: j['id'] as String,
        videoPath: j['video'] as String,
        externalAudioPath: j['audio'] as String?,
        useExternalAudio: j['use_audio'] == true,
        title: (j['title'] as String?) ?? '',
        subtitle: (j['subtitle'] as String?) ?? '',
        ayahCount: (j['ayahs'] as num?)?.toInt() ?? 0,
        durationSeconds: (j['duration'] as num?)?.toDouble() ?? 0,
        width: (j['w'] as num?)?.toInt() ?? 0,
        height: (j['h'] as num?)?.toInt() ?? 0,
        rotation: (j['rot'] as num?)?.toInt() ?? 0,
        fps: (j['fps'] as num?)?.toDouble() ?? 0,
        hasAudioTrack: j['has_audio'] != false,
        updatedAt: DateTime.fromMillisecondsSinceEpoch((j['updated'] as num?)?.toInt() ?? 0),
        wave: [
          for (final v in (j['wave'] as List?) ?? const [])
            if (v is num) (v / 100).clamp(0.0, 1.0).toDouble()
        ],
      );
    } catch (_) {
      return null;
    }
  }
}

/// المعرّف الثابت لمشروع فيديو (نفس اسم ملف تعديلاته بدون الامتداد).
String recentProjectId(String videoPath) =>
    projectEditFileName(videoPath).replaceAll('project_edits_', '').replaceAll('.json', '');

/// عنوان المشروع من المقاطع: "ق • ٢٧–٣٠" مثلاً، و"عدة سور" لو أكثر من سورة.
/// [surahName] بيرجع اسم السورة (أو null).
({String title, String subtitle, int ayahs}) describeProject(
    List<RecitationSegment> segments, String? Function(int surah) surahName) {
  final refs = <(int, int)>{};
  for (final s in segments) {
    if (s.isAyah && s.surah != null && s.ayah != null && s.ayah! > 0) {
      refs.add((s.surah!, s.ayah!));
    }
  }
  if (refs.isEmpty) return (title: 'مشروع بدون آيات', subtitle: '', ayahs: 0);
  final surahs = {for (final r in refs) r.$1}.toList()..sort();
  String name(int s) {
    final n = surahName(s);
    return (n == null || n.trim().isEmpty) ? 'سورة $s' : n.trim();
  }

  if (surahs.length == 1) {
    final ayahs = [for (final r in refs) r.$2]..sort();
    final a = toArabicDigits('${ayahs.first}');
    final b = toArabicDigits('${ayahs.last}');
    return (
      title: name(surahs.first),
      subtitle: ayahs.first == ayahs.last ? 'الآية $a' : 'الآيات $a–$b',
      ayahs: refs.length,
    );
  }
  return (
    title: '${name(surahs.first)} وغيرها',
    subtitle: '${toArabicDigits('${surahs.length}')} سور • ${toArabicDigits('${refs.length}')} آية',
    ayahs: refs.length,
  );
}

/// أرقام عربية-هندية.
String toArabicDigits(String s) {
  const d = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
  final b = StringBuffer();
  for (final c in s.codeUnits) {
    if (c >= 48 && c <= 57) {
      b.write(d[c - 48]);
    } else {
      b.writeCharCode(c);
    }
  }
  return b.toString();
}

/// تصغير موجة (peaks) لـ [n] قيمة للبطاقة (أعلى قيمة بكل جزء، مطبّعة).
List<double> downsampleWave(List<double> peaks, {int n = 48}) {
  if (peaks.isEmpty) return const [];
  final out = List<double>.filled(n, 0);
  for (var i = 0; i < n; i++) {
    final a = (i * peaks.length / n).floor();
    final b = math.max(a + 1, ((i + 1) * peaks.length / n).floor());
    var m = 0.0;
    for (var k = a; k < b && k < peaks.length; k++) {
      if (peaks[k] > m) m = peaks[k];
    }
    out[i] = m;
  }
  final mx = out.fold<double>(0, math.max);
  if (mx <= 0) return out;
  return [for (final v in out) v / mx];
}

/// مخزن المشاريع الأخيرة: `recent_projects.json` + نتيجة تحليل كل مشروع بملف
/// `analysis_<id>.json` بنفس المجلد.
class RecentProjectsStore {
  final Directory dir;
  final int maxProjects;

  RecentProjectsStore(this.dir, {this.maxProjects = 30});

  File get _index => File('${dir.path}/recent_projects.json');
  File _analysis(String id) => File('${dir.path}/analysis_$id.json');

  Future<List<RecentProject>> list() async {
    try {
      if (!await _index.exists()) return const [];
      final j = jsonDecode(await _index.readAsString());
      if (j is! Map || j['projects'] is! List) return const [];
      final out = <RecentProject>[
        for (final p in j['projects'] as List)
          if (RecentProject.fromJson(p) case final r?) r
      ];
      out.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return out;
    } catch (_) {
      return const [];
    }
  }

  Future<void> _writeAtomic(File f, String text) async {
    await f.parent.create(recursive: true);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(text, flush: true);
    await tmp.rename(f.path);
  }

  /// إضافة/تحديث مشروع (بيطلع أول القائمة) مع نتيجة تحليله الأصلية.
  Future<void> upsert(RecentProject p, {List<RecitationSegment>? analysis}) async {
    final all = [...await list()]..removeWhere((e) => e.id == p.id);
    all.insert(0, p);
    final removed = all.length > maxProjects ? all.sublist(maxProjects) : const <RecentProject>[];
    final kept = all.take(maxProjects).toList();
    await _writeAtomic(_index, jsonEncode({'v': 1, 'projects': [for (final e in kept) e.toJson()]}));
    if (analysis != null) {
      await _writeAtomic(_analysis(p.id),
          jsonEncode({'v': 1, 'segments': [for (final s in analysis) s.toJson()]}));
    }
    for (final r in removed) {
      try {
        await _analysis(r.id).delete();
      } catch (_) {}
    }
  }

  /// تحديث وقت آخر فتح بس.
  Future<void> touch(String id) async {
    final all = [...await list()];
    final i = all.indexWhere((e) => e.id == id);
    if (i < 0) return;
    final p = all[i];
    all[i] = RecentProject(
      id: p.id,
      videoPath: p.videoPath,
      externalAudioPath: p.externalAudioPath,
      useExternalAudio: p.useExternalAudio,
      title: p.title,
      subtitle: p.subtitle,
      ayahCount: p.ayahCount,
      durationSeconds: p.durationSeconds,
      width: p.width,
      height: p.height,
      rotation: p.rotation,
      fps: p.fps,
      hasAudioTrack: p.hasAudioTrack,
      updatedAt: DateTime.now(),
      wave: p.wave,
    );
    all.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    await _writeAtomic(_index, jsonEncode({'v': 1, 'projects': [for (final e in all) e.toJson()]}));
  }

  /// نتيجة التحليل الأصلية (أو null لو مش موجودة أو تالفة).
  Future<List<RecitationSegment>?> loadAnalysis(String id) async {
    try {
      final f = _analysis(id);
      if (!await f.exists()) return null;
      final j = jsonDecode(await f.readAsString());
      if (j is! Map || j['segments'] is! List) return null;
      final out = <RecitationSegment>[
        for (final s in j['segments'] as List)
          if (RecitationSegment.fromJson(s) case final r?) r
      ];
      return out.isEmpty ? null : out;
    } catch (_) {
      return null;
    }
  }

  Future<void> remove(String id) async {
    final all = [...await list()]..removeWhere((e) => e.id == id);
    await _writeAtomic(_index, jsonEncode({'v': 1, 'projects': [for (final e in all) e.toJson()]}));
    try {
      await _analysis(id).delete();
    } catch (_) {}
  }
}
