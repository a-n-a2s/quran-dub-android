import 'package:flutter/services.dart';

class RecordedVideo {
  final String path;
  final String name;
  final int bytes;
  const RecordedVideo(this.path, this.name, this.bytes);
}

class CameraPermissionStatus {
  final bool camera;
  final bool audio;
  const CameraPermissionStatus(this.camera, this.audio);
  bool get granted => camera && audio;
}

class CameraPermissionDeniedException implements Exception {
  const CameraPermissionDeniedException();
  @override
  String toString() =>
      'لازم صلاحية الكاميرا والمايكروفون عشان تصوّر مقطع من جوا التطبيق.';
}

class NoCameraAppException implements Exception {
  const NoCameraAppException();
  @override
  String toString() => 'ما في تطبيق كاميرا على الجوال.';
}

/// تصوير فيديو (مع صوت) من جوا التطبيق (يوم 6، المواصفات القسم 2): intent
/// الكاميرا (`ACTION_VIDEO_CAPTURE`) عبر `MainActivity`، بصلاحيات CAMERA
/// وRECORD_AUDIO المطلوبة وقت الحاجة بس (مش عند فتح التطبيق).
class CameraRecorder {
  static const _channel = MethodChannel('com.ayahstudio.app/camera');

  static Future<CameraPermissionStatus> checkPermissions() async {
    final r = await _channel.invokeMapMethod<String, Object?>('checkPermissions');
    return CameraPermissionStatus(r?['camera'] as bool? ?? false, r?['audio'] as bool? ?? false);
  }

  /// بيطلب الصلاحيات الناقصة بس (ما بيطلب شي لو موجودة أصلاً).
  static Future<CameraPermissionStatus> requestPermissions() async {
    final r = await _channel.invokeMapMethod<String, Object?>('requestPermissions');
    return CameraPermissionStatus(r?['camera'] as bool? ?? false, r?['audio'] as bool? ?? false);
  }

  /// بيطلب الصلاحيات أول لو ناقصة، وبعدين بيفتح الكاميرا. null لو المستخدم
  /// لغى التصوير. بيرمي [CameraPermissionDeniedException] لو انرفضت الصلاحية
  /// أو [NoCameraAppException] لو ما في تطبيق كاميرا.
  static Future<RecordedVideo?> recordVideo() async {
    var status = await checkPermissions();
    if (!status.granted) status = await requestPermissions();
    if (!status.granted) throw const CameraPermissionDeniedException();
    try {
      final r = await _channel.invokeMapMethod<String, Object?>('recordVideo');
      if (r == null) return null;
      return RecordedVideo(
          r['path'] as String, r['name'] as String, (r['bytes'] as num).toInt());
    } on PlatformException catch (e) {
      if (e.code == 'PERMISSION_DENIED') throw const CameraPermissionDeniedException();
      if (e.code == 'NO_CAMERA_APP') throw const NoCameraAppException();
      rethrow;
    }
  }
}
