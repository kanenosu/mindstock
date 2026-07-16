import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../logic/chart_calculator.dart';
import '../logic/weekly_summary.dart';
import '../models/models.dart';
import '../providers.dart';
import '../theme.dart';
import '../widgets/candlestick_chart.dart';
import '../widgets/pill_selector.dart';
import '../widgets/weekly_summary_card.dart';
import 'review_screen.dart';

/// メインチャート画面（仕様書 §7-2）。
///
/// 株アプリと同じ構成: 現在値ヘッダー + 日足/週足/月足の切り替え + 本体チャート。
/// 日足はただの点（ライン表示）、週足・月足はローソク足。
/// ピンチズーム・横スクロール・タップで振り返り。
class ChartScreen extends ConsumerStatefulWidget {
  const ChartScreen({super.key});

  @override
  ConsumerState<ChartScreen> createState() => _ChartScreenState();
}

class _ChartScreenState extends ConsumerState<ChartScreen> {
  Timeframe _tf = Timeframe.daily;

  /// タップで選択中の足。ヘッダーがこの足の情報に切り替わる。
  Candle? _selected;

  @override
  Widget build(BuildContext context) {
    final daily = ref.watch(dailyCandlesProvider);
    final candles = ChartCalculator.forTimeframe(daily, _tf);
    final ma = ChartCalculator.movingAverage(candles, _tf.maPeriod);

    return Scaffold(
      appBar: AppBar(title: const Text('推移')),
      body: daily.isEmpty
          ? const _EmptyChart()
          : Column(
              children: [
                _CurrentValueHeader(
                  daily: daily,
                  selected: _selected,
                  tf: _tf,
                  onOpenSelected: _openSelectedReview,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: PillSelector<Timeframe>(
                    items: Timeframe.values,
                    selected: _tf,
                    labelOf: (tf) => tf.longLabel,
                    onChanged: (tf) => setState(() {
                      _tf = tf;
                      _selected = null;
                    }),
                  ),
                ),
                _ComparisonCards(daily: daily),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: CandlestickChart(
                      candles: candles,
                      movingAverage: ma,
                      // 日足はただの点、週足・月足でローソク足になる
                      style: _tf == Timeframe.daily
                          ? ChartStyle.line
                          : ChartStyle.candle,
                      onSelect: _onSelect,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    _tf == Timeframe.daily
                        ? 'ピンチで拡大縮小・ドラッグでスクロール・タップで選択'
                        : 'ヒゲはその期間の最高/最低到達点。タップで選択・ダブルタップでリセット',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: AppColors.inkSoft),
                  ),
                ),
              ],
            ),
    );
  }

  void _onSelect(Candle candle) {
    setState(() => _selected = candle);
    // 週足は「週のまとめ」をボトムシートですぐ見せる
    if (_tf == Timeframe.weekly) _showWeeklySummarySheet(candle);
  }

  /// ヘッダーの「振り返る」から。選択中の足の期間の日記へ。
  void _openSelectedReview() {
    final candle = _selected;
    if (candle == null) return;
    if (_tf == Timeframe.weekly) {
      _showWeeklySummarySheet(candle);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            ReviewScreen(date: candle.date, weekly: _tf != Timeframe.daily),
      ),
    );
  }

  void _showWeeklySummarySheet(Candle candle) {
    final entries = ref.read(entriesProvider).valueOrNull ?? {};
    final summary = WeeklySummary.compute(candle.date, entries);

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.cream,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: AppColors.ink.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              WeeklySummaryCard(summary: summary, elevated: false),
              const SizedBox(height: 12),
              FilledButton.icon(
                icon: const Icon(Icons.menu_book_outlined, size: 18),
                label: const Text('この週の日記を読む'),
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          ReviewScreen(date: summary.weekStart, weekly: true),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 株アプリ風の現在値ヘッダー。
/// 足を選択中はその期間の日付・終値・変動に切り替わり、
/// 「振り返る」で当時の日記へ飛べる。
class _CurrentValueHeader extends StatelessWidget {
  final List<Candle> daily;
  final Candle? selected;
  final Timeframe tf;
  final VoidCallback onOpenSelected;

  const _CurrentValueHeader({
    required this.daily,
    required this.selected,
    required this.tf,
    required this.onOpenSelected,
  });

  @override
  Widget build(BuildContext context) {
    final candle = selected;
    final value = candle?.close ?? daily.last.close;
    final diff = candle != null
        ? candle.close - candle.open
        : ChartCalculator.changeSince(daily, 1);
    final pct = (diff != null && (value - diff).abs() > 1e-9)
        ? diff / (value - diff) * 100
        : null;
    final color = (diff ?? 0) >= 0 ? AppColors.bull : AppColors.bear;

    final periodLabel = candle == null
        ? '今日'
        : switch (tf) {
            Timeframe.daily => DateFormat('M/d (E)', 'ja').format(candle.date),
            Timeframe.weekly => '${DateFormat('M/d').format(candle.date)}の週',
            Timeframe.monthly => DateFormat(
              'yyyy年M月',
              'ja',
            ).format(candle.date),
          };

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: Row(
          key: ValueKey('$periodLabel-$value'),
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              NumberFormat('#,##0.0').format(value),
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w900,
                height: 1.0,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 8),
            if (diff != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  '${diff >= 0 ? '+' : ''}${diff.toStringAsFixed(1)}'
                  '${pct != null ? ' (${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(1)}%)' : ''}',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
            const Spacer(),
            if (candle == null)
              Padding(
                padding: const EdgeInsets.only(right: 8, bottom: 2),
                child: Text(
                  periodLabel,
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: AppColors.inkSoft),
                ),
              )
            else
              TextButton.icon(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: AppColors.ink,
                ),
                icon: Text(
                  periodLabel,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.inkSoft,
                  ),
                ),
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Text(
                      '振り返る',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Icon(Icons.chevron_right, size: 16),
                  ],
                ),
                onPressed: onOpenSelected,
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyChart extends ConsumerWidget {
  const _EmptyChart();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
          const Text(
            '最初の日記を書くと、\nここに人生のチャートが生まれます。',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            icon: const Icon(Icons.auto_graph),
            label: const Text('サンプルデータで試してみる'),
            onPressed: () async {
              await ref.read(entriesProvider.notifier).seedDemoData();
              if (context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('サンプルデータを投入しました')));
              }
            },
          ),
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
    final comparisons = <(String, double?)>[
      ('昨日比', ChartCalculator.changeSince(daily, 1)),
      ('1週間前', ChartCalculator.changeSince(daily, 7)),
      ('1ヶ月前', ChartCalculator.changeSince(daily, 30)),
      ('半年前', ChartCalculator.changeSince(daily, 182)),
      ('1年前', ChartCalculator.changeSince(daily, 365)),
    ];

    return SizedBox(
      height: 80,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        children: [
          for (final (label, diff) in comparisons)
            if (diff != null)
              Card(
                margin: const EdgeInsets.only(right: 8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        label,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppColors.inkSoft,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${diff >= 0 ? '+' : ''}${diff.toStringAsFixed(1)}',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: diff >= 0
                                  ? AppColors.bull
                                  : AppColors.bear,
                              fontWeight: FontWeight.bold,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
