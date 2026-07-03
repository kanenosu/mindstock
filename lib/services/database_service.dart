import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/models.dart';

/// ローカルDB（sqflite）。エントリーを日付キーで保存する。
class DatabaseService {
  static const _dbName = 'mindstock.db';
  static const _table = 'entries';

  Database? _db;

  Future<Database> get database async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dir = await getDatabasesPath();
    return openDatabase(
      join(dir, _dbName),
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_table (
            date TEXT PRIMARY KEY,
            text TEXT NOT NULL DEFAULT '',
            mood_score REAL,
            events_json TEXT NOT NULL DEFAULT '[]'
          )
        ''');
      },
    );
  }

  Future<Map<String, DiaryEntry>> loadAll() async {
    final db = await database;
    final rows = await db.query(_table, orderBy: 'date ASC');
    return {
      for (final row in rows) row['date'] as String: DiaryEntry.fromDbMap(row),
    };
  }

  Future<void> upsert(DiaryEntry entry) async {
    final db = await database;
    await db.insert(
      _table,
      entry.toDbMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> delete(String date) async {
    final db = await database;
    await db.delete(_table, where: 'date = ?', whereArgs: [date]);
  }
}
