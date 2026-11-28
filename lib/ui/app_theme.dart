// الهوية البصرية الجديدة (طلب أنس، 2026-11-28): أخضر زمردي غامق + ذهبي، طابع
// إسلامي فخم، وخط واجهة IBM Plex Sans Arabic (OFL). وضعين: ليلي (الافتراضي)
// ونهاري. المحرر دايماً غامق (زي برامج المونتاج).
import 'package:flutter/material.dart';

/// خط الواجهة (IBM Plex Sans Arabic، 4 أوزان، `assets/fonts/ui`).
const String kUiFont = 'Plex Arabic';

/// ألوان الهوية الثابتة.
class AyahColors {
  AyahColors._();

  // الأخضر (من الأغمق للأفتح).
  static const Color ink = Color(0xFF03170F);
  static const Color deep = Color(0xFF062019);
  static const Color forest = Color(0xFF0A2E23);
  static const Color emerald = Color(0xFF0F4F3B);
  static const Color emeraldLight = Color(0xFF17694F);

  // الذهبي.
  static const Color goldLight = Color(0xFFF8E7AE);
  static const Color gold = Color(0xFFDDB45C);
  static const Color goldDeep = Color(0xFFA8792C);

  static const Color ivory = Color(0xFFFBF5E4);
  static const Color review = Color(0xFFF0A04B);
  static const Color danger = Color(0xFFE86B5F);
  static const Color teal = Color(0xFF52C7B8);

  /// تدرّج الأزرار الذهبية (زي التصميم المقترح: لامع بالنص).
  static const LinearGradient goldGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Color(0xFFC1923F), Color(0xFFF6E19F), Color(0xFFD8AE58), Color(0xFFB98A3A)],
    stops: [0.0, 0.45, 0.75, 1.0],
  );

  static const LinearGradient goldVertical = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [goldLight, gold, goldDeep],
  );
}

/// ألوان كل وضع (ليلي/نهاري) كامتداد للثيم، عشان كل الشاشات تقرأ منه.
@immutable
class AyahPalette extends ThemeExtension<AyahPalette> {
  final Color bgTop;
  final Color bgBottom;
  final Color card;
  final Color cardBorder;
  final Color text;
  final Color textMuted;
  final Color accent;
  final Color accentText;
  final Color pattern;
  final bool dark;

  const AyahPalette({
    required this.bgTop,
    required this.bgBottom,
    required this.card,
    required this.cardBorder,
    required this.text,
    required this.textMuted,
    required this.accent,
    required this.accentText,
    required this.pattern,
    required this.dark,
  });

  static const darkPalette = AyahPalette(
    bgTop: Color(0xFF0E4A37),
    bgBottom: Color(0xFF04180F),
    card: Color(0x14FFFFFF),
    cardBorder: Color(0x8CDDB45C),
    text: AyahColors.ivory,
    textMuted: Color(0xB3E9E1C9),
    accent: AyahColors.gold,
    accentText: Color(0xFFEBCB82),
    pattern: Color(0x26DDB45C),
    dark: true,
  );

  static const lightPalette = AyahPalette(
    bgTop: Color(0xFFFBF6E8),
    bgBottom: Color(0xFFEFE4C8),
    card: Color(0xCCFFFFFF),
    cardBorder: Color(0x99B98A3A),
    text: Color(0xFF0A2E23),
    textMuted: Color(0xFF5B6B60),
    accent: AyahColors.goldDeep,
    accentText: Color(0xFF8A6220),
    pattern: Color(0x22A8792C),
    dark: false,
  );

  LinearGradient get background => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [bgTop, bgBottom],
      );

  static AyahPalette of(BuildContext context) =>
      Theme.of(context).extension<AyahPalette>() ?? darkPalette;

  @override
  AyahPalette copyWith() => this;

  @override
  AyahPalette lerp(ThemeExtension<AyahPalette>? other, double t) {
    if (other is! AyahPalette) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return AyahPalette(
      bgTop: c(bgTop, other.bgTop),
      bgBottom: c(bgBottom, other.bgBottom),
      card: c(card, other.card),
      cardBorder: c(cardBorder, other.cardBorder),
      text: c(text, other.text),
      textMuted: c(textMuted, other.textMuted),
      accent: c(accent, other.accent),
      accentText: c(accentText, other.accentText),
      pattern: c(pattern, other.pattern),
      dark: t < 0.5 ? dark : other.dark,
    );
  }
}

TextTheme _textTheme(Color text, Color muted) {
  TextStyle s(double size, FontWeight w, {Color? color, double h = 1.35}) =>
      TextStyle(fontFamily: kUiFont, fontSize: size, fontWeight: w, color: color ?? text, height: h);
  return TextTheme(
    displaySmall: s(34, FontWeight.w700, h: 1.2),
    headlineMedium: s(26, FontWeight.w700, h: 1.25),
    headlineSmall: s(22, FontWeight.w700),
    titleLarge: s(19, FontWeight.w700),
    titleMedium: s(16, FontWeight.w600),
    titleSmall: s(14, FontWeight.w600),
    bodyLarge: s(16, FontWeight.w400),
    bodyMedium: s(14, FontWeight.w400),
    bodySmall: s(12, FontWeight.w400, color: muted),
    labelLarge: s(15, FontWeight.w600),
    labelMedium: s(13, FontWeight.w500),
    labelSmall: s(11, FontWeight.w500, color: muted),
  );
}

/// ثيم التطبيق للوضع [dark].
ThemeData buildAyahTheme({required bool dark}) {
  final p = dark ? AyahPalette.darkPalette : AyahPalette.lightPalette;
  final scheme = ColorScheme(
    brightness: dark ? Brightness.dark : Brightness.light,
    primary: p.accent,
    onPrimary: AyahColors.ink,
    secondary: AyahColors.emeraldLight,
    onSecondary: Colors.white,
    error: AyahColors.danger,
    onError: Colors.white,
    surface: dark ? AyahColors.forest : const Color(0xFFFFFBF0),
    onSurface: p.text,
    surfaceContainerHighest: dark ? AyahColors.emerald : const Color(0xFFF2E8CF),
    outline: p.cardBorder,
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: kUiFont,
    scaffoldBackgroundColor: p.bgBottom,
    textTheme: _textTheme(p.text, p.textMuted),
    extensions: [p],
  );
  return base.copyWith(
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      foregroundColor: p.text,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
          fontFamily: kUiFont, fontSize: 18, fontWeight: FontWeight.w700, color: p.text),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? AyahColors.emerald : AyahColors.forest,
      contentTextStyle:
          const TextStyle(fontFamily: kUiFont, color: AyahColors.ivory, fontSize: 14),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0x66DDB45C))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: dark ? AyahColors.forest : const Color(0xFFFFFBF0),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(26), side: BorderSide(color: p.cardBorder)),
      titleTextStyle: TextStyle(
          fontFamily: kUiFont, fontSize: 18, fontWeight: FontWeight.w700, color: p.text),
      contentTextStyle: TextStyle(fontFamily: kUiFont, fontSize: 14, color: p.textMuted),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: dark ? AyahColors.forest : const Color(0xFFFFFBF0),
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: p.cardBorder,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.accent,
        foregroundColor: AyahColors.ink,
        minimumSize: const Size(0, 48),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontFamily: kUiFont, fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.accentText,
        side: BorderSide(color: p.cardBorder),
        minimumSize: const Size(0, 48),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontFamily: kUiFont, fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: p.accentText,
        textStyle: const TextStyle(fontFamily: kUiFont, fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.card,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      labelStyle: TextStyle(color: p.textMuted),
      hintStyle: TextStyle(color: p.textMuted),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: p.cardBorder)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: p.cardBorder)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: p.accent, width: 1.6)),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: AyahColors.gold,
      inactiveTrackColor: p.dark ? Colors.white24 : Colors.black12,
      thumbColor: AyahColors.gold,
      overlayColor: AyahColors.gold.withValues(alpha: 0.15),
      trackHeight: 3,
      valueIndicatorColor: AyahColors.emerald,
      valueIndicatorTextStyle: const TextStyle(fontFamily: kUiFont, color: AyahColors.ivory),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? AyahColors.ink : p.textMuted),
      trackColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? AyahColors.gold : (p.dark ? Colors.white12 : Colors.black12)),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: AyahColors.gold,
      linearTrackColor: p.dark ? Colors.white12 : Colors.black12,
      circularTrackColor: Colors.transparent,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        textStyle: WidgetStateProperty.all(
            const TextStyle(fontFamily: kUiFont, fontSize: 13, fontWeight: FontWeight.w600)),
        backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? AyahColors.gold : Colors.transparent),
        foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? AyahColors.ink : p.text),
        side: WidgetStateProperty.all(BorderSide(color: p.cardBorder)),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: p.card,
      selectedColor: AyahColors.gold,
      side: BorderSide(color: p.cardBorder),
      labelStyle: TextStyle(fontFamily: kUiFont, color: p.text, fontSize: 13),
      secondaryLabelStyle: const TextStyle(fontFamily: kUiFont, color: AyahColors.ink, fontSize: 13),
      shape: const StadiumBorder(),
      checkmarkColor: AyahColors.ink,
    ),
    dividerTheme: DividerThemeData(color: p.cardBorder.withValues(alpha: 0.35), thickness: 1),
    listTileTheme: ListTileThemeData(
      iconColor: p.accentText,
      textColor: p.text,
      titleTextStyle: TextStyle(fontFamily: kUiFont, fontSize: 15, color: p.text, fontWeight: FontWeight.w600),
      subtitleTextStyle: TextStyle(fontFamily: kUiFont, fontSize: 12, color: p.textMuted),
    ),
    iconTheme: IconThemeData(color: p.accentText),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: ZoomPageTransitionsBuilder(),
    }),
  );
}
