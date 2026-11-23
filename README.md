# آية ستوديو – Ayah Studio (اسم مبدئي)

تطبيق أندرويد يطابق أي فيديو فيه تلاوة قرآنية (بأي صوت) مع نص القرآن الكامل
والتفسير الميسر تلقائياً وقت الرفع، بالتعرف على الصوت محلياً على الجوال
بدون سيرفر. يعرض الآية بالرسم العثماني وتحتها التفسير، متزامنين مع الصوت،
فوق الفيديو.

جزء من مشروع "تجارة".

- اسم الحزمة (applicationId): `com.ayahstudio.app` (نهائي، ما بيتغيّر بعد أول
  نشر). اسم حزمة Dart الداخلي (`quran_dub`) واسم المستودع بيضلّوا زي ما هم.

## بيانات القرآن والتفسير

التطبيق يحمل قاعدة بيانات القرآن الكامل (الرسم العثماني) والتفسير الميسر
محلياً داخل APK (مضغوطة بصيغة gzip بمجلد `assets/quran/`)، ويبنيها بقاعدة
SQLite محلية مرة واحدة فقط أول ما يفتح التطبيق. شوف
`assets/quran/SOURCES.md` لتفاصيل المصادر والترخيص، و
`lib/data/quran_database.dart` للكود.

## التعرف على التلاوة والمطابقة (يوم 3)

- **المحرك**: [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) + نموذج
  [`Abdou/quran-asr-tiny`](https://huggingface.co/Abdou/quran-asr-tiny)
  (Conformer-CTC مدرّب على التلاوة، int8، **19MB**، رخصة MIT) + Silero VAD
  لتقطيع الصوت على الوقفات. النموذج **مش جوا APK**: منشور كـ GitHub Release
  [`asr-model-v1`](https://github.com/a-n-a2s/quran-dub-android/releases/tag/asr-model-v1)
  والتطبيق رح ينزّله مرة وحدة وقت أول استخدام (الدمج على الجوال: يوم 4).
- **المطابقة** (`lib/matching/`، Dart صافي):
  - `arabic_normalizer.dart`: مفتاح رسم موحّد للعثماني والإملائي.
  - `quran_matcher.dart`: فهرس 4-gram + تصويت + محاذاة semi-global مع
    traceback → السورة/الآيات، نسبة التغطية، الثقة، موقع كل آية بالنص
    (للتوقيت)، والاستعاذة/البسملة.
  - `quran_sequence_matcher.dart`: Viterbi على كل مقاطع الفيديو مع بعض
    (بيحسم المقاطع القصيرة والآيات المكررة).
- **الاختبارات**: `flutter test test/matching` (بتشتغل بكل بناء).
- **النموذج الأولي**: `.github/workflows/asr-prototype.yml` بيشغّل المحرك
  على تلاوات حقيقية لعدة قرّاء وبيطبع النتيجة (`tool/match_transcripts.dart`).
  للتجربة محلياً: `tool/asr_prototype/` + `dart run tool/match_transcripts.dart`.

## التعرف على الجوال (يوم 4)

- **الباكج**: [`sherpa_onnx`](https://pub.dev/packages/sherpa_onnx) 2.0.3 (k2-fsa،
  Apache-2.0)، FFI على onnxruntime.
- `lib/asr/asr_model_manager.dart`: بينزّل ملفات الـ Release `asr-model-v1`
  (`model.int8.onnx`، `tokens.txt`، `silero_vad.onnx`، ~19.5MB) **مرة وحدة**
  لمجلد التطبيق، بيتحقق من SHA256 (ملف `SHA256SUMS` + نسخة مثبّتة بالكود)،
  بيعرض التقدّم، بيعيد المحاولة وبيكمّل من حيث وقف. بعدها كل شي offline.
- `lib/asr/asr_engine.dart`: `OfflineRecognizer` (zipformerCtc) + Silero VAD
  على صوت 16kHz mono، بـ isolate. لكل مقطع: النص + التوكنات + توقيت كل حرف.
- `lib/asr/wav_audio.dart`: قارئ WAV لأي sample rate/قنوات + تحويل لـ 16kHz.
  باقي الصيغ (mp3، m4a، ogg، flac، وفيديو) بتنفك على الجوال بـ MediaCodec
  (`AudioDecoder.kt` + `lib/asr/native_audio_decoder.dart`).
- `lib/asr/recitation_matcher.dart`: `QuranSequenceMatcher` + توقيت كل آية.
- **زر debug** "تجربة التعرف على الصوت" بالشاشة الرئيسية
  (`lib/debug/asr_debug_panel.dart`): بينزّل مقطع الفاتحة ويطبع لكل مقطع
  الوقت، السورة:الآية، الثقة، والـ RTF.
- **بالـ CI**: `tool/asr_engine_cli.dart` بيشغّل نفس كود `lib/asr/` على Linux
  (`asr-prototype.yml`)، و`flutter test test/asr`.
- **APK التجريبي**: arm64-v8a + armeabi-v7a بس، والمكتبات native مضغوطة.

## الحالة الحالية

شوف `claude/quran-dub-app-plan.md` بمشروع كلود "تطبيق القران" للخطة
الكاملة والحالة التفصيلية يوم بيوم.

## البناء

البناء التلقائي (GitHub Actions) ينتج APK تجريبي (debug) بكل رفعة (push)
على فرع `main`، ويرفعه كـ Artifact على الرفعة. شوف
`.github/workflows/build.yml`.

للبناء محلياً:

```bash
flutter pub get
flutter build apk --debug
```
