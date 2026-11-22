/// يمثّل سورة من سور القرآن الكريم (معلومات وصفية فقط، بدون نص الآيات).
class Surah {
  final int number; // رقم السورة (1-114)
  final String nameArabic; // الاسم بالعربي الكامل، مثلاً "سُوْرَةُ الْفَاتِحَةِ"
  final String nameEnglish; // الترجمة الإنجليزية للاسم، مثلاً "The Opening"
  final String nameTransliteration; // الاسم بالحروف اللاتينية، مثلاً "Al-Faatiha"
  final int ayahCount; // عدد آيات السورة
  final String revelationPlace; // "meccan" أو "medinan"

  const Surah({
    required this.number,
    required this.nameArabic,
    required this.nameEnglish,
    required this.nameTransliteration,
    required this.ayahCount,
    required this.revelationPlace,
  });

  bool get isMeccan => revelationPlace == 'meccan';

  factory Surah.fromMap(Map<String, Object?> map) {
    return Surah(
      number: map['number'] as int,
      nameArabic: map['name_ar'] as String,
      nameEnglish: map['name_en'] as String,
      nameTransliteration: map['name_transliteration'] as String,
      ayahCount: map['ayah_count'] as int,
      revelationPlace: map['revelation_place'] as String,
    );
  }
}
