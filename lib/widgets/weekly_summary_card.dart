import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../logic/weekly_summary.dart';
import '../theme.dart';

/// 週のまとめカード。
/// 週足ローソクのタップ（ボトムシート）と週の振り返り画面で使う。
class WeeklySummaryCard extends StatelessWidget {
  final WeeklySummary summary;

  /// ボトムシート内などで影を消したい時は false。
  final bool elevated;

  const WeeklySummaryCard({
    super.key,
    required this.summary,
    this.elevated = true,
  });

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('M/d');
    final range =
        '${fmt.format(summary.weekStart)}〜${fmt.format(summary.weekEnd)}';
    final totalColor = summary.totalDelta >= 0
        ? AppColors.bull
        : AppColors.bear;

    final content = Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '週のまとめ',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AppColors.accent.withValues(alpha: 1),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                range,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: AppColors.inkSoft,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                '${summary.totalDelta >= 0 ? '+' : ''}'
                '${summary.totalDelta.toStringAsFixed(1)}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: totalColor,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            summary.headline,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _stat(context, '記録', '${summary.entryDays}日'),
              _dividerDot(),
              _stat(context, '平穏', '${summary.calmDays}日'),
              _dividerDot(),
              _stat(
                context,
                'プラスの日',
                '${summary.upDays}日',
                color: AppColors.bull,
              ),
              _dividerDot(),
              _stat(
                context,
                'マイナスの日',
                '${summary.downDays}日',
                color: AppColors.bear,
              ),
            ],
          ),
          if (summary.best != null || summary.worst != null) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (summary.best case final best?)
                  _eventChip(
                    context,
                    best.name,
                    '+${best.weight.toStringAsFixed(1)}',
                    AppColors.bull,
                  ),
                if (summary.worst case final worst?)
                  _eventChip(
                    context,
                    worst.name,
                    '-${worst.weight.toStringAsFixed(1)}',
                    AppColors.bear,
                  ),
              ],
            ),
          ],
        ],
      ),
    );

    if (!elevated) {
      return Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(24),
        ),
        child: content,
      );
    }
    return Card(child: content);
  }

  Widget _stat(
    BuildContext context,
    String label,
    String value, {
    Color? color,
  }) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppColors.inkSoft,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: color ?? AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }

  Widget _dividerDot() => Container(
    width: 1,
    height: 24,
    margin: const EdgeInsets.symmetric(horizontal: 8),
    color: AppColors.ink.withValues(alpha: 0.08),
  );

  Widget _eventChip(
    BuildContext context,
    String name,
    String value,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$name  $value',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
