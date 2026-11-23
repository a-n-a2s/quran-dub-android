import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../matching/arabic_normalizer.dart';
import '../matching/quran_matcher.dart';
import 'models/ayah.dart';
import 'models/surah.dart';

/// يدير قاعدة بيانات القرآن والتفسير المحلية (SQLite عبر sqflite).
///
/// البيانات الخام (نص القرآن بالرسم العثماني + التفسير الميسر + معلومات
/// الجزء/الصفحة) موجودة مضغوطة (gzip) بمجلد الأصول assets/quran، وبتتحمّل
/// وتتفرّغ بقاعدة بيانات SQLite محلية **مرة واحدة فقط** أول ما يفتح المستخدم
/// التطبيق. بعد هيك كل القراءة بتصير من القاعدة المحلية مباشرة، بدون أي
/// حاجة للملف الأصلي أو للإنترنت.
class QuranDatabase {
  QuranDatabase._internal();
  static final QuranDatabase instance = QuranDatabase._internal();

  static const String _dbFileName = 'quran.db';
  /// v1: يوم 2 (text_uthmani + tafsir_muyassar + معلومات مساعدة).
  /// v2: يوم 3 — عمود text_simple (نص مبسّط بدون تشكيل، للبحث والمطابقة).
  static const int _dbVersion = 2;
  static const String _seedAssetPath = 'assets/quran/quran_data.json.gz';

  Database? _database;

  /// يرجّع نسخة قاعدة البيانات المفتوحة، وبيبنيها وبيعبيها بالبيانات لو
  /// هاي أول مرة (lazy init + seed مرة وحدة).
  Future<Database> get database async {
    final existing = _database;
    if (existing != null) return existing;
    final opened = await _openAndSeed();
    _database = opened;
    return opened;
  }

  Future<Database> _openAndSeed() async {
    final directory = await getApplicationDocumentsDirectory();
    final dbPath = p.join(directory.path, _dbFileName);

    final db = await openDatabase(
      dbPath,
      version: _dbVersion,
      onCreate: (db, version) async {
        await _createSchema(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // ترقية بدون مسح البيانات الموجودة: نضيف العمود ونعبّيه من
          // text_uthmani الموجود أصلاً.
          await db.execute('ALTER TABLE ayahs ADD COLUMN text_simple TEXT');
          await _backfillSimpleText(db);
        }
      },
    );

    await _seedIfEmpty(db);
    return db;
  }

  Future<void> _createSchema(Database db) async {
    await db.execute('''
      CREATE TABLE surahs (
        number INTEGER PRIMARY KEY,
        name_ar TEXT NOT NULL,
        name_en TEXT NOT NULL,
        name_transliteration TEXT NOT NULL,
        ayah_count INTEGER NOT NULL,
        revelation_place TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE ayahs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        surah_number INTEGER NOT NULL,
        ayah_number INTEGER NOT NULL,
        text_uthmani TEXT NOT NULL,
        text_simple TEXT,
        tafsir_muyassar TEXT NOT NULL,
        juz INTEGER NOT NULL,
        page INTEGER NOT NULL,
        ruku INTEGER NOT NULL,
        manzil INTEGER NOT NULL,
        sajda INTEGER NOT NULL DEFAULT 0,
        UNIQUE(surah_number, ayah_number),
        FOREIGN KEY (surah_number) REFERENCES surahs (number)
      )
    ''');

    await db.execute('CREATE INDEX idx_ayahs_surah ON ayahs (surah_number)');
    await db.execute('CREATE INDEX idx_ayahs_page ON ayahs (page)');
    await db.execute('CREATE INDEX idx_ayahs_juz ON ayahs (juz)');
  }

  /// يتحقق هل القاعدة معبّاة أصلاً (لو التطبيق مفتوح قبل)، ولو فاضية
  /// بيقرأ ملف الأصول المضغوط ويعبّيها بـ batch واحدة داخل transaction.
  Future<void> _seedIfEmpty(Database db) async {
    final existingCount = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM ayahs'),
    );
    if (existingCount != null && existingCount > 0) {
      return; // القاعدة معبّاة من قبل، ما في داعي نعيد.
    }

    final bundle = await _loadSeedBundle();
    final surahs = bundle['surahs'] as List<dynamic>;
    final ayahs = bundle['ayahs'] as List<dynamic>;

    await db.transaction((txn) async {
      final batch = txn.batch();

      for (final raw in surahs) {
        final s = raw as Map<String, dynamic>;
        batch.insert('surahs', {
          'number': s['n'],
          'name_ar': s['ar'],
          'name_en': s['en'],
          'name_transliteration': s['tr'],
          'ayah_count': s['count'],
          'revelation_place': s['place'],
        });
      }

      for (final raw in ayahs) {
        final a = raw as Map<String, dynamic>;
        batch.insert('ayahs', {
          'surah_number': a['s'],
          'ayah_number': a['a'],
          'text_uthmani': a['t'],
          'text_simple': ArabicNormalizer.simple(a['t'] as String),
          'tafsir_muyassar': a['f'],
          'juz': a['j'],
          'page': a['p'],
          'ruku': a['r'],
          'manzil': a['m'],
          'sajda': (a['sj'] as bool) ? 1 : 0,
        });
      }

      await batch.commit(noResult: true);
    });
  }

  Future<void> _backfillSimpleText(Database db) async {
    final rows = await db.query('ayahs', columns: ['id', 'text_uthmani']);
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final r in rows) {
        batch.update(
          'ayahs',
          {'text_simple': ArabicNormalizer.simple(r['text_uthmani'] as String)},
          where: 'id = ?',
          whereArgs: [r['id']],
        );
      }
      await batch.commit(noResult: true);
    });
  }

  /// يقرأ ملف assets/quran/quran_data.json.gz، يفك ضغطه (gzip) ويحوّله
  /// لـ JSON. الملف الأصلي مصدره مشروع Tanzil (نص عثماني - CC BY 3.0) +
  /// تفسير الميسر الصادر عن مجمع الملك فهد لطباعة المصحف الشريف.
  Future<Map<String, dynamic>> _loadSeedBundle() async {
    final byteData = await rootBundle.load(_seedAssetPath);
    final compressedBytes = byteData.buffer.asUint8List(
      byteData.offsetInBytes,
      byteData.lengthInBytes,
    );
    final decompressedBytes = GZipCodec().decode(compressedBytes);
    final jsonString = utf8.decode(decompressedBytes);
    return json.decode(jsonString) as Map<String, dynamic>;
  }

  // ---------------------------------------------------------------------
  // استعلامات مساعدة، رح تُستخدم بشاشات العرض ومطابقة الصوت بالمراحل الجاية
  // ---------------------------------------------------------------------

  Future<List<Surah>> allSurahs() async {
    final db = await database;
    final rows = await db.query('surahs', orderBy: 'number ASC');
    return rows.map(Surah.fromMap).toList();
  }

  Future<List<Ayah>> ayahsOfSurah(int surahNumber) async {
    final db = await database;
    final rows = await db.query(
      'ayahs',
      where: 'surah_number = ?',
      whereArgs: [surahNumber],
      orderBy: 'ayah_number ASC',
    );
    return rows.map(Ayah.fromMap).toList();
  }

  Future<Ayah?> ayahAt(int surahNumber, int ayahNumber) async {
    final db = await database;
    final rows = await db.query(
      'ayahs',
      where: 'surah_number = ? AND ayah_number = ?',
      whereArgs: [surahNumber, ayahNumber],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Ayah.fromMap(rows.first);
  }

  /// بحث نصّي بسيط (LIKE). بيدوّر بالنص المبسّط (بدون تشكيل) عشان
  /// المستخدم يقدر يكتب "الحمد لله" عادي ويلاقي الآية.
  Future<List<Ayah>> searchAyahText(String query) async {
    final db = await database;
    final simpleQuery = ArabicNormalizer.simple(query);
    final rows = await db.query(
      'ayahs',
      where: 'text_simple LIKE ? OR text_uthmani LIKE ?',
      whereArgs: ['%$simpleQuery%', '%$query%'],
      limit: 20,
    );
    return rows.map(Ayah.fromMap).toList();
  }

  /// كل الآيات بالترتيب بالشكل اللي بيحتاجه [QuranMatcher].
  Future<List<MatchableAyah>> matchableAyahs() async {
    final db = await database;
    final rows = await db.query(
      'ayahs',
      columns: ['surah_number', 'ayah_number', 'text_uthmani'],
      orderBy: 'surah_number ASC, ayah_number ASC',
    );
    return [
      for (final r in rows)
        MatchableAyah(r['surah_number'] as int, r['ayah_number'] as int,
            r['text_uthmani'] as String),
    ];
  }

  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }
}
