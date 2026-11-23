import 'package:flutter/services.dart';

import '../pipeline/project_input.dart';

/// معلومات الفيديو من Kotlin (`VideoInfoReader.kt`، يوم 6): العرض/الارتفاع
/// الخام، الدوران، المدة، fps، وفي مسار صوت. حساب الأبعاد بعد الدوران نفسه
/// بـ [VideoInfo] (جزء صافي مختبر بالاختبارات).
class VideoInfoReader {
  static const _channel = MethodChannel('com.ayahstudio.app/video');

  static Future<VideoInfo> read(String path) async {
    final r =
        await _channel.invokeMapMethod<String, Object?>('getInfo', {'path': path});
    if (r == null) throw const VideoInfoException('ما قدرنا نقرأ معلومات الفيديو');
    return VideoInfo.fromJson({
      'width': r['width'],
      'height': r['height'],
      'rotation': r['rotation'],
      'durationMs': r['durationMs'],
      'fps': r['fps'],
      'hasAudioTrack': r['hasAudioTrack'],
    });
  }
}

class VideoInfoException implements Exception {
  final String message;
  const VideoInfoException(this.message);
  @override
  String toString() => 'VideoInfoException: $message';
}
