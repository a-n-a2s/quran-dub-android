// مكوّنات الواجهة المشتركة (الهوية الجديدة): خلفية زمردية بنقش هندسي خفيف،
// بطاقات زجاجية بحد ذهبي، أزرار ذهبية لامعة، صندوق رفع بحد متقطّع، الشعار،
// موجة صوت مزخرفة، ومفتاح الوضع الليلي/النهاري.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_theme.dart';

/// الشعار (موجة صوت ذهبية + "آية") من `assets/branding/logo_mark.png`.
class AyahLogo extends StatelessWidget {
  final double size;
  const AyahLogo({super.key, this.size = 120});

  @override
  Widget build(BuildContext context) => Image.asset(
        'assets/branding/logo_mark.png',
        width: size,
        height: size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
      );
}

/// خلفية الشاشات: تدرّج من الأخضر للأغمق + خطوط هندسية ذهبية خافتة (زي
/// التصميم المقترح) + توهّج خفيف فوق.
class AyahBackground extends StatelessWidget {
  final Widget child;
  final bool pattern;
  const AyahBackground({super.key, required this.child, this.pattern = true});

  @override
  Widget build(BuildContext context) {
    final p = AyahPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(gradient: p.background),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (pattern)
            Positioned.fill(
              child: RepaintBoundary(
                child: CustomPaint(painter: _PatternPainter(p.pattern, p.dark)),
              ),
            ),
          child,
        ],
      ),
    );
  }
}

class _PatternPainter extends CustomPainter {
  final Color color;
  final bool dark;
  _PatternPainter(this.color, this.dark);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = math.min(size.height * 0.42, w * 0.95);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    // خطوط مائلة متقاطعة (معيّنات) بالجزء العلوي، بتتلاشى لتحت.
    final rect = Rect.fromLTWH(0, 0, w, h);
    canvas.save();
    canvas.clipRect(rect);
    final shader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [color, color.withValues(alpha: 0)],
    ).createShader(rect);
    paint.shader = shader;
    final step = w / 3;
    for (var i = -3; i <= 6; i++) {
      final x = i * step;
      canvas.drawLine(Offset(x, 0), Offset(x + h, h), paint);
      canvas.drawLine(Offset(x, 0), Offset(x - h, h), paint);
    }
    // خطين عموديين رفيعين على الأطراف (إطار).
    canvas.drawLine(Offset(w * 0.04, 0), Offset(w * 0.04, h), paint);
    canvas.drawLine(Offset(w * 0.96, 0), Offset(w * 0.96, h), paint);
    canvas.restore();
    // توهّج فوق.
    final glow = Paint()
      ..shader = RadialGradient(colors: [
        (dark ? const Color(0xFF1C7A5C) : const Color(0xFFFFFFFF)).withValues(alpha: dark ? 0.35 : 0.7),
        Colors.transparent,
      ]).createShader(Rect.fromCircle(center: Offset(w / 2, h * 0.25), radius: w * 0.8));
    canvas.drawCircle(Offset(w / 2, h * 0.25), w * 0.8, glow);
  }

  @override
  bool shouldRepaint(covariant _PatternPainter old) => old.color != color || old.dark != dark;
}

/// بطاقة زجاجية بحد ذهبي رفيع.
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;
  final Color? borderColor;
  final bool highlight;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 26,
    this.onTap,
    this.borderColor,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = AyahPalette.of(context);
    final r = BorderRadius.circular(radius);
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: r,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: p.dark
                ? [const Color(0x1FFFFFFF), const Color(0x0AFFFFFF)]
                : [const Color(0xF2FFFFFF), const Color(0xCCFFFFFF)],
          ),
          border: Border.all(
              color: borderColor ?? (highlight ? AyahColors.gold : p.cardBorder),
              width: highlight ? 1.6 : 1),
          boxShadow: [
            BoxShadow(
              color: p.dark ? const Color(0x55000000) : const Color(0x1A6B4E14),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: InkWell(
          borderRadius: r,
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// زر ذهبي لامع (pill) بتوهّج، زي "تحميل الملف" بالتصميم المقترح.
class GoldButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final double height;
  final double fontSize;
  final bool expand;

  const GoldButton({
    super.key,
    required this.label,
    this.icon,
    required this.onPressed,
    this.height = 56,
    this.fontSize = 18,
    this.expand = true,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final child = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, color: AyahColors.ink, size: fontSize + 4),
          const SizedBox(width: 10),
        ],
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: kUiFont,
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              color: AyahColors.ink,
            ),
          ),
        ),
      ],
    );
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          gradient: AyahColors.goldGradient,
          borderRadius: BorderRadius.circular(height / 2),
          boxShadow: enabled
              ? [
                  BoxShadow(
                      color: AyahColors.gold.withValues(alpha: 0.45),
                      blurRadius: 22,
                      spreadRadius: -2,
                      offset: const Offset(0, 6)),
                ]
              : null,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(height / 2),
            onTap: enabled
                ? () {
                    HapticFeedback.lightImpact();
                    onPressed!();
                  }
                : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// زر ثانوي بحد ذهبي (pill شفاف).
class GoldOutlineButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final double height;

  const GoldOutlineButton(
      {super.key, required this.label, this.icon, required this.onPressed, this.height = 50});

  @override
  Widget build(BuildContext context) {
    final p = AyahPalette.of(context);
    return SizedBox(
      height: height,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: icon == null ? const SizedBox.shrink() : Icon(icon, size: 20),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: p.accentText,
          side: BorderSide(color: p.cardBorder, width: 1.2),
          backgroundColor: p.card,
        ),
      ),
    );
  }
}

/// زر دائري (أيقونة) بخلفية زجاجية أو ذهبية.
class RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final bool gold;
  final double size;
  final String? tooltip;
  final Color? iconColor;

  const RoundIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.gold = false,
    this.size = 46,
    this.tooltip,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final p = AyahPalette.of(context);
    final btn = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: gold ? AyahColors.goldVertical : null,
        color: gold ? null : p.card,
        border: gold ? null : Border.all(color: p.cardBorder.withValues(alpha: 0.6)),
        boxShadow: gold
            ? [BoxShadow(color: AyahColors.gold.withValues(alpha: 0.4), blurRadius: 14)]
            : null,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Icon(icon,
              size: size * 0.5, color: iconColor ?? (gold ? AyahColors.ink : p.accentText)),
        ),
      ),
    );
    return tooltip == null ? btn : Tooltip(message: tooltip!, child: btn);
  }
}

/// وسم صغير بحد (زي "الآيات" و"التفسير" بالبطاقات).
class AyahTag extends StatelessWidget {
  final String label;
  final bool gold;
  const AyahTag(this.label, {super.key, this.gold = true});

  @override
  Widget build(BuildContext context) {
    final p = AyahPalette.of(context);
    final c = gold ? p.accentText : p.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(40),
        border: Border.all(color: c.withValues(alpha: 0.8)),
      ),
      child: Text(label,
          style: TextStyle(fontFamily: kUiFont, fontSize: 13, color: c, fontWeight: FontWeight.w500)),
    );
  }
}

/// رسام حد متقطّع (صندوق الرفع).
class DashedBorderPainter extends CustomPainter {
  final Color color;
  final double radius;
  final double dash;
  final double gap;
  final double width;

  DashedBorderPainter(
      {required this.color, this.radius = 28, this.dash = 9, this.gap = 7, this.width = 1.6});

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
        Offset.zero & size, Radius.circular(radius));
    final path = Path()..addRRect(rrect.deflate(width / 2));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, math.min(d + dash, m.length)), paint);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant DashedBorderPainter old) => old.color != color;
}

/// موجة صوت مزخرفة (خطوط طولية بأطراف مدوّرة) من [levels] (0..1).
class WaveBars extends StatelessWidget {
  final List<double> levels;
  final double height;
  final Color? color;
  final double progress;

  const WaveBars({super.key, required this.levels, this.height = 40, this.color, this.progress = 1});

  @override
  Widget build(BuildContext context) {
    final p = AyahPalette.of(context);
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _WaveBarsPainter(levels, color ?? p.accent, p.textMuted.withValues(alpha: 0.35),
            progress),
      ),
    );
  }
}

class _WaveBarsPainter extends CustomPainter {
  final List<double> levels;
  final Color on;
  final Color off;
  final double progress;
  _WaveBarsPainter(this.levels, this.on, this.off, this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    if (levels.isEmpty) return;
    final n = levels.length;
    final pitch = size.width / n;
    final bw = math.max(1.5, pitch * 0.42);
    final paint = Paint()..strokeCap = StrokeCap.round;
    for (var i = 0; i < n; i++) {
      final v = levels[i].clamp(0.06, 1.0);
      final h = math.max(bw, v * size.height);
      final x = pitch * (i + 0.5);
      paint
        ..color = (i / n) <= progress ? on : off
        ..strokeWidth = bw;
      canvas.drawLine(Offset(x, (size.height - h) / 2 + bw / 2),
          Offset(x, (size.height + h) / 2 - bw / 2), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WaveBarsPainter old) =>
      old.levels != levels || old.on != on || old.progress != progress;
}

/// مفتاح الوضع الليلي/النهاري (قمر + شمس) زي التصميم المقترح.
class ThemeModeToggle extends StatelessWidget {
  final bool dark;
  final ValueChanged<bool> onChanged;
  const ThemeModeToggle({super.key, required this.dark, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final p = AyahPalette.of(context);
    Widget knob(IconData icon, bool active, Color activeColor) => AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? activeColor : Colors.transparent,
          ),
          child: Icon(icon,
              size: 20,
              color: active
                  ? (dark ? AyahColors.forest : AyahColors.ink)
                  : AyahColors.gold),
        );
    return Semantics(
      button: true,
      label: dark ? 'الوضع الليلي' : 'الوضع النهاري',
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onChanged(!dark);
        },
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: p.dark ? const Color(0x33000000) : const Color(0x14000000),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: p.cardBorder.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            textDirection: TextDirection.ltr,
            children: [
              knob(Icons.dark_mode_rounded, dark, const Color(0xFFE8E4D8)),
              const SizedBox(width: 2),
              knob(Icons.light_mode_rounded, !dark, AyahColors.goldLight),
            ],
          ),
        ),
      ),
    );
  }
}

/// عنوان قسم (زي "مشاريع القرآن الأخيرة").
class SectionTitle extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const SectionTitle(this.title, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    final p = AyahPalette.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(title,
              style: TextStyle(
                  fontFamily: kUiFont, fontSize: 21, fontWeight: FontWeight.w700, color: p.text)),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// مؤشر تحميل ذهبي بشعار الموجة (بدل الدائرة العادية).
class GoldLoader extends StatefulWidget {
  final double size;
  const GoldLoader({super.key, this.size = 56});

  @override
  State<GoldLoader> createState() => _GoldLoaderState();
}

class _GoldLoaderState extends State<GoldLoader> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size * 0.6,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) => CustomPaint(painter: _LoaderPainter(_c.value)),
      ),
    );
  }
}

class _LoaderPainter extends CustomPainter {
  final double t;
  _LoaderPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    const n = 7;
    final pitch = size.width / n;
    final bw = pitch * 0.5;
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = bw
      ..color = AyahColors.gold;
    for (var i = 0; i < n; i++) {
      final phase = (t * 2 * math.pi) - i * 0.7;
      final v = 0.25 + 0.75 * (0.5 + 0.5 * math.sin(phase));
      final h = math.max(bw, v * size.height);
      final x = pitch * (i + 0.5);
      canvas.drawLine(Offset(x, (size.height - h) / 2 + bw / 2),
          Offset(x, (size.height + h) / 2 - bw / 2), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _LoaderPainter old) => old.t != t;
}

/// شكل حوار موحّد (RTL + حواف مدوّرة).
Future<T?> showAyahDialog<T>(BuildContext context, WidgetBuilder builder) =>
    showDialog<T>(
      context: context,
      builder: (ctx) => Directionality(textDirection: TextDirection.rtl, child: builder(ctx)),
    );
