import 'package:flutter/services.dart';

class PickedMedia {
  final String path;
  final String name;
  final int bytes;
  const PickedMedia(this.path, this.name, this.bytes);
}

/// اختيار ملف صوت أو فيديو من الجوال (يوم 5، للتجربة). Storage Access
/// Framework بالـ Kotlin (MainActivity)، بدون مكتبة خارجية ولا صلاحيات.
/// الملف بينسخ لـ cache التطبيق. يوم 6: المعرض والكاميرا.
class MediaPicker {
  static const _channel = MethodChannel('com.ayahstudio.app/picker');

  /// null لو المستخدم لغى.
  static Future<PickedMedia?> pick() async {
    final r = await _channel.invokeMapMethod<String, Object?>('pickMedia');
    if (r == null) return null;
    return PickedMedia(
        r['path'] as String, r['name'] as String, (r['bytes'] as num).toInt());
  }
}
