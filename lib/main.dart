import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data/quran_database.dart';
import 'screens/home_screen.dart';
import 'ui/app_settings.dart';
import 'ui/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppSettings.load();
  // تجهيز قاعدة بيانات القرآن بالخلفية من أول فتح (بدل شاشة فحص).
  QuranDatabase.instance.database.ignore();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: AyahColors.deep,
  ));
  runApp(const QuranDubApp());
}

/// تطبيق "آية ستوديو – Ayah Studio" (اسم مبدئي)
/// يطابق أي فيديو فيه تلاوة قرآنية مع نص القرآن والتفسير الميسر تلقائياً.
class QuranDubApp extends StatelessWidget {
  const QuranDubApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AppSettings.dark,
      builder: (context, dark, _) => MaterialApp(
        title: 'آية ستوديو',
        debugShowCheckedModeBanner: false,
        theme: buildAyahTheme(dark: dark),
        // الواجهة عربي (يوم 14: 4 لغات واجهة).
        builder: (context, child) =>
            Directionality(textDirection: TextDirection.rtl, child: child!),
        home: const HomeShell(),
      ),
    );
  }
}
