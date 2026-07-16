import 'package:flutter_test/flutter_test.dart';
import 'package:mindstock/models/models.dart';
import 'package:mindstock/services/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  // sqflite はモバイル前提なので、VMテストでは ffi 実装に差し替える。
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late DatabaseService db;

  setUp(() async {
    db = DatabaseService();
    await db.deleteAll(); // 前のテストの残りをクリア
  });

  const entry = DiaryEntry(
    date: '2026-07-16',
    text: '合格した',
    moodScore: 7,
    events: [
      LifeEvent(
        name: '合格',
        kind: EventKind.milestone,
        isPositive: true,
        weight: 107.3,
      ),
    ],
  );

  test('upsert したエントリーを loadAll で読み戻せる', () async {
    await db.upsert(entry);
    final all = await db.loadAll();
    expect(all, hasLength(1));
    expect(all['2026-07-16']?.text, '合格した');
    expect(all['2026-07-16']?.moodScore, 7);
    expect(all['2026-07-16']?.events.first.weight, 107.3);
  });

  test('同じ日付の upsert は上書きになる', () async {
    await db.upsert(entry);
    await db.upsert(entry.copyWith(text: '書き直した'));
    final all = await db.loadAll();
    expect(all, hasLength(1));
    expect(all['2026-07-16']?.text, '書き直した');
  });

  test('delete で1件だけ消える', () async {
    await db.upsert(entry);
    await db.upsert(entry.copyWith(text: '別の日'));
    await db.upsert(const DiaryEntry(date: '2026-07-15', text: '前日'));
    await db.delete('2026-07-16');
    final all = await db.loadAll();
    expect(all.keys, ['2026-07-15']);
  });

  test('deleteAll で全消去できる', () async {
    await db.upsert(entry);
    await db.upsert(const DiaryEntry(date: '2026-07-15', text: '前日'));
    await db.deleteAll();
    expect(await db.loadAll(), isEmpty);
  });

  test('loadAll は日付昇順で返す', () async {
    await db.upsert(const DiaryEntry(date: '2026-07-16', text: 'b'));
    await db.upsert(const DiaryEntry(date: '2026-07-14', text: 'a'));
    await db.upsert(const DiaryEntry(date: '2026-07-18', text: 'c'));
    final all = await db.loadAll();
    expect(all.keys.toList(), ['2026-07-14', '2026-07-16', '2026-07-18']);
  });
}
