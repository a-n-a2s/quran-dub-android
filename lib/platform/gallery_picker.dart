import 'package:flutter/services.dart';

class PickedVideo {
  final String path;
  final String name;
  final int bytes;
  const PickedVideo(this.path, this.name, this.bytes);
}

/// تقدّم نسخ الفيديو المختار من المعرض (المواصفات، يوم 6: "بدون ما يتعلّق
/// التطبيق مع الفيديوهات الكبيرة").
class GalleryCopyProgress {
  final int copiedBytes;
  final int? totalBytes; // null لو الـ Uri ما بيرجّع حجمه مسبقاً.
  const GalleryCopyProgress(this.copiedBytes, this.totalBytes);
  double? get fraction =>
      totalBytes == null || totalBytes == 0 ? null : copiedBytes / totalBytes!;
}

/// اختيار فيديو من معرض الجوال (يوم 6، المواصفات القسم 2): Android Photo
/// Picker (فيديو بس، بدون صلاحيات) من `MainActivity`، ولو مش متوفر على
/// الجوال بيرجع تلقائياً لـ SAF (`ACTION_OPEN_DOCUMENT`، فيديو بس، بدون
/// صلاحيات هو كمان). النسخ من الـ Uri المختار بيصير بتقدّم.
class GalleryPicker {
  static const _channel = MethodChannel('com.ayahstudio.app/gallery');
  static const _progress = EventChannel('com.ayahstudio.app/gallery/progress');

  /// null لو المستخدم لغى.
  static Future<PickedVideo?> pickVideo({
    void Function(GalleryCopyProgress)? onProgress,
  }) async {
    final sub = onProgress == null
        ? null
        : _progress.receiveBroadcastStream().listen((event) {
            final m = event as Map<Object?, Object?>;
            onProgress(GalleryCopyProgress(
              (m['copiedBytes'] as num).toInt(),
              (m['totalBytes'] as num?)?.toInt(),
            ));
          });
    try {
      final r = await _channel.invokeMapMethod<String, Object?>('pickVideo');
      if (r == null) return null;
      return PickedVideo(
          r['path'] as String, r['name'] as String, (r['bytes'] as num).toInt());
    } finally {
      await sub?.cancel();
    }
  }
}
