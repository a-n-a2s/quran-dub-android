import 'package:flutter_test/flutter_test.dart';
import 'package:quran_dub/overlay/tafsir_display.dart';
import 'package:quran_dub/pipeline/recitation_segment.dart';

RecitationSegment ayah({
  String tafsir = '',
  String split = '',
  String full = '',
  SegmentKind kind = SegmentKind.fullAyah,
}) =>
    RecitationSegment(
      start: 0,
      end: 1,
      kind: kind,
      surah: 1,
      ayah: 1,
      text: 'x',
      tafsir: tafsir,
      tafsirSplit: split,
      tafsirFull: full,
      confidence: 1,
    );

void main() {
  test('strips tashkeel but keeps letters and punctuation', () {
    expect(TafsirDisplay.stripTashkeel('قال الله لديَّ اليوم، وقَدَّمْتُ إليكم'),
        'قال الله لدي اليوم، وقدمت إليكم');
    expect(TafsirDisplay.stripTashkeel('(اللهِ) علم؟'), '(الله) علم؟');
    // همزة فوق/تحت منفصلة (0654/0655) ما بتنشال: جزء من الحرف.
    expect(TafsirDisplay.stripTashkeel('أ'), 'أ');
  });

  test('final stop: add period, comma becomes period, existing end kept', () {
    expect(TafsirDisplay.withFinalStop('عن سبيل الهدى'), 'عن سبيل الهدى.');
    expect(TafsirDisplay.withFinalStop('عن سبيل الهدى،'), 'عن سبيل الهدى.');
    expect(TafsirDisplay.withFinalStop('أحد؟'), 'أحد؟');
    expect(TafsirDisplay.withFinalStop('قال:'), 'قال:');
    expect(TafsirDisplay.withFinalStop('تم.'), 'تم.');
    expect(TafsirDisplay.withFinalStop('  '), '');
    expect(TafsirDisplay.withFinalStop(''), '');
  });

  test('mode selection: split vs full under each part', () {
    final s = ayah(tafsir: 'T', split: 'جزء أول', full: 'تفسير كامل');
    expect(TafsirDisplay.select(s, TafsirMode.split), 'جزء أول');
    expect(TafsirDisplay.select(s, TafsirMode.fullUnderEachPart), 'تفسير كامل');
    expect(TafsirDisplay.forDisplay(s, TafsirMode.split), 'جزء أول.');
    expect(TafsirDisplay.forDisplay(s, TafsirMode.fullUnderEachPart),
        'تفسير كامل.');
  });

  test('older segments without split/full fall back to tafsir', () {
    final s = ayah(tafsir: 'نص');
    expect(TafsirDisplay.select(s, TafsirMode.split), 'نص');
    expect(TafsirDisplay.select(s, TafsirMode.fullUnderEachPart), 'نص');
  });

  test('basmala, istiadha and non-Quran never show tafsir', () {
    for (final k in [
      SegmentKind.basmala,
      SegmentKind.istiadha,
      SegmentKind.nonQuran
    ]) {
      final s = ayah(kind: k, tafsir: 'x', split: 'x', full: 'x');
      for (final m in TafsirMode.values) {
        expect(TafsirDisplay.forDisplay(s, m), '', reason: '$k $m');
      }
    }
  });
}
