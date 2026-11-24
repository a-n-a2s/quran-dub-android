import 'package:flutter_test/flutter_test.dart';
import 'package:quran_dub/asr/asr_engine.dart';
import 'package:quran_dub/matching/arabic_normalizer.dart';
import 'package:quran_dub/matching/quran_corpus_loader.dart';
import 'package:quran_dub/matching/quran_matcher.dart';
import 'package:quran_dub/matching/quran_sequence_matcher.dart';
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

    // نفس الشي لما الآيتين بنفس مقطع VAD (مقطع الاختبار على الجوال):
    // (التعرف ما طلّع إشي من 8 لـ 12 ثانية، بس الـ VAD ما قطع المقطع.)
    final p1 = seg(0, 8, 'الحمد لله رب العلمين الرحمن الرحيم');
    final p2 = seg(12, 20, 'اياك نعبد واياك نستعين');
    final one = buildRecitationSegments(matcher, text, [
      AsrSegment(
        start: 0,
        end: 20,
        text: '${p1.text} ${p2.text}',
        charTimes: [...p1.charTimes, 8.0, ...p2.charTimes],
        tokens: const [],
        timestamps: const [],
      ),
    ]);
    expect(pipelineAyahRefs(one), ['1:2', '1:3', '1:4', '1:5'],
        reason: one.map((s) => s.describe()).join('\n'));

    // ومع كلام خربان بالنص (ضجيج قوي) مكان الآية الناقصة:
    final noisy = buildRecitationSegments(matcher, text, [
      seg(0, 8, 'الحمد لله رب العلمين الرحمن الرحيم'),
      seg(8.5, 10, 'شسيب'),
      seg(12, 16, 'اياك نعبد واياك نستعين'),
    ]);
    expect(pipelineAyahRefs(noisy), ['1:2', '1:3', '1:4', '1:5'],
        reason: noisy.map((s) => s.describe()).join('\n'));
    expect(noisy.where((s) => s.kind == SegmentKind.nonQuran), isEmpty);
  });

  test('one-word segments too short to match alone are put back (55:1, "الله")', () {
    final rahman = buildRecitationSegments(matcher, text, [
      seg(0.1, 2.8, 'الرحمن'),
      seg(4.5, 8, 'علم القران'),
      seg(9.5, 14, 'خلق الانسن'),
    ]);
    expect(pipelineAyahRefs(rahman), ['55:1', '55:2', '55:3'],
        reason: rahman.map((s) => s.describe()).join('\n'));
    expect(rahman.first.start, closeTo(0.1, 1e-9));
    expect(rahman.first.needsReview, isTrue);

    final kursi = buildRecitationSegments(matcher, text, [
      seg(0.1, 1.5, 'الله'),
      seg(2.7, 14, 'لا اله الا هو الحي القيوم لا تاخذه سنه ولا نوم له ما في السموت وما في الارض'),
    ]);
    expect(kursi.length, 1, reason: kursi.map((s) => s.describe()).join('\n'));
    expect(kursi.first.ref, '2:255');
    expect(kursi.first.start, closeTo(0.1, 1e-9));
    expect(ArabicNormalizer.key(kursi.first.text).startsWith(ArabicNormalizer.key('الله لا اله')),
        isTrue, reason: kursi.first.text);
  });

  test('reciter repeats an ayah: a new reading, not part 2 of the first', () {
    final segs = buildRecitationSegments(matcher, text, [
      seg(0, 5, 'يوم نقول لجهنم هل امتلات وتقول هل من مزيد'),
      seg(6, 11, 'يوم نقول لجهنم هل امتلات وتقول هل من مزيد'),
    ]);
    expect(segs.map((s) => s.ref).toList(), ['50:30', '50:30'],
        reason: segs.map((s) => s.describe()).join('\n'));
    for (final s in segs) {
      expect([s.kind, s.part, s.partCount, s.showAyahNumber],
          [SegmentKind.fullAyah, 1, 1, true], reason: s.describe());
      expect(s.tafsir, s.tafsirFull);
    }
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

  // ---- يوم 7 (بعد تجربة أنس): كلمات وآيات ناقصة ----

  test('words the ASR missed at the end/start of an ayah are still shown', () {
    // زي 50:29 بتجربة أنس: التعرف ما طلّع "بظلام للعبيد".
    final tail = buildRecitationSegments(matcher, text, [
      seg(0, 6, 'ما يبدل القول لدي وما انا'),
      seg(7, 12, 'يوم نقول لجهنم هل امتلات وتقول هل من مزيد'),
    ]);
    expect(pipelineAyahRefs(tail), ['50:29', '50:30'],
        reason: tail.map((s) => s.describe()).join('\n'));
    final a = tail.firstWhere((s) => s.ref == '50:29');
    expect(a.text, text.ayah(50, 29)!.uthmani);
    expect(a.kind, SegmentKind.fullAyah);
    expect(a.showAyahNumber, isTrue);

    // وأول الآية ناقص ("يوم نقول").
    final head = buildRecitationSegments(matcher, text, [
      seg(0, 6, 'ما يبدل القول لدي وما انا بظلم للعبيد'),
      seg(7, 12, 'لجهنم هل امتلات وتقول هل من مزيد'),
    ]);
    final b = head.firstWhere((s) => s.ref == '50:30',
        orElse: () => throw head.map((s) => s.describe()).join('\n'));
    expect(b.text, text.ayah(50, 30)!.uthmani);
    expect(b.showAyahNumber, isTrue);
  });

  test('reader stops mid-ayah and starts over: first reading shows what was read', () {
    final segs = buildRecitationSegments(matcher, text, [
      seg(0, 6, 'الله لا اله الا هو الحي القيوم لا تاخذه سنه ولا نوم'),
      seg(7, 32, 'الله لا اله الا هو الحي القيوم لا تاخذه سنه ولا نوم له ما في السموت وما في الارض من ذا الذي يشفع عنده الا باذنه يعلم ما بين ايديهم وما خلفهم ولا يحيطون بشيء من علمه الا بما شاء وسع كرسيه السموت والارض ولا يوده حفظهما وهو العلي العظيم'),
    ]);
    expect(segs.map((s) => s.ref).toList(), ['2:255', '2:255'],
        reason: segs.map((s) => s.describe()).join('\n'));
    final full = text.ayah(2, 255)!.uthmani;
    expect(segs[0].showAyahNumber, isFalse);
    expect(segs[0].text.length, lessThan(full.length ~/ 2));
    expect(ArabicNormalizer.key(segs[0].text).endsWith(ArabicNormalizer.key('ولا نوم')),
        isTrue, reason: segs[0].text);
    expect(segs[1].text, full);
    expect(segs[1].showAyahNumber, isTrue);
  });

  test('several ayahs dropped by ASR are inferred when the time fits the reader pace', () {
    // الناس: التعرف طلّع 114:1 و114:6 بس، وبينهم وقت يكفي 4 آيات.
    final segs = buildRecitationSegments(matcher, text, [
      seg(0, 3, 'قل اعوذ برب الناس'),
      seg(14, 17, 'من الجنه والناس'),
    ]);
    expect(pipelineAyahRefs(segs),
        ['114:1', '114:2', '114:3', '114:4', '114:5', '114:6'],
        reason: segs.map((s) => s.describe()).join('\n'));
    expect(segs.where((s) => s.inferred).length, 4);
    for (final s in segs.where((s) => s.inferred)) {
      expect(s.needsReview, isTrue);
      expect(s.start, greaterThanOrEqualTo(2.9));
      expect(s.end, lessThanOrEqualTo(14.01));
    }

    // بس لو ما في وقت يكفي (القارئ قفز)، ما بنخترع آيات.
    final jump = buildRecitationSegments(matcher, text, [
      seg(0, 3, 'قل اعوذ برب الناس'),
      seg(3.6, 6.6, 'من الجنه والناس'),
    ]);
    expect(jump.where((s) => s.inferred), isEmpty,
        reason: jump.map((s) => s.describe()).join('\n'));
  });

  test('weak segment between two consistent ayahs comes back as an ayah (review)', () {
    final texts = [
      'الحمد لله رب العلمين الرحمن الرحيم',
      'ملك يوم الدين',
      'اياك نعبد واياك نستعين',
    ];
    final asr = [seg(0, 6, texts[0]), seg(6.5, 9, texts[1]), seg(9.5, 13, texts[2])];
    final matches = QuranSequenceMatcher(matcher).matchAll(texts);
    expect(matches[1], isNotNull);
    // نخلّي المقطع الثاني "ضعيف" (زي تسجيل جوال فيه ضجيج).
    final weak = List<QuranMatch?>.of(matches)
      ..[1] = matches[1]!.copyWith(confidence: 0.2);
    final segs = segmentsFromMatches(text, asr, weak);
    expect(pipelineAyahRefs(segs), ['1:2', '1:3', '1:4', '1:5'],
        reason: segs.map((s) => s.describe()).join('\n'));
    final m = segs.firstWhere((s) => s.ref == '1:4');
    expect(m.inferred, isFalse); // توقيته الحقيقي
    expect(m.needsReview, isTrue);
    expect(m.start, closeTo(6.5, 0.01));
    expect(segs.where((s) => s.kind == SegmentKind.nonQuran), isEmpty);

    // ضعيف بآخر الفيديو (مش محصور): بيضل "مش قرآن" (ممكن يكون دعاء).
    final tailWeak = List<QuranMatch?>.of(matches)
      ..[2] = matches[2]!.copyWith(confidence: 0.2);
    final segs2 = segmentsFromMatches(text, asr, tailWeak);
    expect(segs2.last.kind, SegmentKind.nonQuran,
        reason: segs2.map((s) => s.describe()).join('\n'));
    expect(segs2.last.suggestedRef, '1:5');
  });
}
