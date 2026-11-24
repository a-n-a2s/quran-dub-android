/// ساعة تشغيل ناعمة للمعاينة (يوم 7). مشغّل الفيديو بيبلّغ عن الموقع كل
/// ~500ms، وهاد خشن كتير لتبديل النص بدقة (البداية عندنا بخطأ وسيط 0.03s).
/// الساعة بتستقرئ الموقع بين التبليغات حسب الوقت الحقيقي، وبتصحّح لما يوصل
/// تبليغ جديد. جزء صافي: الوقت الحقيقي ([wall]) بيجي من برا (Stopwatch).
class PlaybackClock {
  double _anchorPos = 0;
  double _anchorWall = 0;
  bool _playing = false;
  double _speed = 1;

  /// فرق أكبر منه (بالثواني) بين المتوقع والمبلّغ = قفزة (seek): بنثبّت عند
  /// المبلّغ فوراً. أصغر منه: بنقرّب تدريجياً (بدل ما النص يرجع لورا).
  final double snapThreshold;

  /// نسبة تصحيح الفرق الصغير بكل تبليغ.
  final double blend;

  PlaybackClock({this.snapThreshold = 0.2, this.blend = 0.3});

  bool get playing => _playing;

  /// تبليغ من المشغّل: [position] موقعه، [wall] الوقت الحقيقي الآن (ثواني).
  void report({
    required double position,
    required double wall,
    required bool playing,
    double speed = 1,
  }) {
    final predicted = now(wall);
    final stateChanged = playing != _playing || speed != _speed;
    if (!playing || stateChanged || (position - predicted).abs() > snapThreshold) {
      _anchorPos = position;
    } else {
      _anchorPos = predicted + (position - predicted) * blend;
    }
    _anchorWall = wall;
    _playing = playing;
    _speed = speed;
  }

  /// موقع الفيديو المقدّر بالثواني عند الوقت الحقيقي [wall].
  double now(double wall) {
    if (!_playing) return _anchorPos;
    final p = _anchorPos + (wall - _anchorWall) * _speed;
    return p < 0 ? 0 : p;
  }
}
