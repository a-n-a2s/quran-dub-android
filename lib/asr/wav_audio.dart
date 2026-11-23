import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// صوت mono بقيم float بين -1 و 1.
class MonoAudio {
  final Float32List samples;
  final int sampleRate;
  const MonoAudio(this.samples, this.sampleRate);
  double get seconds => samples.length / sampleRate;
}

class UnsupportedAudioException implements Exception {
  final String message;
  const UnsupportedAudioException(this.message);
  @override
  String toString() => 'UnsupportedAudioException: $message';
}

/// قارئ WAV بـ Dart صافي (أي sample rate وأي عدد قنوات):
/// PCM 8/16/24/32-bit، float 32/64، و WAVE_FORMAT_EXTENSIBLE.
/// القنوات بتنخلط لقناة وحدة (متوسط).
///
/// باقي الصيغ (mp3، m4a/aac، ogg، opus، flac، والفيديو) بتنفك على الجوال
/// بـ MediaCodec (`NativeAudioDecoder`) لـ WAV أولاً.
class WavAudio {
  static const targetRate = 16000;

  static bool looksLikeWav(Uint8List b) =>
      b.length >= 12 &&
      String.fromCharCodes(b, 0, 4) == 'RIFF' &&
      String.fromCharCodes(b, 8, 12) == 'WAVE';

  /// لو أول جزء من الملف (يكفي ~64KB) WAV بصيغة بنقدر نقرأها → null،
  /// وإلا السبب.
  static String? unsupportedReason(Uint8List head) {
    try {
      _header(head);
      return null;
    } on UnsupportedAudioException catch (e) {
      return e.message;
    }
  }

  static MonoAudio decode(Uint8List bytes) {
    final h = _header(bytes);
    final bd = ByteData.sublistView(bytes);
    final channels = h.channels, bits = h.bits, isFloat = h.isFloat;
    final bytesPer = bits ~/ 8;
    final dataStart = h.dataStart, dataLen = h.dataLen;
    final frameBytes = bytesPer * channels;
    final frames = dataLen ~/ frameBytes;
    final out = Float32List(frames);
    var o = dataStart;
    for (var i = 0; i < frames; i++) {
      var sum = 0.0;
      for (var c = 0; c < channels; c++) {
        sum += _sample(bd, o, bits, isFloat);
        o += bytesPer;
      }
      out[i] = sum / channels;
    }
    return MonoAudio(out, h.rate);
  }

  static _WavHeader _header(Uint8List bytes) {
    if (!looksLikeWav(bytes)) {
      throw const UnsupportedAudioException('مش ملف WAV (RIFF/WAVE)');
    }
    final bd = ByteData.sublistView(bytes);
    int? format, channels, rate, bits;
    int? dataStart, dataLen;
    var p = 12;
    while (p + 8 <= bytes.length) {
      final id = String.fromCharCodes(bytes, p, p + 4);
      var size = bd.getUint32(p + 4, Endian.little);
      final body = p + 8;
      if (id == 'fmt ') {
        if (body + 16 > bytes.length) break;
        format = bd.getUint16(body, Endian.little);
        channels = bd.getUint16(body + 2, Endian.little);
        rate = bd.getUint32(body + 4, Endian.little);
        bits = bd.getUint16(body + 14, Endian.little);
        if (format == 0xFFFE && size >= 40 && body + 26 <= bytes.length) {
          format = bd.getUint16(body + 24, Endian.little); // SubFormat GUID
        }
      } else if (id == 'data') {
        dataStart = body;
        // حجم 0xFFFFFFFF أو أكبر من الملف (تسجيل انقطع/stream) → لآخر الملف.
        if (size == 0xFFFFFFFF || body + size > bytes.length) {
          size = bytes.length - body;
        }
        dataLen = size;
        break;
      }
      p = body + size + (size & 1);
    }
    if (format == null || channels == null || rate == null || bits == null) {
      throw const UnsupportedAudioException('WAV بدون fmt');
    }
    if (dataStart == null || dataLen == null) {
      throw const UnsupportedAudioException('WAV بدون data');
    }
    if (channels < 1 || rate < 1000) {
      throw UnsupportedAudioException('WAV غريب: $channels قناة، $rate Hz');
    }
    final isFloat = format == 3;
    if (!(format == 1 && (bits == 8 || bits == 16 || bits == 24 || bits == 32)) &&
        !(isFloat && (bits == 32 || bits == 64))) {
      throw UnsupportedAudioException('صيغة WAV مش مدعومة: format=$format bits=$bits');
    }
    return _WavHeader(channels, rate, bits, isFloat, dataStart, dataLen);
  }

  static double _sample(ByteData bd, int o, int bits, bool isFloat) {
    if (isFloat) {
      return bits == 32
          ? bd.getFloat32(o, Endian.little)
          : bd.getFloat64(o, Endian.little);
    }
    switch (bits) {
      case 8:
        return (bd.getUint8(o) - 128) / 128.0;
      case 16:
        return bd.getInt16(o, Endian.little) / 32768.0;
      case 24:
        var v = bd.getUint8(o) | (bd.getUint8(o + 1) << 8) | (bd.getUint8(o + 2) << 16);
        if (v & 0x800000 != 0) v -= 0x1000000;
        return v / 8388608.0;
      default:
        return bd.getInt32(o, Endian.little) / 2147483648.0;
    }
  }

  /// يقرأ ملف WAV ويحوّله لـ 16kHz mono (الصيغة اللي بيحتاجها المحرك والـ VAD).
  static MonoAudio load16kMono(String path) =>
      toRate(decode(File(path).readAsBytesSync()), targetRate);

  static MonoAudio toRate(MonoAudio a, int rate) => a.sampleRate == rate
      ? a
      : MonoAudio(resample(a.samples, a.sampleRate, rate), rate);
}

/// تحويل sample rate بـ windowed-sinc (نافذة Hann، 16 zero-crossing)، مع
/// فلتر low-pass تلقائي لما ننزل بالتردد (عشان ما يصير aliasing). الـ kernel
/// محسوب مسبقاً بجدول (256 نقطة لكل عيّنة) فبيكون سريع.
Float32List resample(Float32List x, int inRate, int outRate) {
  if (inRate == outRate || x.isEmpty) return Float32List.fromList(x);
  final ratio = outRate / inRate;
  final fc = 0.95 * math.min(1.0, ratio); // من Nyquist الإدخال
  const zeros = 16;
  final half = zeros / fc; // نص عرض الـ kernel بعيّنات الإدخال
  const res = 256;
  final tableLen = (half * res).ceil() + 2;
  final table = Float64List(tableLen);
  for (var i = 0; i < tableLen; i++) {
    final d = i / res;
    if (d >= half) break;
    final xx = math.pi * fc * d;
    final sinc = d == 0 ? 1.0 : math.sin(xx) / xx;
    final w = 0.5 * (1 + math.cos(math.pi * d / half));
    table[i] = fc * sinc * w;
  }
  final n = (x.length * ratio).floor();
  final y = Float32List(n);
  final step = 1 / ratio;
  final last = x.length - 1;
  for (var j = 0; j < n; j++) {
    final t = j * step;
    var k0 = (t - half).ceil();
    var k1 = (t + half).floor();
    if (k0 < 0) k0 = 0;
    if (k1 > last) k1 = last;
    var acc = 0.0, wsum = 0.0;
    for (var k = k0; k <= k1; k++) {
      final pos = (t - k).abs() * res;
      final i = pos.floor();
      final frac = pos - i;
      final h = table[i] + (table[i + 1] - table[i]) * frac;
      acc += x[k] * h;
      wsum += h;
    }
    // التطبيع بيصلّح كسب الـ DC (وأطراف الملف).
    y[j] = wsum.abs() > 1e-9 ? acc / wsum : 0.0;
  }
  return y;
}

class _WavHeader {
  final int channels, rate, bits;
  final bool isFloat;
  final int dataStart, dataLen;
  const _WavHeader(this.channels, this.rate, this.bits, this.isFloat,
      this.dataStart, this.dataLen);
}
