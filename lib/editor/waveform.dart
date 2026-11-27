// موجة الصوت بالخط الزمني (يوم 10): استخراج "peaks" (أعلى شدة بكل جزء زمني
// صغير) من نفس ملف الـ WAV اللي خط الأنابيب بيفكّه (`NativeAudioDecoder`)،
// باستعمال نفس قارئ الـ WAV الصافي ([WavAudio], يوم 4). الاستخراج نفسه جزء
// صافي بيتجرب بالاختبارات مباشرة على WAV مصطنع، وبالتطبيق بيشتغل بـ isolate
// (`extractPeaksFromWavFile`) عشان ملف طويل ما يجمّد الواجهة.
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import '../asr/wav_audio.dart';

class WaveformPeaks {
  /// أعلى شدة مطلقة (0..1) بكل جزء، بالترتيب من بداية الملف.
  final List<double> peaks;
  final double bucketSeconds;
  final double durationSeconds;

  const WaveformPeaks(this.peaks, this.bucketSeconds, this.durationSeconds);

  static const empty = WaveformPeaks([], 1, 0);

  /// الشدة بثانية [t] (أقرب جزء).
  double at(double t) {
    if (peaks.isEmpty || bucketSeconds <= 0) return 0;
    final i = (t / bucketSeconds).floor().clamp(0, peaks.length - 1);
    return peaks[i];
  }
}

/// استخراج الـ peaks من صوت [audio] (نفس [MonoAudio] اللي [WavAudio.decode]
/// بيطلّعه): كل جزء طوله `1/bucketsPerSecond` ثانية بياخد أعلى شدة مطلقة
/// فيه (0..1، القيم مقصوصة لأنه PCM طبّع أصلاً بين -1 و1).
WaveformPeaks extractPeaks(MonoAudio audio, {double bucketsPerSecond = 20}) {
  final sampleRate = audio.sampleRate;
  final total = audio.samples.length;
  if (sampleRate <= 0 || total == 0 || bucketsPerSecond <= 0) {
    return const WaveformPeaks([], 1, 0);
  }
  final bucketSeconds = 1 / bucketsPerSecond;
  final bucketSize = math.max(1, (sampleRate * bucketSeconds).round());
  final bucketCount = (total / bucketSize).ceil();
  final peaks = List<double>.filled(bucketCount, 0.0);
  for (var b = 0; b < bucketCount; b++) {
    final from = b * bucketSize;
    final to = math.min(total, from + bucketSize);
    var peak = 0.0;
    for (var i = from; i < to; i++) {
      final v = audio.samples[i].abs();
      if (v > peak) peak = v;
    }
    peaks[b] = peak.clamp(0.0, 1.0).toDouble();
  }
  return WaveformPeaks(peaks, bucketSeconds, total / sampleRate);
}

class _PeakRequest {
  final String path;
  final double bucketsPerSecond;
  const _PeakRequest(this.path, this.bucketsPerSecond);
}

WaveformPeaks _extractInIsolate(_PeakRequest req) {
  final bytes = File(req.path).readAsBytesSync();
  final audio = WavAudio.decode(bytes);
  return extractPeaks(audio, bucketsPerSecond: req.bucketsPerSecond);
}

/// نفس [extractPeaks] بس من مسار ملف WAV، وبـ isolate منفصل (ملف طويل —
/// عشرات الثواني — ما بيجمّد الواجهة وقت القراءة والاستخراج).
Future<WaveformPeaks> extractPeaksFromWavFile(String wavPath,
        {double bucketsPerSecond = 20}) =>
    Isolate.run(() => _extractInIsolate(_PeakRequest(wavPath, bucketsPerSecond)));
