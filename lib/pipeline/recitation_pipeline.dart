import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../asr/asr_engine.dart';
import '../asr/asr_model_manager.dart';
import '../asr/native_audio_decoder.dart';
import '../data/quran_database.dart';
import '../matching/quran_matcher.dart';
import '../matching/quran_matcher_service.dart';
import 'quran_text_source.dart';
import 'recitation_segment.dart';
import 'segment_builder.dart';

/// مراحل خط الأنابيب (لشاشة التقدّم).
enum PipelineStage { preparingModel, preparingQuran, decodingAudio, recognizing, matching, done }

extension PipelineStageLabel on PipelineStage {
  String get label => switch (this) {
        PipelineStage.preparingModel => 'تجهيز محرك التعرف',
        PipelineStage.preparingQuran => 'تجهيز نص القرآن والتفسير',
        PipelineStage.decodingAudio => 'استخراج الصوت',
        PipelineStage.recognizing => 'التعرف على التلاوة',
        PipelineStage.matching => 'مطابقة الآيات والتوقيت',
        PipelineStage.done => 'خلص',
      };
}

class PipelineResult {
  final List<RecitationSegment> segments;
  final AsrTranscript transcript;

  /// وقت كل مرحلة بالـ ms (بالترتيب).
  final Map<String, int> timings;
  final ModelSetupReport modelReport;

  /// ملف WAV اللي انعمل عليه التعرف (نفس الملف لو كان WAV أصلاً).
  final String wavPath;

  const PipelineResult(this.segments, this.transcript, this.timings,
      this.modelReport, this.wavPath);

  List<String> get ayahRefs => pipelineAyahRefs(segments);
  int get totalMs => timings.values.fold(0, (a, b) => a + b);
}

/// خط الأنابيب كامل على الجوال (يوم 5): أي ملف صوت أو فيديو →
/// [NativeAudioDecoder.ensureWav] → [AsrSession] (isolate عايش) →
/// [QuranSequenceMatcher] → قائمة [RecitationSegment] بتوقيتها، مع النص
/// العثماني لكل جزء والتفسير المقسوم.
///
/// الجزء الصافي (بدون Flutter) بـ [buildRecitationSegments]، فبنجرّبه
/// بالاختبارات وبالـ CI على نفس الكود.
class RecitationPipeline {
  RecitationPipeline._();
  static final RecitationPipeline instance = RecitationPipeline._();

  Future<QuranTextSource>? _text;

  /// نص الآيات والتفسير من قاعدة البيانات المحلية (مرة وحدة).
  Future<QuranTextSource> get textSource => _text ??= _loadText();

  Future<QuranTextSource> _loadText() async {
    final db = await QuranDatabase.instance.database;
    final rows = await db.rawQuery(
        'SELECT surah_number, ayah_number, text_uthmani, tafsir_muyassar FROM ayahs');
    return QuranTextSource.fromRows([
      for (final r in rows)
        (
          r['surah_number'] as int,
          r['ayah_number'] as int,
          r['text_uthmani'] as String,
          r['tafsir_muyassar'] as String,
        ),
    ]);
  }

  Future<AsrModelManager> modelManager() async {
    final support = await getApplicationSupportDirectory();
    return AsrModelManager(Directory('${support.path}/asr'));
  }

  Future<PipelineResult> analyze(
    String inputPath, {
    AsrEngineConfig config = const AsrEngineConfig(),
    PipelineOptions options = const PipelineOptions(),
    void Function(PipelineStage stage, double? progress)? onStage,
    AsrSession? session,
  }) async {
    final timings = <String, int>{};
    final sw = Stopwatch()..start();
    void mark(String k) {
      timings[k] = sw.elapsedMilliseconds;
      sw.reset();
    }

    // القرآن والـ matcher بيتجهزوا بالتوازي مع النموذج.
    final quranReady = Future.wait<Object>(
        [QuranMatcherService.instance.matcher, textSource]);

    onStage?.call(PipelineStage.preparingModel, null);
    final mgr = await modelManager();
    final paths = await mgr.ensureReady(
        onProgress: (p) => onStage?.call(PipelineStage.preparingModel, p.fraction));
    mark('model');

    onStage?.call(PipelineStage.decodingAudio, null);
    final wav = await NativeAudioDecoder.ensureWav(
        inputPath, await getTemporaryDirectory());
    mark('decode');

    onStage?.call(PipelineStage.recognizing, null);
    final asr = session ?? await AsrSession.shared();
    final t = await asr.transcribeWavFile(paths, wav, config: config);
    mark('asr');

    onStage?.call(PipelineStage.preparingQuran, null);
    final q = await quranReady;
    mark('quran_wait');

    onStage?.call(PipelineStage.matching, null);
    final segs = buildRecitationSegments(
        q[0] as QuranMatcher, q[1] as QuranTextSource, t.segments,
        options: options);
    mark('match');
    onStage?.call(PipelineStage.done, 1);
    return PipelineResult(segs, t, timings, mgr.lastReport, wav);
  }
}
