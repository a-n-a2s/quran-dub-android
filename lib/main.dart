import 'dart:async';

import 'package:flutter/material.dart';

import 'data/quran_database.dart';
import 'debug/asr_debug_panel.dart';
import 'matching/quran_matcher_service.dart';
import 'pipeline/project_input.dart';
import 'platform/camera_recorder.dart';
import 'platform/gallery_picker.dart';
import 'platform/video_info.dart';
import 'debug/crash_report_banner.dart';
import 'screens/analysis_screen.dart';

void main() {
  runApp(const QuranDubApp());
}

/// تطبيق "آية ستوديو – Ayah Studio" (اسم مبدئي)
/// يطابق أي فيديو فيه تلاوة قرآنية مع نص القرآن والتفسير الميسر تلقائياً.
class QuranDubApp extends StatelessWidget {
  const QuranDubApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'آية ستوديو',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0E6B52)),
        useMaterial3: true,
      ),
      // الواجهة عربي (يوم 10: 4 لغات واجهة).
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      home: const HomeScreen(),
    );
  }
}

/// شاشة ترحيبية بسيطة. مهمتها هلأ إنها تتحقق إنه قاعدة بيانات القرآن
/// والتفسير اتبنت واتعبّت بنجاح من ملف الأصول المضغوط (seed مرة واحدة
/// عند أول فتح)، وتعرض عدد الآيات كتأكيد مرئي سريع لحالة البيانات.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final Future<_SeedStatus> _seedFuture = _checkSeedStatus();

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openAnalysis(String videoPath, VideoSource source) async {
    try {
      final info = await VideoInfoReader.read(videoPath);
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => AnalysisScreen(
          input: ProjectInput(
              videoPath: videoPath, source: source, videoInfo: info),
        ),
      ));
    } catch (e) {
      _showError('ما قدرنا نقرأ معلومات الفيديو: $e');
    }
  }

  /// اختيار مقطع من المعرض (Photo Picker أو SAF، يوم 6)، مع شاشة تقدّم نسخ
  /// بسيطة عشان ما "يتعلّق" التطبيق مع الفيديوهات الكبيرة.
  Future<void> _pickFromGallery() async {
    final progress = ValueNotifier<GalleryCopyProgress?>(null);
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: ValueListenableBuilder<GalleryCopyProgress?>(
          valueListenable: progress,
          builder: (_, p, __) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(value: p?.fraction),
              const SizedBox(height: 12),
              Text(p?.fraction == null
                  ? 'جاري اختيار الفيديو من المعرض...'
                  : 'جاري نسخ الفيديو... ${(p!.fraction! * 100).round()}%'),
            ],
          ),
        ),
      ),
    ));
    try {
      final picked =
          await GalleryPicker.pickVideo(onProgress: (p) => progress.value = p);
      if (!mounted) return;
      Navigator.of(context).pop(); // سكّر شاشة التقدّم.
      if (picked == null) return;
      await _openAnalysis(picked.path, VideoSource.gallery);
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      _showError('ما قدرنا نجيب الفيديو من المعرض: $e');
    }
  }

  /// تصوير مقطع من جوا التطبيق (يوم 6): صلاحيات الكاميرا/المايكروفون
  /// بتنطلب هون بس، وقت الحاجة.
  Future<void> _recordFromCamera() async {
    try {
      final recorded = await CameraRecorder.recordVideo();
      if (recorded == null) return; // المستخدم لغى التصوير.
      await _openAnalysis(recorded.path, VideoSource.camera);
    } on CameraPermissionDeniedException catch (e) {
      _showError('$e');
    } on NoCameraAppException catch (e) {
      _showError('$e');
    } catch (e) {
      _showError('ما قدرنا نفتح الكاميرا: $e');
    }
  }

  Future<_SeedStatus> _checkSeedStatus() async {
    final db = await QuranDatabase.instance.database;
    final surahs = await QuranDatabase.instance.allSurahs();
    final firstAyah = await QuranDatabase.instance.ayahAt(1, 1);
    final ayahCountRow = await db.rawQuery('SELECT COUNT(*) AS c FROM ayahs');
    final ayahCount = ayahCountRow.first['c'] as int;
    List<String> matchCheck;
    try {
      matchCheck = await QuranMatcherService.instance.selfCheck();
    } catch (e) {
      matchCheck = ['خطأ: $e'];
    }
    return _SeedStatus(
      surahCount: surahs.length,
      ayahCount: ayahCount,
      sampleAyah: firstAyah?.textUthmani ?? '',
      matchCheck: matchCheck,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('آية ستوديو')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            const CrashReportBanner(),
            FutureBuilder<_SeedStatus>(
            future: _seedFuture,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Text(
                  'حصل خطأ بتحميل قاعدة بيانات القرآن:\n${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red),
                );
              }
              if (!snapshot.hasData) {
                return const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('جاري تجهيز قاعدة بيانات القرآن والتفسير...'),
                  ],
                );
              }
              final status = snapshot.data!;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'مرحباً بك 👋',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'قاعدة بيانات القرآن والتفسير جاهزة محلياً:\n'
                    '${status.surahCount} سورة، ${status.ayahCount} آية.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    status.sampleAyah,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 22),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'فحص محرك المطابقة (يوم 3):\n${status.matchCheck.join('\n')}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14, color: Colors.black54),
                  ),
                ],
              );
            },
          ),
            const SizedBox(height: 24),
            // يوم 6: رفع مقطع من المعرض أو تصوير مباشر. شكل بسيط هلأ
            // (الهوية الخضراء/الذهبية بأيام الواجهات، يوم 13).
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _pickFromGallery,
                    icon: const Icon(Icons.upload_file),
                    label: const Text('رفع مقطع'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _recordFromCamera,
                    icon: const Icon(Icons.videocam),
                    label: const Text('تصوير'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            // زر تجربة التعرف على الصوت على الجوال (يوم 4).
            const AsrDebugPanel(),
          ],
        ),
      ),
    );
  }
}

class _SeedStatus {
  final int surahCount;
  final int ayahCount;
  final String sampleAyah;
  final List<String> matchCheck;

  const _SeedStatus({
    required this.surahCount,
    required this.ayahCount,
    required this.sampleAyah,
    required this.matchCheck,
  });
}
