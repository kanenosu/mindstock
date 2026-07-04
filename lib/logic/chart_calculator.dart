import 'dart:math';

import '../models/models.dart';

/// チャートの時間軸（株アプリと同じ切り替え、仕様書 §5）。
enum Timeframe {
  daily,
  weekly,
  monthly;

  String get label => switch (this) {
    Timeframe.daily => '日',
    Timeframe.weekly => '週',
    Timeframe.monthly => '月',
  };

  String get longLabel => switch (this) {
    Timeframe.daily => '日足',
    Timeframe.weekly => '週足',
    Timeframe.monthly => '月足',
  };

  /// 移動平均の期間（本数）。
  int get maPeriod => switch (this) {
    Timeframe.daily => 7,
    Timeframe.weekly => 4,
    Timeframe.monthly => 3,
  };
}

/// チャートロジック（仕様書 §4 AI委任型・足し算モデル）。
///
/// 今日の値 = 前日の値 + 今日の出来事の点数の合計。
/// ベースライン移動の機構は持たない（構造的にガクンガクンしない）。
/// 快楽順応・損失回避は AI の採点側に織り込む前提で、
/// ここでは受け取った点数を積むだけにする。
class ChartCalculator {
  /// チャートの基準値。株価指数のように 100 から始める。
  static const double baseValue = 100.0;

  /// 気分スライダー(0〜10)を変動値に変換する係数。
  /// スライダー5が中立、フルスイングで ±2 程度 = 小さな日常イベント相当に
  /// スケールを揃える（仕様書 §3 AI判定の注意点3）。
  static const double moodScale = 0.4;

  /// 記録が無い日に乗せる微小ノイズの振幅（仕様書 §4 日々のノイズ）。
  static const double noiseAmplitude = 0.3;

  /// 日付から決定的に求まる微小ノイズ。
  /// 乱数だと再計算のたびにチャートが変わってしまうため、日付をシードにする。
  static double noiseFor(DateTime day) {
    final seed = day.year * 10000 + day.month * 100 + day.day;
    final r = Random(seed).nextDouble(); // 0..1
    return (r - 0.5) * 2 * noiseAmplitude;
  }

  /// 気分スライダー値を変動値へ。
  static double moodDelta(double moodScore) => (moodScore - 5.0) * moodScale;

  /// エントリー一覧から日足ローソクを計算する。
  ///
  /// [entries] は日付キー('yyyy-MM-dd') → エントリーのマップ。
  /// 最初の記録日から [until]（省略時は今日）まで、空白日も含めて
  /// 1日1本のローソクを返す。空白日は前の水準を維持した平穏な足になる
  /// （空白は罰しない — 仕様書 §2）。
  static List<Candle> dailyCandles(
    Map<String, DiaryEntry> entries, {
    DateTime? until,
  }) {
    if (entries.isEmpty) return [];

    final dates = entries.keys.map(DateTime.parse).toList()..sort();
    final start = dates.first;
    final endSource = until ?? DateTime.now();
    final end = DateTime(endSource.year, endSource.month, endSource.day);

    final candles = <Candle>[];
    var prevClose = baseValue;
    var day = start;

    while (!day.isAfter(end)) {
      final key = _dateKey(day);
      final entry = entries[key];
      final open = prevClose;

      double positiveSum = 0;
      double negativeSum = 0;

      if (entry != null) {
        for (final event in entry.events) {
          final d = event.delta;
          if (d >= 0) {
            positiveSum += d;
          } else {
            negativeSum += d;
          }
        }
        if (entry.moodScore != null) {
          final d = moodDelta(entry.moodScore!);
          if (d >= 0) {
            positiveSum += d;
          } else {
            negativeSum += d;
          }
        }
      }

      // 完全な水平線にならないための微小な揺れ。
      final noise = noiseFor(day);
      if (noise >= 0) {
        positiveSum += noise;
      } else {
        negativeSum += noise;
      }

      // 高値 = ポジティブを全部積み上げた最高到達点、
      // 安値 = ネガティブを全部積み上げた最低到達点（仕様書 §5）。
      final close = open + positiveSum + negativeSum;
      final high = open + positiveSum;
      final low = open + negativeSum;

      candles.add(
        Candle(
          date: day,
          open: open,
          high: high,
          low: low,
          close: close,
          hasEntry: entry != null,
        ),
      );

      prevClose = close;
      day = day.add(const Duration(days: 1));
    }
    return candles;
  }

  /// 日足を週足に集約する（1本 = 月曜始まりの1週間）。
  static List<Candle> weeklyCandles(List<Candle> daily) {
    if (daily.isEmpty) return [];

    final weekly = <Candle>[];
    List<Candle> bucket = [];
    DateTime? weekStart;

    for (final c in daily) {
      final start = c.date.subtract(Duration(days: c.date.weekday - 1));
      if (weekStart == null || start != weekStart) {
        if (bucket.isNotEmpty) weekly.add(_aggregate(weekStart!, bucket));
        weekStart = start;
        bucket = [];
      }
      bucket.add(c);
    }
    if (bucket.isNotEmpty) weekly.add(_aggregate(weekStart!, bucket));
    return weekly;
  }

  /// 日足を月足に集約する（1本 = 1ヶ月）。
  static List<Candle> monthlyCandles(List<Candle> daily) {
    if (daily.isEmpty) return [];

    final monthly = <Candle>[];
    List<Candle> bucket = [];
    DateTime? monthStart;

    for (final c in daily) {
      final start = DateTime(c.date.year, c.date.month);
      if (monthStart == null || start != monthStart) {
        if (bucket.isNotEmpty) monthly.add(_aggregate(monthStart!, bucket));
        monthStart = start;
        bucket = [];
      }
      bucket.add(c);
    }
    if (bucket.isNotEmpty) monthly.add(_aggregate(monthStart!, bucket));
    return monthly;
  }

  /// 時間軸に応じた足を返すヘルパー。
  static List<Candle> forTimeframe(List<Candle> daily, Timeframe tf) =>
      switch (tf) {
        Timeframe.daily => daily,
        Timeframe.weekly => weeklyCandles(daily),
        Timeframe.monthly => monthlyCandles(daily),
      };

  static Candle _aggregate(DateTime start, List<Candle> bucket) => Candle(
    date: start,
    open: bucket.first.open,
    close: bucket.last.close,
    high: bucket.map((c) => c.high).reduce(max),
    low: bucket.map((c) => c.low).reduce(min),
    hasEntry: bucket.any((c) => c.hasEntry),
  );

  /// 終値の単純移動平均。データ不足の先頭区間は null。
  static List<double?> movingAverage(List<Candle> candles, int period) {
    final result = List<double?>.filled(candles.length, null);
    if (period <= 0) return result;
    double sum = 0;
    for (var i = 0; i < candles.length; i++) {
      sum += candles[i].close;
      if (i >= period) sum -= candles[i - period].close;
      if (i >= period - 1) result[i] = sum / period;
    }
    return result;
  }

  /// N日前の終値との差分（過去の自分との多重比較用、仕様書 §6）。
  /// データが足りなければ null。
  static double? changeSince(List<Candle> daily, int daysAgo) {
    if (daily.isEmpty) return null;
    final idx = daily.length - 1 - daysAgo;
    if (idx < 0) return null;
    return daily.last.close - daily[idx].close;
  }

  static String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static String dateKey(DateTime d) => _dateKey(d);
}
