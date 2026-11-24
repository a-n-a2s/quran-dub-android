import 'ayah_font.dart';
import 'overlay_colors.dart';
import 'overlay_layout.dart';
import '../pipeline/recitation_segment.dart';

/// خط التفسير والعناصر النصية الثانية (اسم السورة، القارئ، الترجمة).
/// **كل واحد لحاله** عن خط الآية ([AyahFont]) (المواصفات القسم 3).
enum TafsirFont {
  /// أميري (SIL OFL): الافتراضي، زي المقطع المرجعي (يوم 7).
  amiri('Amiri', 'أميري'),

  /// أميري قرآن: نفس عائلة خط الآية، شكل أثقل وأقرب للمصحف.
  amiriQuran('Amiri Quran', 'أميري قرآن');

  final String family;
  final String label;
  const TafsirFont(this.family, this.label);

  static const TafsirFont defaultFont = amiri;
}

/// خلفية شفافة ورا العنصر (المواصفات القسم 3): صندوق حوالين النص أو شريط
/// بعرض عمود النص. بلون **عكس** لون النص ([OverlayTextColor.backdrop])،
/// وبشفافية بيختارها المستخدم. الافتراضي بدون خلفية (زي المقطع المرجعي).
enum OverlayBackgroundMode {
  none('بدون'),
  box('صندوق'),
  bar('شريط');

  final String label;
  const OverlayBackgroundMode(this.label);
}

class OverlayBackground {
  final OverlayBackgroundMode mode;

  /// 0..1 (شفافية الخلفية؛ 0 = ما بتبيّن).
  final double opacity;

  const OverlayBackground(
      {this.mode = OverlayBackgroundMode.none, this.opacity = defaultOpacity});

  static const double defaultOpacity = 0.45;
  static const double maxOpacity = 0.9;

  bool get visible => mode != OverlayBackgroundMode.none && opacity > 0;

  OverlayBackground copyWith(
          {OverlayBackgroundMode? mode, double? opacity}) =>
      OverlayBackground(
        mode: mode ?? this.mode,
        opacity: (opacity ?? this.opacity).clamp(0.0, maxOpacity).toDouble(),
      );

  Map<String, Object?> toJson() => {
        'mode': mode.name,
        'opacity': (opacity * 1e4).round() / 1e4,
      };

  static OverlayBackground fromJson(Object? j) {
    if (j is! Map) return const OverlayBackground();
    final m = j['mode'];
    final o = j['opacity'];
    return OverlayBackground(
      mode: OverlayBackgroundMode.values.firstWhere((e) => e.name == m,
          orElse: () => OverlayBackgroundMode.none),
      opacity: o is num
          ? o.toDouble().clamp(0.0, maxOpacity).toDouble()
          : defaultOpacity,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is OverlayBackground &&
      other.mode == mode &&
      (other.opacity - opacity).abs() < 1e-9;
  @override
  int get hashCode => Object.hash(mode, opacity.toStringAsFixed(6));
}

/// اختيارات المستخدم لشكل النص فوق الفيديو: **نفس** القيم بتروح للمعاينة
/// ([AyahOverlayFrame]) وللتصدير، فما في نسختين من الإعدادات (يوم 8). يوم 9
/// (المحرر 1) وسّعه: العناصر الخمسة ومواقعها وأحجامها ([layout])، خط التفسير
/// ([tafsirFont])، شدة الظل 0..1 ([shadowStrength])، والخلفية الشفافة
/// ([background]). كل شي بينعكس على التصدير تلقائياً لأنه التصدير بيرسم بنفس
/// [AyahOverlayFrame]، والقوالب بتحفظه كله ([toJson]/[OverlayStyle.fromJson]).
///
/// **الألوان**: أبيض أو أسود بس (قرار أنس يوم 7، وأكّده يوم 9)؛ الظل والخلفية
/// بلون عكس النص.
class OverlayStyle {
  final TafsirMode tafsirMode;

  /// خط الآية (مصحف المدينة / أميري قرآن).
  final AyahFont font;

  /// خط التفسير وباقي العناصر.
  final TafsirFont tafsirFont;
  final OverlayTextColor color;

  /// شدة الظل: 0 = بدون ظل، 1 = أقوى ظل معقول وواضح. بلون عكس النص.
  final double shadowStrength;
  final OverlayBackground background;

  /// تشغيل/إطفاء، حجم، وموقع كل عنصر من الخمسة.
  final OverlayLayout layout;

  /// اسم القارئ اللي بيكتبه المستخدم (عنصر "اسم القارئ"). بيخص المشروع، مش
  /// القالب: ما بينحفظ مع القوالب.
  final String reciterName;

  /// أحجام خاصة بمقطع معين (يوم 9، طلب أنس): index المقطع بقائمة المقاطع الأصلية
  /// ← (عنصر ← معامل الحجم). بتغلب على حجم [layout] العام لهالمقطع بس. بتخص
  /// المشروع مش القالب، فما بتنحفظ مع القوالب.
  final Map<int, Map<OverlayElement, double>> segmentScales;

  const OverlayStyle({
    this.tafsirMode = TafsirMode.split,
    this.font = AyahFont.defaultFont,
    this.tafsirFont = TafsirFont.defaultFont,
    this.color = OverlayTextColor.defaultColor,
    this.shadowStrength = 0,
    this.background = const OverlayBackground(),
    this.layout = OverlayLayout.reference,
    this.reciterName = '',
    this.segmentScales = const {},
  });

  /// القيمة الافتراضية لما المستخدم يشغّل الظل: بتبيّن بوضوح (مش أضعف من
  /// القديم اللي ما ظهر بالتصدير).
  static const double defaultShadowStrength = 0.7;

  bool get shadow => shadowStrength > 0;

  /// الشكل لمقطع رقم [index]: نفس الشكل بس بأحجام ذلك المقطع الخاصة (لو في).
  /// المعاينة والتصدير بيرسموا فيه.
  OverlayStyle forSegment(int index) {
    final o = segmentScales[index];
    if (o == null || o.isEmpty) return this;
    var l = layout;
    o.forEach((e, v) => l = l.update(e, (p) => p.copyWith(scale: v)));
    return copyWith(layout: l, segmentScales: const {});
  }

  /// كل التخطيطات الممكنة بالفيديو (العام + كل مقطع إله أحجام خاصة): الشريط
  /// بيغطي اتحادها.
  List<OverlayLayout> get allLayouts =>
      [layout, for (final k in segmentScales.keys) forSegment(k).layout];

  OverlayStyle copyWith({
    TafsirMode? tafsirMode,
    AyahFont? font,
    TafsirFont? tafsirFont,
    OverlayTextColor? color,
    double? shadowStrength,
    OverlayBackground? background,
    OverlayLayout? layout,
    String? reciterName,
    Map<int, Map<OverlayElement, double>>? segmentScales,
  }) =>
      OverlayStyle(
        tafsirMode: tafsirMode ?? this.tafsirMode,
        font: font ?? this.font,
        tafsirFont: tafsirFont ?? this.tafsirFont,
        color: color ?? this.color,
        shadowStrength:
            (shadowStrength ?? this.shadowStrength).clamp(0.0, 1.0).toDouble(),
        background: background ?? this.background,
        layout: layout ?? this.layout,
        reciterName: reciterName ?? this.reciterName,
        segmentScales: segmentScales ?? this.segmentScales,
      );

  /// JSON للخطة (plan.json) وللقوالب. [forTemplate]: بدون اسم القارئ (بيخص
  /// المشروع).
  Map<String, Object?> toJson({bool forTemplate = false}) => {
        'tafsirMode': tafsirMode.name,
        'font': font.name,
        'tafsirFont': tafsirFont.name,
        'color': color.name,
        'shadowStrength': (shadowStrength * 1e4).round() / 1e4,
        'background': background.toJson(),
        'layout': layout.toJson(),
        if (!forTemplate) 'reciterName': reciterName,
        if (!forTemplate)
          'segmentScales': {
            for (final k in segmentScales.keys.toList()..sort())
              '$k': {
                for (final e in segmentScales[k]!.keys)
                  e.name: (segmentScales[k]![e]! * 1e4).round() / 1e4
              }
          },
      };

  /// من JSON (قوالب محفوظة): الحقول الناقصة أو الغلط بتاخد الافتراضي،
  /// فالقوالب القديمة بتضل تشتغل لما نضيف حقول.
  factory OverlayStyle.fromJson(Object? j) {
    if (j is! Map) return const OverlayStyle();
    T pick<T extends Enum>(List<T> values, Object? name, T fallback) {
      for (final v in values) {
        if (v.name == name) return v;
      }
      return fallback;
    }

    final ss = j['shadowStrength'];
    // قوالب أقدم (يوم 8) كان فيها shadow: true/false.
    final legacy = j['shadow'];
    final rn = j['reciterName'];
    final segScales = <int, Map<OverlayElement, double>>{};
    final raw = j['segmentScales'];
    if (raw is Map) {
      raw.forEach((k, v) {
        final idx = int.tryParse('$k');
        if (idx == null || v is! Map) return;
        final m = <OverlayElement, double>{};
        for (final e in OverlayElement.values) {
          final x = v[e.name];
          if (x is num) m[e] = clampScale(x.toDouble());
        }
        if (m.isNotEmpty) segScales[idx] = m;
      });
    }
    return OverlayStyle(
      tafsirMode: pick(TafsirMode.values, j['tafsirMode'], TafsirMode.split),
      font: pick(AyahFont.values, j['font'], AyahFont.defaultFont),
      tafsirFont:
          pick(TafsirFont.values, j['tafsirFont'], TafsirFont.defaultFont),
      color:
          pick(OverlayTextColor.values, j['color'], OverlayTextColor.defaultColor),
      shadowStrength: ss is num
          ? ss.toDouble().clamp(0.0, 1.0).toDouble()
          : (legacy == true ? defaultShadowStrength : 0),
      background: OverlayBackground.fromJson(j['background']),
      layout: OverlayLayout.fromJson(j['layout']),
      reciterName: rn is String ? rn : '',
      segmentScales: segScales,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is OverlayStyle &&
      other.tafsirMode == tafsirMode &&
      other.font == font &&
      other.tafsirFont == tafsirFont &&
      other.color == color &&
      (other.shadowStrength - shadowStrength).abs() < 1e-9 &&
      other.background == background &&
      other.layout == layout &&
      other.reciterName == reciterName &&
      _sameSegScales(other.segmentScales, segmentScales);

  @override
  int get hashCode => Object.hash(tafsirMode, font, tafsirFont, color,
      shadowStrength.toStringAsFixed(6), background, layout, reciterName,
      segmentScales.length);

  @override
  String toString() {
    final parts = <String>[
      'تفسير ${tafsirMode.name}',
      'خط ${font.label}',
      'نص ${color.label}',
      if (shadow) 'ظل ${(shadowStrength * 100).round()}٪',
      if (background.visible)
        'خلفية ${background.mode.label} ${(background.opacity * 100).round()}٪',
      'عناصر: ${layout.toString()}',
      if (reciterName.isNotEmpty) 'القارئ: $reciterName',
    ];
    return parts.join('، ');
  }
}

bool _sameSegScales(
    Map<int, Map<OverlayElement, double>> a, Map<int, Map<OverlayElement, double>> b) {
  if (a.length != b.length) return false;
  for (final k in a.keys) {
    final x = a[k], y = b[k];
    if (y == null || x!.length != y.length) return false;
    for (final e in x.keys) {
      final v = y[e];
      if (v == null || (v - x[e]!).abs() > 1e-6) return false;
    }
  }
  return true;
}
