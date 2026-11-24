import 'package:flutter_test/flutter_test.dart';
import 'package:quran_dub/export/export_status.dart';

void main() {
  test('التقدّم الكلي: تجهيز → ترميز → حفظ، دايماً بيزيد', () {
    var last = -1.0;
    for (final (phase, f) in [
      (ExportPhase.idle, 0.0),
      (ExportPhase.preparing, 0.0),
      (ExportPhase.preparing, 0.5),
      (ExportPhase.preparing, 1.0),
      (ExportPhase.encoding, 0.0),
      (ExportPhase.encoding, 0.37),
      (ExportPhase.encoding, 1.0),
      (ExportPhase.saving, 0.0),
      (ExportPhase.saving, 1.0),
      (ExportPhase.done, 1.0),
    ]) {
      final p = overallProgress(phase, f);
      expect(p, greaterThanOrEqualTo(last), reason: '$phase $f');
      expect(p, inInclusiveRange(0, 1));
      last = p;
    }
    expect(overallProgress(ExportPhase.done, 0), 1);
    expect(overallProgress(ExportPhase.encoding, 0.5),
        closeTo(preparingWeight + encodingWeight / 2, 1e-9));
    // قيم غريبة من الـ Kotlin.
    expect(overallProgress(ExportPhase.encoding, 7), overallProgress(ExportPhase.encoding, 1));
    expect(overallProgress(ExportPhase.encoding, double.nan), preparingWeight);
  });

  test('قراءة الحالة من الـ Kotlin (ExportHub)', () {
    final s = ExportStatus.fromMap({
      'id': 'exp1',
      'phase': 'done',
      'fraction': 1.0,
      'outputPath': null,
      'contentUri': 'content://media/external/video/media/12',
      'savedToGallery': true,
      'galleryPath': 'Movies/AyahStudio/x.mp4',
      'width': 1080,
      'height': 1920,
      'fileSizeBytes': 12345678,
      'durationMs': 58800,
      'elapsedMs': 41000,
      'videoEncoder': 'c2.qti.avc.encoder',
      'averageVideoBitrate': 7400000,
    });
    expect(s.phase, ExportPhase.done);
    expect(s.savedToGallery, isTrue);
    expect(s.width, 1080);
    expect(s.error, isNull);
    expect(s.progress, 1);
    expect(s.label, contains('خلص'));
  });

  test('الأخطاء بالعربي، وكود مش معروف = unknown', () {
    final s = ExportStatus.fromMap(
        {'id': 'e', 'phase': 'failed', 'error': 'noSpace', 'errorDetail': 'x'});
    expect(s.error, ExportErrorKind.noSpace);
    expect(s.label, contains('المساحة'));
    expect(ExportStatus.fromMap({'phase': 'failed', 'error': 'wat'}).error,
        ExportErrorKind.unknown);
    expect(ExportStatus.fromMap({'phase': 'whatever'}).phase, ExportPhase.idle);
    for (final k in ExportErrorKind.values) {
      expect(k.message, isNotEmpty);
    }
    expect(ExportErrorKind.encoderUnsupported.message, contains('ترميز'));
    expect(ExportStatus.fromMap({'phase': 'cancelled'}).label, contains('انلغى'));
  });

  test('مراحل شغّالة/خالصة', () {
    expect(ExportPhase.encoding.isRunning, isTrue);
    expect(ExportPhase.done.isRunning, isFalse);
    expect(ExportPhase.failed.isFinished, isTrue);
    expect(ExportPhase.idle.isFinished, isFalse);
  });

  test('حجم مقروء', () {
    expect(formatBytes(512 * 1024), '512KB');
    expect(formatBytes(12 * 1024 * 1024 + 300 * 1024), '12.3MB');
    expect(formatBytes(3 * 1024 * 1024 * 1024), '3.00GB');
  });
}
