// نصوص حقيقية من قاعدة البيانات (assets/quran) للاختبارات وتجربة التصدير
// بالمحاكي (integration_test/export_e2e_test.dart). يوم 8.
import 'package:quran_dub/pipeline/recitation_segment.dart';

const String ayah50_27a = 'قَالَ قَرِينُهُۥ رَبَّنَا مَآ أَطۡغَيۡتُهُۥ وَلَٰكِن';
const String ayah50_27b = 'كَانَ فِي ضَلَٰلِۭ بَعِيدࣲ';
const String ayah50_28 = 'قَالَ لَا تَخۡتَصِمُواْ لَدَيَّ وَقَدۡ قَدَّمۡتُ إِلَيۡكُم بِٱلۡوَعِيدِ';
const String tafsir50_27 = 'قال شيطانه الذي كان معه في الدنيا: ربنا ما أضللته، ولكن كان في طريق بعيد عن سبيل الهدى';
const String tafsir50_28 = 'قال الله تعالى: لا تختصموا لديَّ اليوم في موقف الجزاء والحساب؛ إذ لا فائدة من ذلك، وقد قَدَّمْتُ إليكم في الدنيا بالوعيد لمن كفر بي وعصاني';
const String ayah2_255 = 'ٱللَّهُ لَآ إِلَٰهَ إِلَّا هُوَ ٱلۡحَيُّ ٱلۡقَيُّومُۚ لَا تَأۡخُذُهُۥ سِنَةࣱ وَلَا نَوۡمࣱۚ لَّهُۥ مَا فِي ٱلسَّمَٰوَٰتِ وَمَا فِي ٱلۡأَرۡضِۗ مَن ذَا ٱلَّذِي يَشۡفَعُ عِندَهُۥٓ إِلَّا بِإِذۡنِهِۦۚ يَعۡلَمُ مَا بَيۡنَ أَيۡدِيهِمۡ وَمَا خَلۡفَهُمۡۖ وَلَا يُحِيطُونَ بِشَيۡءࣲ مِّنۡ عِلۡمِهِۦٓ إِلَّا بِمَا شَآءَۚ وَسِعَ كُرۡسِيُّهُ ٱلسَّمَٰوَٰتِ وَٱلۡأَرۡضَۖ وَلَا يَـُٔودُهُۥ حِفۡظُهُمَاۚ وَهُوَ ٱلۡعَلِيُّ ٱلۡعَظِيمُ';
const String tafsir2_255 = 'الله الذي لا يستحق الألوهية والعبودية إلا هو، الحيُّ الذي له جميع معاني الحياة الكاملة كما يليق بجلاله، القائم على كل شيء، لا تأخذه سِنَة أي: نعاس، ولا نوم، كل ما في السماوات وما في الأرض ملك له، ولا يتجاسر أحد أن يشفع عنده إلا بإذنه، محيط علمه بجميع الكائنات ماضيها وحاضرها ومستقبلها، يعلم ما بين أيدي الخلائق من الأمور المستقبلة، وما خلفهم من الأمور الماضية، ولا يَطَّلعُ أحد من الخلق على شيء من علمه إلا بما أعلمه الله وأطلعه عليه. وسع كرسيه السماوات والأرض، والكرسي: هو موضع قدمي الرب -جل جلاله- ولا يعلم كيفيته إلا الله سبحانه، ولا يثقله سبحانه حفظهما، وهو العلي بذاته وصفاته على جميع مخلوقاته، الجامع لجميع صفات العظمة والكبرياء. وهذه الآية أعظم آية في القرآن، وتسمى: (آية الكرسي)';

/// مقاطع زي مقطع أنس المرجعي (ق 50:27 جزئين + 50:28) بتوقيت [offset].
List<RecitationSegment> referenceSegments({double offset = 0}) => [
      RecitationSegment(
        start: offset + 0.2, end: offset + 2.0, kind: SegmentKind.partialAyah,
        surah: 50, ayah: 27, part: 1, partCount: 2, text: ayah50_27a,
        showAyahNumber: false, tafsir: tafsir50_27, tafsirFull: tafsir50_27,
        tafsirSplit: tafsir50_27, confidence: 0.9),
      RecitationSegment(
        start: offset + 2.0, end: offset + 3.6, kind: SegmentKind.partialAyah,
        surah: 50, ayah: 27, part: 2, partCount: 2, text: ayah50_27b,
        showAyahNumber: true, tafsir: tafsir50_27, tafsirFull: tafsir50_27,
        tafsirSplit: tafsir50_27, confidence: 0.9),
      RecitationSegment(
        start: offset + 3.6, end: offset + 5.4, kind: SegmentKind.fullAyah,
        surah: 50, ayah: 28, text: ayah50_28, showAyahNumber: true,
        tafsir: tafsir50_28, tafsirFull: tafsir50_28, tafsirSplit: tafsir50_28,
        confidence: 0.95),
    ];

/// آية الكرسي كاملة (كتلة طويلة بتتصغّر لتتسع).
RecitationSegment longSegment({double start = 0, double end = 5}) =>
    RecitationSegment(
        start: start, end: end, kind: SegmentKind.fullAyah, surah: 2,
        ayah: 255, text: ayah2_255, showAyahNumber: true,
        tafsir: tafsir2_255, tafsirFull: tafsir2_255, tafsirSplit: tafsir2_255,
        confidence: 1);
