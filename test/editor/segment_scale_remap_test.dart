// إعادة ربط segmentScales عند حذف/إضافة/إعادة ترتيب المقاطع (يوم 10).
import 'package:flutter_test/flutter_test.dart';
import 'package:quran_dub/editor/segment_scale_remap.dart';
import 'package:quran_dub/overlay/overlay_layout.dart';

void main() {
  group('remapSegmentScales', () {
    test('بدون تغيير بالقائمة: نفس المفاتيح', () {
      final old = {
        1: {OverlayElement.ayah: 1.3},
        2: {OverlayElement.tafsir: 0.8},
      };
      final mapping = [0, 1, 2];
      final out = remapSegmentScales(old, mapping);
      expect(out, old);
    });

    test('حذف مقطع: المفاتيح اللي بعده بتنزل واحد، وحجم المحذوف بيضيع', () {
      // قائمة أصلية من 4 مقاطع (0..3)، عنا حجم خاص للمقطع 1 والمقطع 3.
      final old = {
        1: {OverlayElement.ayah: 1.4},
        3: {OverlayElement.tafsir: 0.7},
      };
      final mapping = mappingForDelete(4, 1); // حذفنا رقم 1
      expect(mapping, [0, null, 1, 2]);
      final out = remapSegmentScales(old, mapping);
      // المقطع المحذوف (1) راح، والمقطع 3 صار 2.
      expect(out.containsKey(1), isFalse);
      expect(out[2], {OverlayElement.tafsir: 0.7});
      expect(out.length, 1);
    });

    test('حذف المقطع نفسه اللي إله حجم خاص: بيضيع حجمه هو بس', () {
      final old = {
        0: {OverlayElement.ayah: 1.5},
      };
      final mapping = mappingForDelete(2, 0);
      final out = remapSegmentScales(old, mapping);
      expect(out, isEmpty);
    });

    test('إضافة مقطع بالنص: كل اللي بعده بيتزحزح خطوة', () {
      final old = {
        0: {OverlayElement.ayah: 1.2},
        1: {OverlayElement.tafsir: 0.9},
      };
      final mapping = mappingForInsert(2, 1); // إضافة بمكان 1
      expect(mapping, [0, 2]);
      final out = remapSegmentScales(old, mapping);
      expect(out[0], {OverlayElement.ayah: 1.2});
      expect(out[2], {OverlayElement.tafsir: 0.9});
      expect(out.containsKey(1), isFalse); // المكان الجديد فاضي (مقطع جديد)
    });

    test('إضافة بأول القائمة: كل القديم بيتزحزح', () {
      final old = {
        0: {OverlayElement.ayah: 1.2},
      };
      final mapping = mappingForInsert(1, 0);
      expect(mapping, [1]);
      expect(remapSegmentScales(old, mapping), {
        1: {OverlayElement.ayah: 1.2},
      });
    });

    test('إعادة ترتيب: المفاتيح بتتبع مكانها الجديد', () {
      final old = {
        0: {OverlayElement.ayah: 1.1},
        1: {OverlayElement.tafsir: 0.6},
        2: {OverlayElement.reciter: 1.4},
      };
      // الترتيب الجديد: القديم 2 صار أول، بعده القديم 0، وحذفنا القديم 1.
      final mapping = mappingForReorder([2, 0]);
      expect(mapping, [1, null, 0]);
      final out = remapSegmentScales(old, mapping);
      expect(out[1], {OverlayElement.ayah: 1.1}); // كان 0
      expect(out[0], {OverlayElement.reciter: 1.4}); // كان 2
      expect(out.containsKey(2), isFalse); // كان 1، انحذف بالترتيب الجديد
    });

    test('مفتاح قديم برا حدود mapping بينشال بأمان', () {
      final old = {
        5: {OverlayElement.ayah: 1.1}, // index غلط/قديم جداً
        0: {OverlayElement.tafsir: 0.5},
      };
      final mapping = [0]; // قائمة قصيرة
      final out = remapSegmentScales(old, mapping);
      expect(out, {
        0: {OverlayElement.tafsir: 0.5},
      });
    });

    test('mappingForReorder لقائمة فاضية = فاضية', () {
      expect(mappingForReorder(const []), isEmpty);
    });
  });
}
