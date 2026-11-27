// موجة الصوت بالخط الزمني (يوم 10): استخراج "peaks" (أعلى شدة بكل جزء زمني
// صغير) من نفس ملف الـ WAV اللي خط الأنابيب بيفكّه (`NativeAudioDecoder`)،
// باستعمال نفس قارئ الـ WAV الصافي ([WavAudio], يوم 4). الاستخراج نفسه جزء
// صافي بيتجرب بالاختبارات مباشرة على WAV مصطنع، وبالتطبيق بيشتغل بـ isolate
// (`extractPeaksFromWavFile`) عشان ملف طويل ما يجمّد الواجهة.
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

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
  final streamed = extractPeaksPcm16Streaming(req.path,
      bucketsPerSecond: req.bucketsPerSecond);
  if (streamed != null) return streamed;
  final bytes = File(req.path).readAsBytesSync();
  final audio = WavAudio.decode(bytes);
  return extractPeaks(audio, bucketsPerSecond: req.bucketsPerSecond);
}

/// طريق سريع للـ WAV اللي بيطلّعه `NativeAudioDecoder` (PCM 16-bit، أي عدد
/// قنوات): قراءة بقطع 1MB بدل ما نحمّل الملف كامل بالذاكرة (فيديو 10 دقائق
/// بـ 48kHz = ~58MB WAV + ~115MB عيّنات float لو فكّيناه كامل). الشدة = أعلى
/// قيمة مطلقة لمتوسط القنوات (نفس [WavAudio.decode] اللي بيدمج القنوات
/// بالمتوسط). أي صيغة ثانية (float، 24-bit…) → null والمتصل بيرجع للطريق
/// الكامل.
WaveformPeaks? extractPeaksPcm16Streaming(String path,
    {double bucketsPerSecond = 20}) {
  final raf = File(path).openSync();
  try {
    final head = raf.readSync(12);
    if (head.length < 12 ||
        String.fromCharCodes(head.sublist(0, 4)) != 'RIFF' ||
        String.fromCharCodes(head.sublist(8, 12)) != 'WAVE') {
      return null;
    }
    int? channels, rate, bits, format;
    var pos = 12;
    final len = raf.lengthSync();
    while (pos + 8 <= len) {
      raf.setPositionSync(pos);
      final ch = raf.readSync(8);
      if (ch.length < 8) return null;
      final id = String.fromCharCodes(ch.sublist(0, 4));
      final size = ByteData.sublistView(ch).getUint32(4, Endian.little);
      final body = pos + 8;
      if (id == 'fmt ') {
        final f = raf.readSync(16);
        if (f.length < 16) return null;
        final bd = ByteData.sublistView(f);
        format = bd.getUint16(0, Endian.little);
        channels = bd.getUint16(2, Endian.little);
        rate = bd.getUint32(4, Endian.little);
        bits = bd.getUint16(14, Endian.little);
      } else if (id == 'data') {
        // 1 = PCM، 0xFFFE = extensible (غالباً PCM): بس 16-bit.
        if (channels == null || rate == null || bits != 16 || rate <= 0 ||
            channels <= 0 || (format != 1 && format != 0xFFFE)) {
          return null;
        }
        final dataLen = math.min(size, len - body);
        return _peaksFromPcm16(raf, body, dataLen, channels, rate, bucketsPerSecond);
      }
      pos = body + size + (size.isOdd ? 1 : 0);
    }
    return null;
  } catch (_) {
    return null;
  } finally {
    raf.closeSync();
  }
}

WaveformPeaks _peaksFromPcm16(RandomAccessFile raf, int start, int dataLen,
    int channels, int rate, double bucketsPerSecond) {
  if (bucketsPerSecond <= 0) return WaveformPeaks.empty;
  final frameBytes = 2 * channels;
  final frames = dataLen ~/ frameBytes;
  if (frames == 0) return WaveformPeaks.empty;
  final bucketSeconds = 1 / bucketsPerSecond;
  final bucketFrames = math.max(1, (rate * bucketSeconds).round());
  final peaks = List<double>.filled((frames / bucketFrames).ceil(), 0.0);
  raf.setPositionSync(start);
  const chunkFrames = 1 << 18;
  var frame = 0;
  while (frame < frames) {
    final n = math.min(chunkFrames, frames - frame);
    final bytes = raf.readSync(n * frameBytes);
    final got = bytes.length ~/ frameBytes;
    if (got == 0) break;
    final bd = ByteData.sublistView(bytes);
    for (var i = 0; i < got; i++) {
      var sum = 0;
      for (var c = 0; c < channels; c++) {
        sum += bd.getInt16((i * channels + c) * 2, Endian.little);
      }
      final v = (sum / channels).abs() / 32768.0;
      final b = (frame + i) ~/ bucketFrames;
      if (v > peaks[b]) peaks[b] = v > 1 ? 1.0 : v;
    }
    frame += got;
  }
  return WaveformPeaks(peaks, bucketSeconds, frames / rate);
}

/// نفس [extractPeaks] بس من مسار ملف WAV، وبـ isolate منفصل (ملف طويل —
/// عشرات الثواني — ما بيجمّد الواجهة وقت القراءة والاستخراج).
Future<WaveformPeaks> extractPeaksFromWavFile(String wavPath,
        {double bucketsPerSecond = 20}) =>
    Isolate.run(() => _extractInIsolate(_PeakRequest(wavPath, bucketsPerSecond)));
