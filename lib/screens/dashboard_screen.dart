import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../logic/chart_calculator.dart';
import '../models/models.dart';
import '../providers.dart';
import '../theme.dart';
import 'entry_screen.dart';
import 'review_screen.dart';

/// ダッシュボード（ホーム画面）。株アプリ風 × 温かいトーン。
///
/// - Life Index: 現在値を株価指数風に大きく表示 + 前日比% + トレンドバッジ
/// - ミニローソク足チャート（タップで推移タブへ）
/// - 統計カード: 1ヶ月前 / 半年前 / 平穏日
/// - 今日の記録カード（まだ書いてなければ書くボタン、30秒でOK）
class DashboardScreen extends ConsumerWidget {
  /// ミニチャートタップ時に推移タブへ切り替えるコールバック。
  final VoidCallback onOpenChart;

  /// 「書く」ボタンで日記タブへ切り替えるコールバック。
  final VoidCallback onOpenDiary;

  const DashboardScreen({
    super.key,
    required this.onOpenChart,
    required this.onOpenDiary,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final daily = ref.watch(dailyCandlesProvider);
    final weekly = ref.watch(weeklyCandlesProvider);
    final entries = ref.watch(entriesProvider).valueOrNull ?? {};
    final todayKey = ChartCalculator.dateKey(DateTime.now());
    final todayEntry = entries[todayKey];

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            _header(context),
            const SizedBox(height: 16),
            _LifeIndexCard(daily: daily, weekly: weekly, onTap: onOpenChart),
            const SizedBox(height: 14),
            _StatRow(daily: daily),
            const SizedBox(height: 14),
            _TodayCard(entry: todayEntry, onWrite: onOpenDiary),
            const SizedBox(height: 20),
            _RecentSection(entries: entries),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '今日もゆっくり積み上げる',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.inkSoft,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'ダッシュボード',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: AppColors.card,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.ink.withValues(alpha: 0.06),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: const Text('⛅', style: TextStyle(fontSize: 20)),
        ),
      ],
    );
  }
}

/// Life Index ヒーローカード。株価指数風の大きな現在値 + トレンド。
class _LifeIndexCard extends StatelessWidget {
  final List<Candle> daily;
  final List<Candle> weekly;
  final VoidCallback onTap;

  const _LifeIndexCard({
    required this.daily,
    required this.weekly,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final current = daily.isNotEmpty ? daily.last.close : null;
    final diffYesterday = ChartCalculator.changeSince(daily, 1);
    final pct = (current != null && diffYesterday != null &&
            (current - diffYesterday).abs() > 1e-9)
        ? diffYesterday / (current - diffYesterday) * 100
        : null;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Life Index',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: AppColors.inkSoft,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const Spacer(),
                  _trendBadge(context),
                ],
              ),
              const SizedBox(height: 6),
              if (current == null)
                Text(
                  'まだ記録がありません',
                  style: Theme.of(context).textTheme.titleMedium,
                )
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      NumberFormat('#,##0.0').format(current),
                      style: Theme.of(context)
                          .textTheme
                          .displaySmall
                          ?.copyWith(
                            fontWeight: FontWeight.w900,
                            height: 1.0,
                            fontFeatures: const [
                              FontFeature.tabularFigures(),
                            ],
                          ),
                    ),
                    const SizedBox(width: 8),
                    if (pct != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          '${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(1)}%',
                          style: TextStyle(
                            color: pct >= 0 ? AppColors.bull : AppColors.bear,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                      ),
                  ],
                ),
              const SizedBox(height: 10),
              Text(
                _message(),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.inkSoft,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 130,
                width: double.infinity,
                child: daily.isEmpty
                    ? const SizedBox.shrink()
                    : CustomPaint(
                        painter: _MiniCandlePainter(
                          candles: weekly.length > 12
                              ? weekly.sublist(weekly.length - 12)
                              : weekly,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _trendBadge(BuildContext context) {
    final diffWeek = ChartCalculator.changeSince(daily, 7);
    final (label, icon, color) = switch (diffWeek) {
      null => ('はじまり', Icons.spa_outlined, AppColors.inkSoft),
      final d when d > 1 => ('上向き', Icons.north_east, AppColors.bull),
      final d when d < -1 => ('谷の途中', Icons.south_east, AppColors.bear),
      _ => ('横ばい', Icons.trending_flat, AppColors.accent),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  /// 状態に応じた一言。成長を押し付けず、事実に寄り添う（仕様書 §6）。
  String _message() {
    if (daily.isEmpty) {
      return '最初の日記を書くと、ここに人生のチャートが生まれる。';
    }
    final y = ChartCalculator.changeSince(daily, 1) ?? 0;
    final long = ChartCalculator.changeSince(daily, 182) ??
        ChartCalculator.changeSince(daily, 30);

    if (y < 0 && long != null && long > 0) {
      return '昨日より少し揺れても、以前の谷からはちゃんと離れてる。今日は悪くない。';
    }
    if (y >= 0 && (long == null || long >= 0)) {
      return '静かに積み上がってる。今日も、ただ書くだけでいい。';
    }
    return 'いまは谷の途中かもしれない。谷も人生の一部。記録はちゃんと残ってる。';
  }
}

/// 統計カード3枚（1ヶ月前 / 半年前 / 平穏日）。
class _StatRow extends StatelessWidget {
  final List<Candle> daily;

  const _StatRow({required this.daily});

  @override
  Widget build(BuildContext context) {
    final month = ChartCalculator.changeSince(daily, 30);
    final halfYear = ChartCalculator.changeSince(daily, 182);
    final recent = daily.length > 30 ? daily.sublist(daily.length - 30) : daily;
    final calmDays = recent.where((c) => !c.hasEntry).length;

    return Row(
      children: [
        Expanded(child: _diffCard(context, '1ヶ月前', month)),
        const SizedBox(width: 10),
        Expanded(child: _diffCard(context, '半年前', halfYear)),
        const SizedBox(width: 10),
        Expanded(
          child: _statCard(
            context,
            label: '平穏日',
            child: Text(
              '$calmDays日',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _diffCard(BuildContext context, String label, double? diff) {
    return _statCard(
      context,
      label: label,
      child: Text(
        diff == null
            ? '—'
            : '${diff >= 0 ? '+' : ''}${diff.toStringAsFixed(1)}',
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w800,
          color: diff == null
              ? AppColors.inkSoft
              : (diff >= 0 ? AppColors.bull : AppColors.bear),
        ),
      ),
    );
  }

  Widget _statCard(
    BuildContext context, {
    required String label,
    required Widget child,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: AppColors.inkSoft,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            child,
          ],
        ),
      ),
    );
  }
}

/// 今日の記録カード。まだ書いてなければ「30秒でOK」の書く導線。
class _TodayCard extends StatelessWidget {
  final DiaryEntry? entry;
  final VoidCallback onWrite;

  const _TodayCard({required this.entry, required this.onWrite});

  @override
  Widget build(BuildContext context) {
    final written = entry != null &&
        (entry!.text.isNotEmpty || entry!.moodScore != null);
    final total =
        entry?.events.fold<double>(0, (sum, e) => sum + e.delta) ?? 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '今日の記録',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                Text(
                  written
                      ? '${total >= 0 ? '+' : ''}${total.toStringAsFixed(1)}'
                      : '30秒でOK',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: written
                        ? (total >= 0 ? AppColors.bull : AppColors.bear)
                        : AppColors.inkSoft,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        written
                            ? (entry!.text.isEmpty
                                  ? '気分だけ記録した日'
                                  : entry!.text.replaceAll('\n', ' '))
                            : 'まだ書いてない',
                        maxLines: written ? 2 : 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        written
                            ? 'タップで続きを書ける。微調整もここから。'
                            : '文章でも、気分スライダーだけでもいい。空白でも罰しない。',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.inkSoft,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _writeButton(),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _writeButton() {
    return Material(
      color: AppColors.inkButton,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onWrite,
        borderRadius: BorderRadius.circular(20),
        child: const SizedBox(
          width: 56,
          height: 56,
          child: Center(child: Text('✍️', style: TextStyle(fontSize: 22))),
        ),
      ),
    );
  }
}

/// 最近の記録（直近3件）。
class _RecentSection extends StatelessWidget {
  final Map<String, DiaryEntry> entries;

  const _RecentSection({required this.entries});

  @override
  Widget build(BuildContext context) {
    final recent = entries.values.toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    if (recent.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '最近の記録',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              for (final (i, entry) in recent.take(3).indexed) ...[
                if (i > 0) const Divider(height: 1, indent: 20, endIndent: 20),
                _tile(context, entry),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _tile(BuildContext context, DiaryEntry entry) {
    final total = entry.events.fold<double>(0, (sum, e) => sum + e.delta);
    final preview = entry.text.replaceAll('\n', ' ');
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      title: Text(
        DateFormat('M月d日 (E)', 'ja').format(entry.dateTime),
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
      ),
      subtitle: preview.isEmpty
          ? null
          : Text(
              preview,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.inkSoft, fontSize: 12),
            ),
      trailing: Text(
        '${total >= 0 ? '+' : ''}${total.toStringAsFixed(1)}',
        style: TextStyle(
          color: total >= 0 ? AppColors.bull : AppColors.bear,
          fontWeight: FontWeight.w800,
        ),
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ReviewScreen(date: entry.dateTime)),
      ),
      onLongPress: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => EntryScreen(initialDate: entry.dateTime),
        ),
      ),
    );
  }
}

/// ヒーローカード内のミニローソク足。丸みのある実体 + 終値の滑らかなライン。
class _MiniCandlePainter extends CustomPainter {
  final List<Candle> candles;

  _MiniCandlePainter({required this.candles});

  @override
  void paint(Canvas canvas, Size size) {
    if (candles.isEmpty) return;

    final minV = candles.map((c) => c.low).reduce(min);
    final maxV = candles.map((c) => c.high).reduce(max);
    final range = max(maxV - minV, 1e-6);

    final slot = size.width / candles.length;
    final bodyWidth = min(slot * 0.45, 14.0);

    double xFor(int i) => slot * i + slot / 2;
    double yFor(double v) => (maxV - v) / range * (size.height - 12) + 6;

    // 薄いグリッド
    final grid = Paint()
      ..color = AppColors.ink.withValues(alpha: 0.05)
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    // 終値を結ぶ滑らかなライン（中間点quadratic）
    final linePath = Path()..moveTo(xFor(0), yFor(candles.first.close));
    for (var i = 1; i < candles.length; i++) {
      final x0 = xFor(i - 1);
      final y0 = yFor(candles[i - 1].close);
      final x1 = xFor(i);
      final y1 = yFor(candles[i].close);
      linePath.quadraticBezierTo(x0, y0, (x0 + x1) / 2, (y0 + y1) / 2);
      if (i == candles.length - 1) linePath.lineTo(x1, y1);
    }
    canvas.drawPath(
      linePath,
      Paint()
        ..color = const Color(0xFF6E8FC9).withValues(alpha: 0.7)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    // ローソク（丸みのある実体）
    for (var i = 0; i < candles.length; i++) {
      final c = candles[i];
      final cx = xFor(i);
      final color = c.isBullish ? AppColors.bull : AppColors.bear;
      final paint = Paint()..color = color;

      canvas.drawLine(
        Offset(cx, yFor(c.high)),
        Offset(cx, yFor(c.low)),
        Paint()
          ..color = color
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round,
      );

      final top = yFor(max(c.open, c.close));
      final bottom = max(yFor(min(c.open, c.close)), top + 3);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(cx - bodyWidth / 2, top, cx + bodyWidth / 2, bottom),
          const Radius.circular(4),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MiniCandlePainter old) =>
      old.candles != candles;
}
