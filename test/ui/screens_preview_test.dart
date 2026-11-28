// لقطات للواجهة الجديدة (للمراجعة البصرية، مش مقارنة golden): بترسم الشاشات
// بالخطوط الحقيقية وبتحفظها PNG بـ build/ui_preview (بترتفع كـ artifact بالـ CI).
// الهدف: نشوف الشكل بدون جهاز. الاختبار بينجح طالما الرسم ما فيه أخطاء.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quran_dub/editor/waveform.dart';
import 'package:quran_dub/overlay/overlay_frame.dart';
import 'package:quran_dub/overlay/overlay_style.dart';
import 'package:quran_dub/overlay/overlay_timeline.dart';
import 'package:quran_dub/pipeline/recitation_segment.dart';
import 'package:quran_dub/projects/recent_projects.dart';
import 'package:quran_dub/screens/home_screen.dart';
import 'package:quran_dub/screens/widgets/editor_timeline.dart';
import 'package:quran_dub/ui/app_settings.dart';
import 'package:quran_dub/ui/app_theme.dart';
import 'package:quran_dub/ui/ayah_widgets.dart';

Future<void> _font(String family, List<String> paths) async {
  final loader = FontLoader(family);
  for (final p in paths) {
    final bytes = File(p).readAsBytesSync();
    loader.addFont(Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)));
  }
  await loader.load();
}

String? _materialIcons() {
  final c = <String>[];
  final env = Platform.environment['FLUTTER_ROOT'];
  if (env != null) c.add('$env/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  var dir = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 8; i++) {
    c.add('${dir.path}/material_fonts/MaterialIcons-Regular.otf');
    c.add('${dir.path}/artifacts/material_fonts/MaterialIcons-Regular.otf');
    c.add('${dir.path}/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    dir = dir.parent;
  }
  for (final p in c) {
    if (File(p).existsSync()) return p;
  }
  return null;
}

final _key = GlobalKey();

Future<void> _shot(WidgetTester t, String name) async {
  final ro = _key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final bytes = await t.runAsync(() async {
    final img = await ro.toImage(pixelRatio: 2);
    final d = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    return d!.buffer.asUint8List();
  });
  final dir = Directory('build/ui_preview')..createSync(recursive: true);
  File('${dir.path}/$name.png').writeAsBytesSync(bytes!);
}

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    await t.pump(const Duration(milliseconds: 50));
  }
}

Widget _app(Widget home, {bool dark = true}) => RepaintBoundary(
      key: _key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAyahTheme(dark: dark),
        builder: (c, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
        home: home,
      ),
    );

RecitationSegment _a(int s, int a, double t0, double t1, String text,
        {bool review = false, int part = 1, int parts = 1}) =>
    RecitationSegment(
        start: t0,
        end: t1,
        kind: parts > 1 ? SegmentKind.partialAyah : SegmentKind.fullAyah,
        surah: s,
        ayah: a,
        part: part,
        partCount: parts,
        text: text,
        showAyahNumber: part == parts,
        tafsir: 'قال قرينه من الشياطين: ربنا ما أضللته، ولكن كان في ضلال بعيد عن الحق',
        confidence: review ? 0.4 : 0.95,
        needsReview: review);

void main() {
  setUpAll(() async {
    await _font(kUiFont, [
      for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold'])
        'assets/fonts/ui/IBMPlexSansArabic-$w.ttf'
    ]);
    await _font('Amiri', ['assets/fonts/Amiri-Regular.ttf']);
    await _font('Amiri Quran', ['assets/fonts/AmiriQuran.ttf']);
    await _font('KFGQPC Hafs', ['assets/fonts/KFGQPC_HafsUthmanic_v18.ttf']);
    final icons = _materialIcons();
    if (icons != null) await _font('MaterialIcons', [icons]);
  });

  Future<void> phone(WidgetTester t) async {
    t.view.physicalSize = const Size(412 * 2, 915 * 2);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
  }

  testWidgets('الرئيسية (ليلي، فيها مشاريع)', (t) async {
    await phone(t);
    final dir = await t.runAsync(() => Directory.systemTemp.createTemp('ui_prev'));
    final store = RecentProjectsStore(dir!);
    AppSettings.storeForTest = store;
    await t.runAsync(() async {
      await store.upsert(RecentProject(
        id: 'a',
        videoPath: '/x/a.mp4',
        title: 'سُوْرَةُ البَقَرَةِ',
        subtitle: 'الآيات ٢٥٥–٢٥٧',
        ayahCount: 3,
        durationSeconds: 74,
        width: 1080,
        height: 1920,
        updatedAt: DateTime.now().subtract(const Duration(minutes: 12)),
        wave: [for (var i = 0; i < 48; i++) (0.25 + 0.7 * ((i * 37) % 11) / 10).clamp(0, 1).toDouble()],
      ));
      await store.upsert(RecentProject(
        id: 'b',
        videoPath: '/x/b.mp4',
        title: 'سُوْرَةُ الكَهْفِ',
        subtitle: 'الآيات ١–١٠',
        ayahCount: 10,
        durationSeconds: 182,
        width: 1080,
        height: 1920,
        updatedAt: DateTime.now().subtract(const Duration(days: 2)),
        wave: [for (var i = 0; i < 48; i++) (0.2 + 0.6 * ((i * 13) % 7) / 6).clamp(0, 1).toDouble()],
      ));
    });
    AppSettings.dark.value = true;
    await t.pumpWidget(_app(const HomeShell()));
    await t.runAsync(() async {
      final ctx = _key.currentContext!;
      await precacheImage(const AssetImage('assets/branding/logo_mark.png'), ctx);
      await precacheImage(const AssetImage('assets/branding/logo_wave.png'), ctx);
    });
    await _settle(t);
    await _shot(t, '01_home_dark');
  });

  testWidgets('الرئيسية (نهاري، فاضية)', (t) async {
    await phone(t);
    final dir = await t.runAsync(() => Directory.systemTemp.createTemp('ui_prev2'));
    AppSettings.storeForTest = RecentProjectsStore(dir!);
    AppSettings.dark.value = false;
    await t.pumpWidget(_app(const HomeShell(), dark: false));
    await t.runAsync(() async {
      final ctx = _key.currentContext!;
      await precacheImage(const AssetImage('assets/branding/logo_mark.png'), ctx);
      await precacheImage(const AssetImage('assets/branding/logo_wave.png'), ctx);
    });
    await _settle(t);
    await _shot(t, '02_home_light_empty');
    AppSettings.dark.value = true;
  });

  testWidgets('المحرر: المعاينة + الخط الزمني + شريط الأدوات (تركيب للمراجعة)', (t) async {
    await phone(t);
    final segs = [
      _a(50, 27, 0.4, 2.9, 'قَالَ قَرِينُهُۥ رَبَّنَا مَآ أَطۡغَيۡتُهُۥ وَلَٰكِن', part: 1, parts: 2),
      _a(50, 27, 2.9, 5.2, 'كَانَ فِي ضَلَٰلِۭ بَعِيدࣲ', part: 2, parts: 2),
      _a(50, 28, 5.6, 9.8, 'قَالَ لَا تَخۡتَصِمُواْ لَدَيَّ وَقَدۡ قَدَّمۡتُ إِلَيۡكُم بِٱلۡوَعِيدِ',
          review: true),
      _a(50, 29, 10.2, 14, 'مَا يُبَدَّلُ ٱلۡقَوۡلُ لَدَيَّ وَمَآ أَنَا۠ بِظَلَّٰمࣲ لِّلۡعَبِيدِ'),
    ];
    final timeline = OverlayTimeline.build(segs, videoDuration: 16);
    final playhead = ValueNotifier<double>(3.4);
    final peaks = WaveformPeaks(
        [for (var i = 0; i < 320; i++) (0.15 + 0.8 * ((i * 29) % 17) / 16) * (i % 40 < 6 ? 0.2 : 1)],
        0.05,
        16);
    Widget tool(IconData i, String l, {Color c = Colors.white}) => SizedBox(
          width: 70,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(i, color: c, size: 26),
            const SizedBox(height: 6),
            Text(l, style: TextStyle(fontFamily: kUiFont, fontSize: 11.5, color: c)),
          ]),
        );
    await t.pumpWidget(_app(
      Scaffold(
        backgroundColor: const Color(0xFF020E0A),
        body: SafeArea(
          child: Column(children: [
            SizedBox(
              height: 54,
              child: Row(children: [
                const SizedBox(width: 8),
                const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                const Spacer(),
                const Text('1080P', style: TextStyle(color: Colors.white70, fontFamily: kUiFont)),
                const SizedBox(width: 10),
                GoldButton(label: 'تصدير', icon: Icons.file_upload_outlined, height: 38, fontSize: 15, expand: false, onPressed: () {}),
                const SizedBox(width: 12),
              ]),
            ),
            Expanded(
              child: Container(
                color: Colors.black,
                alignment: Alignment.center,
                child: FittedBox(
                  child: Container(
                    width: 1080,
                    height: 1920,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFF3A5A78), Color(0xFF9B7B5C), Color(0xFF2B2B2B)],
                      ),
                    ),
                    child: AyahOverlayFrame(
                      videoWidth: 1080,
                      videoHeight: 1920,
                      cue: timeline.cueAt(3.4),
                      style: const OverlayStyle(shadowStrength: 0.7),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(
              height: 52,
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: Row(children: [
                  const SizedBox(width: 12),
                  const Text('00:03 / 00:16', style: TextStyle(color: Colors.white, fontFamily: kUiFont)),
                  const Spacer(),
                  const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 34),
                  const Spacer(),
                  const Icon(Icons.undo_rounded, color: Colors.white),
                  const SizedBox(width: 16),
                  const Icon(Icons.redo_rounded, color: Colors.white24),
                  const SizedBox(width: 12),
                ]),
              ),
            ),
            Container(
              color: const Color(0xFF071A13),
              padding: const EdgeInsets.only(top: 6),
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: EditorTimeline(
                  segments: segs,
                  duration: 16,
                  peaks: peaks,
                  thumbs: const [],
                  playhead: playhead,
                  selectedIndex: 1,
                  onScrubStart: () {},
                  onScrub: (_) {},
                  onScrubEnd: () {},
                  onSelect: (_) {},
                  onHandleStart: (_, __) {},
                  onDragHandle: (_, __, ___) {},
                  onHandleEnd: () {},
                  onAdd: () {},
                ),
              ),
            ),
            Container(
              height: 78,
              color: const Color(0xFF020E0A),
              child: ListView(scrollDirection: Axis.horizontal, children: [
                tool(Icons.chevron_right_rounded, 'رجوع', c: Colors.white60),
                tool(Icons.swap_horiz_rounded, 'تغيير الآية'),
                tool(Icons.tune_rounded, 'التوقيت'),
                tool(Icons.play_circle_outline_rounded, 'تشغيلها'),
                tool(Icons.text_snippet_outlined, 'نص خاص'),
                tool(Icons.delete_outline_rounded, 'حذف', c: AyahColors.danger),
              ]),
            ),
          ]),
        ),
      ),
    ));
    await _settle(t);
    await _shot(t, '03_editor');
  });
}
