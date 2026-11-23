import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:quran_dub/matching/arabic_normalizer.dart';
import 'package:quran_dub/matching/quran_corpus_loader.dart';
import 'package:quran_dub/matching/quran_matcher.dart';
import 'package:quran_dub/matching/quran_sequence_matcher.dart';

void main() {
  late List<MatchableAyah> ayahs;
  late QuranMatcher matcher;

  setUpAll(() {
    ayahs = loadSeedFile('assets/quran/quran_data.json.gz');
    final sw = Stopwatch()..start();
    matcher = QuranMatcher.build(ayahs);
    // ignore: avoid_print
    print('matcher built in ${sw.elapsedMilliseconds}ms: '
        '${matcher.ayahCount} ayahs, ${matcher.corpusLength} letters');
  });

  group('ArabicNormalizer', () {
    test('Uthmani and imlaei spellings share the same key', () {
      const pairs = [
        ['ٱلۡحَمۡدُ لِلَّهِ رَبِّ ٱلۡعَٰلَمِينَ', 'الحمد لله رب العالمين'],
        ['يَٰٓأَيُّهَا ٱلَّذِينَ ءَامَنُواْ', 'يا أيها الذين آمنوا'],
        ['ذَٰلِكَ ٱلۡكِتَٰبُ لَا رَيۡبَۛ فِيهِۛ هُدࣰ ى لِّلۡمُتَّقِينَ',
            'ذلك الكتاب لا ريب فيه هدى للمتقين'],
        ['بِسۡمِ ٱللَّهِ ٱلرَّحۡمَٰنِ ٱلرَّحِيمِ', 'بسم الله الرحمن الرحيم'],
      ];
      for (final p in pairs) {
        expect(ArabicNormalizer.key(p[0]), ArabicNormalizer.key(p[1]),
            reason: p[1]);
      }
    });

    test('simple() keeps words and alefs but drops marks', () {
      expect(ArabicNormalizer.simple('ٱلۡحَمۡدُ لِلَّهِ رَبِّ ٱلۡعَٰلَمِينَ'),
          'الحمد لله رب العلمين');
    });

    test('keyWithMap points back to source characters', () {
      const s = 'قُلۡ هُوَ';
      final n = ArabicNormalizer.keyWithMap(s);
      expect(n.key, 'قلهو');
      for (var i = 0; i < n.key.length; i++) {
        expect(s[n.sourceIndex[i]], n.key[i]);
      }
    });
  });

  group('QuranMatcher', () {
    void expectAt(QuranMatch? r, int s, int a, {int? lastS, int? lastA}) {
      expect(r, isNotNull);
      expect('${r!.first!.surah}:${r.first!.ayah}', '$s:$a', reason: '$r');
      if (lastS != null) {
        expect('${r.last!.surah}:${r.last!.ayah}', '$lastS:$lastA',
            reason: '$r');
      }
    }

    test('single ayah in plain imlaei spelling', () {
      final r = matcher.match('قل هو الله أحد');
      expectAt(r, 112, 1);
      expect(r!.similarity, 1.0);
      // 9 حروف بس: الثقة مقصود تكون أوطى من المقاطع الطويلة.
      expect(r.confidence, greaterThan(0.3));
    });

    test('multi-ayah span is split per ayah', () {
      final r = matcher.match(
          'الحمد لله رب العالمين الرحمن الرحيم مالك يوم الدين إياك نعبد');
      expectAt(r, 1, 2, lastS: 1, lastA: 5);
      expect(r!.ayahs.map((e) => e.ayah).toList(), [2, 3, 4, 5]);
      expect(r.ayahs.last.coverage, lessThan(1.0)); // 1:5 ناقصة
      expect(r.confidence, greaterThan(0.9));
    });

    test('partial Ayat al-Kursi with ASR-like errors', () {
      // حذف/استبدال حروف عمداً (الحى→الحي، القيوم→القيم، سنه→سنت)
      final r = matcher.match(
          'الله لا اله الا هو الحي القيم لا تاخذه سنت ولا نوم له ما في السماوات');
      expectAt(r, 2, 255);
      expect(r!.similarity, greaterThan(0.85));
    });

    test('istiadha + basmala preambles are detected', () {
      final r = matcher.match(
          'أعوذ بالله من الشيطان الرجيم بسم الله الرحمن الرحيم قل أعوذ برب الناس ملك الناس');
      expectAt(r, 114, 1, lastS: 114, lastA: 2);
      expect(r!.preambles.map((p) => p.type).toList(),
          [PreambleType.istiadha, PreambleType.basmala]);
    });

    test('basmala followed by Al-Fatiha becomes ayah 1:1', () {
      final r = matcher.match('بسم الله الرحمن الرحيم الحمد لله رب العالمين');
      expectAt(r, 1, 1, lastS: 1, lastA: 2);
      expect(r!.preambles, isEmpty);
    });

    test('repeated ayah is ambiguous alone, resolved by context', () {
      const refrain = 'فبأي آلاء ربكما تكذبان';
      final alone = matcher.match(refrain);
      expect(alone, isNotNull);
      expect(alone!.isAmbiguous, isTrue, reason: '$alone');

      final prevEnd = matcher.corpusEndOf(55, 15)!;
      final r = matcher.match(refrain, previousEnd: prevEnd);
      expectAt(r, 55, 16);
      expect(r!.continuesContext, isTrue);
      expect(r.isAmbiguous, isFalse);
    });

    test('ayah dropped mid-segment by ASR (affine gap, يوم 5)', () {
      // سيناريو حقيقي: فاتحة العفاسي، التعرف أسقط آية 1:4 "مالك يوم الدين"
      // كاملة من نص المقطع (التلاوة فيها، بس التعرف ما طلّعها). قبل إصلاح
      // المحاذاة (affine gap)، المحاذاة بتكلفة موحّدة كانت بتفضّل تتوقف
      // عند 1:5 بدل ما تعبر الفجوة لـ 1:6/1:7.
      const text = 'بسم الله الرحمن الرحيم '
          'الحمد لله رب العالمين '
          'الرحمن الرحيم '
          // (1:4 مالك يوم الدين: ناقصة)
          'اياك نعبد واياك نستعين '
          'اهدنا الصراط المستقيم '
          'صراط الذين انعمت عليهم غير المغضوب عليهم ولا الضالين';
      final r = matcher.match(text);
      expectAt(r, 1, 1, lastS: 1, lastA: 7);
      expect(r!.ayahs.map((e) => e.ayah).toList(), [1, 2, 3, 5, 6, 7],
          reason: 'الآية 1:4 لازم تبقى غايبة (ما انقرأت أصلاً) بدون ما '
              'توقف المحاذاة قبل 1:6/1:7: $r');
      // الفجوة (مكان 1:4 المحذوفة) ما لازم توقّف الثقة كتير.
      expect(r.confidence, greaterThan(0.5), reason: '$r');
    });

    test('too short / non-Quran text', () {
      expect(matcher.match('من'), isNull);
      final r = matcher.match('السلام عليكم ورحمة الله وبركاته كيف حالكم اليوم');
      expect(r == null || r.confidence < 0.6, isTrue, reason: '$r');
    });

    test('sequence: short ambiguous segments resolved by neighbours', () {
      final seq = QuranSequenceMatcher(matcher);
      String at(QuranMatch? r) =>
          r?.first == null ? '-' : '${r!.first!.surah}:${r.first!.ayah}';

      // آية الكرسي مقطّعة: أول مقطع لحاله ممكن يكون 3:2.
      final kursi = seq.matchAll([
        'الله لا اله الا هو الحي القيوم',
        'لا تاخذه سنه ولا نوم له ما في السموت وما في الارض',
        'من ذا الذي يشفع عنده الا باذنه',
      ]);
      expect(kursi.map(at).toList(), ['2:255', '2:255', '2:255']);

      // الفاتحة: بسملة لحالها، وبعدها مقاطع قصيرة موجودة بأماكن ثانية.
      final fatiha = seq.matchAll([
        'بسم الله الرحمن الرحيم',
        'الحمد لله رب العلمين',
        'الرحمن الرحيم',
        'ملك يوم الدين',
        'اياك نعبد واياك نستعين',
      ]);
      expect(fatiha.map(at).toList(), ['1:1', '1:2', '1:3', '1:4', '1:5']);

      // الرحمن: اللازمة المكررة بتنحسم من الآية اللي بعدها.
      final rahman = seq.matchAll([
        'فباي الاء ربكما تكذبان',
        'خلق الانسن من صلصل كالفخار',
        'وخلق الجان من مارج من نار',
        'فباي الاء ربكما تكذبان',
      ]);
      expect(rahman.map(at).toList(), ['55:13', '55:14', '55:15', '55:16']);

      // مقطع ضجيج بالنص ما بيكسر السلسلة.
      final noisy = seq.matchAll(['قل هو الله احد', 'ل', 'الله الصمد', 'لم يلد ولم يولد']);
      expect(noisy.map(at).toList(), ['112:1', '-', '112:2', '112:3']);
      expect(noisy[2]!.confidence, greaterThan(0.5));
    });

    test('random noisy segments (simulated ASR, ~10% char errors)', () {
      final rnd = Random(42);
      final keys = [for (final a in ayahs) ArabicNormalizer.key(a.text)];
      const letters = ArabicNormalizer.alphabet;
      var ok = 0, total = 0;
      final sw = Stopwatch()..start();
      for (var t = 0; t < 300; t++) {
        final i = rnd.nextInt(ayahs.length);
        var j = min(ayahs.length, i + 1 + rnd.nextInt(3));
        while (j - 1 > i && ayahs[j - 1].surah != ayahs[i].surah) {
          j--;
        }
        var s = keys.sublist(i, j).join();
        if (s.length > 400) s = s.substring(0, 400);
        if (s.length < 12) continue;
        final b = StringBuffer();
        for (final ch in s.split('')) {
          final r = rnd.nextDouble();
          if (r < 0.05) {
            b.write(letters[rnd.nextInt(letters.length)]);
          } else if (r < 0.08) {
            // حذف
          } else if (r < 0.10) {
            b
              ..write(ch)
              ..write(letters[rnd.nextInt(letters.length)]);
          } else {
            b.write(ch);
          }
        }
        final r = matcher.match(b.toString());
        total++;
        if (r != null && r.first != null) {
          final got = ayahs.indexWhere(
              (a) => a.surah == r.first!.surah && a.ayah == r.first!.ayah);
          // آيات بنص متطابق حرفياً بأماكن ثانية بتنحسب صح.
          if (keys.sublist(i, j).contains(keys[got])) ok++;
        }
      }
      final acc = ok / total;
      // ignore: avoid_print
      print('noisy accuracy: $ok/$total = ${acc.toStringAsFixed(3)}, '
          'avg ${(sw.elapsedMilliseconds / total).toStringAsFixed(1)}ms/match');
      expect(acc, greaterThan(0.93));
    });

    test('every 9th ayah matches itself from its own Uthmani text', () {
      var ok = 0, total = 0;
      for (var i = 0; i < ayahs.length; i += 9) {
        final key = ArabicNormalizer.key(ayahs[i].text);
        if (key.length < QuranMatcher.minQueryLetters) continue;
        final r = matcher.match(ayahs[i].text);
        total++;
        if (r != null && r.first != null) {
          final got = ayahs.indexWhere(
              (a) => a.surah == r.first!.surah && a.ayah == r.first!.ayah);
          if (ArabicNormalizer.key(ayahs[got].text).contains(key) ||
              key.contains(ArabicNormalizer.key(ayahs[got].text))) {
            ok++;
          }
        }
      }
      // ignore: avoid_print
      print('self-match: $ok/$total');
      expect(ok / total, greaterThan(0.97));
    });
  });
}
