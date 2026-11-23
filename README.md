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
