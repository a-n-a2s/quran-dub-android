import 'package:flutter_test/flutter_test.dart';
import 'package:quran_dub/pipeline/project_input.dart';

VideoInfo info({
  int width = 1080,
  int height = 1920,
  int rotation = 0,
  int durationMs = 58800,
  double fps = 30,
  bool hasAudio = true,
}) =>
    VideoInfo(
      width: width,
      height: height,
      rotationDegrees: rotation,
      durationMs: durationMs,
      fps: fps,
      hasAudioTrack: hasAudio,
    );

void main() {
  group('VideoInfo: rotated dimensions', () {
    test('0°: عمودي زي ما هو', () {
      final v = info(width: 1080, height: 1920, rotation: 0);
      expect([v.rotatedWidth, v.rotatedHeight], [1080, 1920]);
      expect(v.orientation, VideoOrientation.portrait);
    });

    test('90°: الأبعاد بتنعكس (عمودي خام ← أفقي ظاهر)', () {
      final v = info(width: 1080, height: 1920, rotation: 90);
      expect([v.rotatedWidth, v.rotatedHeight], [1920, 1080]);
      expect(v.orientation, VideoOrientation.landscape);
    });

    test('180°: الأبعاد زي ما هي (مش معكوسة)', () {
      final v = info(width: 1080, height: 1920, rotation: 180);
      expect([v.rotatedWidth, v.rotatedHeight], [1080, 1920]);
      expect(v.orientation, VideoOrientation.portrait);
    });

    test('270°: الأبعاد بتنعكس', () {
      final v = info(width: 1920, height: 1080, rotation: 270);
      expect([v.rotatedWidth, v.rotatedHeight], [1080, 1920]);
      expect(v.orientation, VideoOrientation.portrait);
    });

    test('مربع: نفس العرض والارتفاع بأي دوران', () {
      final v = info(width: 1080, height: 1080, rotation: 90);
      expect([v.rotatedWidth, v.rotatedHeight], [1080, 1080]);
      expect(v.orientation, VideoOrientation.square);
    });

    test('دوران سلبي أو غريب بيترجع لأقرب 0/90/180/270', () {
      expect(info(rotation: -90).normalizedRotation, 270);
      expect(info(rotation: 450).normalizedRotation, 90);
      expect(info(rotation: 91).normalizedRotation, 90);
      expect(info(rotation: 0).normalizedRotation, 0);
    });

    test('toJson/fromJson رايح وجاي بدون فقدان', () {
      final v = info(rotation: 90, fps: 29.97, hasAudio: false);
      final back = VideoInfo.fromJson(v.toJson());
      expect(back.width, v.width);
      expect(back.height, v.height);
      expect(back.rotationDegrees, v.rotationDegrees);
      expect(back.durationMs, v.durationMs);
      expect(back.fps, v.fps);
      expect(back.hasAudioTrack, v.hasAudioTrack);
    });

    test('مقطع قصير جداً', () {
      expect(info(durationMs: 500).tooShort, isTrue);
      expect(info(durationMs: 58800).tooShort, isFalse);
      expect(info(durationMs: 0).tooShort, isFalse); // 0 = غير معروف
    });
  });

  group('ProjectInput: مصدر التعرف', () {
    test('بدون ملف منفصل: صوت الفيديو نفسه', () {
      final p = ProjectInput(
          videoPath: '/x/video.mp4', source: VideoSource.gallery, videoInfo: info());
      expect(p.recognitionSourcePath, '/x/video.mp4');
      expect(p.hasExternalAudio, isFalse);
    });

    test('ملف منفصل بس مش مفعّل: برجع لصوت الفيديو', () {
      final p = ProjectInput(
        videoPath: '/x/video.mp4',
        source: VideoSource.camera,
        videoInfo: info(),
        externalAudioPath: '/x/qari.mp3',
        useExternalAudio: false,
      );
      expect(p.recognitionSourcePath, '/x/video.mp4');
      expect(p.hasExternalAudio, isTrue);
    });

    test('ملف منفصل مفعّل: التعرف عليه', () {
      final p = ProjectInput(
              videoPath: '/x/video.mp4', source: VideoSource.gallery, videoInfo: info())
          .withExternalAudio('/x/qari.mp3');
      expect(p.recognitionSourcePath, '/x/qari.mp3');
      expect(p.useExternalAudio, isTrue);
    });

    test('withoutExternalAudio بيمسح الملف المنفصل والتفعيل', () {
      final p = ProjectInput(
              videoPath: '/x/video.mp4', source: VideoSource.gallery, videoInfo: info())
          .withExternalAudio('/x/qari.mp3')
          .withoutExternalAudio();
      expect(p.externalAudioPath, isNull);
      expect(p.useExternalAudio, isFalse);
      expect(p.recognitionSourcePath, '/x/video.mp4');
    });

    test('withUseExternalAudio بيتحكم بالتفعيل بس، وبيحتفظ بالمسار', () {
      final base = ProjectInput(
              videoPath: '/x/video.mp4', source: VideoSource.gallery, videoInfo: info())
          .withExternalAudio('/x/qari.mp3', use: false);
      expect(base.recognitionSourcePath, '/x/video.mp4');
      final on = base.withUseExternalAudio(true);
      expect(on.recognitionSourcePath, '/x/qari.mp3');
      expect(on.externalAudioPath, '/x/qari.mp3');
    });
  });
}
