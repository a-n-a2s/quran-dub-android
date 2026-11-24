import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../platform/video_exporter.dart';

/// بيعرض تقرير آخر انهيار/خروج غير طبيعي (لو في) مع زر نسخ وإخفاء.
/// تشخيص بعد بلاغ التصدير (يوم 8)؛ بيضل مفيد لحد التجارب النهائية.
class CrashReportBanner extends StatefulWidget {
  const CrashReportBanner({super.key});

  @override
  State<CrashReportBanner> createState() => _CrashReportBannerState();
}

class _CrashReportBannerState extends State<CrashReportBanner> {
  String? _report;

  @override
  void initState() {
    super.initState();
    VideoExporter.crashReport().then((r) {
      if (mounted && r != null && r.isNotEmpty) setState(() => _report = r);
    });
  }

  @override
  Widget build(BuildContext context) {
    final r = _report;
    if (r == null) return const SizedBox.shrink();
    return Card(
      color: Colors.red.shade50,
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('التطبيق طلع لحاله آخر مرة',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 160),
              child: SingleChildScrollView(
                child: SelectableText(r,
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(fontSize: 11)),
              ),
            ),
            const SizedBox(height: 8),
            Row(children: [
              FilledButton(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: r));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('اننسخ التقرير')));
                },
                child: const Text('نسخ التقرير'),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () async {
                  await VideoExporter.clearCrashReport();
                  if (mounted) setState(() => _report = null);
                },
                child: const Text('إخفاء'),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
