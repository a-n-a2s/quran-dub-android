// قوالب شكل النص (يوم 9، المواصفات القسم 3 و7). جزء صافي (dart:io بس للتخزين).
//
// - قوالب جاهزة ([builtInTemplates]): أولها "المقطع المرجعي" = الافتراضي.
// - قوالب المستخدم: بيحفظها محلياً (اسم، تعديل، حذف) بملف JSON
//   ([TemplateStorage]). بالخطة المجانية التخصيص = قوالب جاهزة بس
//   ([EditorCapabilities.canCustomize]؛ الحدود الفعلية يوم 16–18).
import 'dart:convert';
import 'dart:io';

import 'overlay_layout.dart';
import 'overlay_style.dart';

/// علم الصلاحيات بالمحرر (يوم 9: بدون تطبيق الحدود، يوم 16–18 بيربطه
/// بالخطة). [canCustomize] = false (الخطة المجانية): قوالب جاهزة بس، بدون
/// تخصيص (عناصر/خطوط/ألوان/سحب) وبدون حفظ قوالب.
class EditorCapabilities {
  final bool canCustomize;
  const EditorCapabilities({this.canCustomize = true});

  /// الخطة المجانية (المواصفات القسم 7).
  static const EditorCapabilities free = EditorCapabilities(canCustomize: false);
  static const EditorCapabilities full = EditorCapabilities();
}

class OverlayTemplate {
  final String id;
  final String name;
  final OverlayStyle style;
  final bool builtIn;

  const OverlayTemplate({
    required this.id,
    required this.name,
    required this.style,
    this.builtIn = false,
  });

  OverlayTemplate copyWith({String? name, OverlayStyle? style}) =>
      OverlayTemplate(
          id: id, name: name ?? this.name, style: style ?? this.style, builtIn: builtIn);

  /// الشكل الناتج لما المستخدم يطبّق القالب على [current]. اسم القارئ بيخص
  /// المشروع فبيضل. القوالب الجاهزة ما بتغيّر لون النص (أبيض/أسود بيتحدد حسب
  /// الفيديو)؛ قوالب المستخدم بترجّع اللون اللي انحفظ.
  OverlayStyle applyTo(OverlayStyle current) => builtIn
      ? style.copyWith(color: current.color, reciterName: current.reciterName)
      : style.copyWith(reciterName: current.reciterName);

  Map<String, Object?> toJson() =>
      {'id': id, 'name': name, 'style': style.toJson(forTemplate: true)};

  static OverlayTemplate? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'], name = j['name'];
    if (id is! String || name is! String || name.trim().isEmpty) return null;
    return OverlayTemplate(
        id: id, name: name, style: OverlayStyle.fromJson(j['style']));
  }
}

/// القوالب الجاهزة. الأول = المقطع المرجعي (الافتراضي بالضبط).
final List<OverlayTemplate> builtInTemplates = [
  const OverlayTemplate(
      id: 'builtin.reference',
      name: 'المقطع المرجعي',
      builtIn: true,
      style: OverlayStyle()),
  OverlayTemplate(
      id: 'builtin.ayah_only',
      name: 'آية فقط',
      builtIn: true,
      style: OverlayStyle(
          layout: OverlayLayout.reference
              .update(OverlayElement.tafsir, (p) => p.copyWith(enabled: false)))),
  OverlayTemplate(
      id: 'builtin.with_surah',
      name: 'مع اسم السورة',
      builtIn: true,
      style: OverlayStyle(
          layout: OverlayLayout.reference
              .update(OverlayElement.surahRef, (p) => p.copyWith(enabled: true)))),
  const OverlayTemplate(
      id: 'builtin.clear_shadow',
      name: 'ظل واضح',
      builtIn: true,
      style: OverlayStyle(shadowStrength: OverlayStyle.defaultShadowStrength)),
  const OverlayTemplate(
      id: 'builtin.glass_bar',
      name: 'شريط شفاف',
      builtIn: true,
      style: OverlayStyle(
          background: OverlayBackground(mode: OverlayBackgroundMode.bar, opacity: 0.45))),
  OverlayTemplate(
      id: 'builtin.big_ayah',
      name: 'آية كبيرة',
      builtIn: true,
      style: OverlayStyle(
          layout: OverlayLayout.reference
              .update(OverlayElement.ayah, (p) => p.copyWith(scale: 1.3))
              .update(OverlayElement.tafsir, (p) => p.copyWith(scale: 0.85)))),
];

/// تخزين قوالب المستخدم: ملف JSON واحد (كتابة آمنة: ملف مؤقت ثم rename). ملف
/// تالف أو مفقود = قائمة فاضية (ما بيوقّع التطبيق).
class TemplateStorage {
  final File file;
  const TemplateStorage(this.file);

  Future<List<OverlayTemplate>> load() async {
    try {
      if (!await file.exists()) return [];
      final j = jsonDecode(await file.readAsString());
      if (j is! Map || j['templates'] is! List) return [];
      return [
        for (final t in j['templates'] as List)
          if (OverlayTemplate.fromJson(t) case final tpl?) tpl,
      ];
    } catch (_) {
      return [];
    }
  }

  Future<void> save(List<OverlayTemplate> templates) async {
    final tmp = File('${file.path}.tmp');
    await file.parent.create(recursive: true);
    await tmp.writeAsString(jsonEncode({
      'version': 1,
      'templates': [for (final t in templates) t.toJson()],
    }), flush: true);
    await tmp.rename(file.path);
  }
}

/// قوالب المستخدم بالذاكرة + حفظ. كل تعديل (إضافة/تسمية/حذف/تحديث) بينحفظ.
class TemplateStore {
  final TemplateStorage? _storage;
  final List<OverlayTemplate> _user;
  int _counter = 0;

  TemplateStore._(this._storage, this._user);

  /// بدون تخزين (للاختبار والمحرر لو فشل الملف).
  factory TemplateStore.memory([List<OverlayTemplate> initial = const []]) =>
      TemplateStore._(null, [...initial]);

  static Future<TemplateStore> open(TemplateStorage storage) async =>
      TemplateStore._(storage, await storage.load());

  List<OverlayTemplate> get userTemplates => List.unmodifiable(_user);

  /// الجاهزة أول، وبعدها قوالب المستخدم.
  List<OverlayTemplate> get all => [...builtInTemplates, ..._user];

  String _newId() =>
      'user.${DateTime.now().microsecondsSinceEpoch}.${_counter++}';

  Future<OverlayTemplate> add(String name, OverlayStyle style) async {
    final t = OverlayTemplate(
        id: _newId(), name: _cleanName(name), style: _forStore(style));
    _user.add(t);
    await _persist();
    return t;
  }

  /// تحديث شكل قالب المستخدم (من الشكل الحالي بالمحرر).
  Future<void> updateStyle(String id, OverlayStyle style) async {
    final i = _user.indexWhere((t) => t.id == id);
    if (i < 0) return;
    _user[i] = _user[i].copyWith(style: _forStore(style));
    await _persist();
  }

  Future<void> rename(String id, String name) async {
    final i = _user.indexWhere((t) => t.id == id);
    if (i < 0) return;
    _user[i] = _user[i].copyWith(name: _cleanName(name));
    await _persist();
  }

  Future<void> delete(String id) async {
    _user.removeWhere((t) => t.id == id);
    await _persist();
  }

  /// اسم القارئ بيخص المشروع: ما بينحفظ بالقالب.
  OverlayStyle _forStore(OverlayStyle s) => s.copyWith(reciterName: '', segmentScales: const {});

  String _cleanName(String n) {
    final t = n.trim();
    return t.isEmpty ? 'قالب' : t;
  }

  Future<void> _persist() async {
    await _storage?.save(_user);
  }
}
