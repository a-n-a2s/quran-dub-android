// خطوط الإرشاد والالتصاق أثناء سحب العنصر بالمحرر (يوم 9، طلب أنس): خط عمودي
// بنص الفيديو، خط أفقي بنص الفيديو، وخطوط محاذاة مع حواف/مراكز العناصر
// الثانية (عشان الكلام يضل مستقيم). Dart صافي، بإحداثيات الفيديو بالبكسل.
import 'dart:math' as math;
import 'dart:ui';

enum GuideAxis { vertical, horizontal }

enum GuideKind { center, align }

class SnapGuide {
  final GuideAxis axis;

  /// x للخط العمودي، y للأفقي (بكسلات الفيديو).
  final double position;
  final GuideKind kind;
  const SnapGuide(this.axis, this.position, this.kind);

  @override
  bool operator ==(Object o) =>
      o is SnapGuide &&
      o.axis == axis &&
      o.kind == kind &&
      (o.position - position).abs() < 0.01;
  @override
  int get hashCode => Object.hash(axis, kind, position.round());

  @override
  String toString() => '${axis.name}@${position.toStringAsFixed(1)}(${kind.name})';
}

class SnapResult {
  final Rect rect;
  final List<SnapGuide> guides;
  const SnapResult(this.rect, this.guides);
}

/// التصاق [r] بمنتصف الفيديو ([video]) وبحواف/مراكز [others] لو أقرب من
/// [threshold]. لو [snap] = false ما بتتحرك [r] بس بترجع الخطوط اللي صارت
/// قريبة (للتكبير بإصبعين). الخطوط بترجع لكل محاذاة فعلية بعد الالتصاق.
SnapResult snapRect(
  Rect r, {
  required Size video,
  List<Rect> others = const [],
  required double threshold,
  bool snap = true,
}) {
  final xt = <(double, GuideKind)>[(video.width / 2, GuideKind.center)];
  final yt = <(double, GuideKind)>[(video.height / 2, GuideKind.center)];
  for (final o in others) {
    xt
      ..add((o.left, GuideKind.align))
      ..add((o.center.dx, GuideKind.align))
      ..add((o.right, GuideKind.align));
    yt
      ..add((o.top, GuideKind.align))
      ..add((o.center.dy, GuideKind.align))
      ..add((o.bottom, GuideKind.align));
  }

  double bestDelta(List<double> mine, List<(double, GuideKind)> targets) {
    var best = double.infinity;
    for (final m in mine) {
      for (final t in targets) {
        final d = t.$1 - m;
        if (d.abs() <= threshold && d.abs() < best.abs()) best = d;
      }
    }
    return best.isFinite ? best : 0;
  }

  final dx = snap ? bestDelta([r.left, r.center.dx, r.right], xt) : 0.0;
  final dy = snap ? bestDelta([r.top, r.center.dy, r.bottom], yt) : 0.0;
  final out = r.shift(Offset(dx, dy));
  final eps = snap ? 0.5 : math.min(threshold, 3.0);

  final guides = <SnapGuide>[];
  void collect(GuideAxis axis, List<double> mine, List<(double, GuideKind)> targets) {
    for (final t in targets) {
      if (mine.any((m) => (m - t.$1).abs() <= eps)) {
        final g = SnapGuide(axis, t.$1, t.$2);
        if (!guides.contains(g)) guides.add(g);
      }
    }
  }

  collect(GuideAxis.vertical, [out.left, out.center.dx, out.right], xt);
  collect(GuideAxis.horizontal, [out.top, out.center.dy, out.bottom], yt);
  return SnapResult(out, guides);
}
