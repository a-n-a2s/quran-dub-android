// الشاشة الرئيسية الجديدة (طلب أنس 2026-11-28، حسب التصميم المقترح): خلفية
// زمردية بنقش هندسي، الشعار، صندوق "تحميل الملف" بحد ذهبي متقطّع، و"مشاريع القرآن
// الأخيرة" كبطاقات (اسم السورة، موجة، زر تشغيل، وسوم الآيات والتفسير)، وشريط
// تنقّل سفلي زجاجي بزر رفع ذهبي بالنص.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/quran_database.dart';
import '../debug/asr_debug_panel.dart';
import '../debug/crash_report_banner.dart';
import '../matching/quran_matcher_service.dart';
import '../pipeline/project_input.dart';
import '../platform/camera_recorder.dart';
import '../platform/gallery_picker.dart';
import '../platform/video_info.dart';
import '../projects/recent_projects.dart';
import '../ui/app_settings.dart';
import '../ui/app_theme.dart';
import '../ui/ayah_widgets.dart';
import 'analysis_screen.dart';
import 'overlay_editor_screen.dart';

/// تشغيل مشروع جديد (من المعرض أو الكاميرا) أو فتح مشروع قديم. مشترك بين
/// الرئيسية وزر الرفع بالشريط السفلي.
class ProjectLauncher {
  ProjectLauncher._();

  static void _toast(BuildContext context, String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  static Future<void> _openAnalysis(
      BuildContext context, String videoPath, VideoSource source) async {
    try {
      final info = await VideoInfoReader.read(videoPath);
      if (!context.mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => AnalysisScreen(
          input: ProjectInput(videoPath: videoPath, source: source, videoInfo: info),
        ),
      ));
    } catch (e) {
      if (context.mounted) _toast(context, 'ما قدرنا نقرأ معلومات الفيديو: $e');
    }
  }

  /// اختيار مقطع من المعرض (Photo Picker أو SAF، يوم 6) مع تقدّم النسخ.
  static Future<void> pickFromGallery(BuildContext context) async {
    final progress = ValueNotifier<GalleryCopyProgress?>(null);
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          content: ValueListenableBuilder<GalleryCopyProgress?>(
            valueListenable: progress,
            builder: (_, p, __) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const GoldLoader(),
                const SizedBox(height: 18),
                Text(p?.fraction == null
                    ? 'جاري اختيار الفيديو…'
                    : 'جاري تجهيز الفيديو… ${(p!.fraction! * 100).round()}٪'),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(value: p?.fraction, minHeight: 6),
                ),
              ],
            ),
          ),
        ),
      ),
    ));
    try {
      final picked = await GalleryPicker.pickVideo(onProgress: (p) => progress.value = p);
      if (!context.mounted) return;
      Navigator.of(context).pop();
      if (picked == null) return;
      await _openAnalysis(context, picked.path, VideoSource.gallery);
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop();
        _toast(context, 'ما قدرنا نجيب الفيديو من المعرض: $e');
      }
    }
  }

  /// تصوير مقطع (يوم 6): الصلاحيات وقت الحاجة بس.
  static Future<void> recordFromCamera(BuildContext context) async {
    try {
      final recorded = await CameraRecorder.recordVideo();
      if (recorded == null || !context.mounted) return;
      await _openAnalysis(context, recorded.path, VideoSource.camera);
    } on CameraPermissionDeniedException catch (e) {
      if (context.mounted) _toast(context, '$e');
    } on NoCameraAppException catch (e) {
      if (context.mounted) _toast(context, '$e');
    } catch (e) {
      if (context.mounted) _toast(context, 'ما قدرنا نفتح الكاميرا: $e');
    }
  }

  /// قائمة سفلية: من المعرض أو تصوير.
  static Future<void> chooseSource(BuildContext context) async {
    final p = AyahPalette.of(context);
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('مشروع جديد',
                    textAlign: TextAlign.center,
                    style: Theme.of(ctx).textTheme.titleLarge),
                const SizedBox(height: 6),
                Text('اختار مقطع فيه تلاوة، والتطبيق بيكتب الآيات والتفسير لحاله',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: p.textMuted, fontSize: 13)),
                const SizedBox(height: 20),
                GoldButton(
                  label: 'من المعرض',
                  icon: Icons.video_library_rounded,
                  onPressed: () => Navigator.pop(ctx, 'gallery'),
                ),
                const SizedBox(height: 12),
                GoldOutlineButton(
                  label: 'تصوير مقطع',
                  icon: Icons.videocam_rounded,
                  onPressed: () => Navigator.pop(ctx, 'camera'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!context.mounted) return;
    if (choice == 'gallery') await pickFromGallery(context);
    if (choice == 'camera') await recordFromCamera(context);
  }

  /// فتح مشروع قديم: مباشرة على المحرر لو نتيجة التحليل محفوظة، وإلا تحليل جديد.
  static Future<void> openRecent(BuildContext context, RecentProject p) async {
    if (!File(p.videoPath).existsSync()) {
      final remove = await showAyahDialog<bool>(
        context,
        (ctx) => AlertDialog(
          title: const Text('الفيديو ما عاد موجود'),
          content: const Text(
              'ملف الفيديو انمسح من الجوال (أو من ذاكرة التطبيق المؤقتة). بدك تشيل المشروع من القائمة؟'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('خليه')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('شيله')),
          ],
        ),
      );
      if (remove == true) {
        final store = await AppSettings.projects();
        await store.remove(p.id);
        AppSettings.projectsChanged();
      }
      return;
    }
    final store = await AppSettings.projects();
    final segments = await store.loadAnalysis(p.id);
    unawaited(store.touch(p.id).then((_) => AppSettings.projectsChanged()));
    if (!context.mounted) return;
    if (segments == null) {
      await Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => AnalysisScreen(input: p.input)));
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => OverlayEditorScreen(input: p.input, segments: segments),
    ));
  }
}

/// الهيكل: صفحات (الرئيسية، المشاريع، الإعدادات) + شريط تنقّل سفلي زجاجي.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final p = AyahPalette.of(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: p.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        extendBody: true,
        body: AyahBackground(
          child: SafeArea(
            bottom: false,
            child: IndexedStack(
              index: _tab,
              children: [
                HomePage(onSeeAll: () => setState(() => _tab = 1)),
                const ProjectsPage(),
                const SettingsPage(),
              ],
            ),
          ),
        ),
        bottomNavigationBar: _BottomBar(
          index: _tab,
          onTab: (i) => setState(() => _tab = i),
          onUpload: () => ProjectLauncher.chooseSource(context),
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTab;
  final VoidCallback onUpload;
  const _BottomBar({required this.index, required this.onTab, required this.onUpload});

  @override
  Widget build(BuildContext context) {
    final p = AyahPalette.of(context);
    Widget item(int i, IconData icon, IconData active, String label) {
      final on = index == i;
      return Expanded(
        child: InkResponse(
          onTap: () {
            HapticFeedback.selectionClick();
            onTab(i);
          },
          radius: 36,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: on ? AyahColors.gold.withValues(alpha: 0.16) : Colors.transparent,
                ),
                child: Icon(on ? active : icon,
                    size: 26, color: on ? AyahColors.gold : p.textMuted),
              ),
              const SizedBox(height: 3),
              Text(label,
                  style: TextStyle(
                      fontFamily: kUiFont,
                      fontSize: 11,
                      fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                      color: on ? p.accentText : p.textMuted)),
            ],
          ),
        ),
      );
    }

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
        child: Container(
          height: 74,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            color: p.dark ? const Color(0xF20A2C21) : const Color(0xF7FFFBF0),
            border: Border.all(color: p.cardBorder.withValues(alpha: 0.5)),
            boxShadow: const [
              BoxShadow(color: Color(0x66000000), blurRadius: 24, offset: Offset(0, 8)),
            ],
          ),
          child: Row(
            children: [
              item(0, Icons.home_outlined, Icons.home_rounded, 'الرئيسية'),
              item(1, Icons.video_library_outlined, Icons.video_library_rounded, 'مشاريعي'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: RoundIconButton(
                  icon: Icons.add_rounded,
                  gold: true,
                  size: 58,
                  tooltip: 'مشروع جديد',
                  onPressed: onUpload,
                ),
              ),
              item(2, Icons.settings_outlined, Icons.settings_rounded, 'الإعدادات'),
            ],
          ),
        ),
      ),
    );
  }
}

/// الصفحة الرئيسية.
class HomePage extends StatelessWidget {
  final VoidCallback onSeeAll;
  const HomePage({super.key, required this.onSeeAll});

  @override
  Widget build(BuildContext context) {
    final p = AyahPalette.of(context);
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          sliver: SliverToBoxAdapter(
            child: Row(
              children: [
                // الشعار بحلقة ذهبية (مكان صورة الحساب لحد يوم 15).
                Container(
                  width: 56,
                  height: 56,
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AyahColors.deep,
                    border: Border.all(color: AyahColors.gold, width: 2),
                    boxShadow: [
                      BoxShadow(color: AyahColors.gold.withValues(alpha: 0.3), blurRadius: 14),
                    ],
                  ),
                  child: const AyahLogo(size: 40),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('آية ستوديو',
                          style: TextStyle(
                              fontFamily: kUiFont,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: p.text)),
                      Text('الآيات والتفسير فوق مقطعك تلقائياً',
                          style: TextStyle(fontFamily: kUiFont, fontSize: 12, color: p.textMuted)),
                    ],
                  ),
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: AppSettings.dark,
                  builder: (_, dark, __) =>
                      ThemeModeToggle(dark: dark, onChanged: AppSettings.setDark),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: Theme(data: ThemeData.light(), child: const CrashReportBanner()),
          ),
        ),
        const SliverPadding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
          sliver: SliverToBoxAdapter(child: _UploadCard()),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 30, 20, 12),
          sliver: SliverToBoxAdapter(
            child: SectionTitle(
              'مشاريع القرآن الأخيرة',
              trailing: IconButton(
                tooltip: 'كل المشاريع',
                onPressed: onSeeAll,
                icon: Icon(Icons.more_horiz_rounded, color: p.textMuted, size: 30),
              ),
            ),
          ),
        ),
        const _RecentList(limit: 4),
        const SliverToBoxAdapter(child: SizedBox(height: 120)),
      ],
    );
  }
}

class _UploadCard extends StatelessWidget {
  const _UploadCard();

  @override
  Widget build(BuildContext context) {
    final p = AyahPalette.of(context);
    return CustomPaint(
      painter: DashedBorderPainter(color: p.accent.withValues(alpha: 0.75)),
      child: Container(
        padding: const EdgeInsets.fromLTRB(22, 28, 22, 24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: p.dark
                ? [const Color(0x14FFFFFF), const Color(0x05FFFFFF)]
                : [const Color(0x99FFFFFF), const Color(0x55FFFFFF)],
          ),
        ),
        child: Column(
          children: [
            ShaderMask(
              shaderCallback: (r) => AyahColors.goldVertical.createShader(r),
              child: const Icon(Icons.cloud_upload_outlined, size: 84, color: Colors.white),
            ),
            const SizedBox(height: 14),
            GoldButton(
              label: 'تحميل الملف',
              height: 60,
              fontSize: 21,
              onPressed: () => ProjectLauncher.pickFromGallery(context),
            ),
            const SizedBox(height: 14),
            Text('ارفع مقطع قرآن لإضافة الآيات والتفسير',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: kUiFont, fontSize: 15, color: p.accentText)),
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: () => ProjectLauncher.recordFromCamera(context),
              icon: const Icon(Icons.videocam_outlined, size: 20),
              label: const Text('أو صوّر مقطع هلأ'),
            ),
          ],
        ),
      ),
    );
  }
}

/// قائمة المشاريع (بتسمع لـ [AppSettings.projectsRevision]).
class _RecentList extends StatefulWidget {
  final int? limit;
  const _RecentList({this.limit});

  @override
  State<_RecentList> createState() => _RecentListState();
}

class _RecentListState extends State<_RecentList> {
  List<RecentProject>? _items;

  @override
  void initState() {
    super.initState();
    AppSettings.projectsRevision.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    AppSettings.projectsRevision.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    List<RecentProject> all;
    try {
      final store = await AppSettings.projects();
      all = await store.list();
    } catch (_) {
      all = const [];
    }
    if (mounted) setState(() => _items = all);
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    if (items == null) {
      return const SliverToBoxAdapter(
        child: Padding(padding: EdgeInsets.all(30), child: Center(child: GoldLoader())),
      );
    }
    if (items.isEmpty) {
      return const SliverPadding(
        padding: EdgeInsets.symmetric(horizontal: 20),
        sliver: SliverToBoxAdapter(child: _EmptyProjects()),
      );
    }
    final shown = widget.limit == null ? items : items.take(widget.limit!).toList();
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      sliver: SliverList.separated(
        itemCount: shown.length,
        separatorBuilder: (_, __) => const SizedBox(height: 14),
        itemBuilder: (_, i) => ProjectCard(project: shown[i], highlight: i == 0),
      ),
    );
  }
}

class _EmptyProjects extends StatelessWidget {
  const _EmptyProjects();

  @override
  Widget build(BuildContext context) {
    final p = AyahPalette.of(context);
    return GlassCard(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      child: Column(
        children: [
          Opacity(
            opacity: 0.55,
            child: Image.asset('assets/branding/logo_wave.png', height: 46),
          ),
          const SizedBox(height: 14),
          Text('ما في مشاريع لسا',
              style: TextStyle(
                  fontFamily: kUiFont, fontSize: 17, fontWeight: FontWeight.w700, color: p.text)),
          const SizedBox(height: 6),
          Text('أول مقطع بترفعه رح يطلع هون، وبترجع تكمّل عليه وقت ما بدك.',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: kUiFont, fontSize: 13, color: p.textMuted)),
        ],
      ),
    );
  }
}

/// بطاقة مشروع: اسم السورة، الآيات، موجة، زر تشغيل، ووسوم.
class ProjectCard extends StatelessWidget {
  final RecentProject project;
  final bool highlight;
  const ProjectCard({super.key, required this.project, this.highlight = false});

  String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'هلأ';
    if (d.inHours < 1) return 'قبل ${toArabicDigits('${d.inMinutes}')} د';
    if (d.inDays < 1) return 'قبل ${toArabicDigits('${d.inHours}')} س';
    if (d.inDays < 30) return 'قبل ${toArabicDigits('${d.inDays}')} يوم';
    return '${toArabicDigits('${t.year}')}/${toArabicDigits('${t.month}')}/${toArabicDigits('${t.day}')}';
  }

  String _dur(double s) {
    final t = s.round();
    return toArabicDigits('${t ~/ 60}:${(t % 60).toString().padLeft(2, '0')}');
  }

  Future<void> _menu(BuildContext context) async {
    final ok = await showAyahDialog<bool>(
      context,
      (ctx) => AlertDialog(
        title: const Text('شيل المشروع من القائمة؟'),
        content: const Text('الفيديو الأصلي ما بينمسح من الجوال.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('شيله')),
        ],
      ),
    );
    if (ok != true) return;
    final store = await AppSettings.projects();
    await store.remove(project.id);
    AppSettings.projectsChanged();
  }

  @override
  Widget build(BuildContext context) {
    final p = AyahPalette.of(context);
    final wave = project.wave.isEmpty ? List<double>.filled(40, 0.3) : project.wave;
    return GlassCard(
      highlight: highlight,
      padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
      onTap: () => ProjectLauncher.openRecent(context, project),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(project.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontFamily: 'Amiri',
                        fontSize: 24,
                        height: 1.4,
                        fontWeight: FontWeight.w700,
                        color: p.text)),
                Text('${project.subtitle}  •  ${_dur(project.durationSeconds)}  •  ${_ago(project.updatedAt)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontFamily: kUiFont, fontSize: 12, color: p.textMuted)),
                const SizedBox(height: 10),
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: WaveBars(
                    levels: wave,
                    height: 38,
                    color: highlight ? AyahColors.gold : p.accent.withValues(alpha: 0.75),
                  ),
                ),
                const SizedBox(height: 10),
                const Row(children: [
                  AyahTag('الآيات'),
                  SizedBox(width: 8),
                  AyahTag('التفسير', gold: false),
                ]),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkResponse(
                onTap: () => _menu(context),
                radius: 22,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: p.dark ? const Color(0x22FFFFFF) : const Color(0x11000000),
                  ),
                  child: Icon(Icons.delete_outline_rounded, size: 20, color: p.textMuted),
                ),
              ),
              const SizedBox(height: 22),
              RoundIconButton(
                icon: Icons.play_arrow_rounded,
                gold: true,
                size: 52,
                tooltip: 'افتح بالمحرر',
                onPressed: () => ProjectLauncher.openRecent(context, project),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// كل المشاريع.
class ProjectsPage extends StatelessWidget {
  const ProjectsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final p = AyahPalette.of(context);
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 6),
          sliver: SliverToBoxAdapter(
            child: Text('مشاريعي',
                style: TextStyle(
                    fontFamily: kUiFont, fontSize: 28, fontWeight: FontWeight.w700, color: p.text)),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
          sliver: SliverToBoxAdapter(
            child: Text('كل مقطع حلّلته، مع تعديلاتك عليه. اكبس عليه لترجع للمحرر.',
                style: TextStyle(fontFamily: kUiFont, fontSize: 13, color: p.textMuted)),
          ),
        ),
        const _RecentList(),
        const SliverToBoxAdapter(child: SizedBox(height: 120)),
      ],
    );
  }
}

/// الإعدادات: الوضع، عن التطبيق، وأدوات المطوّر (زر تجربة التعرف ويوم 4–5).
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _dev = false;
  Future<String>? _dbCheck;

  Future<String> _checkDb() async {
    final db = await QuranDatabase.instance.database;
    final surahs = await QuranDatabase.instance.allSurahs();
    final row = await db.rawQuery('SELECT COUNT(*) AS c FROM ayahs');
    List<String> match;
    try {
      match = await QuranMatcherService.instance.selfCheck();
    } catch (e) {
      match = ['خطأ: $e'];
    }
    return '${surahs.length} سورة، ${row.first['c']} آية.\n${match.join('\n')}';
  }

  @override
  Widget build(BuildContext context) {
    final p = AyahPalette.of(context);
    Widget tile(IconData icon, String title, String? sub, {Widget? trailing, VoidCallback? onTap}) =>
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 6),
          leading: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AyahColors.gold.withValues(alpha: 0.14),
            ),
            child: Icon(icon, color: p.accentText, size: 22),
          ),
          title: Text(title),
          subtitle: sub == null ? null : Text(sub),
          trailing: trailing,
          onTap: onTap,
        );
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 130),
      children: [
        Text('الإعدادات',
            style: TextStyle(
                fontFamily: kUiFont, fontSize: 28, fontWeight: FontWeight.w700, color: p.text)),
        const SizedBox(height: 18),
        GlassCard(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
          child: Column(
            children: [
              ValueListenableBuilder<bool>(
                valueListenable: AppSettings.dark,
                builder: (_, dark, __) => tile(
                  dark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                  'المظهر',
                  dark ? 'ليلي' : 'نهاري',
                  trailing: ThemeModeToggle(dark: dark, onChanged: AppSettings.setDark),
                ),
              ),
              const Divider(height: 1),
              tile(Icons.translate_rounded, 'لغة الواجهة', 'العربية (باقي اللغات قريباً)'),
              const Divider(height: 1),
              tile(Icons.menu_book_rounded, 'مصادر النص والتفسير',
                  'الرسم العثماني (مجمع الملك فهد عبر Tanzil) • التفسير الميسر',
                  onTap: () => showLicensePage(
                      context: context, applicationName: 'آية ستوديو', applicationVersion: '0.1.0')),
            ],
          ),
        ),
        const SizedBox(height: 16),
        GlassCard(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
          child: Column(
            children: [
              tile(Icons.developer_mode_rounded, 'أدوات المطوّر',
                  'تجربة التعرف على الصوت وفحص قاعدة البيانات',
                  trailing: Switch(value: _dev, onChanged: (v) => setState(() => _dev = v))),
            ],
          ),
        ),
        if (_dev) ...[
          const SizedBox(height: 16),
          Theme(
            data: ThemeData.light(useMaterial3: true),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FutureBuilder<String>(
                      future: _dbCheck ??= _checkDb(),
                      builder: (_, s) => Text(
                        s.hasError
                            ? 'خطأ بقاعدة البيانات: ${s.error}'
                            : (s.data ?? 'جاري فحص قاعدة البيانات…'),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const AsrDebugPanel(),
                  ],
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 28),
        Center(child: Opacity(opacity: 0.8, child: const AyahLogo(size: 90))),
        const SizedBox(height: 6),
        Center(
          child: Text('آية ستوديو • نسخة تجريبية',
              style: TextStyle(fontFamily: kUiFont, fontSize: 12, color: p.textMuted)),
        ),
      ],
    );
  }
}
