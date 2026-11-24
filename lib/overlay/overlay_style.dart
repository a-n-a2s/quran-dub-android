import 'ayah_font.dart';
import 'overlay_frame.dart';
import '../pipeline/recitation_segment.dart';

/// اختيارات المستخدم لشكل النص فوق الفيديو (يوم 8): **نفس** القيم بتروح
/// للمعاينة ([AyahOverlayFrame]) وللتصدير، فما في نسختين من الإعدادات. يوم 9
/// (التخصيص والقوالب) بيوسّع هالكلاس (أحجام، مواقع، عناصر، ألوان...) وكل شي
/// بينعكس على التصدير تلقائياً لأنه التصدير بيرسم بنفس [AyahOverlayFrame].
class OverlayStyle {
  final TafsirMode tafsirMode;
  final AyahFont font;
  final OverlayTextColor color;
  final bool shadow;

  const OverlayStyle({
    this.tafsirMode = TafsirMode.split,
    this.font = AyahFont.defaultFont,
    this.color = OverlayTextColor.defaultColor,
    this.shadow = false,
  });

  OverlayStyle copyWith({
    TafsirMode? tafsirMode,
    AyahFont? font,
    OverlayTextColor? color,
    bool? shadow,
  }) =>
      OverlayStyle(
        tafsirMode: tafsirMode ?? this.tafsirMode,
        font: font ?? this.font,
        color: color ?? this.color,
        shadow: shadow ?? this.shadow,
      );

  Map<String, Object?> toJson() => {
        'tafsirMode': tafsirMode.name,
        'font': font.name,
        'color': color.name,
        'shadow': shadow,
      };

  @override
  String toString() =>
      'تفسير ${tafsirMode.name}، خط ${font.label}، نص ${color.label}${shadow ? '، مع ظل' : ''}';
}
