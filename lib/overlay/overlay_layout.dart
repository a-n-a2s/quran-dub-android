// العناصر الخمسة ومواقعها (يوم 9، المواصفات القسم 3). جزء صافي بدون Flutter.
//
// كل عنصر: تشغيل/إطفاء، حجم (معامل ضرب بالحجم المرجعي)، وموقع اختياري.
// **الموقع نسبي** (كسر من عرض/ارتفاع الفيديو)، مش بكسلات شاشة، فنفس التصميم
// بيطلع صح على عمودي/أفقي/مربّع وبأي دقة وبالتصدير:
//  - بدون موقع (`anchor == null`): المكان الافتراضي (شكل المقطع المرجعي):
//    الآية أول سطر عند 61% والتفسير تحتها مباشرة، واسم السورة فوق الآية،
//    واسم القارئ تحت التفسير.
//  - بموقع ([ElementAnchor]): العنصر انسحب بالإصبع: منتصفه الأفقي عند
//    `cx × عرض الفيديو` وأعلاه عند `top × ارتفاع الفيديو`.
import 'dart:math' as math;

/// العناصر الخمسة، بترتيب العرض الافتراضي (من فوق لتحت).
enum OverlayElement {
  /// اسم السورة ورقم الآية (الأسماء من جدول `surahs`).
  surahRef('اسم السورة ورقم الآية'),

  /// الآية بالرسم العثماني.
  ayah('الآية'),

  /// الترجمة (العنصر والإعداد بس؛ المصدر والنص يوم 12).
  translation('الترجمة'),

  /// التفسير الميسر.
  tafsir('التفسير'),

  /// اسم القارئ (المستخدم بيكتبه).
  reciter('اسم القارئ');

  final String label;
  const OverlayElement(this.label);

  /// بتنرسم بالكتلة الأساسية ([flowElements]) وبتتتابع تحت بعض.
  bool get inFlow => this != surahRef;

  /// الترجمة لسا ما إلها مصدر (يوم 12): معطّلة بالواجهة.
  bool get available => this != translation;
}

/// عناصر الكتلة الأساسية بترتيبها: الآية، الترجمة، التفسير، القارئ.
const List<OverlayElement> flowElements = [
  OverlayElement.ayah,
  OverlayElement.translation,
  OverlayElement.tafsir,
  OverlayElement.reciter,
];

/// موقع عنصر انسحب: منتصفه الأفقي [cx] وأعلاه [top]، كأكسار من أبعاد الفيديو.
class ElementAnchor {
  final double cx;
  final double top;
  const ElementAnchor(this.cx, this.top);

  /// ضمن حدود معقولة (العنصر ما بيطلع كله برا الفيديو).
  ElementAnchor clamped() => ElementAnchor(
      cx.clamp(minCx, maxCx).toDouble(), top.clamp(minTop, maxTop).toDouble());

  static const double minCx = 0.0;
  static const double maxCx = 1.0;
  static const double minTop = 0.0;
  static const double maxTop = 0.96;

  @override
  bool operator ==(Object other) =>
      other is ElementAnchor &&
      (other.cx - cx).abs() < 1e-9 &&
      (other.top - top).abs() < 1e-9;
  @override
  int get hashCode => Object.hash(cx.toStringAsFixed(6), top.toStringAsFixed(6));

  List<double> toJson() => [_r(cx), _r(top)];

  static ElementAnchor? fromJson(Object? j) {
    if (j is List && j.length == 2 && j[0] is num && j[1] is num) {
      return ElementAnchor((j[0] as num).toDouble(), (j[1] as num).toDouble())
          .clamped();
    }
    return null;
  }

  @override
  String toString() => '(${cx.toStringAsFixed(3)}, ${top.toStringAsFixed(3)})';
}

double _r(double v) => (v * 1e5).round() / 1e5;

/// إعدادات عنصر واحد.
class ElementPlacement {
  final bool enabled;

  /// معامل الحجم (1.0 = الحجم المرجعي).
  final double scale;

  /// null = المكان الافتراضي.
  final ElementAnchor? anchor;

  const ElementPlacement({this.enabled = true, this.scale = 1.0, this.anchor});

  static const double minScale = 0.6;
  static const double maxScale = 1.6;

  /// [clearAnchor]: يرجّع العنصر لمكانه الافتراضي.
  ElementPlacement copyWith(
          {bool? enabled,
          double? scale,
          ElementAnchor? anchor,
          bool clearAnchor = false}) =>
      ElementPlacement(
        enabled: enabled ?? this.enabled,
        scale: (scale ?? this.scale).clamp(minScale, maxScale).toDouble(),
        anchor: clearAnchor ? null : (anchor ?? this.anchor),
      );

  bool get isDetached => anchor != null;

  @override
  bool operator ==(Object other) =>
      other is ElementPlacement &&
      other.enabled == enabled &&
      (other.scale - scale).abs() < 1e-9 &&
      other.anchor == anchor;
  @override
  int get hashCode =>
      Object.hash(enabled, scale.toStringAsFixed(6), anchor);

  Map<String, Object?> toJson() => {
        'enabled': enabled,
        'scale': _r(scale),
        'anchor': anchor?.toJson(),
      };

  static ElementPlacement fromJson(Object? j, ElementPlacement fallback) {
    if (j is! Map) return fallback;
    final en = j['enabled'];
    final sc = j['scale'];
    return ElementPlacement(
      enabled: en is bool ? en : fallback.enabled,
      scale: sc is num
          ? sc.toDouble().clamp(minScale, maxScale).toDouble()
          : fallback.scale,
      anchor: ElementAnchor.fromJson(j['anchor']),
    );
  }

  @override
  String toString() =>
      '${enabled ? 'شغّال' : 'مطفي'} ×${scale.toStringAsFixed(2)}${anchor == null ? '' : ' @$anchor'}';
}

/// مواقع وتشغيل وأحجام العناصر الخمسة. الافتراضي = شكل المقطع المرجعي بالضبط:
/// الآية + التفسير بس، أول سطر عند 61%.
class OverlayLayout {
  final Map<OverlayElement, ElementPlacement> _p;

  const OverlayLayout._(this._p);

  /// الافتراضي = شكل المقطع المرجعي: الآية والتفسير شغّالين بمكانهم، والباقي
  /// مطفي.
  static const OverlayLayout reference = OverlayLayout._({
    OverlayElement.surahRef: ElementPlacement(enabled: false),
    OverlayElement.ayah: ElementPlacement(),
    OverlayElement.translation: ElementPlacement(enabled: false),
    OverlayElement.tafsir: ElementPlacement(),
    OverlayElement.reciter: ElementPlacement(enabled: false),
  });

  /// من خريطة جزئية؛ العناصر الناقصة بتاخد قيمة المرجع.
  factory OverlayLayout.of(Map<OverlayElement, ElementPlacement> m) =>
      OverlayLayout._({
        for (final e in OverlayElement.values) e: m[e] ?? reference[e],
      });

  ElementPlacement operator [](OverlayElement e) => _p[e]!;

  bool isEnabled(OverlayElement e) => _p[e]!.enabled;

  OverlayLayout withElement(OverlayElement e, ElementPlacement p) =>
      OverlayLayout._({..._p, e: p});

  OverlayLayout update(
          OverlayElement e, ElementPlacement Function(ElementPlacement) f) =>
      withElement(e, f(this[e]));

  /// العناصر المشغّلة والمنسحبة (بموقع خاص).
  List<OverlayElement> get detached => [
        for (final e in OverlayElement.values)
          if (this[e].enabled && this[e].isDetached) e
      ];

  /// شكل المقطع المرجعي بالضبط (لا سحب ولا أحجام، آية + تفسير بس)؟
  bool get isReference => this == reference;

  @override
  bool operator ==(Object other) {
    if (other is! OverlayLayout) return false;
    for (final e in OverlayElement.values) {
      if (other[e] != this[e]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll([for (final e in OverlayElement.values) this[e]]);

  Map<String, Object?> toJson() =>
      {for (final e in OverlayElement.values) e.name: this[e].toJson()};

  factory OverlayLayout.fromJson(Object? j) {
    if (j is! Map) return reference;
    return OverlayLayout._({
      for (final e in OverlayElement.values)
        e: ElementPlacement.fromJson(j[e.name], reference[e]),
    });
  }

  @override
  String toString() => [
        for (final e in OverlayElement.values)
          if (this[e].enabled) '${e.label}: ${this[e]}'
      ].join('، ');
}

/// موقع عنصر منسحب بالبكسل لفيديو [width]×[height] (للرسم والاختبار).
({double cx, double top}) anchorToPixels(
        ElementAnchor a, int width, int height) =>
    (cx: a.cx * width, top: a.top * height);

/// من بكسل لموقع نسبي.
ElementAnchor anchorFromPixels(double cx, double top, int width, int height) =>
    ElementAnchor(cx / width, top / height).clamped();

double clampScale(double v) =>
    math.max(ElementPlacement.minScale, math.min(ElementPlacement.maxScale, v));
