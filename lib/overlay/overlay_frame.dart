import 'package:flutter/material.dart';

import '../pipeline/recitation_segment.dart';
import 'ayah_font.dart';
import 'overlay_metrics.dart';
import 'overlay_timeline.dart';
import 'tafsir_display.dart';

/// ألوان النص فوق الفيديو (من المقطع المرجعي).
const Color overlayWhite = Color(0xFFFFFFFF);
const Color overlayGold = Color(0xFFD9B55E);
const Color overlayBlack = Color(0xFF000000);

/// لون النص فوق الفيديو: **أبيض أو أسود بس** (طلب أنس يوم 7، لما النص
/// الأبيض ما بيّن فوق خلفية فاتحة). الأبيض = شكل المقطع المرجعي (النص أبيض
/// والأقواس ذهبية). الأسود = كل شي أسود (الآية والأقواس ودائرة الرقم
/// والتفسير)، لأنه الذهبي كمان ما بيبيّن على الأبيض. التخصيص الكامل (ألوان
/// ثانية، ظل، خلفية) = يوم 9.
enum OverlayTextColor {
  white('أبيض'),
  black('أسود');

  final String label;
  const OverlayTextColor(this.label);

  static const OverlayTextColor defaultColor = white;

  Color get text => this == white ? overlayWhite : overlayBlack;
  Color get bracket => this == white ? overlayGold : overlayBlack;

  /// اللون الأوضح فوق خلفية متوسط سطوعها [luma] (0 أسود .. 1 أبيض) ونسبة
  /// البكسلات الفاتحة فيها [brightFraction] (بمنطقة النص).
  static OverlayTextColor forBackground(double luma, double brightFraction) =>
      luma > 0.58 || brightFraction > 0.5 ? black : white;
}

/// عائلة خط التفسير ورقم الآية (Amiri، SIL OFL).
const String tafsirFontFamily = 'Amiri';

/// إطار النص فوق الفيديو بأبعاد الفيديو **الحقيقية بالبكسل**
/// ([videoWidth]×[videoHeight] بعد الدوران): بنرسم بنفس المقاسات اللي رح
/// يتصدّر فيها الفيديو (يوم 8)، والمعاينة بتصغّره بـ FittedBox. بدون أي
/// صندوق أو خلفية: الفيديو بيضل ظاهر وراء النص.
///
/// الشكل (المقطع المرجعي): ﴿ الآية [رقم] ﴾ بالرسم العثماني، أبيض والأقواس
/// ذهبية، والرقم بدائرة بيضاء صغيرة (أرقام عربية-هندية) مع آخر جزء بس،
/// والتفسير تحتها مباشرة. أول سطر عند 61% من الارتفاع؛ وكتلة أطول من المتاح
/// بتتصغّر لتتسع (ما بتطلع برا الفيديو).
class AyahOverlayFrame extends StatelessWidget {
  final int videoWidth;
  final int videoHeight;
  final OverlayCue? cue;
  final TafsirMode tafsirMode;
  final AyahFont font;
  final OverlayTextColor color;

  const AyahOverlayFrame({
    super.key,
    required this.videoWidth,
    required this.videoHeight,
    required this.cue,
    this.tafsirMode = TafsirMode.split,
    this.font = AyahFont.defaultFont,
    this.color = OverlayTextColor.defaultColor,
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
              Positioned(
                left: 0,
                right: 0,
                top: m.top,
                height: m.availableHeight,
                child: Opacity(
                  opacity: c.opacity.clamp(0.0, 1.0),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.topCenter,
                    child: SizedBox(
                      width: m.maxTextWidth,
                      child: _TextBlock(
                        segment: c.item.segment,
                        metrics: m,
                        tafsirMode: tafsirMode,
                        font: font,
                        color: color,
                      ),
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

class _TextBlock extends StatelessWidget {
  final RecitationSegment segment;
  final OverlayMetrics metrics;
  final TafsirMode tafsirMode;
  final AyahFont font;
  final OverlayTextColor color;

  const _TextBlock({
    required this.segment,
    required this.metrics,
    required this.tafsirMode,
    required this.font,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    final ayahLine = _ayahLine(m);
    final tafsir = TafsirDisplay.forDisplay(segment, tafsirMode);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (ayahLine != null) ayahLine,
          if (ayahLine != null && tafsir.isNotEmpty) SizedBox(height: m.gap),
          if (tafsir.isNotEmpty)
            Text(
              tafsir,
              key: const ValueKey('overlay-tafsir'),
              textAlign: TextAlign.center,
              textDirection: TextDirection.rtl,
              style: TextStyle(
                fontFamily: tafsirFontFamily,
                fontSize: m.tafsirFontSize,
                height: m.tafsirLineHeight,
                color: color.text,
                decoration: TextDecoration.none,
              ),
            ),
        ],
      ),
    );
  }

  Widget? _ayahLine(OverlayMetrics m) {
    // نص مستخدم لجزء غير قرآني (يوم 10 بيعبّيه): سطر عادي بدون أقواس.
    if (segment.kind == SegmentKind.nonQuran) {
      final t = segment.userText ?? '';
      if (t.isEmpty) return null;
      return Text(
        t,
        key: const ValueKey('overlay-user-text'),
        textAlign: TextAlign.center,
        textDirection: TextDirection.rtl,
        style: TextStyle(
          fontFamily: tafsirFontFamily,
          fontSize: m.ayahFontSize,
          height: m.tafsirLineHeight,
          color: color.text,
          decoration: TextDecoration.none,
        ),
      );
    }
    if (segment.text.isEmpty) return null;
    final base = TextStyle(
      fontFamily: font.family,
      fontSize: m.ayahFontSize,
      height: m.ayahLineHeight,
      color: color.text,
      decoration: TextDecoration.none,
    );
    final bracket = base.copyWith(
      fontFamily: AyahFont.amiriQuran.family,
      color: color.bracket,
    );
    return Text.rich(
      TextSpan(
        style: base,
        children: [
          TextSpan(text: ayahOpenBracket, style: bracket),
          TextSpan(text: font.prepare(segment.text)),
          if (segment.showAyahNumber && segment.ayah != null)
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: _AyahNumberCircle(
                  number: segment.ayah!, metrics: m, color: color.text),
            ),
          TextSpan(text: ayahCloseBracket, style: bracket),
        ],
      ),
      key: const ValueKey('overlay-ayah'),
      textAlign: TextAlign.center,
      textDirection: TextDirection.rtl,
    );
  }
}

/// دائرة رقم الآية: حد رفيع ورقم بأرقام عربية-هندية، بلون النص.
class _AyahNumberCircle extends StatelessWidget {
  final int number;
  final OverlayMetrics metrics;
  final Color color;
  const _AyahNumberCircle(
      {required this.number, required this.metrics, required this.color});

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: m.circleMargin),
      child: Container(
        key: const ValueKey('overlay-ayah-number'),
        width: m.circleSize,
        height: m.circleSize,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: color, width: m.circleBorder),
        ),
        // رقم من 3 خانات (آية 100+) بيصغّر ليتسع بالدائرة.
        child: Padding(
          padding: EdgeInsets.all(m.circleBorder * 1.5),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              toArabicIndic(number),
              textDirection: TextDirection.rtl,
              style: TextStyle(
                fontFamily: tafsirFontFamily,
                fontSize: m.numberFontSize,
                height: 1,
                color: color,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
