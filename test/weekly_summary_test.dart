import 'package:flutter_test/flutter_test.dart';
import 'package:mindstock/logic/weekly_summary.dart';
import 'package:mindstock/models/models.dart';

void main() {
  DiaryEntry entry(String date, List<LifeEvent> events, {double? mood}) =>
      DiaryEntry(date: date, text: 'test', events: events, moodScore: mood);

  LifeEvent ev(
    String name,
    double weight, {
    bool positive = true,
    EventKind kind = EventKind.daily,
  }) => LifeEvent(name: name, kind: kind, isPositive: positive, weight: weight);

  group('WeeklySummary.compute', () {
    test('週の開始は月曜。週内どの日を渡しても同じ週になる', () {
      // 2026-01-05 は月曜
      final a = WeeklySummary.compute(DateTime(2026, 1, 5), {});
      final b = WeeklySummary.compute(DateTime(2026, 1, 11), {}); // 日曜
      expect(a.weekStart, DateTime(2026, 1, 5));
      expect(b.weekStart, DateTime(2026, 1, 5));
      expect(a.weekEnd, DateTime(2026, 1, 11));
    });

    test('変動合計・記録日数・プラス/マイナス日数を集計する', () {
      final entries = {
        '2026-01-05': entry('2026-01-05', [ev('良い日', 3)]),
        '2026-01-07': entry('2026-01-07', [ev('悪い日', 5, positive: false)]),
        '2026-01-09': entry('2026-01-09', [], mood: 10), // +2.0
      };
      final s = WeeklySummary.compute(DateTime(2026, 1, 5), entries);

      expect(s.entryDays, 3);
      expect(s.calmDays, 4);
      expect(s.upDays, 2);
      expect(s.downDays, 1);
      expect(s.totalDelta, closeTo(3 - 5 + 2.0, 1e-9));
    });

    test('ベスト/ワーストの出来事を選ぶ', () {
      final entries = {
        '2026-01-05': entry('2026-01-05', [
          ev('小さな喜び', 1),
          ev('大きな喜び', 6),
        ]),
        '2026-01-06': entry('2026-01-06', [ev('つらい出来事', 4, positive: false)]),
      };
      final s = WeeklySummary.compute(DateTime(2026, 1, 5), entries);
      expect(s.best?.name, '大きな喜び');
      expect(s.worst?.name, 'つらい出来事');
    });

    test('記録ゼロの週は静かな週のヘッドライン', () {
      final s = WeeklySummary.compute(DateTime(2026, 1, 5), {});
      expect(s.entryDays, 0);
      expect(s.headline, contains('静かな週'));
    });

    test('節目がある週はヘッドラインに出来事名が入る', () {
      final entries = {
        '2026-01-06': entry('2026-01-06', [
          ev('第一志望に合格', 8, kind: EventKind.milestone),
        ]),
      };
      final s = WeeklySummary.compute(DateTime(2026, 1, 5), entries);
      expect(s.hasMilestone, isTrue);
      expect(s.headline, contains('第一志望に合格'));
    });

    test('大きく沈んだ週でもポジティブの瞬間を拾う', () {
      final entries = {
        '2026-01-05': entry('2026-01-05', [ev('退職勧告', 7, positive: false)]),
        '2026-01-07': entry('2026-01-07', [ev('友人の励まし', 2)]),
      };
      final s = WeeklySummary.compute(DateTime(2026, 1, 5), entries);
      expect(s.totalDelta, lessThan(-3));
      expect(s.headline, contains('友人の励まし'));
    });
  });
}
