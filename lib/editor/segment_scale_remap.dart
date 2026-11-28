// إعادة ربط `OverlayStyle.segmentScales` (يوم 10، طلب يوم 9 الصريح):
// المفاتيح index بقائمة المقاطع **الأصلية**. أي حذف/إضافة/إعادة ترتيب
// للمقاطع لازم يعيد حساب المفاتيح، وإلا الحجم الخاص بيصير على المقطع الغلط
// (أو بيضيع). جزء صافي، مستقل تماماً عن الواجهة فبيتجرب لحاله.
import '../overlay/overlay_layout.dart';

typedef SegmentScaleMap = Map<int, Map<OverlayElement, double>>;

/// [mapping] بطول القائمة **القديمة**: `mapping[oldIndex]` = مكانه الجديد،
/// أو null لو انحذف. أي مفتاح قديم برا حدود [mapping] (قائمة تغيّر طولها
/// بدون ما نولّد mapping كامل) بينشال بأمان بدل ما ينهار.
SegmentScaleMap remapSegmentScales(SegmentScaleMap old, List<int?> mapping) {
  final out = <int, Map<OverlayElement, double>>{};
  old.forEach((oldIndex, scales) {
    if (oldIndex < 0 || oldIndex >= mapping.length) return;
    final newIndex = mapping[oldIndex];
    if (newIndex != null) out[newIndex] = scales;
  });
  return out;
}

/// نفس [remapSegmentScales] لأي خريطة مفاتيحها index مقطع (مثلاً
/// `OverlayStyle.segmentStyles`، الشكل الخاص بكل آية).
Map<int, T> remapIndexMap<T>(Map<int, T> old, List<int?> mapping) {
  final out = <int, T>{};
  old.forEach((oldIndex, v) {
    if (oldIndex < 0 || oldIndex >= mapping.length) return;
    final newIndex = mapping[oldIndex];
    if (newIndex != null) out[newIndex] = v;
  });
  return out;
}

/// حذف المقطع رقم [deletedIndex] من قائمة طولها [oldLength]: كل اللي بعده
/// بيرجع مرتبة وحدة، وهو نفسه بيصير null (حجمه الخاص بيضيع مع حذفه).
List<int?> mappingForDelete(int oldLength, int deletedIndex) => [
      for (var i = 0; i < oldLength; i++)
        if (i == deletedIndex)
          null
        else if (i < deletedIndex)
          i
        else
          i - 1,
    ];

/// إضافة مقطع جديد بمكان [insertAt] (مكانه بالقائمة الجديدة) على قائمة
/// كان طولها [oldLength]: كل مقطع قديم بمكان ≥ [insertAt] بيتزحزح خطوة.
List<int?> mappingForInsert(int oldLength, int insertAt) => [
      for (var i = 0; i < oldLength; i++) i < insertAt ? i : i + 1,
    ];

/// إعادة ترتيب: [newOrderOldIndices] هي القائمة الجديدة، كل عنصر فيها هو
/// **مكان ذلك المقطع بالقائمة القديمة** (مثلاً `[2, 0, 1]` يعني المقطع
/// الجديد رقم 0 هو كان رقم 2 قبل). القديم اللي ما ظهر بالقائمة الجديدة
/// (انحذف ضمن نفس العملية) بيصير null.
List<int?> mappingForReorder(List<int> newOrderOldIndices) {
  if (newOrderOldIndices.isEmpty) return const [];
  final byOld = <int, int>{};
  for (var newIndex = 0; newIndex < newOrderOldIndices.length; newIndex++) {
    byOld[newOrderOldIndices[newIndex]] = newIndex;
  }
  final maxOld = newOrderOldIndices.reduce((a, b) => a > b ? a : b);
  return [for (var i = 0; i <= maxOld; i++) byOld[i]];
}
