import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
/// - チャート: 日/週/月の切り替えと横スクロールに対応（タップで推移タブへ）
/// - 統計カード: 1ヶ月前 / 半年前 / 平穏日
/// - 今日の記録カード（まだ書いてなければ書くボタン、30秒でOK）
class DashboardScreen extends ConsumerWidget {
  /// チャートタップ時に推移タブへ切り替えるコールバック。
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
    final entries = ref.watch(entriesProvider).valueOrNull ?? {};
    final todayKey = ChartCalculator.dateKey(DateTime.now());
    final todayEntry = entries[todayKey];

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            _Header(),
            const SizedBox(height: 16),
            _LifeIndexCard(daily: daily, onOpenChart: onOpenChart),
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
}

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    final (greeting, emoji) = switch (hour) {
      >= 5 && < 11 => ('おはよう。今日もゆっくり積み上げる', '🌅'),
      >= 11 && < 17 => ('こんにちは。今日もゆっくり積み上げる', '☀️'),
      _ => ('こんばんは。今日もおつかれさま', '🌙'),
    };
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                greeting,
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
          child: Text(emoji, style: const TextStyle(fontSize: 20)),
        ),
      ],
    );
  }
}

/// Life Index ヒーローカード。
/// 日/週/月の切り替えと横スクロールができるチャート付き。
class _LifeIndexCard extends StatefulWidget {
  final List<Candle> daily;
  final VoidCallback onOpenChart;

  const _LifeIndexCard({required this.daily, required this.onOpenChart});

  @override
  State<_LifeIndexCard> createState() => _LifeIndexCardState();
}

class _LifeIndexCardState extends State<_LifeIndexCard> {
  Timeframe _tf = Timeframe.weekly;

  /// 右端から何本分過去へスクロールしているか。0 = 最新。
  double _offset = 0;

  int get _visibleCount => switch (_tf) {
    Timeframe.daily => 30,
    Timeframe.weekly => 12,
    Timeframe.monthly => 12,
  };

  @override
  Widget build(BuildContext context) {
    final daily = widget.daily;
    final current = daily.isNotEmpty ? daily.last.close : null;
    final diffYesterday = ChartCalculator.changeSince(daily, 1);
    final pct =
        (current != null &&
            diffYesterday != null &&
            (current - diffYesterday).abs() > 1e-9)
        ? diffYesterday / (current - diffYesterday) * 100
        : null;

    final candles = ChartCalculator.forTimeframe(daily, _tf);
    final maxOffset = max(0, candles.length - _visibleCount).toDouble();
    final clampedOffset = _offset.clamp(0.0, maxOffset);
    final last = candles.length - clampedOffset.round();
    final window = candles.isEmpty
        ? const <Candle>[]
        : candles.sublist(max(0, last - _visibleCount), last);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: widget.onOpenChart,
              child: Row(
                children: [
                  Text(
                    'Life Index',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: AppColors.inkSoft,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.chevron_right,
                    size: 16,
                    color: AppColors.inkSoft,
                  ),
                  const Spacer(),
                  _TrendBadge(daily: daily),
                ],
              ),
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
                  // カウントアップで気持ちよく着地する現在値
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: current),
                    duration: const Duration(milliseconds: 900),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, _) => Text(
                      NumberFormat('#,##0.0').format(value),
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        height: 1.0,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
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
              _message(daily),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.inkSoft,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 14),
            if (daily.isNotEmpty) ...[
              // 横ドラッグで過去へスクロールできるチャート
              LayoutBuilder(
                builder: (context, constraints) {
                  final slot = constraints.maxWidth / _visibleCount;
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: widget.onOpenChart,
                    onHorizontalDragUpdate: (details) {
                      setState(() {
                        _offset = (_offset + details.delta.dx / slot).clamp(
                          0.0,
                          maxOffset,
                        );
                      });
                    },
                    onDoubleTap: () {
                      HapticFeedback.lightImpact();
                      setState(() => _offset = 0);
                    },
                    child: SizedBox(
                      height: 130,
                      width: double.infinity,
                      child: CustomPaint(
                        painter: _MiniCandlePainter(
                          candles: window,
                          asLine: _tf == Timeframe.daily,
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  SizedBox(
                    width: 150,
                    child: _TimeframePills(
                      selected: _tf,
                      onChanged: (tf) => setState(() {
                        _tf = tf;
                        _offset = 0;
                      }),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _rangeLabel(window),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.inkSoft,
                      fontFeatures: const [FontFeature.tabularFigures()],
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

  String _rangeLabel(List<Candle> window) {
    if (window.isEmpty) return '';
    final fmt = DateFormat('M/d');
    final fmtMonth = DateFormat('yyyy/M');
    return _tf == Timeframe.monthly
        ? '${fmtMonth.format(window.first.date)}〜${fmtMonth.format(window.last.date)}'
        : '${fmt.format(window.first.date)}〜${fmt.format(window.last.date)}';
  }

  /// 状態に応じた一言。成長を押し付けず、事実に寄り添う（仕様書 §6）。
  String _message(List<Candle> daily) {
    if (daily.isEmpty) {
      return '最初の日記を書くと、ここに人生のチャートが生まれる。';
    }
    final y = ChartCalculator.changeSince(daily, 1) ?? 0;
    final long =
        ChartCalculator.changeSince(daily, 182) ??
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

/// 日/週/月のミニピル（カード内用の小型版）。
class _TimeframePills extends StatelessWidget {
  final Timeframe selected;
  final ValueChanged<Timeframe> onChanged;

  const _TimeframePills({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      decoration: BoxDecoration(
        color: AppColors.ink.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          for (final tf in Timeframe.values)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (tf == selected) return;
                  HapticFeedback.selectionClick();
                  onChanged(tf);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: tf == selected ? AppColors.card : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: tf == selected
                        ? [
                            BoxShadow(
                              color: AppColors.ink.withValues(alpha: 0.1),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ]
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    tf.label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: tf == selected
                          ? FontWeight.w800
                          : FontWeight.w600,
                      color: tf == selected ? AppColors.ink : AppColors.inkSoft,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TrendBadge extends StatelessWidget {
  final List<Candle> daily;

  const _TrendBadge({required this.daily});

  @override
  Widget build(BuildContext context) {
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
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
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
    final written =
        entry != null && (entry!.text.isNotEmpty || entry!.moodScore != null);
    final total = entry?.events.fold<double>(0, (sum, e) => sum + e.delta) ?? 0;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onWrite,
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
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          written
                              ? 'タップで続きを書ける。微調整もここから。'
                              : '文章でも、気分の絵文字ひとつでもいい。空白でも罰しない。',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: AppColors.inkSoft, height: 1.5),
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
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
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

/// カード内チャート。丸みのあるローソク or ライン + 終値の滑らかな青ライン。
class _MiniCandlePainter extends CustomPainter {
  final List<Candle> candles;

  /// true なら終値のライン＋点だけで描く（日足用）。
  final bool asLine;

  _MiniCandlePainter({required this.candles, this.asLine = false});

  @override
  void paint(Canvas canvas, Size size) {
    if (candles.isEmpty) return;

    final minV = asLine
        ? candles.map((c) => c.close).reduce(min)
        : candles.map((c) => c.low).reduce(min);
    final maxV = asLine
        ? candles.map((c) => c.close).reduce(max)
        : candles.map((c) => c.high).reduce(max);
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

    // 終値を結ぶ滑らかなライン
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
        ..color = const Color(0xFF6E8FC9).withValues(alpha: asLine ? 0.9 : 0.7)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    if (asLine) {
      // 日足: 記録がある日に緑/赤の点を打つ
      final dotRadius = (slot / 4).clamp(1.5, 4.0);
      for (var i = 0; i < candles.length; i++) {
        final c = candles[i];
        if (!c.hasEntry) continue;
        canvas.drawCircle(
          Offset(xFor(i), yFor(c.close)),
          dotRadius,
          Paint()..color = c.isBullish ? AppColors.bull : AppColors.bear,
        );
      }
      return;
    }

    // ローソク（丸みのある実体）
    for (var i = 0; i < candles.length; i++) {
      final c = candles[i];
      final cx = xFor(i);
      final color = c.isBullish ? AppColors.bull : AppColors.bear;

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
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MiniCandlePainter old) =>
      old.candles != candles || old.asLine != asLine;
}
