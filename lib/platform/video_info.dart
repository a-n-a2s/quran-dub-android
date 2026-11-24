import 'dart:typed_data';

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

  /// إطار الفيديو بالثانية [timeUs] (ميكروثانية) مستقيم ومصغّر لـ
  /// [width]×[height]، كبكسلات RGBA (يوم 8: تجربة التصدير بالمحاكي).
  static Future<Uint8List> frameRgba(
      String path, int timeUs, int width, int height) async {
    final r = await _channel.invokeMethod<Uint8List>('frameRgba', {
      'path': path,
      'timeUs': timeUs,
      'width': width,
      'height': height,
    });
    if (r == null) throw const VideoInfoException('ما قدرنا نقرأ إطار');
    return r;
  }

  /// سطوع الفيديو بمنطقة النص (يوم 7، `FrameBrightness.kt`): (متوسط السطوع
  /// 0..1، نسبة البكسلات الفاتحة). null لو ما قدرنا نقرأ إطارات.
  static Future<({double luma, double brightFraction})?> textBandBrightness(
      VideoInfo info, String path) async {
    try {
      final r = await _channel
          .invokeMapMethod<String, Object?>('textBandBrightness', {
        'path': path,
        'durationMs': info.durationMs,
        'expectPortrait': switch (info.orientation) {
          VideoOrientation.portrait => true,
          VideoOrientation.landscape => false,
          VideoOrientation.square => null,
        },
      });
      if (r == null) return null;
      return (
        luma: (r['luma'] as num).toDouble(),
        brightFraction: (r['brightFraction'] as num).toDouble(),
      );
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}

class VideoInfoException implements Exception {
  final String message;
  const VideoInfoException(this.message);
  @override
  String toString() => 'VideoInfoException: $message';
}
