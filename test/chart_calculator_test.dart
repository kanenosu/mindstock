import 'package:flutter_test/flutter_test.dart';
import 'package:mindstock/logic/chart_calculator.dart';
import 'package:mindstock/models/models.dart';

void main() {
  DiaryEntry entry(String date, List<LifeEvent> events, {double? mood}) =>
      DiaryEntry(date: date, text: 'test', events: events, moodScore: mood);

  LifeEvent ev(double weight, {bool positive = true}) => LifeEvent(
    name: 'e',
    kind: EventKind.daily,
    isPositive: positive,
    weight: weight,
  );

  group('dailyCandles', () {
    test('空のエントリーなら空のリスト', () {
      expect(ChartCalculator.dailyCandles({}), isEmpty);
    });

    test('今日の値 = 前日の値 + 出来事の合計（足し算モデル）', () {
      final entries = {
        '2026-01-01': entry('2026-01-01', [ev(3)]),
        '2026-01-02': entry('2026-01-02', [ev(2, positive: false)]),
      };
      final candles = ChartCalculator.dailyCandles(
        entries,
        until: DateTime(2026, 1, 2),
      );

      expect(candles, hasLength(2));
      final noise1 = ChartCalculator.noiseFor(DateTime(2026, 1, 1));
      final noise2 = ChartCalculator.noiseFor(DateTime(2026, 1, 2));

      expect(candles[0].open, ChartCalculator.baseValue);
      expect(
        candles[0].close,
        closeTo(ChartCalculator.baseValue + 3 + noise1, 1e-9),
      );
      // 前日終値が今日の始値になる
      expect(candles[1].open, candles[0].close);
      expect(candles[1].close, closeTo(candles[1].open - 2 + noise2, 1e-9));
    });

    test('高値はポジティブ積み上げ、安値はネガティブ積み上げ（ヒゲの表現）', () {
      final entries = {
        '2026-01-01': entry('2026-01-01', [
          ev(5),
          ev(3, positive: false),
        ]),
      };
      final c = ChartCalculator.dailyCandles(
        entries,
        until: DateTime(2026, 1, 1),
      ).single;
      final noise = ChartCalculator.noiseFor(DateTime(2026, 1, 1));
      final posNoise = noise >= 0 ? noise : 0;
      final negNoise = noise < 0 ? noise : 0;

      expect(c.high, closeTo(c.open + 5 + posNoise, 1e-9));
      expect(c.low, closeTo(c.open - 3 + negNoise, 1e-9));
      // マイナスを飛び越えてトータルでプラス（下ヒゲの長い陽線）
      expect(c.close, greaterThan(c.open));
      expect(c.high, greaterThanOrEqualTo(c.close));
      expect(c.low, lessThanOrEqualTo(c.open));
    });

    test('空白日は罰しない: 前の水準を維持した平穏な足になる', () {
      final entries = {
        '2026-01-01': entry('2026-01-01', [ev(3)]),
        // 1/2〜1/3 は空白
      };
      final candles = ChartCalculator.dailyCandles(
        entries,
        until: DateTime(2026, 1, 3),
      );
      expect(candles, hasLength(3));
      expect(candles[1].hasEntry, isFalse);
      expect(candles[2].hasEntry, isFalse);
      // 空白日の変動はノイズのみ（±noiseAmplitude以内）
      for (final c in candles.skip(1)) {
        expect(
          (c.close - c.open).abs(),
          lessThanOrEqualTo(ChartCalculator.noiseAmplitude),
        );
      }
    });

    test('気分スライダーはAI採点とスケールが揃った小さな揺れとして反映', () {
      final entries = {'2026-01-01': entry('2026-01-01', [], mood: 10)};
      final c = ChartCalculator.dailyCandles(
        entries,
        until: DateTime(2026, 1, 1),
      ).single;
      final noise = ChartCalculator.noiseFor(DateTime(2026, 1, 1));
      // mood 10 → (10-5)*0.4 = +2.0
      expect(c.close - c.open, closeTo(2.0 + noise, 1e-9));
    });

    test('ノイズは日付から決定的（再計算でチャートが変わらない）', () {
      final d = DateTime(2026, 3, 15);
      expect(ChartCalculator.noiseFor(d), ChartCalculator.noiseFor(d));
      expect(
        ChartCalculator.noiseFor(d).abs(),
        lessThanOrEqualTo(ChartCalculator.noiseAmplitude),
      );
    });
  });

  group('weeklyCandles', () {
    test('週足は 始値=週初、終値=週末、高値/安値=週間の極値', () {
      // 2026-01-05 は月曜
      final entries = {
        '2026-01-05': entry('2026-01-05', [ev(5)]),
        '2026-01-07': entry('2026-01-07', [ev(8, positive: false)]),
        '2026-01-12': entry('2026-01-12', [ev(1)]), // 翌週の月曜
      };
      final daily = ChartCalculator.dailyCandles(
        entries,
        until: DateTime(2026, 1, 12),
      );
      final weekly = ChartCalculator.weeklyCandles(daily);

      expect(weekly, hasLength(2));
      final w1 = weekly.first;
      expect(w1.date, DateTime(2026, 1, 5));
      expect(w1.open, daily.first.open);
      expect(w1.close, daily[6].close);
      expect(
        w1.high,
        daily.take(7).map((c) => c.high).reduce((a, b) => a > b ? a : b),
      );
      expect(
        w1.low,
        daily.take(7).map((c) => c.low).reduce((a, b) => a < b ? a : b),
      );
    });
  });

  group('monthlyCandles', () {
    test('月足は 始値=月初、終値=月末、高値/安値=月間の極値', () {
      final entries = {
        '2026-01-05': entry('2026-01-05', [ev(5)]),
        '2026-01-20': entry('2026-01-20', [ev(8, positive: false)]),
        '2026-02-03': entry('2026-02-03', [ev(2)]),
      };
      final daily = ChartCalculator.dailyCandles(
        entries,
        until: DateTime(2026, 2, 10),
      );
      final monthly = ChartCalculator.monthlyCandles(daily);

      expect(monthly, hasLength(2));
      expect(monthly.first.date, DateTime(2026, 1));
      expect(monthly.last.date, DateTime(2026, 2));

      final jan = daily.where((c) => c.date.month == 1).toList();
      expect(monthly.first.open, jan.first.open);
      expect(monthly.first.close, jan.last.close);
      expect(
        monthly.first.high,
        jan.map((c) => c.high).reduce((a, b) => a > b ? a : b),
      );
      expect(
        monthly.first.low,
        jan.map((c) => c.low).reduce((a, b) => a < b ? a : b),
      );
      // 月をまたいで終値が引き継がれる
      expect(monthly.last.open, monthly.first.close);
    });

    test('forTimeframe は時間軸に応じた足を返す', () {
      final entries = {'2026-01-05': entry('2026-01-05', [ev(1)])};
      final daily = ChartCalculator.dailyCandles(
        entries,
        until: DateTime(2026, 1, 12),
      );
      expect(ChartCalculator.forTimeframe(daily, Timeframe.daily), daily);
      expect(
        ChartCalculator.forTimeframe(daily, Timeframe.weekly).length,
        ChartCalculator.weeklyCandles(daily).length,
      );
      expect(
        ChartCalculator.forTimeframe(daily, Timeframe.monthly),
        hasLength(1),
      );
    });
  });

  group('movingAverage', () {
    test('期間未満は null、以降は直近N本の終値平均', () {
      final entries = {
        for (var d = 1; d <= 5; d++)
          '2026-01-0$d': entry('2026-01-0$d', [ev(1)]),
      };
      final daily = ChartCalculator.dailyCandles(
        entries,
        until: DateTime(2026, 1, 5),
      );
      final ma = ChartCalculator.movingAverage(daily, 3);

      expect(ma[0], isNull);
      expect(ma[1], isNull);
      expect(
        ma[2],
        closeTo((daily[0].close + daily[1].close + daily[2].close) / 3, 1e-9),
      );
      expect(
        ma[4],
        closeTo((daily[2].close + daily[3].close + daily[4].close) / 3, 1e-9),
      );
    });
  });

  group('changeSince', () {
    test('N日前の終値との差分。データ不足なら null', () {
      final entries = {
        '2026-01-01': entry('2026-01-01', [ev(3)]),
        '2026-01-02': entry('2026-01-02', [ev(2)]),
        '2026-01-03': entry('2026-01-03', [ev(1)]),
      };
      final daily = ChartCalculator.dailyCandles(
        entries,
        until: DateTime(2026, 1, 3),
      );
      expect(
        ChartCalculator.changeSince(daily, 1),
        closeTo(daily.last.close - daily[1].close, 1e-9),
      );
      expect(ChartCalculator.changeSince(daily, 30), isNull);
    });
  });
}
