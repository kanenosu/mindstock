import 'package:flutter_test/flutter_test.dart';
import 'package:mindstock/models/models.dart';

void main() {
  group('LifeEvent', () {
    test('delta は方向×重み', () {
      const pos = LifeEvent(
        name: 'x',
        kind: EventKind.daily,
        isPositive: true,
        weight: 8,
      );
      expect(pos.delta, 8);
      expect(pos.copyWith(isPositive: false).delta, -8);
    });

    test('fromJson は weight を 0〜300 にクランプする', () {
      // 新スケール（節目で200超あり）を許容しつつ、異常な巨大値は抑える
      final big = LifeEvent.fromJson({
        'name': '合格',
        'kind': 'milestone',
        'isPositive': true,
        'weight': 999,
      });
      expect(big.weight, 300);

      final normal = LifeEvent.fromJson({
        'name': '褒められ',
        'kind': 'daily',
        'isPositive': true,
        'weight': 8.4,
      });
      expect(normal.weight, 8.4);
    });

    test('JSON round-trip で全フィールドが保たれる', () {
      const e = LifeEvent(
        name: '失恋',
        kind: EventKind.milestone,
        isPositive: false,
        weight: 150.1,
      );
      final restored = LifeEvent.fromJson(e.toJson());
      expect(restored.name, e.name);
      expect(restored.kind, e.kind);
      expect(restored.isPositive, e.isPositive);
      expect(restored.weight, e.weight);
    });

    test('未知の kind は daily にフォールバックする', () {
      final e = LifeEvent.fromJson({
        'name': 'x',
        'kind': 'unknown_kind',
        'isPositive': true,
        'weight': 1,
      });
      expect(e.kind, EventKind.daily);
    });
  });

  group('DiaryEntry', () {
    test('DBマップの round-trip で本文・気分・出来事が保たれる', () {
      const entry = DiaryEntry(
        date: '2026-07-16',
        text: '今日は合格した。\n嬉しい。',
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
      final restored = DiaryEntry.fromDbMap(entry.toDbMap());
      expect(restored.date, entry.date);
      expect(restored.text, entry.text);
      expect(restored.moodScore, entry.moodScore);
      expect(restored.events, hasLength(1));
      expect(restored.events.first.name, '合格');
      expect(restored.events.first.weight, 107.3);
    });

    test('events_json が空でも壊れない', () {
      final restored = DiaryEntry.fromDbMap({
        'date': '2026-07-16',
        'text': '',
        'mood_score': null,
        'events_json': '[]',
      });
      expect(restored.events, isEmpty);
      expect(restored.moodScore, isNull);
    });
  });
}
