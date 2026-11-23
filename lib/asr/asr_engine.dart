import 'dart:async';
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

  /// مرة وحدة (بيبني المحرك ويحرره). للجلسات الطويلة استعمل
  /// [AsrRecognizer] (sync) أو [AsrSession] (isolate عايش طول الجلسة).
  static AsrTranscript transcribeSamplesSync(
    AsrModelPaths paths,
    Float32List samples, {
    AsrEngineConfig config = const AsrEngineConfig(),
    int loadAudioMs = 0,
    int sourceSampleRate = sampleRate,
  }) {
    final rec = AsrRecognizer(paths, config: config);
    try {
      return rec.transcribeSamples(samples,
          loadAudioMs: loadAudioMs, sourceSampleRate: sourceSampleRate);
    } finally {
      rec.free();
    }
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

/// محرك التعرف **عايش** (يوم 5): النموذج بيتحمّل مرة وحدة (~0.5 ثانية على
/// الجوال) وبيضل بالذاكرة لكل الملفات بعدها. الـ VAD بينبني جديد لكل ملف
/// (حالته مربوطة بالملف، وبناؤه بأجزاء من الثانية). مش thread-safe: استعمله
/// من isolate واحد ([AsrSession] بيعمل هيك).
class AsrRecognizer {
  final AsrModelPaths paths;
  final AsrEngineConfig config;
  late final so.OfflineRecognizer _recognizer;
  late final so.VadModelConfig _vadConfig;

  /// وقت تحميل النموذج (مرة وحدة).
  late final int initMs;
  int _uses = 0;
  bool _freed = false;

  AsrRecognizer(this.paths, {this.config = const AsrEngineConfig()}) {
    AsrEngine.ensureBindings();
    final sw = Stopwatch()..start();
    _recognizer = so.OfflineRecognizer(so.OfflineRecognizerConfig(
      model: so.OfflineModelConfig(
        zipformerCtc: so.OfflineZipformerCtcModelConfig(model: paths.model),
        tokens: paths.tokens,
        numThreads: config.numThreads,
        debug: false,
      ),
    ));
    _vadConfig = so.VadModelConfig(
      sileroVad: so.SileroVadModelConfig(
        model: paths.vad,
        minSilenceDuration: config.minSilence,
        minSpeechDuration: config.minSpeech,
        maxSpeechDuration: config.maxSpeech,
      ),
      sampleRate: AsrEngine.sampleRate,
      numThreads: 1,
      debug: false,
    );
    initMs = sw.elapsedMilliseconds;
  }

  AsrTranscript transcribeWavFile(String wavPath) {
    final sw = Stopwatch()..start();
    final raw = WavAudio.decode(File(wavPath).readAsBytesSync());
    final audio = WavAudio.toRate(raw, AsrEngine.sampleRate);
    return transcribeSamples(audio.samples,
        loadAudioMs: sw.elapsedMilliseconds, sourceSampleRate: raw.sampleRate);
  }

  AsrTranscript transcribeSamples(Float32List samples,
      {int loadAudioMs = 0, int sourceSampleRate = AsrEngine.sampleRate}) {
    if (_freed) throw StateError('AsrRecognizer freed');
    const sampleRate = AsrEngine.sampleRate;
    // أول استعمال بيحسب وقت تحميل النموذج، الباقي 0 (المحرك جاهز).
    final init = _uses++ == 0 ? initMs : 0;
    final sw = Stopwatch()..start();
    final vad = so.VoiceActivityDetector(
        config: _vadConfig, bufferSizeInSeconds: config.maxSpeech.ceil() + 35);
    final segments = <AsrSegment>[];
    void drain() {
      while (!vad.isEmpty()) {
        final seg = vad.front();
        vad.pop();
        segments.add(
            AsrEngine._decode(_recognizer, seg.samples, seg.start / sampleRate));
      }
    }

    try {
      final window = _vadConfig.sileroVad.windowSize;
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
    }
    return AsrTranscript(
      segments: segments,
      audioSeconds: samples.length / sampleRate,
      sourceSampleRate: sourceSampleRate,
      numThreads: config.numThreads,
      loadAudioMs: loadAudioMs,
      initMs: init,
      recognizeMs: sw.elapsedMilliseconds,
    );
  }

  void free() {
    if (_freed) return;
    _freed = true;
    _recognizer.free();
  }
}

/// isolate واحد عايش طول الجلسة فيه [AsrRecognizer] (يوم 5): ما بيعلّق
/// الواجهة، والنموذج ما بينبني من جديد بكل ملف. لو تغيّر عدد الخيوط بيبني
/// المحرك من جديد جوا نفس الـ isolate.
class AsrSession {
  AsrSession._(this._isolate, this._send, this._responses);

  final Isolate _isolate;
  final SendPort _send;
  final Stream<dynamic> _responses;
  int _nextId = 0;
  Future<void> _queue = Future.value();

  static AsrSession? _shared;

  /// نسخة وحيدة للتطبيق كله.
  static Future<AsrSession> shared() async => _shared ??= await start();

  static Future<AsrSession> start() async {
    final rx = ReceivePort();
    final isolate = await Isolate.spawn(_asrWorkerMain, rx.sendPort,
        debugName: 'asr-session');
    final responses = rx.asBroadcastStream();
    final send = await responses.first as SendPort;
    return AsrSession._(isolate, send, responses);
  }

  /// طلب واحد بكل مرة (بالترتيب).
  Future<AsrTranscript> transcribeWavFile(AsrModelPaths paths, String wavPath,
      {AsrEngineConfig config = const AsrEngineConfig()}) {
    final c = Completer<AsrTranscript>();
    _queue = _queue.then((_) async {
      final id = _nextId++;
      final reply = _responses.firstWhere((m) => m is List && m[0] == id);
      _send.send([id, paths.model, paths.tokens, paths.vad, wavPath,
        config.numThreads, config.minSilence, config.minSpeech, config.maxSpeech]);
      try {
        final m = await reply as List;
        if (m[1] is AsrTranscript) {
          c.complete(m[1] as AsrTranscript);
        } else {
          c.completeError(StateError('ASR: ${m[1]}'));
        }
      } catch (e, st) {
        if (!c.isCompleted) c.completeError(e, st);
      }
    });
    return c.future;
  }

  void dispose() {
    _send.send(null);
    _isolate.kill(priority: Isolate.beforeNextEvent);
    if (identical(_shared, this)) _shared = null;
  }
}

void _asrWorkerMain(SendPort main) {
  final rx = ReceivePort();
  main.send(rx.sendPort);
  AsrRecognizer? rec;
  String? key;
  rx.listen((dynamic msg) {
    if (msg == null) {
      rec?.free();
      rx.close();
      return;
    }
    final m = msg as List;
    final id = m[0] as int;
    try {
      final paths = AsrModelPaths(
          model: m[1] as String, tokens: m[2] as String, vad: m[3] as String);
      final config = AsrEngineConfig(
          numThreads: m[5] as int,
          minSilence: m[6] as double,
          minSpeech: m[7] as double,
          maxSpeech: m[8] as double);
      final k = '${paths.model}|${config.numThreads}|${config.minSilence}|'
          '${config.minSpeech}|${config.maxSpeech}';
      if (rec == null || key != k) {
        rec?.free();
        rec = AsrRecognizer(paths, config: config);
        key = k;
      }
      main.send([id, rec!.transcribeWavFile(m[4] as String)]);
    } catch (e) {
      main.send([id, '$e']);
    }
  });
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
