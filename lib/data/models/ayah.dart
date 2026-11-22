/// يمثّل آية واحدة: نصّها بالرسم العثماني + التفسير الميسر + معلومات مساعدة
/// (الجزء، الصفحة، الربع...) هاي المعلومات المساعدة رح تساعدنا بالمراحل
/// الجاية لما نطابق الصوت مع الآية الصحيحة (الجزء/الصفحة بيحصروا نطاق
/// البحث بدل ما نقارن مع كل القرآن).
class Ayah {
  final int surahNumber;
  final int ayahNumber;
  final String textUthmani; // نص الآية بالرسم العثماني مع الحركات
  final String tafsirMuyassar; // التفسير الميسر (مجمع الملك فهد)
  final int juz; // رقم الجزء (1-30)
  final int page; // رقم الصفحة بالمصحف المعتمد (مصحف المدينة، طبعة حفص)
  final int ruku; // رقم الربع/الركوع
  final int manzil; // رقم المنزل (تقسيم أسبوعي قديم)
  final bool isSajda; // آية فيها سجدة تلاوة

  const Ayah({
    required this.surahNumber,
    required this.ayahNumber,
    required this.textUthmani,
    required this.tafsirMuyassar,
    required this.juz,
    required this.page,
    required this.ruku,
    required this.manzil,
    required this.isSajda,
  });

  factory Ayah.fromMap(Map<String, Object?> map) {
    return Ayah(
      surahNumber: map['surah_number'] as int,
      ayahNumber: map['ayah_number'] as int,
      textUthmani: map['text_uthmani'] as String,
      tafsirMuyassar: map['tafsir_muyassar'] as String,
      juz: map['juz'] as int,
      page: map['page'] as int,
      ruku: map['ruku'] as int,
      manzil: map['manzil'] as int,
      isSajda: (map['sajda'] as int) == 1,
    );
  }
}
