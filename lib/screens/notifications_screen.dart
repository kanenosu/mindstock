import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../logic/chart_calculator.dart';
import '../logic/weekly_summary.dart';
import '../providers.dart';
import '../theme.dart';
import '../widgets/motion.dart';
import 'review_screen.dart';

/// 通知欄（お知らせ）。週が終わるたびに自動生成される週次レポートが並ぶ。
/// 開いた時点で全件既読になり、ホームのベルのバッジが消える。
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    // 開いたら最新レポートまで既読にする
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final reports = ref.read(weeklyReportsProvider);
      if (reports.isEmpty) return;
      ref
          .read(notificationsLastSeenProvider.notifier)
          .save(ChartCalculator.dateKey(reports.first.weekStart));
    });
  }

  @override
  Widget build(BuildContext context) {
    final reports = ref.watch(weeklyReportsProvider);
    final lastSeen = ref.watch(notificationsLastSeenProvider).valueOrNull ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('お知らせ')),
      body: reports.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.notifications_none_rounded,
                    size: 56,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '週が終わると、ここに週次レポートが届きます。',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: reports.length,
              itemBuilder: (context, i) {
                final report = reports[i];
                final isNew =
                    ChartCalculator.dateKey(
                      report.weekStart,
                    ).compareTo(lastSeen) >
                    0;
                return FadeSlideIn(
                  delayMs: (i * 60).clamp(0, 360),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _ReportTile(report: report, isNew: isNew),
                  ),
                );
              },
            ),
    );
  }
}

class _ReportTile extends StatelessWidget {
  final WeeklySummary report;
  final bool isNew;

  const _ReportTile({required this.report, required this.isNew});

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('M/d');
    final up = report.totalDelta >= 0;
    final color = up ? AppColors.bull : AppColors.bear;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ReviewScreen(date: report.weekStart, weekly: true),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Text(
                  up ? '📈' : '📉',
                  style: const TextStyle(fontSize: 20),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '週次レポート '
                          '${fmt.format(report.weekStart)}〜${fmt.format(report.weekEnd)}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (isNew) ...[
                          const SizedBox(width: 6),
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: AppColors.accent,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      report.headline,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.inkSoft,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${report.totalDelta >= 0 ? '+' : ''}'
                '${report.totalDelta.toStringAsFixed(1)}',
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
