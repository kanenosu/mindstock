import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../logic/chart_calculator.dart';
import '../models/models.dart';
import '../providers.dart';
import '../widgets/candlestick_chart.dart';
import 'review_screen.dart';

/// メインチャート画面（仕様書 §7-2）。
///
/// 日足はただの点（ライン表示）、週足に切り替えるとローソク足になる。
/// 移動平均 + 指標カード（多重比較）+ ピンチズーム/スクロール。
class ChartScreen extends ConsumerStatefulWidget {
  const ChartScreen({super.key});

  @override
  ConsumerState<ChartScreen> createState() => _ChartScreenState();
}

class _ChartScreenState extends ConsumerState<ChartScreen> {
  bool _weekly = false;

  @override
  Widget build(BuildContext context) {
    final daily = ref.watch(dailyCandlesProvider);
    final candles = _weekly ? ref.watch(weeklyCandlesProvider) : daily;
    final ma = ChartCalculator.movingAverage(candles, _weekly ? 4 : 7);

    return Scaffold(
      appBar: AppBar(
        title: const Text('人生チャート'),
        actions: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('日足')),
              ButtonSegment(value: true, label: Text('週足')),
            ],
            selected: {_weekly},
            onSelectionChanged: (s) => setState(() => _weekly = s.first),
            showSelectedIcon: false,
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: daily.isEmpty
          ? const _EmptyChart()
          : Column(
              children: [
                _ComparisonCards(daily: daily),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: CandlestickChart(
                      candles: candles,
                      movingAverage: ma,
                      // 日足はただの点、週足でローソク足になる
                      style: _weekly ? ChartStyle.candle : ChartStyle.line,
                      onSelect: (candle) => _openReview(candle),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    _weekly
                        ? '週足ローソク: ヒゲはその週の最高/最低到達点。タップで振り返り'
                        : 'ピンチで拡大縮小・ドラッグでスクロール・タップでその日を振り返る',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
    );
  }

  void _openReview(Candle candle) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReviewScreen(date: candle.date, weekly: _weekly),
      ),
    );
  }
}

class _EmptyChart extends StatelessWidget {
  const _EmptyChart();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.candlestick_chart_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          const Text('最初の日記を書くと、\nここに人生のチャートが生まれます。',
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

/// 過去の自分との多重比較カード（仕様書 §6 (1)）。
///
/// 「昨日よりはマイナスだけど、半年前のどん底からは大きくプラス」が
/// 一目で分かるようにする。成長を押し付けない — 事実の提示に留める。
class _ComparisonCards extends StatelessWidget {
  final List<Candle> daily;

  const _ComparisonCards({required this.daily});

  @override
  Widget build(BuildContext context) {
    final current = daily.last.close;
    final comparisons = <(String, double?)>[
      ('昨日比', ChartCalculator.changeSince(daily, 1)),
      ('1ヶ月前', ChartCalculator.changeSince(daily, 30)),
      ('半年前', ChartCalculator.changeSince(daily, 182)),
      ('1年前', ChartCalculator.changeSince(daily, 365)),
    ];

    return SizedBox(
      height: 88,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          _card(
            context,
            label: '現在値',
            value: NumberFormat('#,##0.0').format(current),
            color: null,
          ),
          for (final (label, diff) in comparisons)
            if (diff != null)
              _card(
                context,
                label: label,
                value: '${diff >= 0 ? '+' : ''}${diff.toStringAsFixed(1)}',
                color: diff >= 0
                    ? const Color(0xFF26A69A)
                    : const Color(0xFFEF5350),
              ),
        ],
      ),
    );
  }

  Widget _card(
    BuildContext context, {
    required String label,
    required String value,
    Color? color,
  }) {
    return Card(
      margin: const EdgeInsets.only(right: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 4),
            Text(
              value,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.bold,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
