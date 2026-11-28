// إعدادات الواجهة البسيطة (الوضع الليلي/النهاري) + مكان تخزين المشاريع
// الأخيرة. ملف JSON صغير بمجلد التطبيق (بدون مكتبة خارجية).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../projects/recent_projects.dart';

class AppSettings {
  AppSettings._();

  /// الوضع الليلي (الافتراضي) أو النهاري.
  static final ValueNotifier<bool> dark = ValueNotifier<bool>(true);

  /// بيتغيّر كل ما تغيّرت قائمة المشاريع (الرئيسية والمشاريع بيسمعوه).
  static final ValueNotifier<int> projectsRevision = ValueNotifier<int>(0);

  static Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/ui_settings.json');
  }

  static Future<void> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return;
      final j = jsonDecode(await f.readAsString());
      if (j is Map && j['dark'] is bool) dark.value = j['dark'] as bool;
    } catch (_) {
      // ملف تالف: الافتراضي.
    }
  }

  static Future<void> setDark(bool v) async {
    dark.value = v;
    try {
      final f = await _file();
      await f.writeAsString(jsonEncode({'dark': v}), flush: true);
    } catch (_) {}
  }

  static RecentProjectsStore? _store;

  static Future<RecentProjectsStore> projects() async {
    final s = _store;
    if (s != null) return s;
    final dir = await getApplicationSupportDirectory();
    return _store = RecentProjectsStore(Directory('${dir.path}/projects'));
  }

  static void projectsChanged() => projectsRevision.value++;
}
