import 'dart:math' as math;

import '../matching/arabic_normalizer.dart';

/// تقطيع النص العثماني لآية على **حدود الكلمات** حسب مواقع بمفتاح الآية
/// المطبّع (اللي بيطلعها الـ matcher لكل جزء: [AyahSpan.keyStart/keyEnd]).
class AyahTextCutter {
  final String text;
  final NormalizedText _key;

  AyahTextCutter(this.text) : _key = ArabicNormalizer.keyWithMap(text);

  int get keyLength => _key.key.length;

  /// موقع بالنص (code unit) لحد كلمة قريب من الحرف رقم [k] بالمفتاح
  /// (الحد بين حرف k-1 وحرف k). 0 = أول النص، keyLength = آخره.
  int boundaryAt(int k) {
    if (k <= 0 || keyLength == 0) return 0;
    if (k >= keyLength) return text.length;
    final a = _key.sourceIndex[k - 1], b = _key.sourceIndex[k];
    // في مسافة بين الحرفين؟ هي الحد.
    for (var i = a + 1; i < b; i++) {
      if (text.codeUnitAt(i) == 0x20) return i;
    }
    // بنص كلمة: أقرب مسافة يمين أو شمال.
    var l = a;
    while (l > 0 && text.codeUnitAt(l) != 0x20) {
      l--;
    }
    var r = b;
    while (r < text.length && text.codeUnitAt(r) != 0x20) {
      r++;
    }
    return (b - l) < (r - a) ? l : r;
  }

  String slice(int from, int to) =>
      from >= to ? '' : text.substring(from, to).trim();

  /// الكلمات كاملة اللي فيها حروف المفتاح [ks, ke) (للأجزاء الصغيرة جداً
  /// اللي بتطلع فاضية لو قصّيناها على أقرب حد).
  String wordsCovering(int ks, int ke) {
    if (keyLength == 0) return text.trim();
    ks = ks.clamp(0, keyLength - 1);
    ke = ke.clamp(ks + 1, keyLength);
    var from = _key.sourceIndex[ks];
    while (from > 0 && text.codeUnitAt(from - 1) != 0x20) {
      from--;
    }
    var to = _key.sourceIndex[ke - 1];
    while (to < text.length && text.codeUnitAt(to) != 0x20) {
      to++;
    }
    return slice(from, to);
  }
}

/// تقسيم التفسير على أجزاء الآية (المواصفات، القسم 3): كل جزء بياخد قطعة
/// بنسبة موقعه بالآية، والقطع بتنقطع على **حدود الجمل** (. ؟ ! ؛ :) لو في
/// وحدة قريبة، وإلا على **الفواصل** (، ,)، وإلا على مسافة.
class TafsirSplitter {
  TafsirSplitter._();

  static const _sentence = '.؟!؛:';
  static const _comma = '،,';

  /// حد بالتفسير قريب من النسبة [frac] (0..1) من طوله.
  static int boundary(String t, double frac) {
    if (frac <= 0 || t.isEmpty) return 0;
    if (frac >= 1) return t.length;
    final target = (frac * t.length).round().clamp(0, t.length);
    final win = math.max(30, (t.length * 0.2).round());
    for (final cls in [_sentence, _comma, ' ']) {
      var best = -1;
      final lo = math.max(1, target - win);
      final hi = math.min(t.length - 1, target + win);
      for (var i = lo; i <= hi; i++) {
        if (!cls.contains(t[i])) continue;
        // الحد بعد علامة الترقيم (والمسافة بتنشال بالـ trim).
        final pos = cls == ' ' ? i : i + 1;
        if (best < 0 || (pos - target).abs() < (best - target).abs()) {
          best = pos;
        }
      }
      if (best > 0 && best < t.length) return best;
    }
    return target;
  }

  /// يقسم [tafsir] على أجزاء، كل جزء بنطاق نسبي [from, to) من الآية.
  /// الأجزاء المتتالية (to تبع جزء = from تبع اللي بعده) بتتشارك نفس الحد،
  /// فالقطع متصلة بدون تكرار. بيرجّع null لو طلع جزء فاضي (التفسير قصير)
  /// → المتصل بيعرض التفسير كامل.
  static List<String>? split(String tafsir, List<(double, double)> ranges) {
    if (ranges.length <= 1) return [tafsir];
    final cache = <double, int>{};
    int b(double f) => cache.putIfAbsent(f, () => boundary(tafsir, f));
    final out = <String>[];
    for (final r in ranges) {
      final from = b(r.$1), to = b(r.$2);
      final s = from >= to ? '' : tafsir.substring(from, to).trim();
      if (s.isEmpty) return null;
      out.add(s);
    }
    return out;
  }
}
