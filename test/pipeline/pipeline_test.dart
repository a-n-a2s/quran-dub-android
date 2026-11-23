import 'package:flutter_test/flutter_test.dart';
import 'package:quran_dub/asr/asr_engine.dart';
import 'package:quran_dub/matching/arabic_normalizer.dart';
import 'package:quran_dub/matching/quran_corpus_loader.dart';
import 'package:quran_dub/matching/quran_matcher.dart';
import 'package:quran_dub/pipeline/quran_text_source.dart';
import 'package:quran_dub/pipeline/recitation_segment.dart';
import 'package:quran_dub/pipeline/segment_builder.dart';
import 'package:quran_dub/pipeline/text_splitter.dart';

/// مقطع "زي ناتج محرك التعرف": النص حرف حرف مع توقيت منتظم.
AsrSegment seg(double start, double end, String text) {
  final n = text.length;
  return AsrSegment(
    start: start,
    end: end,
    text: text,
    charTimes: [
      for (var i = 0; i < n; i++) start + (end - start) * (i + 0.5) / n,
    ],
    tokens: const [],
    timestamps: const [],
  );
}

void main() {
  late QuranMatcher matcher;
  late QuranTextSource text;

  setUpAll(() {
    matcher = QuranMatcher.build(loadSeedFile('assets/quran/quran_data.json.gz'));
    text = QuranTextSource.fromSeedFile('assets/quran/quran_data.json.gz');
  });

  test('text source: 6236 ayahs, display cleanup', () {
    expect(text.length, 6236);
    expect(QuranTextSource.cleanForDisplay('۞ وَإِذۡ‏ قَالَ'), 'وَإِذۡ قَالَ');
    // ما في ۞ بأي آية بعد التنظيف.
    for (final ref in [(2, 74), (2, 142), (18, 75)]) {
      expect(text.ayah(ref.$1, ref.$2)!.uthmani.contains('۞'), isFalse);
    }
  });

  test('Fatiha: basmala segment is 1:1 with tafsir, every ayah full', () {
    final segs = buildRecitationSegments(matcher, text, [
      seg(0.1, 5.5, 'بسم الله الرحمن الرحيم'),
      seg(6.0, 10.0, 'الحمد لله رب العلمين'),
      seg(10.5, 13.0, 'الرحمن الرحيم'),
      seg(13.5, 16.0, 'ملك يوم الدين'),
      seg(16.5, 21.0, 'اياك نعبد واياك نستعين'),
      seg(21.5, 25.0, 'اهدنا الصرط المستقيم'),
      seg(25.5, 35.0, 'صرط الذين انعمت عليهم غير المغضوب عليهم ولا الضالين'),
    ]);
    expect(pipelineAyahRefs(segs),
        ['1:1', '1:2', '1:3', '1:4', '1:5', '1:6', '1:7']);
    for (final s in segs) {
      expect(s.kind, SegmentKind.fullAyah, reason: s.describe());
      expect(s.showAyahNumber, isTrue, reason: s.describe());
      expect(s.text, text.ayah(s.surah!, s.ayah!)!.uthmani);
      expect(s.tafsir, isNotEmpty);
    }
    expect(segs.first.tafsir, text.ayah(1, 1)!.tafsir); // البسملة هون آية
    expect(segs.first.start, closeTo(0.1, 1e-9));
  });

  test('long ayah over two pauses: word-boundary parts, number on last, split tafsir', () {
    final asr = [
      seg(0, 12, 'الله لا اله الا هو الحي القيوم لا تاخذه سنه ولا نوم له ما في السموت وما في الارض من ذا الذي يشفع عنده الا باذنه'),
      seg(12.5, 26, 'يعلم ما بين ايديهم وما خلفهم ولا يحيطون بشيء من علمه الا بما شاء وسع كرسيه السموت والارض ولا يوده حفظهما وهو العلي العظيم'),
    ];
    final segs = buildRecitationSegments(matcher, text, asr);
    expect(segs.length, 2, reason: segs.map((s) => s.describe()).join('\n'));
    final full = text.ayah(2, 255)!;
    final a = segs[0], b = segs[1];
    expect([a.ref, b.ref], ['2:255', '2:255']);
    expect([a.kind, b.kind], [SegmentKind.partialAyah, SegmentKind.partialAyah]);
    expect([a.part, a.partCount, b.part, b.partCount], [1, 2, 2, 2]);
    expect([a.showAyahNumber, b.showAyahNumber], [false, true]);
    // الجزئين مع بعض = الآية كاملة بالضبط (مقطوعة على حد كلمة).
    expect('${a.text} ${b.text}', full.uthmani);
    expect(ArabicNormalizer.key(a.text).endsWith(ArabicNormalizer.key('الا باذنه')),
        isTrue, reason: a.text);
    // التفسير مقسوم: قطعتين متصلتين بيرجعوا التفسير كامل.
    expect(a.tafsir, isNot(full.tafsir));
    expect('${a.tafsir} ${b.tafsir}'.replaceAll(' ', ''),
        full.tafsir.replaceAll(' ', ''));
    expect(a.tafsirFull, full.tafsir);

    // خيار "تفسير كامل تحت كل جزء" (زي مقطع أنس المرجعي).
    final whole = buildRecitationSegments(matcher, text, asr,
        options: const PipelineOptions(tafsirMode: TafsirMode.fullUnderEachPart));
    expect(whole.map((s) => s.tafsir).toSet(), {full.tafsir});
  });

  test('ayah dropped by ASR between two matched ayahs is inferred (review)', () {
    // زي فاتحة العفاسي: التعرف ما طلّع "مالك يوم الدين" أبداً.
    final segs = buildRecitationSegments(matcher, text, [
      seg(0, 8, 'الحمد لله رب العلمين الرحمن الرحيم'),
      seg(12, 16, 'اياك نعبد واياك نستعين'),
    ]);
    expect(pipelineAyahRefs(segs), ['1:2', '1:3', '1:4', '1:5'],
        reason: segs.map((s) => s.describe()).join('\n'));
    final m = segs.firstWhere((s) => s.ref == '1:4');
    expect(m.inferred, isTrue);
    expect(m.needsReview, isTrue);
    expect(m.kind, SegmentKind.fullAyah);
    expect(m.text, text.ayah(1, 4)!.uthmani);
    expect(m.start, closeTo(8, 0.01));
    expect(m.end, closeTo(12, 0.01));
    expect(segs.where((s) => s.inferred).length, 1);
  });

  test('istiadha hidden, basmala shown without tafsir before a surah', () {
    final segs = buildRecitationSegments(matcher, text, [
      seg(0, 4, 'اعوذ بالله من الشيطان الرجيم'),
      seg(4.5, 8, 'بسم الله الرحمن الرحيم'),
      seg(8.5, 11, 'قل اعوذ برب الناس'),
      seg(11.5, 14, 'ملك الناس اله الناس'),
    ]);
    expect(segs.map((s) => s.kind).toList(), [
      SegmentKind.istiadha,
      SegmentKind.basmala,
      SegmentKind.fullAyah,
      SegmentKind.fullAyah,
      SegmentKind.fullAyah,
    ], reason: segs.map((s) => s.describe()).join('\n'));
    expect(segs[0].isVisible, isFalse);
    expect(segs[0].text, isEmpty);
    expect(segs[1].text, text.ayah(1, 1)!.uthmani);
    expect(segs[1].tafsir, isEmpty);
    expect(pipelineAyahRefs(segs), ['114:1', '114:2', '114:3']);
  });

  test('non-Quran intro is an empty placeholder for user text', () {
    final segs = buildRecitationSegments(matcher, text, [
      seg(0, 5, 'السلام عليكم ورحمه الله وبركاته اليوم نستمع لسوره الاخلاص'),
      seg(5.5, 7, 'قل هو الله احد'),
      seg(7.5, 9, 'الله الصمد'),
    ]);
    expect(segs.first.kind, SegmentKind.nonQuran,
        reason: segs.map((s) => s.describe()).join('\n'));
    expect(segs.first.isVisible, isFalse);
    expect(segs.first.copyWith(userText: 'مقدمة').isVisible, isTrue);
    expect(pipelineAyahRefs(segs), ['112:1', '112:2']);
  });

  test('tafsir splitter prefers sentence, then comma boundaries', () {
    const t = 'الجملة الأولى هنا طويلة قليلا. والجملة الثانية، وفيها فاصلة ثم تكمل حتى النهاية.';
    final b = TafsirSplitter.boundary(t, 0.4);
    expect(t.substring(0, b).trim().endsWith('.'), isTrue, reason: t.substring(0, b));
    final parts = TafsirSplitter.split(t, [(0.0, 0.4), (0.4, 1.0)])!;
    expect(parts.join(' '), t);
  });

  test('word cutter never splits inside a word', () {
    final c = AyahTextCutter(text.ayah(2, 255)!.uthmani);
    for (var k = 0; k <= c.keyLength; k += 7) {
      final b = c.boundaryAt(k);
      expect(b == 0 || b == c.text.length || c.text[b] == ' ', isTrue,
          reason: 'k=$k b=$b');
    }
  });
}
