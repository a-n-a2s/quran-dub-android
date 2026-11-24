import 'package:flutter/material.dart';

import '../pipeline/recitation_segment.dart';
import 'ayah_font.dart';
import 'overlay_colors.dart';
import 'overlay_layout.dart';
import 'overlay_metrics.dart';
import 'overlay_style.dart';
import 'overlay_timeline.dart';
import 'tafsir_display.dart';

export 'overlay_colors.dart';

/// عائلة خط التفسير ورقم الآية الافتراضية (Amiri، SIL OFL). (يوم 9: الخط صار
/// اختيار المستخدم، [TafsirFont].)
const String tafsirFontFamily = 'Amiri';

/// اسم السورة بالعربي من رقمها (من جدول `surahs`): بيتمرّر للإطار كـ lookup
/// عشان [AyahOverlayFrame] يضل بدون قاعدة بيانات.
typedef SurahNameLookup = String? Function(int surah);

/// سطر "اسم السورة • الآية ٢٧" لمقطع، أو null (بسملة بدون آية، استعاذة، غير
/// قرآني، أو ما في رقم).
String? surahRefText(RecitationSegment seg, SurahNameLookup? lookup) {
  final s = seg.surah, a = seg.ayah;
  if (!seg.isAyah || s == null || a == null) return null;
  final name = lookup?.call(s);
  final head = (name == null || name.trim().isEmpty) ? 'سورة $s' : name.trim();
  return '$head • الآية ${toArabicIndic(a)}';
}

/// ظلال النص بلون عكس النص وبشدة [strength] (0..1)، بمقاسات نسبية من الوحدة
/// (نفس الشكل بكل الأبعاد). null لما الشدة صفر (بدون ظل).
List<Shadow>? overlayShadows(
    OverlayMetrics m, OverlayTextColor color, double strength) {
  final layers = m.shadowLayers(strength);
  if (layers.isEmpty) return null;
  return [
    for (final l in layers)
      Shadow(
        color: color.shadow.withValues(alpha: l.alpha),
        offset: Offset(0, l.dy),
        blurRadius: l.blur,
      ),
  ];
}

/// إطار النص فوق الفيديو بأبعاد الفيديو **الحقيقية بالبكسل**
/// ([videoWidth]×[videoHeight] بعد الدوران): بنرسم بنفس المقاسات اللي رح
/// يتصدّر فيها الفيديو (يوم 8)، والمعاينة بتصغّره بـ FittedBox. بدون أي
/// صندوق أو خلفية افتراضياً: الفيديو بيضل ظاهر وراء النص.
///
/// الشكل الافتراضي (المقطع المرجعي): ﴿ الآية [رقم] ﴾ بالرسم العثماني، أبيض
/// والأقواس ذهبية، والرقم بعلامة نهاية الآية المزخرفة زي المصحف (أرقام
/// عربية-هندية، بنفس خط الآية وعلى نفس السطر) مع آخر جزء بس، والتفسير تحتها
/// مباشرة. أول سطر عند 61% من الارتفاع؛ وكتلة أطول من المتاح بتتصغّر لتتسع.
///
/// يوم 9: **كل شي بيجي من [style]** ([OverlayStyle]): العناصر الخمسة (الآية،
/// الترجمة، التفسير، اسم السورة، القارئ) تشغيل/إطفاء/حجم/موقع، الخطوط، شدة
/// الظل، والخلفية الشفافة. المعاينة والتصدير بيرسموا بهالويدجت نفسه.
///
/// العناصر بدون موقع بتنرسم بالكتلة الأساسية (الآية، الترجمة، التفسير، القارئ
/// تحت بعض)، واسم السورة فوق الآية. العنصر المنسحب ([ElementPlacement.anchor])
/// بيتحط بموقعه النسبي، وبيضل مكانه فاضي بالكتلة (الباقي ما بيتحرك).
class AyahOverlayFrame extends StatelessWidget {
  final int videoWidth;
  final int videoHeight;
  final OverlayCue? cue;
  final OverlayStyle style;

  /// أسماء السور (من جدول `surahs`) لعنصر "اسم السورة ورقم الآية".
  final SurahNameLookup? surahName;

  /// للمحرر: مفاتيح بتتحط على كل عنصر ظاهر عشان يعرف مكانه وحجمه (لسحبه). بدون
  /// مفاتيح بالتصدير.
  final Map<OverlayElement, GlobalKey>? elementKeys;

  const AyahOverlayFrame({
    super.key,
    required this.videoWidth,
    required this.videoHeight,
    required this.cue,
    this.style = const OverlayStyle(),
    this.surahName,
    this.elementKeys,
  });

  @override
  Widget build(BuildContext context) {
    final m = OverlayMetrics.forSize(videoWidth, videoHeight);
    final c = cue;
    return MediaQuery(
      // حجم الخط بالبكسل الحقيقي بغض النظر عن إعدادات خط الجوال.
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
      child: SizedBox(
        width: videoWidth.toDouble(),
        height: videoHeight.toDouble(),
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            if (c != null && c.opacity > 0.001)
              Positioned.fill(
                child: Opacity(
                  opacity: c.opacity.clamp(0.0, 1.0),
                  child: Directionality(
                    textDirection: TextDirection.rtl,
                    child: _OverlayContent(
                      segment: c.item.segment,
                      metrics: m,
                      style: style,
                      surahName: surahName,
                      elementKeys: elementKeys,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _OverlayContent extends StatelessWidget {
  final RecitationSegment segment;
  final OverlayMetrics metrics;
  final OverlayStyle style;
  final SurahNameLookup? surahName;
  final Map<OverlayElement, GlobalKey>? elementKeys;

  const _OverlayContent({
    required this.segment,
    required this.metrics,
    required this.style,
    required this.surahName,
    required this.elementKeys,
  });

  OverlayMetrics get m => metrics;
  OverlayTextColor get color => style.color;
  List<Shadow>? get _shadows => overlayShadows(m, color, style.shadowStrength);

  /// العنصر [e] كويدجت، أو null لو ما في شي يتعرض بهالمقطع (نص فاضي، أو
  /// الترجمة لسا ما إلها مصدر). [withKeys]: false لنسخة الفراغ بالكتلة (بدون
  /// مفاتيح، عشان ما يتكرّر المفتاح).
  Widget? _element(OverlayElement e, {required bool withKeys}) {
    final p = style.layout[e];
    Widget? w;
    switch (e) {
      case OverlayElement.ayah:
        w = _ayahLine(p, withKeys);
      case OverlayElement.tafsir:
        w = _tafsir(p, withKeys);
      case OverlayElement.surahRef:
        w = _surahRef(p, withKeys);
      case OverlayElement.reciter:
        w = _reciter(p, withKeys);
      case OverlayElement.translation:
        // العنصر والإعداد بس (يوم 9)؛ المصدر والنص يوم 12.
        w = null;
    }
    if (w == null) return null;
    w = _backdrop(w, p.scale);
    final k = withKeys ? elementKeys?[e] : null;
    return k == null ? w : KeyedSubtree(key: k, child: w);
  }

  /// خلفية شفافة (صندوق/شريط) بلون عكس النص، حشوتها جزء من تخطيط العنصر.
  Widget _backdrop(Widget child, double scale) {
    final bg = style.background;
    if (!bg.visible) return child;
    final box = DecoratedBox(
      decoration: BoxDecoration(
        color: color.backdrop.withValues(alpha: bg.opacity),
        borderRadius:
            BorderRadius.circular(m.unit * OverlayMetrics.backdropRadiusRatio * scale),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: m.unit * OverlayMetrics.backdropPadXRatio * scale,
          vertical: m.unit * OverlayMetrics.backdropPadYRatio * scale,
        ),
        child: child,
      ),
    );
    // الشريط: بعرض عمود النص كله (مش بعرض الكلام بس).
    return bg.mode == OverlayBackgroundMode.bar
        ? SizedBox(width: double.infinity, child: box)
        : box;
  }

  TextStyle _plain(double size, double scale, {double? lineHeight}) => TextStyle(
        fontFamily: style.tafsirFont.family,
        fontSize: size * scale,
        height: lineHeight ?? m.tafsirLineHeight,
        color: color.text,
        shadows: _shadows,
        decoration: TextDecoration.none,
      );

  Widget? _tafsir(ElementPlacement p, bool withKeys) {
    final t = TafsirDisplay.forDisplay(segment, style.tafsirMode);
    if (t.isEmpty) return null;
    return Text(
      t,
      key: withKeys ? const ValueKey('overlay-tafsir') : null,
      textAlign: TextAlign.center,
      textDirection: TextDirection.rtl,
      style: _plain(m.tafsirFontSize, p.scale),
    );
  }

  Widget? _surahRef(ElementPlacement p, bool withKeys) {
    final t = surahRefText(segment, surahName);
    if (t == null) return null;
    return Text(
      t,
      key: withKeys ? const ValueKey('overlay-surah-ref') : null,
      textAlign: TextAlign.center,
      textDirection: TextDirection.rtl,
      maxLines: OverlayMetrics.singleLineElementMaxLines,
      overflow: TextOverflow.ellipsis,
      style: _plain(m.unit * OverlayMetrics.surahRefSizeRatio, p.scale),
    );
  }

  Widget? _reciter(ElementPlacement p, bool withKeys) {
    final t = style.reciterName.trim();
    if (t.isEmpty) return null;
    return Text(
      t,
      key: withKeys ? const ValueKey('overlay-reciter') : null,
      textAlign: TextAlign.center,
      textDirection: TextDirection.rtl,
      maxLines: OverlayMetrics.singleLineElementMaxLines,
      overflow: TextOverflow.ellipsis,
      style: _plain(m.unit * OverlayMetrics.reciterSizeRatio, p.scale),
    );
  }

  Widget? _ayahLine(ElementPlacement p, bool withKeys) {
    final size = m.ayahFontSize * p.scale;
    // نص مستخدم لجزء غير قرآني (يوم 10 بيعبّيه): سطر عادي بدون أقواس.
    if (segment.kind == SegmentKind.nonQuran) {
      final t = segment.userText ?? '';
      if (t.isEmpty) return null;
      return Text(
        t,
        key: withKeys ? const ValueKey('overlay-user-text') : null,
        textAlign: TextAlign.center,
        textDirection: TextDirection.rtl,
        style: _plain(m.ayahFontSize, p.scale),
      );
    }
    if (segment.text.isEmpty) return null;
    final font = style.font;
    final base = TextStyle(
      fontFamily: font.family,
      fontSize: size,
      height: m.ayahLineHeight,
      color: color.text,
      shadows: _shadows,
      decoration: TextDecoration.none,
    );
    final bracket = base.copyWith(
      fontFamily: AyahFont.amiriQuran.family,
      color: color.bracket,
    );
    final number = segment.showAyahNumber && segment.ayah != null;
    return Text.rich(
      TextSpan(
        style: base,
        children: [
          TextSpan(text: ayahOpenBracket, style: bracket),
          TextSpan(text: font.prepare(segment.text)),
          // رقم الآية بعلامة نهاية الآية زي المصحف (زخرفة حوالين الرقم)، بنفس
          // خط الآية وعلى نفس السطر. مسافة ما بتنكسر قبلها عشان العلامة ما
          // تنزل لحالها لسطر جديد.
          if (number)
            TextSpan(text: ' ${font.ayahNumberMark(segment.ayah!)}'),
          // مسافة ضيقة (ما بتنكسر) بين العلامة والقوس.
          TextSpan(
              text: number ? ' $ayahCloseBracket' : ayahCloseBracket,
              style: bracket),
        ],
      ),
      key: withKeys ? const ValueKey('overlay-ayah') : null,
      textAlign: TextAlign.center,
      textDirection: TextDirection.rtl,
    );
  }

  @override
  Widget build(BuildContext context) {
    final layout = style.layout;
    final children = <Widget>[];

    // 1) الكتلة الأساسية: الآية، الترجمة، التفسير، القارئ (اللي بدون موقع،
    // ومكان فاضي للمنسحبين عشان الباقي ما يتحرك).
    final flow = <Widget>[];
    for (final e in flowElements) {
      if (!layout.isEnabled(e)) continue;
      final detached = layout[e].isDetached;
      final w = _element(e, withKeys: !detached);
      if (w == null) continue;
      if (flow.isNotEmpty) flow.add(SizedBox(height: m.gap));
      flow.add(detached
          ? Visibility(
              visible: false,
              maintainSize: true,
              maintainAnimation: true,
              maintainState: true,
              child: w)
          : w);
    }
    if (flow.isNotEmpty) {
      children.add(Positioned(
        left: 0,
        right: 0,
        top: m.top,
        height: m.availableHeight,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: m.maxTextWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: flow,
            ),
          ),
        ),
      ));
    }

    // 2) اسم السورة: بمكانه الافتراضي (فوق أول سطر الآية) لو ما انسحب.
    if (layout.isEnabled(OverlayElement.surahRef) &&
        !layout[OverlayElement.surahRef].isDetached) {
      final w = _element(OverlayElement.surahRef, withKeys: true);
      if (w != null) {
        children.add(Positioned(
          left: 0,
          right: 0,
          bottom: m.height - m.top + m.unit * OverlayMetrics.surahRefGapRatio,
          child: Align(
            alignment: Alignment.bottomCenter,
            heightFactor: 1.0,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: m.maxTextWidth),
              child: w,
            ),
          ),
        ));
      }
    }

    // 3) العناصر المنسحبة: بموقعها النسبي (منتصفها الأفقي وأعلاها).
    for (final e in OverlayElement.values) {
      if (!layout.isEnabled(e)) continue;
      final a = layout[e].anchor;
      if (a == null) continue;
      final w = _element(e, withKeys: true);
      if (w == null) continue;
      final topPx = a.top * m.height;
      children.add(Positioned(
        left: a.cx * m.width - m.maxTextWidth / 2,
        top: topPx,
        width: m.maxTextWidth,
        height: m.detachedHeightAt(topPx),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: m.maxTextWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [w],
            ),
          ),
        ),
      ));
    }

    return Stack(clipBehavior: Clip.hardEdge, children: children);
  }
}
