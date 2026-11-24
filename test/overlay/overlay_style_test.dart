// نموذج التخصيص (يوم 9): العناصر الخمسة، OverlayStyle، الظل، القوالب. صافي.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quran_dub/export/export_plan.dart';
import 'package:quran_dub/overlay/ayah_font.dart';
import 'package:quran_dub/overlay/overlay_colors.dart';
import 'package:quran_dub/overlay/overlay_layout.dart';
import 'package:quran_dub/overlay/overlay_metrics.dart';
import 'package:quran_dub/overlay/overlay_style.dart';
import 'package:quran_dub/overlay/overlay_templates.dart';
import 'package:quran_dub/pipeline/recitation_segment.dart';

void main() {
  group('العناصر ومواقعها', () {
    test('الافتراضي = المقطع المرجعي: آية + تفسير بس، بدون سحب وبحجم 1', () {
      const l = OverlayLayout.reference;
      for (final e in OverlayElement.values) {
        final want = e == OverlayElement.ayah || e == OverlayElement.tafsir;
        expect(l.isEnabled(e), want, reason: e.name);
        expect(l[e].scale, 1.0);
        expect(l[e].anchor, isNull);
      }
      expect(l.isReference, isTrue);
      expect(const OverlayStyle().layout.isReference, isTrue);
      expect(l.detached, isEmpty);
    });

    test('الحجم بحدود، والموقع بحدود الفيديو', () {
      final p = const ElementPlacement().copyWith(scale: 9);
      expect(p.scale, ElementPlacement.maxScale);
      expect(const ElementPlacement().copyWith(scale: 0.01).scale,
          ElementPlacement.minScale);
      final a = const ElementAnchor(-1, 5).clamped();
      expect(a.cx, 0);
      expect(a.top, ElementAnchor.maxTop);
    });

    test('المواقع نسبية: نفس الموقع النسبي = أماكن متناسبة بالأبعاد الثلاثة', () {
      const a = ElementAnchor(0.3, 0.2);
      for (final s in const [(1080, 1920), (1920, 1080), (1080, 1080), (2160, 3840)]) {
        final px = anchorToPixels(a, s.$1, s.$2);
        expect(px.cx / s.$1, closeTo(0.3, 1e-9));
        expect(px.top / s.$2, closeTo(0.2, 1e-9));
        final back = anchorFromPixels(px.cx, px.top, s.$1, s.$2);
        expect(back.cx, closeTo(0.3, 1e-9));
        expect(back.top, closeTo(0.2, 1e-9));
      }
    });

    test('تشغيل/إطفاء وسحب وإرجاع للمكان الافتراضي', () {
      var l = OverlayLayout.reference
          .update(OverlayElement.surahRef, (p) => p.copyWith(enabled: true))
          .update(OverlayElement.ayah, (p) => p.copyWith(anchor: const ElementAnchor(0.5, 0.1)));
      expect(l.isEnabled(OverlayElement.surahRef), isTrue);
      expect(l.detached, [OverlayElement.ayah]);
      expect(l.isReference, isFalse);
      l = l.update(OverlayElement.ayah, (p) => p.copyWith(clearAnchor: true));
      expect(l.detached, isEmpty);
      // المطفي ما بينحسب منسحب.
      l = l
          .update(OverlayElement.tafsir, (p) => p.copyWith(anchor: const ElementAnchor(0.5, 0.5)))
          .update(OverlayElement.tafsir, (p) => p.copyWith(enabled: false));
      expect(l.detached, isEmpty);
    });

    test('JSON: ذهاب وإياب، وعناصر ناقصة أو غلط بترجع للافتراضي', () {
      final l = OverlayLayout.reference
          .update(OverlayElement.reciter, (p) => p.copyWith(enabled: true, scale: 1.25))
          .update(OverlayElement.ayah, (p) => p.copyWith(anchor: const ElementAnchor(0.25, 0.4)));
      final back = OverlayLayout.fromJson(jsonDecode(jsonEncode(l.toJson())));
      expect(back, l);
      expect(OverlayLayout.fromJson(null), OverlayLayout.reference);
      expect(OverlayLayout.fromJson('x'), OverlayLayout.reference);
      final partial = OverlayLayout.fromJson({
        'ayah': {'enabled': false, 'scale': 'غلط', 'anchor': [2, 2]},
        'tafsir': 5,
      });
      expect(partial.isEnabled(OverlayElement.ayah), isFalse);
      expect(partial[OverlayElement.ayah].scale, 1.0);
      expect(partial[OverlayElement.ayah].anchor, const ElementAnchor(1, ElementAnchor.maxTop));
      expect(partial.isEnabled(OverlayElement.tafsir), isTrue);
    });

    test('الترجمة معطّلة (يوم 12)، والباقي متاح', () {
      expect(OverlayElement.translation.available, isFalse);
      for (final e in OverlayElement.values.where((e) => e != OverlayElement.translation)) {
        expect(e.available, isTrue);
      }
      expect(OverlayElement.values.length, 5);
    });
  });

  group('OverlayStyle', () {
    test('الافتراضي: شكل المرجع، أبيض، بدون ظل ولا خلفية', () {
      const s = OverlayStyle();
      expect(s.color, OverlayTextColor.white);
      expect(s.shadowStrength, 0);
      expect(s.shadow, isFalse);
      expect(s.background.visible, isFalse);
      expect(s.tafsirMode, TafsirMode.split);
      expect(s.font, AyahFont.defaultFont);
      expect(s.reciterName, '');
    });

    test('JSON: ذهاب وإياب لكل الحقول', () {
      final s = OverlayStyle(
        tafsirMode: TafsirMode.fullUnderEachPart,
        font: AyahFont.amiriQuran,
        tafsirFont: TafsirFont.amiriQuran,
        color: OverlayTextColor.black,
        shadowStrength: 0.35,
        background: const OverlayBackground(mode: OverlayBackgroundMode.box, opacity: 0.6),
        layout: OverlayLayout.reference
            .update(OverlayElement.surahRef, (p) => p.copyWith(enabled: true))
            .update(OverlayElement.tafsir, (p) => p.copyWith(scale: 0.8)),
        reciterName: 'القارئ',
      );
      final back = OverlayStyle.fromJson(jsonDecode(jsonEncode(s.toJson())));
      expect(back, s);
      expect(back.hashCode, s.hashCode);
      // القالب بدون اسم القارئ.
      expect(s.toJson(forTemplate: true).containsKey('reciterName'), isFalse);
    });

    test('أسماء المفاتيح ثابتة (plan.json والتقارير)', () {
      final j = const OverlayStyle().toJson();
      expect(j.keys, containsAll([
        'tafsirMode', 'font', 'tafsirFont', 'color', 'shadowStrength',
        'background', 'layout', 'reciterName',
      ]));
      expect(j['shadowStrength'], 0);
      expect(j['color'], 'white');
      expect((j['layout'] as Map).keys.toSet(),
          OverlayElement.values.map((e) => e.name).toSet());
    });

    test('قديم/تالف: الحقول الناقصة بتاخد الافتراضي، وshadow:true القديم بيصير شدة', () {
      final legacy = OverlayStyle.fromJson({
        'tafsirMode': 'split', 'font': 'amiriQuran', 'color': 'black', 'shadow': true,
      });
      expect(legacy.color, OverlayTextColor.black);
      expect(legacy.font, AyahFont.amiriQuran);
      expect(legacy.shadowStrength, OverlayStyle.defaultShadowStrength);
      expect(legacy.layout.isReference, isTrue);
      expect(OverlayStyle.fromJson(null), const OverlayStyle());
      expect(OverlayStyle.fromJson({'color': 'أحمر', 'shadowStrength': 9, 'font': 7}).shadowStrength, 1.0);
      expect(OverlayStyle.fromJson({'color': 'أحمر'}).color, OverlayTextColor.white);
    });

    test('شدة الظل محصورة 0..1، والخلفية الشفافة بحد أقصى', () {
      expect(const OverlayStyle().copyWith(shadowStrength: 5).shadowStrength, 1.0);
      expect(const OverlayStyle().copyWith(shadowStrength: -1).shadowStrength, 0.0);
      expect(const OverlayBackground().copyWith(opacity: 5).opacity, OverlayBackground.maxOpacity);
      expect(const OverlayBackground().visible, isFalse);
      expect(const OverlayBackground(mode: OverlayBackgroundMode.bar, opacity: 0).visible, isFalse);
    });

    test('الظل والخلفية بلون عكس النص (أبيض/أسود بس)', () {
      expect(OverlayTextColor.white.shadow, overlayBlack);
      expect(OverlayTextColor.black.shadow, overlayWhite);
      expect(OverlayTextColor.white.backdrop, overlayBlack);
      expect(OverlayTextColor.black.backdrop, overlayWhite);
      expect(OverlayTextColor.values.length, 2);
    });
  });

  group('شدة الظل (OverlayMetrics.shadowLayers)', () {
    final m = OverlayMetrics.forSize(1080, 1920);
    double mass(OverlayMetrics m, double s) {
      // كثافة × مساحة تقريبية: مجموع (ألفا × (نعومة + 1)) لكل طبقة.
      var t = 0.0;
      for (final l in m.shadowLayers(s)) {
        t += l.alpha * (l.blur + 1);
      }
      return t;
    }

    test('0 = بدون ظل (نفس الظل المطفي)', () {
      expect(m.shadowLayers(0), isEmpty);
      expect(m.shadowLayers(-1), isEmpty);
    });

    test('بتزيد بزيادة الشدة: الكثافة والنعومة والإزاحة، مش بس الشفافية', () {
      var prev = 0.0;
      for (final s in [0.1, 0.3, 0.5, 0.7, 1.0]) {
        final k = mass(m, s);
        expect(k, greaterThan(prev), reason: 's=$s');
        prev = k;
      }
      double maxBlur(double s) =>
          m.shadowLayers(s).map((l) => l.blur).reduce((a, b) => a > b ? a : b);
      double maxAlpha(double s) =>
          m.shadowLayers(s).map((l) => l.alpha).reduce((a, b) => a > b ? a : b);
      expect(maxBlur(1.0), greaterThan(maxBlur(0.3) * 1.5));
      expect(maxAlpha(1.0), greaterThan(maxAlpha(0.3)));
      expect(m.shadowLayers(1.0).length, greaterThan(m.shadowLayers(0.3).length));
      // 100٪ أقوى بوضوح من الظل القديم (إزاحة 1/450، نعومة 2.5/450، ألفا 0.9+0.6).
      expect(mass(m, 1.0), greaterThan(mass(m, 0.3) * 2));
    });

    test('نسبي من الوحدة: نفس الشكل بكل الأبعاد والدقات', () {
      final a = OverlayMetrics.forSize(720, 1280), b = OverlayMetrics.forSize(2160, 3840);
      final la = a.shadowLayers(0.8), lb = b.shadowLayers(0.8);
      expect(lb.length, la.length);
      for (var i = 0; i < la.length; i++) {
        expect(lb[i].blur / la[i].blur, closeTo(3, 1e-9));
        expect(lb[i].dy / la[i].dy, closeTo(3, 1e-9));
        expect(lb[i].alpha, la[i].alpha);
      }
      final land = OverlayMetrics.forSize(1920, 1080);
      expect(land.shadowLayers(0.8).first.blur, closeTo(m.shadowLayers(0.8).first.blur, 1e-9));
    });

    test('أقصى مدى للظل (100٪) جوا هامش الشريط، بكل الأبعاد', () {
      for (final s in const [(720, 1280), (1080, 1920), (1920, 1080), (1080, 1080), (2160, 3840)]) {
        final mm = OverlayMetrics.forSize(s.$1, s.$2);
        expect(mm.bandMargin, greaterThan(mm.maxShadowExtent), reason: '$s');
      }
    });
  });

  group('شريط التصدير (overlayBandFor)', () {
    final m = OverlayMetrics.forSize(1080, 1920);

    test('الافتراضي: نفس شريط الكتلة (آية + تفسير) حوالين 61%..96%', () {
      final b = overlayBandFor(m);
      expect(b.top.isEven && b.height.isEven, isTrue);
      expect(b.top, lessThan(m.top));
      expect(b.bottom, greaterThan(m.bottomLimit));
      expect(b.bottom, lessThanOrEqualTo(1920));
      // مش الإطار كامل (الذاكرة).
      expect(b.height, lessThan(1920 * 0.5));
      expect(overlayBandFor(m, layout: OverlayLayout.reference), b);
    });

    test('اسم السورة فوق الآية بيوسّع الشريط لفوق بس', () {
      final l = OverlayLayout.reference
          .update(OverlayElement.surahRef, (p) => p.copyWith(enabled: true));
      final b = overlayBandFor(m, layout: l), base = overlayBandFor(m);
      expect(b.top, lessThan(base.top));
      expect(b.bottom, base.bottom);
    });

    test('عنصر مسحوب لفوق/لتحت: الشريط بيغطيه (اتحاد المستطيلات)', () {
      for (final top in [0.0, 0.1, 0.3, 0.6, 0.8, 0.95]) {
        final l = OverlayLayout.reference
            .update(OverlayElement.ayah, (p) => p.copyWith(anchor: ElementAnchor(0.5, top)));
        final b = overlayBandFor(m, layout: l);
        expect(b.top, lessThanOrEqualTo((top * 1920).floor()), reason: 'top=$top');
        // وبيضل غطاء الكتلة (التفسير بمكانه).
        expect(b.bottom, greaterThanOrEqualTo(m.bottomLimit.floor()), reason: 'top=$top');
        expect(b.top.isEven && b.height.isEven, isTrue);
        expect(b.top, greaterThanOrEqualTo(0));
        expect(b.bottom, lessThanOrEqualTo(1920));
      }
    });

    test('كل العناصر مسحوبة: الشريط بيغطي كل واحد منها ولا يطلع من الفيديو', () {
      var l = OverlayLayout.reference;
      var y = 0.0;
      for (final e in OverlayElement.values) {
        l = l.update(e, (p) => p.copyWith(enabled: true, anchor: ElementAnchor(0.4, y)));
        y += 0.17;
      }
      for (final s in const [(1080, 1920), (1920, 1080), (1080, 1080)]) {
        final mm = OverlayMetrics.forSize(s.$1, s.$2);
        final b = overlayBandFor(mm, layout: l);
        expect(b.top, 0);
        expect(b.bottom, lessThanOrEqualTo(s.$2));
        for (final r in overlayInkRanges(mm, l)) {
          expect(b.top, lessThanOrEqualTo(r.$1.floor()));
          expect(b.bottom, greaterThanOrEqualTo(r.$2.floor().clamp(0, s.$2)));
        }
      }
    });

    test('الشريط ما بيتغيّر بشدة الظل (بيغطي 100٪ دايماً)', () {
      // overlayBandFor ما بياخد شدة الظل أصلاً: مجرد تأكيد على الهامش.
      expect(m.bandMargin, greaterThanOrEqualTo(m.maxShadowExtent + m.unit * 0.03 - 1e-9));
    });
  });

  group('القوالب', () {
    test('أول قالب جاهز = المقطع المرجعي = الافتراضي بالضبط', () {
      expect(builtInTemplates.first.name, 'المقطع المرجعي');
      expect(builtInTemplates.first.style, const OverlayStyle());
      expect(builtInTemplates.every((t) => t.builtIn), isTrue);
      expect(builtInTemplates.length, greaterThanOrEqualTo(3));
      expect({for (final t in builtInTemplates) t.id}.length, builtInTemplates.length);
      expect({for (final t in builtInTemplates) t.name}.length, builtInTemplates.length);
    });

    test('القوالب الجاهزة: بتحافظ على لون النص واسم القارئ، وبتطبّق الباقي', () {
      final cur = const OverlayStyle(color: OverlayTextColor.black, reciterName: 'س');
      for (final t in builtInTemplates) {
        final r = t.applyTo(cur);
        expect(r.color, OverlayTextColor.black, reason: t.name);
        expect(r.reciterName, 'س', reason: t.name);
        expect(r.layout, t.style.layout, reason: t.name);
        expect(r.shadowStrength, t.style.shadowStrength, reason: t.name);
        expect(r.background, t.style.background, reason: t.name);
      }
      final ayahOnly = builtInTemplates.firstWhere((t) => t.id == 'builtin.ayah_only');
      expect(ayahOnly.style.layout.isEnabled(OverlayElement.tafsir), isFalse);
      final withSurah = builtInTemplates.firstWhere((t) => t.id == 'builtin.with_surah');
      expect(withSurah.style.layout.isEnabled(OverlayElement.surahRef), isTrue);
      final clear = builtInTemplates.firstWhere((t) => t.id == 'builtin.clear_shadow');
      expect(clear.style.shadowStrength, OverlayStyle.defaultShadowStrength);
    });

    test('قالب المستخدم: بيرجّع اللون ويحافظ على اسم القارئ الحالي', () {
      final t = OverlayTemplate(
          id: 'u1',
          name: 'تجربة',
          style: const OverlayStyle(color: OverlayTextColor.black, shadowStrength: 0.4));
      final r = t.applyTo(const OverlayStyle(reciterName: 'ص'));
      expect(r.color, OverlayTextColor.black);
      expect(r.shadowStrength, 0.4);
      expect(r.reciterName, 'ص');
    });

    test('حفظ/قراءة/تعديل/حذف بالملف، واسم القارئ ما بينحفظ', () async {
      final dir = Directory.systemTemp.createTempSync('ayah_tpl');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/sub/overlay_templates.json');
      final storage = TemplateStorage(file);
      var store = await TemplateStore.open(storage);
      expect(store.userTemplates, isEmpty);
      expect(store.all.length, builtInTemplates.length);

      final style = OverlayStyle(
        color: OverlayTextColor.black,
        shadowStrength: 0.9,
        reciterName: 'سر',
        layout: OverlayLayout.reference
            .update(OverlayElement.ayah, (p) => p.copyWith(anchor: const ElementAnchor(0.2, 0.3))),
      );
      final a = await store.add('  قالبي  ', style);
      final b = await store.add('', style);
      expect(a.name, 'قالبي'); // مقصوص
      expect(b.name, 'قالب'); // اسم فاضي → افتراضي
      expect(a.id, isNot(b.id));
      expect(a.style.reciterName, '');

      // جلسة جديدة: نفس القوالب بنفس الترتيب.
      store = await TemplateStore.open(storage);
      expect(store.userTemplates.map((t) => t.name), ['قالبي', 'قالب']);
      expect(store.userTemplates.first.style.color, OverlayTextColor.black);
      expect(store.userTemplates.first.style.shadowStrength, 0.9);
      expect(store.userTemplates.first.style.layout[OverlayElement.ayah].anchor,
          const ElementAnchor(0.2, 0.3));
      expect(store.all.last.id, store.userTemplates.last.id);

      await store.rename(a.id, 'اسم جديد');
      await store.updateStyle(a.id, const OverlayStyle(shadowStrength: 0.2, reciterName: 'م'));
      await store.delete(b.id);
      store = await TemplateStore.open(storage);
      expect(store.userTemplates.length, 1);
      expect(store.userTemplates.single.name, 'اسم جديد');
      expect(store.userTemplates.single.style.shadowStrength, 0.2);
      expect(store.userTemplates.single.style.reciterName, '');
      // ما في ملف مؤقت متروك.
      expect(File('${file.path}.tmp').existsSync(), isFalse);
    });

    test('ملف تالف أو ناقص: قائمة فاضية بدون انهيار', () async {
      final dir = Directory.systemTemp.createTempSync('ayah_tpl2');
      addTearDown(() => dir.deleteSync(recursive: true));
      final f = File('${dir.path}/t.json');
      f.writeAsStringSync('{ هاي مش JSON');
      expect(await TemplateStorage(f).load(), isEmpty);
      f.writeAsStringSync(jsonEncode({'templates': 5}));
      expect(await TemplateStorage(f).load(), isEmpty);
      f.writeAsStringSync(jsonEncode({
        'templates': [
          {'id': 'x', 'name': 'ماشي', 'style': {'color': 'black'}},
          {'id': 5, 'name': 'غلط'},
          {'id': 'y', 'name': '  '},
          'نص',
        ]
      }));
      final r = await TemplateStorage(f).load();
      expect(r.length, 1);
      expect(r.single.style.color, OverlayTextColor.black);
      expect(await TemplateStorage(File('${dir.path}/ما-في.json')).load(), isEmpty);
    });

    test('علم canCustomize: المجاني قوالب جاهزة بس (بدون تطبيق الحدود)', () {
      expect(EditorCapabilities.free.canCustomize, isFalse);
      expect(EditorCapabilities.full.canCustomize, isTrue);
      expect(const EditorCapabilities().canCustomize, isTrue);
    });
  });
}
