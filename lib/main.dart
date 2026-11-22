import 'package:flutter/material.dart';

void main() {
  runApp(const QuranDubApp());
}

/// تطبيق "تلاوة وتفسير" (اسم مؤقت)
/// يطابق أي فيديو فيه تلاوة قرآنية مع نص القرآن والتفسير الميسر تلقائياً.
class QuranDubApp extends StatelessWidget {
  const QuranDubApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'تلاوة وتفسير',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0E6B52)),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تلاوة وتفسير')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: Text(
            'مرحباً بك 👋\n'
            'هاي بداية مشروع تطبيق "تلاوة وتفسير".\n'
            'لسا الشغل عالهيكلة الأساسية، قاعدة بيانات القرآن والتفسير،\n'
            'ومطابقة الصوت جاية بالأيام الجاية.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16),
          ),
        ),
      ),
    );
  }
}
