import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as so;

import 'asr_model_manager.dart';
import 'wav_audio.dart';

/// مقطع كلام واحد (من VAD) بعد التعرف عليه.
class AsrSegment {
  /// بالثواني من بداية الملف.
  final double start;
  final double end;

  /// النص حرف حرف (بنفس ترتيب [charTimes]): ناتج النموذج حروف عربية بدون
  /// تشكيل + مسافة بين الكلمات.
  final String text;

  /// توقيت كل حرف بـ [text] (ثواني من بداية الملف).
  final List<double> charTimes;

  /// الناتج الخام من sherpa-onnx (توكنات + توقيتها نسبةً لبداية المقطع).
  final List<String> tokens;
  final List<double> timestamps;

  const AsrSegment({
    required this.start,
    required this.end,
    required this.text,
    required this.charTimes,
    required this.tokens,
    required this.timestamps,
  });

  Map<String, Object> toJson() => {
        'start': start,
        'end': end,
        'text': text,
        'char_times': charTimes,
        'tokens': tokens,
        'timestamps': timestamps,
      };
}

class AsrTranscript {
  final List<AsrSegment> segments;
  final double audioSeconds;
  final int sourceSampleRate;
  final int numThreads;

  /// قراءة/تحويل الصوت لـ 16kHz، تحميل النموذج، VAD + تعرف.
  final int loadAudioMs;
  final int initMs;
  final int recognizeMs;

  const AsrTranscript({
    required this.segments,
    required this.audioSeconds,
    required this.sourceSampleRate,
    required this.numThreads,
    required this.loadAudioMs,
    required this.initMs,
    required this.recognizeMs,
  });

  int get totalMs => loadAudioMs + initMs + recognizeMs;

  /// Real-Time Factor للـ VAD + التعرف (أقل من 1 = أسرع من الوقت الحقيقي).
  double get rtf => audioSeconds == 0 ? 0 : recognizeMs / 1000 / audioSeconds;

  /// RTF لكل المراحل (مع تحميل النموذج وقراءة الصوت).
  double get rtfTotal => audioSeconds == 0 ? 0 : totalMs / 1000 / audioSeconds;
}

/// إعدادات المحرك. نفس قيم tool/asr_prototype/run_asr.py (يوم 3).
class AsrEngineConfig {
  final int numThreads;
  final double minSilence;
  final double minSpeech;
  final double maxSpeech;
  const AsrEngineConfig({
    this.numThreads = 2,
    this.minSilence = 0.35,
    this.minSpeech = 0.25,
    this.maxSpeech = 25,
  });
}

/// محرك التعرف على التلاوة (يوم 4): sherpa-onnx OfflineRecognizer بإعداد
/// zipformerCtc (نموذج quran-asr-tiny) + Silero VAD، على صوت 16kHz mono.
///
/// Dart صافي (FFI) فبيشتغل على الجوال وعلى Linux (أداة الـ CI
/// `tool/asr_engine_cli.dart`)، نفس الكود بالضبط.
class AsrEngine {
  static const sampleRate = WavAudio.targetRate;
  static bool _bindings = false;

  /// لازم بكل isolate (كل isolate إله FFI state خاص فيه).
  static void ensureBindings() {
    if (_bindings) return;
    so.initBindings();
    _bindings = true;
  }

  /// ملف WAV (أي rate/قنوات) → مقاطع. للصيغ الثانية فكّها لـ WAV أول
  /// (NativeAudioDecoder على الجوال).
  static AsrTranscript transcribeWavFileSync(AsrModelPaths paths, String wavPath,
      {AsrEngineConfig config = const AsrEngineConfig()}) {
    final sw = Stopwatch()..start();
    final raw = WavAudio.decode(File(wavPath).readAsBytesSync());
    final audio = WavAudio.toRate(raw, sampleRate);
    final loadMs = sw.elapsedMilliseconds;
    return transcribeSamplesSync(paths, audio.samples,
        config: config, loadAudioMs: loadMs, sourceSampleRate: raw.sampleRate);
  }

  /// نفس اللي فوق بس بـ isolate منفصل (ما بيعلّق الواجهة).
  static Future<AsrTranscript> transcribeWavFile(
          AsrModelPaths paths, String wavPath,
          {AsrEngineConfig config = const AsrEngineConfig()}) =>
      Isolate.run(() => transcribeWavFileSync(paths, wavPath, config: config));

  static AsrTranscript transcribeSamplesSync(
    AsrModelPaths paths,
    Float32List samples, {
    AsrEngineConfig config = const AsrEngineConfig(),
    int loadAudioMs = 0,
    int sourceSampleRate = sampleRate,
  }) {
    ensureBindings();
    final sw = Stopwatch()..start();
    final recognizer = so.OfflineRecognizer(so.OfflineRecognizerConfig(
      model: so.OfflineModelConfig(
        zipformerCtc: so.OfflineZipformerCtcModelConfig(model: paths.model),
        tokens: paths.tokens,
        numThreads: config.numThreads,
        debug: false,
      ),
    ));
    final vadConfig = so.VadModelConfig(
      sileroVad: so.SileroVadModelConfig(
        model: paths.vad,
        minSilenceDuration: config.minSilence,
        minSpeechDuration: config.minSpeech,
        maxSpeechDuration: config.maxSpeech,
      ),
      sampleRate: sampleRate,
      numThreads: 1,
      debug: false,
    );
    final vad = so.VoiceActivityDetector(
        config: vadConfig,
        bufferSizeInSeconds: config.maxSpeech.ceil() + 35);
    final initMs = sw.elapsedMilliseconds;

    sw.reset();
    final segments = <AsrSegment>[];
    void drain() {
      while (!vad.isEmpty()) {
        final seg = vad.front();
        vad.pop();
        segments.add(_decode(recognizer, seg.samples, seg.start / sampleRate));
      }
    }

    try {
      final window = vadConfig.sileroVad.windowSize;
      for (var i = 0; i + window <= samples.length; i += window) {
        vad.acceptWaveform(Float32List.sublistView(samples, i, i + window));
        drain();
      }
      final tail = samples.length % window;
      if (tail > 0) {
        final pad = Float32List(window)
          ..setRange(0, tail, samples, samples.length - tail);
        vad.acceptWaveform(pad);
      }
      vad.flush();
      drain();
    } finally {
      vad.free();
      recognizer.free();
    }
    return AsrTranscript(
      segments: segments,
      audioSeconds: samples.length / sampleRate,
      sourceSampleRate: sourceSampleRate,
      numThreads: config.numThreads,
      loadAudioMs: loadAudioMs,
      initMs: initMs,
      recognizeMs: sw.elapsedMilliseconds,
    );
  }

  static AsrSegment _decode(
      so.OfflineRecognizer rec, Float32List samples, double offset) {
    final stream = rec.createStream();
    try {
      stream.acceptWaveform(samples: samples, sampleRate: sampleRate);
      rec.decode(stream);
      final r = rec.getResult(stream);
      final ct = charTimes(r.tokens, r.timestamps, offset);
      return AsrSegment(
        start: offset,
        end: offset + samples.length / sampleRate,
        text: ct.$1.isEmpty ? r.text : ct.$1,
        charTimes: ct.$2,
        tokens: r.tokens,
        timestamps: r.timestamps,
      );
    } finally {
      stream.free();
    }
  }
}

/// نص + توقيت لكل حرف (كل token بهالنموذج = حرف أو فاصل كلمة "▁").
/// نفس `char_times` بـ run_asr.py.
(String, List<double>) charTimes(
    List<String> tokens, List<double> timestamps, double offset) {
  if (tokens.isEmpty || tokens.length != timestamps.length) return ('', const []);
  final text = StringBuffer();
  final times = <double>[];
  for (var i = 0; i < tokens.length; i++) {
    final tok = tokens[i];
    if (tok == '<blk>' || tok == '<blank>' || tok == '<unk>' || tok == '<sos/eos>') {
      continue;
    }
    final t = tok.replaceAll('▁', ' ');
    final ts = ((offset + timestamps[i]) * 1000).round() / 1000;
    for (final ch in t.runes) {
      text.writeCharCode(ch);
      times.add(ts);
    }
  }
  return (text.toString(), times);
}
