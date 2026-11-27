// استخراج peaks موجة الصوت من WAV مصطنع (يوم 10).
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quran_dub/asr/wav_audio.dart';
import 'package:quran_dub/editor/waveform.dart';

/// WAV صافي PCM16 mono بسيط (16-bit، قناة وحدة) من عيّنات جاهزة.
Uint8List _buildWav(List<int> samples, {int sampleRate = 8000, int channels = 1}) {
  final dataLen = samples.length * 2;
  final b = BytesBuilder();
  void u32(int v) => b.add(Uint32List.fromList([v]).buffer.asUint8List());
  void u16(int v) => b.add(Uint16List.fromList([v]).buffer.asUint8List());
  b.add('RIFF'.codeUnits);
  u32(36 + dataLen);
  b.add('WAVE'.codeUnits);
  b.add('fmt '.codeUnits);
  u32(16);
  u16(1); // PCM
  u16(channels);
  u32(sampleRate);
  u32(sampleRate * 2 * channels); // byte rate
  u16(2 * channels); // block align
  u16(16); // bits per sample
  b.add('data'.codeUnits);
  u32(dataLen);
  for (final s in samples) {
    u16(s & 0xFFFF);
  }
  return b.toBytes();
}

void main() {
  group('extractPeaks (MonoAudio)', () {
    test('فاضي أو sampleRate صفري → فاضي بدون انهيار', () {
      expect(extractPeaks(MonoAudio(Float32List(0), 16000)).peaks,
          isEmpty);
      expect(
          extractPeaks(MonoAudio(Float32List.fromList([0.1, 0.2]), 0)).peaks,
          isEmpty);
    });

    test('جزء واحد هادئ وجزء واحد عالي: أعلى شدة مطلقة بكل جزء', () {
      final samples = Float32List.fromList([
        0.01, -0.02, 0.01, 0.0, // جزء 1: هادئ
        0.9, -0.95, 0.3, -0.1, // جزء 2: عالي (0.95 الأعلى)
      ]);
      // 4 عيّنات/جزء، sampleRate=8 → bucketsPerSecond=2 يعطي bucketSize=4.
      final r = extractPeaks(MonoAudio(samples, 8), bucketsPerSecond: 2);
      expect(r.peaks.length, 2);
      expect(r.peaks[0], closeTo(0.02, 1e-6));
      expect(r.peaks[1], closeTo(0.95, 1e-6));
      expect(r.durationSeconds, closeTo(1.0, 1e-9));
    });

    test('at(t) بترجع أقرب جزء', () {
      final r = WaveformPeaks([0.1, 0.8, 0.3], 0.5, 1.5);
      expect(r.at(0.0), 0.1);
      expect(r.at(0.6), 0.8);
      expect(r.at(1.4), 0.3);
      expect(r.at(100), 0.3); // برا الحدود: آخر جزء
    });

    test('قيم خارج -1..1 (خطأ نظري) بتنقص لـ 1', () {
      final r = extractPeaks(
          MonoAudio(Float32List.fromList([1.5, -2.0]), 2),
          bucketsPerSecond: 1);
      expect(r.peaks.single, 1.0);
    });
  });

  group('WavAudio.decode + extractPeaks (ملف WAV مصطنع كامل)', () {
    test('موجة sine بسيطة: peaks بين 0 و1 وبعدد منطقي', () {
      const sampleRate = 8000;
      const seconds = 2;
      final n = sampleRate * seconds;
      final samples = List<int>.generate(n, (i) {
        final t = i / sampleRate;
        final v = (16000 * (i % 50 < 25 ? 1 : -1) * (t < 1 ? 1 : 0.2)).round();
        return v.clamp(-32768, 32767);
      });
      final bytes = _buildWav(samples, sampleRate: sampleRate);
      expect(WavAudio.looksLikeWav(bytes), isTrue);
      final audio = WavAudio.decode(bytes);
      expect(audio.sampleRate, sampleRate);
      expect(audio.samples.length, n);
      final peaks = extractPeaks(audio, bucketsPerSecond: 10);
      expect(peaks.peaks.length, closeTo(20, 1)); // ~10/ثانية لمدة ثانيتين
      expect(peaks.peaks.every((p) => p >= 0 && p <= 1), isTrue);
      // النص الأول أعلى شدة (±1 بالكامل) من النص الثاني (×0.2).
      final firstHalfMax = peaks.peaks.take(10).reduce((a, b) => a > b ? a : b);
      final secondHalfMax = peaks.peaks.skip(10).reduce((a, b) => a > b ? a : b);
      expect(firstHalfMax, greaterThan(secondHalfMax));
    });
  });

  group('extractPeaksPcm16Streaming (الطريق السريع بالقطع، بدون تحميل الملف كامل)', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('ayah_wave'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('نفس نتيجة الفك الكامل (mono)، وطول الملف صح', () {
      const sr = 8000;
      final samples = [
        for (var i = 0; i < sr * 3; i++) ((i % 40 < 20 ? 1 : -1) * (i < sr ? 3000 : 20000)),
      ];
      final f = File('${dir.path}/m.wav')..writeAsBytesSync(_buildWav(samples, sampleRate: sr));
      final fast = extractPeaksPcm16Streaming(f.path, bucketsPerSecond: 10)!;
      final full = extractPeaks(WavAudio.decode(f.readAsBytesSync()), bucketsPerSecond: 10);
      expect(fast.peaks.length, full.peaks.length);
      for (var i = 0; i < fast.peaks.length; i++) {
        expect(fast.peaks[i], closeTo(full.peaks[i], 1e-4));
      }
      expect(fast.durationSeconds, closeTo(3, 1e-9));
      expect(fast.at(0.5), lessThan(fast.at(2.0)));
    });

    test('ستيريو: متوسط القنوات (زي WavAudio.decode)', () {
      const sr = 4000;
      // قناة يسار 10000 ويمين 0 → المتوسط 5000.
      final inter = <int>[for (var i = 0; i < sr; i++) ...[10000, 0]];
      final f = File('${dir.path}/s.wav')
        ..writeAsBytesSync(_buildWav(inter, sampleRate: sr, channels: 2));
      final fast = extractPeaksPcm16Streaming(f.path, bucketsPerSecond: 4)!;
      expect(fast.peaks, hasLength(4));
      for (final p in fast.peaks) {
        expect(p, closeTo(5000 / 32768, 1e-4));
      }
    });

    test('مش WAV أو مش 16-bit = null (بيرجع للطريق الكامل)', () {
      final f = File('${dir.path}/x.wav')..writeAsBytesSync([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13]);
      expect(extractPeaksPcm16Streaming(f.path), isNull);
    });

    test('extractPeaksFromWavFile بـ isolate', () async {
      final f = File('${dir.path}/i.wav')
        ..writeAsBytesSync(_buildWav(List.filled(16000, 8000), sampleRate: 8000));
      final p = await extractPeaksFromWavFile(f.path, bucketsPerSecond: 20);
      expect(p.peaks, hasLength(40));
      expect(p.peaks.first, closeTo(8000 / 32768, 1e-4));
    });
  });
}
