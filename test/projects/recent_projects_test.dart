// المشاريع الأخيرة (الواجهة الجديدة): العنوان من المقاطع، تصغير الموجة، والتخزين
// (حفظ/ترتيب/حد أقصى/نتيجة التحليل/ملف تالف).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quran_dub/pipeline/recitation_segment.dart';
import 'package:quran_dub/projects/recent_projects.dart';

RecitationSegment _ayah(int s, int a, double t) => RecitationSegment(
    start: t, end: t + 2, kind: SegmentKind.fullAyah, surah: s, ayah: a, confidence: 1,
    text: 'نص', showAyahNumber: true);

RecentProject _p(String id, DateTime at, {String title = 'ق'}) => RecentProject(
      id: id,
      videoPath: '/v/$id.mp4',
      title: title,
      subtitle: 'الآيات',
      ayahCount: 2,
      durationSeconds: 12.5,
      width: 1920,
      height: 1080,
      rotation: 90,
      fps: 30,
      updatedAt: at,
      wave: const [0.1, 0.5, 1.0],
    );

void main() {
  test('العنوان: سورة وحدة بنطاق آيات، أكثر من سورة، وبدون آيات', () {
    final names = {50: 'سُوْرَةُ ق', 112: 'سُوْرَةُ الإِخْلَاصِ'};
    final one = describeProject([_ayah(50, 27, 0), _ayah(50, 30, 2), _ayah(50, 28, 4)], (n) => names[n]);
    expect(one.title, 'سُوْرَةُ ق');
    expect(one.subtitle, 'الآيات ٢٧–٣٠');
    expect(one.ayahs, 3);
    final single = describeProject([_ayah(50, 27, 0)], (n) => names[n]);
    expect(single.subtitle, 'الآية ٢٧');
    final many = describeProject([_ayah(50, 27, 0), _ayah(112, 1, 2)], (n) => names[n]);
    expect(many.title, contains('وغيرها'));
    final none = describeProject(
        const [RecitationSegment(start: 0, end: 1, kind: SegmentKind.nonQuran, confidence: 0)],
        (n) => null);
    expect(none.ayahs, 0);
    expect(describeProject([_ayah(7, 1, 0)], (n) => null).title, 'سورة 7');
  });

  test('أرقام عربية-هندية', () {
    expect(toArabicDigits('50:27'), '٥٠:٢٧');
  });

  test('تصغير الموجة: العدد والتطبيع', () {
    final peaks = [for (var i = 0; i < 1000; i++) (i % 10) / 20.0];
    final w = downsampleWave(peaks, n: 48);
    expect(w.length, 48);
    expect(w.reduce((a, b) => a > b ? a : b), closeTo(1.0, 1e-9));
    expect(downsampleWave(const []), isEmpty);
    expect(downsampleWave(const [0.2, 0.4], n: 4).length, 4);
  });

  test('VideoInfo من المشروع (الأبعاد الخام + الدوران)', () {
    final p = _p('a', DateTime(2026));
    expect(p.videoInfo.rotatedWidth, 1080);
    expect(p.videoInfo.rotatedHeight, 1920);
    expect(p.videoInfo.durationMs, 12500);
    expect(p.input.videoPath, '/v/a.mp4');
    expect(p.input.useExternalAudio, isFalse);
  });

  test('المخزن: إضافة، ترتيب بالأحدث، تحديث، حد أقصى، تحليل، حذف، ملف تالف', () async {
    final dir = await Directory.systemTemp.createTemp('recent_');
    addTearDown(() => dir.delete(recursive: true));
    final store = RecentProjectsStore(dir, maxProjects: 3);
    expect(await store.list(), isEmpty);

    await store.upsert(_p('a', DateTime(2026, 1, 1)), analysis: [_ayah(50, 27, 0)]);
    await store.upsert(_p('b', DateTime(2026, 1, 2)));
    var all = await store.list();
    expect(all.map((e) => e.id), ['b', 'a']);
    expect(all.last.wave, [0.1, 0.5, 1.0]);
    expect(all.last.rotation, 90);

    final seg = await store.loadAnalysis('a');
    expect(seg, isNotNull);
    expect(seg!.single.surah, 50);
    expect(await store.loadAnalysis('b'), isNull);

    // نفس المعرّف بيتحدّث بدل ما يتكرر.
    await store.upsert(_p('a', DateTime(2026, 1, 3), title: 'جديد'));
    all = await store.list();
    expect(all.length, 2);
    expect(all.first.title, 'جديد');

    await store.touch('b');
    expect((await store.list()).first.id, 'b');

    await store.upsert(_p('c', DateTime(2026, 1, 4)));
    await store.upsert(_p('d', DateTime(2026, 1, 5)), analysis: [_ayah(1, 1, 0)]);
    all = await store.list();
    expect(all.length, 3);

    await store.remove('d');
    expect((await store.list()).any((e) => e.id == 'd'), isFalse);
    expect(await store.loadAnalysis('d'), isNull);

    await File('${dir.path}/recent_projects.json').writeAsString('{خربان');
    expect(await store.list(), isEmpty);
  });

  test('المعرّف ثابت لنفس المسار ومختلف لمسار ثاني', () {
    expect(recentProjectId('/a.mp4'), recentProjectId('/a.mp4'));
    expect(recentProjectId('/a.mp4'), isNot(recentProjectId('/b.mp4')));
  });
}
