import 'dart:io';

import 'package:flutter/services.dart';

import 'wav_audio.dart';

class NativeDecodeResult {
  final String wavPath;
  final int sampleRate;
  final int channels;
  final int frames;
  final String mime;
  final int elapsedMs;

  /// وقت كل جزء بالفك (يوم 6، لقياس أين الوقت عم بيروح — شوف
  /// `AudioDecoder.kt`). المجموع تقريباً = [elapsedMs].
  final int extractorMs;
  final int decodeMs;
  final int writeMs;

  const NativeDecodeResult(this.wavPath, this.sampleRate, this.channels,
      this.frames, this.mime, this.elapsedMs,
      {this.extractorMs = 0, this.decodeMs = 0, this.writeMs = 0});
  double get seconds => sampleRate == 0 ? 0 : frames / sampleRate;

  /// ثانية فك لكل دقيقة صوت (الهدف يوم 6: أقل من 2).
  double get secondsPerMinuteOfAudio =>
      seconds == 0 ? 0 : (elapsedMs / 1000) / (seconds / 60);
}

/// فك أي ملف صوت أو فيديو على الجوال (MediaExtractor + MediaCodec بالـ
/// Kotlin، `AudioDecoder.kt`) لـ WAV PCM16 mono بنفس الـ sample rate.
class NativeAudioDecoder {
  static const _channel = MethodChannel('com.ayahstudio.app/audio');

  static Future<NativeDecodeResult> decodeToMonoWav(
      String input, String output) async {
    final r = await _channel.invokeMapMethod<String, Object?>(
        'decodeToMonoWav', {'input': input, 'output': output});
    if (r == null) throw const UnsupportedAudioException('فك الصوت ما رجّع نتيجة');
    return NativeDecodeResult(
      output,
      r['sampleRate'] as int,
      r['channels'] as int,
      r['frames'] as int,
      r['mime'] as String,
      r['elapsedMs'] as int,
      extractorMs: (r['extractorMs'] as int?) ?? 0,
      decodeMs: (r['decodeMs'] as int?) ?? 0,
      writeMs: (r['writeMs'] as int?) ?? 0,
    );
  }

  /// أي ملف → مسار WAV جاهز لـ `AsrEngine.transcribeWavFile`. لو الملف WAV
  /// بصيغة بيقرأها Dart بيرجع نفسه (أسرع)، وإلا بيفكّه لـ [tempDir].
  static Future<String> ensureWav(String input, Directory tempDir) async {
    final raf = await File(input).open();
    try {
      final head = await raf.read(64 * 1024);
      // WAV بصيغة بيقرأها Dart → نفسه. غير هيك (mp3، m4a، فيديو، أو WAV
      // مضغوط زي ADPCM) → فك أصلي.
      if (WavAudio.unsupportedReason(head) == null) return input;
    } finally {
      await raf.close();
    }
    await tempDir.create(recursive: true);
    final out = '${tempDir.path}/decoded_${DateTime.now().millisecondsSinceEpoch}.wav';
    await decodeToMonoWav(input, out);
    return out;
  }
}
