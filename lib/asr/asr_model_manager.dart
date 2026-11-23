import 'dart:io';

import 'file_downloader.dart';

/// مسارات ملفات محرك التعرف بعد ما تكون نازلة ومتحقق منها.
class AsrModelPaths {
  final String model;
  final String tokens;
  final String vad;
  const AsrModelPaths(
      {required this.model, required this.tokens, required this.vad});
}

class AsrModelFile {
  final String name;
  final String sha256;
  final int bytes;
  const AsrModelFile(this.name, this.sha256, this.bytes);
}

/// تقدّم تجهيز النموذج (كل الملفات مع بعض).
class ModelDownloadProgress {
  final String file;
  final int fileIndex; // من 1
  final int fileCount;
  final int received; // كل الملفات
  final int total;
  const ModelDownloadProgress(
      this.file, this.fileIndex, this.fileCount, this.received, this.total);
  double get fraction => total == 0 ? 0 : (received / total).clamp(0.0, 1.0);
  @override
  String toString() =>
      '$file ($fileIndex/$fileCount) ${(received / 1e6).toStringAsFixed(1)}/'
      '${(total / 1e6).toStringAsFixed(1)}MB';
}

/// أوقات تجهيز النموذج (يوم 5)، عشان شاشة أول استخدام تحكي شو عم بيصير.
class ModelSetupReport {
  /// كان جاهز (ملف .verified + الأحجام)، بدون تحميل ولا hashing.
  bool alreadyReady = false;
  int checkMs = 0; // فحص isReady
  int sumsMs = 0; // تحميل SHA256SUMS
  int downloadMs = 0; // تحميل الملفات (بدون التحقق)
  int verifyMs = 0; // SHA256 لكل الملفات
  int downloadedBytes = 0;
  int get totalMs => checkMs + sumsMs + downloadMs + verifyMs;
  @override
  String toString() => alreadyReady
      ? 'جاهز (فحص ${checkMs}ms)'
      : 'فحص ${checkMs}ms + SHA256SUMS ${sumsMs}ms + تحميل '
          '${(downloadedBytes / 1e6).toStringAsFixed(1)}MB ${downloadMs}ms + '
          'تحقق SHA256 ${verifyMs}ms';
}

/// مدير ملفات المحرك (يوم 4): بينزّل ملفات الـ Release `asr-model-v1`
/// **مرة وحدة** لمجلد التطبيق، وبيتحقق من SHA256 حسب ملف `SHA256SUMS`
/// (ومن نسخة مثبّتة بالكود كمان، عشان ما حدا يقدر يبدّل الملفات بالـ
/// Release)، وبعدها كل شي offline.
///
/// Dart صافي: المجلد بينمرّر من برا (بالتطبيق: getApplicationSupportDirectory).
class AsrModelManager {
  static const releaseTag = 'asr-model-v1';
  static const releaseBase =
      'https://github.com/a-n-a2s/quran-dub-android/releases/download/$releaseTag/';

  /// نفس محتوى SHA256SUMS بالـ Release.
  static const files = [
    AsrModelFile('model.int8.onnx',
        '58de6db034bb4f6516b3bc1c68e7a0ac4e77abffe603a550ee87b39dcd0c7ac6', 18850806),
    AsrModelFile('tokens.txt',
        '75b53814499cee84a07c7b7a318524d30bcaf84273c0f8b28a04176023e8c74f', 180),
    AsrModelFile('silero_vad.onnx',
        '9e2449e1087496d8d4caba907f23e0bd3f78d91fa552479bb9c23ac09cbb1fd6', 643854),
  ];

  /// مقطع اختبار (الفاتحة، العفاسي، WAV 16kHz mono، 46 ثانية). للتطوير بس.
  static const testClip = AsrModelFile('test_fatiha_alafasy_16k.wav',
      'abbc2dc59d597c4a5e84689a7195b97479de34df1ce5e1ccbfe70a780de128d3', 1475996);

  static int get totalBytes => files.fold(0, (s, f) => s + f.bytes);

  final Directory dir;
  AsrModelManager(Directory baseDir)
      : dir = Directory('${baseDir.path}${Platform.pathSeparator}$releaseTag');

  File _file(String name) => File('${dir.path}${Platform.pathSeparator}$name');
  File get _marker => _file('.verified');

  AsrModelPaths get paths => AsrModelPaths(
        model: _file('model.int8.onnx').path,
        tokens: _file('tokens.txt').path,
        vad: _file('silero_vad.onnx').path,
      );

  String get _markerContent =>
      files.map((f) => '${f.sha256}  ${f.name}  ${f.bytes}').join('\n');

  /// سريع (بدون hashing): الملفات موجودة بأحجامها وفي علامة تحقق سابق.
  Future<bool> isReady() async {
    if (!await _marker.exists()) return false;
    if (await _marker.readAsString() != _markerContent) return false;
    for (final f in files) {
      final file = _file(f.name);
      if (!await file.exists() || await file.length() != f.bytes) return false;
    }
    return true;
  }

  /// بيرجع المسارات، وبينزّل اللي ناقص/خربان أول مرة بس.
  /// أوقات آخر [ensureReady].
  ModelSetupReport lastReport = ModelSetupReport();

  Future<AsrModelPaths> ensureReady(
      {void Function(ModelDownloadProgress)? onProgress}) async {
    final report = lastReport = ModelSetupReport();
    final sw = Stopwatch()..start();
    if (await isReady()) {
      report
        ..alreadyReady = true
        ..checkMs = sw.elapsedMilliseconds;
      return paths;
    }
    report.checkMs = sw.elapsedMilliseconds;
    await dir.create(recursive: true);

    // 1) SHA256SUMS من الـ Release، ولازم يطابق النسخة المثبّتة بالكود.
    final sumsFile = _file('SHA256SUMS');
    sw.reset();
    await downloadFile(Uri.parse('${releaseBase}SHA256SUMS'), sumsFile);
    report.sumsMs = sw.elapsedMilliseconds;
    final sums = parseSha256Sums(await sumsFile.readAsString());
    for (final f in files) {
      if (sums[f.name] != f.sha256) {
        throw DownloadException('SHA256SUMS بالـ Release ما بيطابق التطبيق '
            'لـ ${f.name} (${sums[f.name]})');
      }
    }

    // 2) كل ملف: لو موجود وسليم منخليه، وإلا بنزّله.
    final total = totalBytes;
    var done = 0;
    for (var i = 0; i < files.length; i++) {
      final f = files[i];
      final file = _file(f.name);
      var ok = await file.exists() && await file.length() == f.bytes;
      if (ok) {
        sw.reset();
        ok = await sha256OfFile(file) == f.sha256;
        report.verifyMs += sw.elapsedMilliseconds;
      }
      if (!ok) {
        final base = done;
        var verify = 0;
        sw.reset();
        await downloadFile(
          Uri.parse('$releaseBase${f.name}'),
          file,
          expectedSha256: sums[f.name],
          onVerified: (ms) => verify += ms,
          onProgress: (r, _) => onProgress?.call(
              ModelDownloadProgress(f.name, i + 1, files.length, base + r, total)),
        );
        report.downloadMs += sw.elapsedMilliseconds - verify;
        report.verifyMs += verify;
        report.downloadedBytes += f.bytes;
      }
      done += f.bytes;
      onProgress?.call(
          ModelDownloadProgress(f.name, i + 1, files.length, done, total));
    }
    await _marker.writeAsString(_markerContent, flush: true);
    return paths;
  }

  /// مقطع الاختبار (بيتحمّل مرة وحدة كمان، مع تحقق SHA256).
  Future<String> ensureTestClip({DownloadProgress? onProgress}) async {
    final file = _file(testClip.name);
    if (await file.exists() && await file.length() == testClip.bytes) {
      return file.path;
    }
    await downloadFile(Uri.parse('$releaseBase${testClip.name}'), file,
        expectedSha256: testClip.sha256, onProgress: onProgress);
    return file.path;
  }
}

/// `sha256  name` لكل سطر (صيغة sha256sum).
Map<String, String> parseSha256Sums(String text) {
  final out = <String, String>{};
  for (final line in text.split('\n')) {
    final m = RegExp(r'^([0-9a-fA-F]{64})\s+\*?(.+?)\s*$').firstMatch(line);
    if (m != null) out[m.group(2)!] = m.group(1)!.toLowerCase();
  }
  return out;
}
