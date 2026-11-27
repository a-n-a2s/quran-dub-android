// حفظ/تحميل تعديلات المحرر محلياً (يوم 10، القسم 6: "التعديلات اليدوية ما
// تنمسح لما المستخدم يرجع للمحرر").
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quran_dub/editor/project_edit_store.dart';
import 'package:quran_dub/pipeline/recitation_segment.dart';
import 'package:quran_dub/pipeline/segment_factory.dart';
import 'package:quran_dub/pipeline/quran_text_source.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('ayah_edits'));
  tearDown(() => dir.deleteSync(recursive: true));

  final text = QuranTextSource.fromRows([
    (50, 27, 'نص الآية', 'تفسير الآية'),
  ]);

  test('أول فتح (ما في ملف): null', () async {
    final store = ProjectEditStore(File('${dir.path}/edits.json'));
    expect(await store.load(), isNull);
  });

  test('حفظ ثم تحميل: نفس المقاطع بالضبط', () async {
    final store = ProjectEditStore(File('${dir.path}/edits.json'));
    final segments = [
      buildWholeAyahSegment(text: text, surah: 50, ayah: 27, start: 0, end: 2),
      buildUserTextSegment(start: 2, end: 3, userText: 'بسم الله نبدأ'),
    ];
    await store.save(segments);
    final loaded = await store.load();
    expect(loaded, isNotNull);
    expect(loaded!.length, 2);
    expect(loaded[0].surah, 50);
    expect(loaded[0].text, 'نص الآية');
    expect(loaded[1].userText, 'بسم الله نبدأ');
  });

  test('حفظ مرتين: الثانية بتبدّل الأولى بدون أي أثر منها', () async {
    final store = ProjectEditStore(File('${dir.path}/edits.json'));
    await store.save([
      buildWholeAyahSegment(text: text, surah: 50, ayah: 27, start: 0, end: 2),
    ]);
    await store.save([
      buildWholeAyahSegment(text: text, surah: 50, ayah: 27, start: 1, end: 5)
          .copyWith(needsReview: true),
    ]);
    final loaded = await store.load();
    expect(loaded!.length, 1);
    expect(loaded.first.start, 1);
    expect(loaded.first.needsReview, isTrue);
  });

  test('ملف تالف (JSON غلط) = null بدون انهيار', () async {
    final f = File('${dir.path}/edits.json')..createSync(recursive: true);
    f.writeAsStringSync('{"segments": [1, 2, "كلام غلط"');
    expect(await ProjectEditStore(f).load(), isNull);
  });

  test('ملف فيه عنصر مقطع تالف: الملف كامل بيترفض (ما بنثق بنصه)', () async {
    final f = File('${dir.path}/edits.json')..createSync(recursive: true);
    f.writeAsStringSync('{"segments": [{"start": 0, "end": 1}, {"no_start": true}]}');
    expect(await ProjectEditStore(f).load(), isNull);
  });

  test('clear بيمسح الملف فبعدها load بترجع null', () async {
    final store = ProjectEditStore(File('${dir.path}/edits.json'));
    await store.save([
      buildWholeAyahSegment(text: text, surah: 50, ayah: 27, start: 0, end: 2),
    ]);
    expect(await store.load(), isNotNull);
    await store.clear();
    expect(await store.load(), isNull);
  });

  test('projectEditFileName ثابت لنفس المسار ومختلف لمسار تاني', () {
    final a = projectEditFileName('/a/b/video.mp4');
    final a2 = projectEditFileName('/a/b/video.mp4');
    final b = projectEditFileName('/a/b/other.mp4');
    expect(a, a2);
    expect(a, isNot(b));
  });
}
