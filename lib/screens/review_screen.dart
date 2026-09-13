import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logic/chart_calculator.dart';
import '../logic/weekly_summary.dart';
import '../models/models.dart';
import '../providers.dart';
import '../l10n.dart';
import '../theme.dart';
import '../widgets/candlestick_chart.dart';
import '../widgets/weekly_summary_card.dart';
import 'edit_screen.dart';

/// 振り返り画面（仕様書 §7-3）。
///
/// チャート上のローソクから飛んでくる。その期間に書いた「生の言葉」を
/// 当時のチャート位置と一緒に読み返せる（仕様書 §6 (3)）。
/// アプリが「成長してます！」と押し付けるのではなく、本人が読んで気づく設計。
class ReviewScreen extends ConsumerWidget {
  final DateTime date;

  /// true なら1週間分をまとめて表示。
  final bool weekly;

  const ReviewScreen({super.key, required this.date, this.weekly = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(entriesProvider).valueOrNull ?? {};
    final daily = ref.watch(dailyCandlesProvider);
    final i18n = context.i18n;
    final summaryStyle =
        ref.watch(appSummaryStyleProvider).valueOrNull ??
        AiSummaryStyle.balanced;

    final days = weekly
        ? List.generate(7, (i) => date.add(Duration(days: i)))
        : [date];
    final dayEntries = [
      for (final d in days)
        if (entries[ChartCalculator.dateKey(d)] case final e?) e,
    ];

    final candle = daily.where((c) => !c.date.isBefore(date)).firstOrNull;
    final current = daily.isNotEmpty ? daily.last.close : null;

    final title = weekly
        ? i18n.tr(
            'review_title_week',
            args: {
              'date': i18n.date(date, jaPattern: 'M/d', enPattern: 'MMM d'),
            },
          )
        : i18n.tr(
            'review_title_day',
            args: {
              'date': i18n.date(
                date,
                jaPattern: 'yyyy年M月d日 (E)',
                enPattern: 'MMM d, yyyy (E)',
              ),
            },
          );
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 週の振り返りには自動生成の「週のまとめ」を先頭に置く
          if (weekly) ...[
            WeeklySummaryCard(
              summary: WeeklySummary.compute(
                date,
                entries,
                i18n: i18n,
                style: summaryStyle,
              ),
            ),
            const SizedBox(height: 12),
            _weekChartCard(context, daily),
            const SizedBox(height: 12),
          ],
          if (candle != null) _positionCard(context, candle, current),
          const SizedBox(height: 16),
          if (dayEntries.isEmpty)
            Padding(
              padding: EdgeInsets.only(top: 32),
              child: Center(child: Text(i18n.tr('review_empty'))),
            )
          else
            for (final entry in dayEntries) ...[
              _entryCard(context, entry, ref),
              const SizedBox(height: 12),
            ],
        ],
      ),
    );
  }

  /// その週の日足チャート（月曜〜日曜の7本）。週のまとめの直下に置く。
  Widget _weekChartCard(BuildContext context, List<Candle> daily) {
    final weekStart = DateTime(
      date.year,
      date.month,
      date.day,
    ).subtract(Duration(days: date.weekday - 1));
    final weekEnd = weekStart.add(const Duration(days: 6));
    final weekCandles = daily
        .where((c) => !c.date.isBefore(weekStart) && !c.date.isAfter(weekEnd))
        .toList();

    if (weekCandles.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.i18n.tr('review_week_chart'),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: AppColors.inkSoft,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 160,
              // 日足なので点＋ラインで表示（週内の1日1本）
              child: CandlestickChart(
                candles: weekCandles,
                i18n: context.i18n,
                style: ChartStyle.line,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 当時のチャート位置と今との距離。事実だけを淡々と示す。
  Widget _positionCard(BuildContext context, Candle candle, double? current) {
    final diff = current != null ? current - candle.close : null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _metric(
              context,
              context.i18n.tr('value_at_time'),
              candle.close.toStringAsFixed(1),
            ),
            if (diff != null)
              _metric(
                context,
                context.i18n.tr('diff_from_now'),
                '${diff >= 0 ? '+' : ''}${diff.toStringAsFixed(1)}',
                color: diff >= 0 ? AppColors.bull : AppColors.bear,
              ),
          ],
        ),
      ),
    );
  }

  Widget _metric(
    BuildContext context,
    String label,
    String value, {
    Color? color,
  }) {
    return Column(
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _entryCard(BuildContext context, DiaryEntry entry, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  context.i18n.date(
                    entry.dateTime,
                    jaPattern: 'M月d日 (E)',
                    enPattern: 'MMM d (E)',
                  ),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.tune, size: 20),
                  tooltip: context.i18n.tr('edit_events'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => EditScreen(dateKey: entry.date),
                    ),
                  ),
                ),
              ],
            ),
            if (entry.text.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(entry.text, style: const TextStyle(height: 1.7)),
            ],
            if (entry.events.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final e in entry.events)
                    Chip(
                      visualDensity: VisualDensity.compact,
                      avatar: Icon(
                        e.isPositive ? Icons.trending_up : Icons.trending_down,
                        size: 16,
                        color: e.isPositive ? AppColors.bull : AppColors.bear,
                      ),
                      label: Text(
                        '${e.name} ${e.isPositive ? '+' : '-'}'
                        '${e.weight.toStringAsFixed(1)}',
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
