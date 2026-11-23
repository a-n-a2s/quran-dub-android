import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quran_dub/asr/asr_engine.dart';
import 'package:quran_dub/asr/asr_model_manager.dart';
import 'package:quran_dub/asr/wav_audio.dart';

/// WAV صناعي: [channels] قنوات، كل قناة نفس الموجة × (1 / رقم القناة).
Uint8List makeWav({
  required int rate,
  required int channels,
  required int bits,
  bool float = false,
  bool extensible = false,
  double freq = 440,
  double seconds = 1,
  bool unknownDataSize = false,
}) {
  final frames = (rate * seconds).round();
  final bps = bits ~/ 8;
  final dataLen = frames * channels * bps;
  final fmtLen = extensible ? 40 : 16;
  final b = BytesBuilder();
  void str(String s) => b.add(s.codeUnits);
  void u32(int v) => b.add((ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List());
  void u16(int v) => b.add((ByteData(2)..setUint16(0, v, Endian.little)).buffer.asUint8List());
  final code = float ? 3 : 1;
  str('RIFF');
  u32(4 + 8 + fmtLen + 8 + dataLen + 8 + 4);
  str('WAVE');
  str('LIST'); // chunk زيادة لازم ينتجاوز
  u32(4);
  str('INFO');
  str('fmt ');
  u32(fmtLen);
  u16(extensible ? 0xFFFE : code);
  u16(channels);
  u32(rate);
  u32(rate * channels * bps);
  u16(channels * bps);
  u16(bits);
  if (extensible) {
    u16(22);
    u16(bits);
    u32(0);
    u16(code);
    b.add(List.filled(14, 0));
  }
  str('data');
  u32(unknownDataSize ? 0xFFFFFFFF : dataLen);
  final d = ByteData(dataLen);
  var o = 0;
  for (var i = 0; i < frames; i++) {
    final v = 0.5 * math.sin(2 * math.pi * freq * i / rate);
    for (var c = 0; c < channels; c++) {
      final x = v / (c + 1);
      if (float) {
        d.setFloat32(o, x, Endian.little);
      } else if (bits == 16) {
        d.setInt16(o, (x * 32767).round(), Endian.little);
      } else if (bits == 24) {
        final s = (x * 8388607).round() & 0xFFFFFF;
        d.setUint8(o, s & 0xff);
        d.setUint8(o + 1, (s >> 8) & 0xff);
        d.setUint8(o + 2, (s >> 16) & 0xff);
      } else if (bits == 32) {
        d.setInt32(o, (x * 2147483647).round(), Endian.little);
      } else {
        d.setUint8(o, (x * 127 + 128).round());
      }
      o += bps;
    }
  }
  b.add(d.buffer.asUint8List());
  return b.toBytes();
}

double estimateFreq(Float32List x, int rate) {
  var crossings = 0;
  for (var i = 1; i < x.length; i++) {
    if ((x[i - 1] < 0) != (x[i] < 0)) crossings++;
  }
  return crossings / 2 / (x.length / rate);
}

double rms(Float32List x, {int skip = 0}) {
  var s = 0.0;
  for (var i = skip; i < x.length - skip; i++) {
    s += x[i] * x[i];
  }
  return math.sqrt(s / (x.length - 2 * skip));
}

void main() {
  group('WavAudio', () {
    test('16-bit stereo 44.1kHz → mono → 16kHz', () {
      final a = WavAudio.decode(makeWav(rate: 44100, channels: 2, bits: 16));
      expect(a.sampleRate, 44100);
      expect(a.samples.length, 44100);
      // متوسط القناتين: 0.5 و 0.25 → 0.375
      expect(rms(a.samples), closeTo(0.375 / math.sqrt2, 0.01));
      final r = WavAudio.toRate(a, 16000);
      expect(r.samples.length, 16000);
      expect(estimateFreq(r.samples, 16000), closeTo(440, 3));
      expect(rms(r.samples, skip: 200), closeTo(0.375 / math.sqrt2, 0.01));
    });

    test('24-bit، 32-bit، 8-bit، float32، extensible', () {
      for (final w in [
        makeWav(rate: 48000, channels: 1, bits: 24),
        makeWav(rate: 22050, channels: 1, bits: 32),
        makeWav(rate: 8000, channels: 1, bits: 8),
        makeWav(rate: 16000, channels: 3, bits: 32, float: true),
        makeWav(rate: 44100, channels: 2, bits: 16, extensible: true),
      ]) {
        final a = WavAudio.toRate(WavAudio.decode(w), 16000);
        expect(a.samples.length, closeTo(16000, 1));
        expect(estimateFreq(a.samples, 16000), closeTo(440, 4));
      }
    });

    test('حجم data مش معروف (0xFFFFFFFF) → لآخر الملف', () {
      final a = WavAudio.decode(
          makeWav(rate: 16000, channels: 1, bits: 16, unknownDataSize: true));
      expect(a.samples.length, 16000);
    });

    test('فلتر ضد الـ aliasing لما ننزل لـ 16kHz', () {
      // 6kHz بيضل (تحت Nyquist 8kHz)، 11kHz لازم ينشال تقريباً.
      final pass = WavAudio.toRate(
          WavAudio.decode(makeWav(rate: 44100, channels: 1, bits: 16, freq: 6000)), 16000);
      final stop = WavAudio.toRate(
          WavAudio.decode(makeWav(rate: 44100, channels: 1, bits: 16, freq: 11000)), 16000);
      expect(rms(pass.samples, skip: 200), greaterThan(0.3));
      expect(rms(stop.samples, skip: 200), lessThan(0.02));
    });

    test('مش WAV / صيغة مش مدعومة', () {
      expect(WavAudio.unsupportedReason(Uint8List.fromList('ID3\x03abcdefghijk'.codeUnits)),
          isNotNull);
      final adpcm = makeWav(rate: 16000, channels: 1, bits: 16);
      ByteData.sublistView(adpcm).setUint16(32, 2, Endian.little); // format=2 (ADPCM)
      expect(WavAudio.unsupportedReason(adpcm), isNotNull);
      expect(WavAudio.unsupportedReason(
          Uint8List.sublistView(makeWav(rate: 16000, channels: 1, bits: 16), 0, 4096)), isNull);
    });
  });

  test('charTimes: توكن لكل حرف + فاصل كلمات', () {
    final r = charTimes(
      ['ب', 'س', 'م', '▁', 'ا', 'ل', 'ل', 'ه', '<blk>'],
      [0.0, 0.04, 0.08, 0.12, 0.2, 0.24, 0.28, 0.32, 0.36],
      10,
    );
    expect(r.$1, 'بسم الله');
    expect(r.$2.length, r.$1.length);
    expect(r.$2.first, 10.0);
    expect(r.$2.last, 10.32);
    expect(charTimes(['a'], [], 0).$1, '');
  });

  test('parseSha256Sums + القيم المثبّتة بالتطبيق', () {
    final sums = parseSha256Sums(
        '58de6db034bb4f6516b3bc1c68e7a0ac4e77abffe603a550ee87b39dcd0c7ac6  model.int8.onnx\n'
        '75b53814499cee84a07c7b7a318524d30bcaf84273c0f8b28a04176023e8c74f  tokens.txt\n'
        '9e2449e1087496d8d4caba907f23e0bd3f78d91fa552479bb9c23ac09cbb1fd6  silero_vad.onnx\n');
    for (final f in AsrModelManager.files) {
      expect(sums[f.name], f.sha256);
    }
    expect(AsrModelManager.totalBytes, greaterThan(19000000));
  });
}
