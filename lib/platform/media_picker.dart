import 'package:flutter/services.dart';

class PickedMedia {
  final String path;
  final String name;
  final int bytes;
  const PickedMedia(this.path, this.name, this.bytes);
}

/// اختيار ملف صوت أو فيديو من الجوال (يوم 5، للتجربة؛ يوم 6: نفسه لاختيار
/// ملف تلاوة منفصل بيتركّب على الفيديو، المواصفات القسم 2). Storage Access
/// Framework بالـ Kotlin (MainActivity)، بدون مكتبة خارجية ولا صلاحيات.
/// الملف بينسخ لـ cache التطبيق. (اختيار الفيديو نفسه من المعرض صار له
/// طريق مخصص بـ `gallery_picker.dart` — Photo Picker + تقدّم نسخ.)
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
