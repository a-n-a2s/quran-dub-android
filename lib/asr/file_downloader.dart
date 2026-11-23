import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// تقدّم تحميل ملف واحد: [received] بايت من [total] (null لو السيرفر ما
/// حكى الحجم).
typedef DownloadProgress = void Function(int received, int? total);

class DownloadException implements Exception {
  final String message;
  const DownloadException(this.message);
  @override
  String toString() => 'DownloadException: $message';
}

/// SHA256 لملف (hex صغير) بدون ما نحمّله كله بالذاكرة.
Future<String> sha256OfFile(File f) async =>
    (await sha256.bind(f.openRead()).first).toString();

/// تحميل ملف لـ [dest] مع:
/// - ملف مؤقت `.part` (ما بينحط بمكانه إلا لما يكمل ويتحقق)،
/// - **استكمال** من حيث وقف (Range) لو انقطع النت بالنص،
/// - **إعادة محاولة** [maxAttempts] مرات بانتظار متزايد (2، 4، 8 ثواني)،
/// - **تحقق SHA256** لو [expectedSha256] موجود (لو ما طابق بينمسح وبيعيد).
///
/// Dart صافي (dart:io)، فبيشتغل بالتطبيق وبأدوات سطر الأوامر والاختبارات.
Future<void> downloadFile(
  Uri url,
  File dest, {
  String? expectedSha256,
  DownloadProgress? onProgress,
  int maxAttempts = 4,
  Duration timeout = const Duration(seconds: 30),
}) async {
  await dest.parent.create(recursive: true);
  final part = File('${dest.path}.part');
  Object? lastError;
  for (var attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      await _downloadOnce(url, part, onProgress, timeout);
      if (expectedSha256 != null) {
        final got = await sha256OfFile(part);
        if (got != expectedSha256.toLowerCase()) {
          await part.delete();
          throw DownloadException(
              'SHA256 ما طابق لـ ${url.pathSegments.last}: '
              'المتوقع $expectedSha256، الموجود $got');
        }
      }
      if (await dest.exists()) await dest.delete();
      await part.rename(dest.path);
      return;
    } catch (e) {
      lastError = e;
      if (attempt == maxAttempts) break;
      await Future<void>.delayed(Duration(seconds: 1 << attempt));
    }
  }
  throw DownloadException(
      'فشل تحميل ${url.pathSegments.last} بعد $maxAttempts محاولات: $lastError');
}

Future<void> _downloadOnce(
    Uri url, File part, DownloadProgress? onProgress, Duration timeout) async {
  final client = HttpClient()..connectionTimeout = timeout;
  try {
    final existing = await part.exists() ? await part.length() : 0;
    final req = await client.getUrl(url).timeout(timeout);
    req.followRedirects = true;
    req.maxRedirects = 8;
    if (existing > 0) {
      req.headers.set(HttpHeaders.rangeHeader, 'bytes=$existing-');
    }
    final res = await req.close().timeout(timeout);
    int offset;
    if (res.statusCode == HttpStatus.partialContent) {
      offset = existing;
    } else if (res.statusCode == HttpStatus.ok) {
      offset = 0;
    } else if (res.statusCode == HttpStatus.requestedRangeNotSatisfiable &&
        existing > 0) {
      // الملف المؤقت غالباً كامل؛ التحقق (SHA256) هو اللي بيقرر.
      await res.drain<void>();
      return;
    } else {
      await res.drain<void>();
      throw DownloadException('HTTP ${res.statusCode} من $url');
    }
    final total = res.contentLength >= 0 ? res.contentLength + offset : null;
    final sink =
        part.openWrite(mode: offset > 0 ? FileMode.append : FileMode.write);
    var received = offset;
    onProgress?.call(received, total);
    try {
      await for (final chunk in res.timeout(timeout)) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
    } finally {
      await sink.flush();
      await sink.close();
    }
    if (total != null && received != total) {
      throw DownloadException('التحميل انقطع ($received من $total بايت)');
    }
  } finally {
    client.close(force: true);
  }
}
