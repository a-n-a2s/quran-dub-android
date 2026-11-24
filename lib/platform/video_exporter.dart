import 'dart:async';

import 'package:flutter/services.dart';

import '../export/export_status.dart';

/// قناة التصدير مع الـ Kotlin (`ExportService.kt` + `MainActivity.kt`، يوم 8).
class VideoExporter {
  static const _channel = MethodChannel('com.ayahstudio.app/export');
  static const _events = EventChannel('com.ayahstudio.app/export/status');

  static Stream<ExportStatus>? _stream;

  /// حالة التصدير (بتبعت الحالة الحالية أول ما تشترك، وبعدين كل تغيير).
  static Stream<ExportStatus> get statusStream => _stream ??= _events
      .receiveBroadcastStream()
      .map((e) => ExportStatus.fromMap(e as Map<Object?, Object?>))
      .asBroadcastStream();

  static Future<ExportStatus> status() async {
    final m = await _channel.invokeMapMethod<Object?, Object?>('getStatus');
    return m == null ? ExportStatus.idle : ExportStatus.fromMap(m);
  }

  /// بيشغّل خدمة التصدير بالخلفية على خطة [planPath] (JSON).
  static Future<void> start(String planPath) =>
      _channel.invokeMethod('start', {'plan': planPath});

  /// خطوة بسجل التشخيص (بيضل بعد الانهيار؛ `START` بيمسح القديم).
  static Future<void> trace(String line) async {
    try {
      await _channel.invokeMethod('trace', {'line': line});
    } catch (_) {}
  }

  /// تقرير آخر انهيار/خروج غير طبيعي (null لو ما في).
  static Future<String?> crashReport() async {
    try {
      return await _channel.invokeMethod<String>('crashReport');
    } catch (_) {
      return null;
    }
  }

  static Future<void> clearCrashReport() async {
    try {
      await _channel.invokeMethod('clearCrashReport');
    } catch (_) {}
  }

  static Future<void> cancel() => _channel.invokeMethod('cancel');

  /// قائمة المشاركة تبع الجوال (واتساب، انستغرام، تيك توك، يوتيوب...).
  static Future<void> share() => _channel.invokeMethod('share');

  /// فتح الفيديو بتطبيق المعرض/المشغّل.
  static Future<void> open() => _channel.invokeMethod('open');

  /// إعادة الحفظ بالمعرض (لو ما انحفظ أول مرة).
  static Future<bool> saveToGallery() async =>
      (await _channel.invokeMethod<bool>('saveToGallery')) ?? false;

  /// أندرويد 13+: صلاحية الإشعارات، وقت الضغط على "تصدير" بس.
  static Future<bool> requestNotificationPermission() async {
    try {
      return (await _channel.invokeMethod<bool>('requestNotificationPermission')) ??
          false;
    } on PlatformException {
      return false;
    }
  }

  /// أندرويد 7–9 بس: صلاحية التخزين للحفظ بالمعرض (10+ ما بدها).
  static Future<bool> requestStoragePermission() async {
    try {
      return (await _channel.invokeMethod<bool>('requestStoragePermission')) ??
          false;
    } on PlatformException {
      return false;
    }
  }

  static Future<int> freeBytes(String path) async =>
      (await _channel.invokeMethod<int>('freeBytes', {'path': path})) ?? -1;
}
