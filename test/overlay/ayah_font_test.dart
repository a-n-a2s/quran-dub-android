import 'package:flutter_test/flutter_test.dart';
import 'package:quran_dub/overlay/ayah_font.dart';
import 'package:quran_dub/pipeline/quran_text_source.dart';

/// كل رموز نص القرآن بعد التحويل لـ KFGQPC موجودة بجدول الحروف (cmap) تبع
/// الخط `KFGQPC_HafsUthmanic_v18.ttf` (مفحوصة بـ fontTools وقت كتابة الاختبار).
const _kfgqpcCodePoints = <int>{
  0x0020, 0x0621, 0x0627, 0x0628, 0x0629, 0x062A, 0x062B, 0x062C, 0x062D,
  0x062E, 0x062F, 0x0630, 0x0631, 0x0632, 0x0633, 0x0634, 0x0635, 0x0636,
  0x0637, 0x0638, 0x0639, 0x063A, 0x0640, 0x0641, 0x0642, 0x0643, 0x0644,
  0x0645, 0x0646, 0x0647, 0x0648, 0x0649, 0x064A, 0x064B, 0x064C, 0x064D,
  0x064E, 0x064F, 0x0650, 0x0651, 0x0652, 0x0653, 0x0654, 0x0655, 0x0656,
  0x0657, 0x065E, 0x0670, 0x0671, 0x06D6, 0x06D7, 0x06D8, 0x06DA, 0x06DB,
  0x06DC, 0x06E0, 0x06E1, 0x06E2, 0x06E4, 0x06E5, 0x06E6, 0x06E7, 0x06E8,
  0x06EA, 0x06EC, 0x06ED,
};

void main() {
  late QuranTextSource text;
  setUpAll(() {
    text = QuranTextSource.fromSeedFile('assets/quran/quran_data.json.gz');
  });

  test('KFGQPC: open tanween remapped to the font encoding', () {
    // "هُدࣰ ى": فتح مفتوح + مسافة فاصلة + ألف مقصورة → حرفين متصلين.
    expect(KfgqpcCompat.convert('\u0647\u064F\u062F\u08F0 \u0649'),
        '\u0647\u064F\u062F\u0657\u0649');
    // ضم مفتوح / كسر مفتوح (بدون مسافة قبل الكلمة الجاية).
    expect(KfgqpcCompat.convert('\u062F\u08F1'), '\u062F\u065E');
    expect(KfgqpcCompat.convert('\u062F\u08F2'), '\u062F\u0656');
    // المسافة قبل كلمة عادية (مش ا/ى) ما بتنشال.
    expect(KfgqpcCompat.convert('\u062F\u08F2 \u0648'), '\u062F\u0656 \u0648');
    // تنوين عادي وعلامات ثانية ما بتتغير.
    expect(KfgqpcCompat.convert('أَحَدٌ'), 'أَحَدٌ');
    expect(KfgqpcCompat.convert('وَٱلۡجَارِ'), 'وَٱلۡجَارِ');
    // علامة 11:41 الوحيدة.
    expect(KfgqpcCompat.convert('\u065C'), '\u06EA');
    expect(KfgqpcCompat.convert(''), '');
  });

  test('Amiri Quran: text unchanged; KFGQPC default', () {
    const t = 'وَلَٰكِن كَانَ فِي ضَلَٰلِۭ بَعِيد\u08F2';
    expect(AyahFont.amiriQuran.prepare(t), t);
    expect(AyahFont.kfgqpcHafs.prepare(t), isNot(t));
    expect(AyahFont.defaultFont, AyahFont.kfgqpcHafs);
    expect(AyahFont.kfgqpcHafs.family, 'KFGQPC Hafs');
    expect(AyahFont.amiriQuran.family, 'Amiri Quran');
  });

  test('every ayah converted for KFGQPC uses only glyphs the font has', () {
    final missing = <int>{};
    var withOpenTanween = 0;
    for (var s = 1; s <= 114; s++) {
      for (var a = 1;; a++) {
        final c = text.ayah(s, a);
        if (c == null) break;
        final raw = c.uthmani;
        if (RegExp('[ࣰ-ࣲ]').hasMatch(raw)) withOpenTanween++;
        final converted = KfgqpcCompat.convert(raw);
        expect(RegExp('[ࣰ-ࣲٜ]').hasMatch(converted), isFalse,
            reason: '$s:$a');
        for (final r in converted.runes) {
          if (!_kfgqpcCodePoints.contains(r)) missing.add(r);
        }
      }
    }
    expect(missing, isEmpty,
        reason: missing.map((r) => r.toRadixString(16)).join(','));
    // الاختبار فعلاً بيغطي التنوين المفتوح (مش فاضي).
    expect(withOpenTanween, greaterThan(1500));
  });

  test('ayah 50:27 renders the reference text', () {
    final c = text.ayah(50, 27)!;
    expect(c.uthmani.contains('ࣲ'), isTrue);
    expect(AyahFont.kfgqpcHafs.prepare(c.uthmani).contains('ٖ'), isTrue);
  });

  test('Arabic-Indic digits', () {
    expect(toArabicIndic(27), '٢٧');
    expect(toArabicIndic(1), '١');
    expect(toArabicIndic(286), '٢٨٦');
    expect(toArabicIndic(0), '٠');
  });

  test('brackets are the ornate parentheses', () {
    expect(ayahOpenBracket.codeUnitAt(0), 0xFD3F);
    expect(ayahCloseBracket.codeUnitAt(0), 0xFD3E);
  });
}
