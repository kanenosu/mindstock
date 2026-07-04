import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../logic/chart_calculator.dart';
import '../models/models.dart';
import '../providers.dart';
import 'entry_screen.dart';
import 'review_screen.dart';

/// ダッシュボード（ホーム画面）。
///
/// - 現在値と昨日比のサマリー
/// - ミニチャート（タップでメインチャート画面へ）
/// - クイック入力欄（書く→即反映のコア体験をホームから直接）
/// - 日付を選んで過去のエントリーを書く導線
/// - 最近の記録
class DashboardScreen extends ConsumerStatefulWidget {
  /// ミニチャートタップ時にチャートタブへ切り替えるコールバック。
  final VoidCallback onOpenChart;

  const DashboardScreen({super.key, required this.onOpenChart});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  final _controller = TextEditingController();
  double? _mood;
  bool _submitting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submitQuick() async {
    final text = _controller.text.trim();
    if (text.isEmpty && _mood == null) return;
    setState(() => _submitting = true);
    try {
      await ref
          .read(entriesProvider.notifier)
          .submitDiary(date: DateTime.now(), text: text, moodScore: _mood);
      if (!mounted) return;
      _controller.clear();
      setState(() => _mood = null);
      FocusScope.of(context).unfocus();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('記録しました。チャートに反映済みです')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _pickDateAndWrite() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 10),
      lastDate: now,
    );
    if (picked == null || !mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => EntryScreen(initialDate: picked)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final daily = ref.watch(dailyCandlesProvider);
    final entries = ref.watch(entriesProvider).valueOrNull ?? {};
    final recent = entries.values.toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    return Scaffold(
      appBar: AppBar(
        title: const Text('MindStock'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_calendar_outlined),
            tooltip: '日付を選んで書く',
            onPressed: _pickDateAndWrite,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SummaryCard(daily: daily),
          const SizedBox(height: 12),
          _MiniChartCard(daily: daily, onTap: widget.onOpenChart),
          const SizedBox(height: 12),
          _quickEntryCard(context),
          const SizedBox(height: 20),
          if (recent.isNotEmpty) ...[
            Text('最近の記録', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            for (final entry in recent.take(3)) _recentTile(context, entry),
          ],
        ],
      ),
    );
  }

  Widget _quickEntryCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('今日を記録', style: Theme.of(context).textTheme.titleSmall),
                const Spacer(),
                Text(
                  DateFormat('M月d日 (E)', 'ja').format(DateTime.now()),
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(
                hintText: '今日のことを、ただ書くだけ。',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('😞', style: TextStyle(fontSize: 14)),
                Expanded(
                  child: Slider(
                    value: _mood ?? 5,
                    min: 0,
                    max: 10,
                    divisions: 20,
                    label: _mood?.toStringAsFixed(1) ?? '気分（任意）',
                    onChanged: (v) => setState(() => _mood = v),
                  ),
                ),
                const Text('😊', style: TextStyle(fontSize: 14)),
              ],
            ),
            FilledButton.icon(
              onPressed: _submitting ? null : _submitQuick,
              icon: _submitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: Text(_submitting ? '解析中…' : '記録する'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _recentTile(BuildContext context, DiaryEntry entry) {
    final total = entry.events.fold<double>(0, (sum, e) => sum + e.delta);
    final color =
        total >= 0 ? const Color(0xFF26A69A) : const Color(0xFFEF5350);
    final preview = entry.text.replaceAll('\n', ' ');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        DateFormat('M月d日 (E)', 'ja').format(entry.dateTime),
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      subtitle: preview.isEmpty
          ? null
          : Text(preview, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Text(
        '${total >= 0 ? '+' : ''}${total.toStringAsFixed(1)}',
        style: TextStyle(color: color, fontWeight: FontWeight.bold),
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ReviewScreen(date: entry.dateTime),
        ),
      ),
    );
  }
}

/// 現在値と比較のサマリーカード。
class _SummaryCard extends StatelessWidget {
  final List<Candle> daily;

  const _SummaryCard({required this.daily});

  @override
  Widget build(BuildContext context) {
    if (daily.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            '最初の日記を書くと、人生のチャートが生まれます。',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
    }
    final current = daily.last.close;
    final diffYesterday = ChartCalculator.changeSince(daily, 1);
    final diffMonth = ChartCalculator.changeSince(daily, 30);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('現在値', style: Theme.of(context).textTheme.labelMedium),
                  Text(
                    NumberFormat('#,##0.0').format(current),
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            _diffChip(context, '昨日比', diffYesterday),
            const SizedBox(width: 8),
            _diffChip(context, '1ヶ月', diffMonth),
          ],
        ),
      ),
    );
  }

  Widget _diffChip(BuildContext context, String label, double? diff) {
    if (diff == null) return const SizedBox.shrink();
    final color =
        diff >= 0 ? const Color(0xFF26A69A) : const Color(0xFFEF5350);
    return Column(
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 2),
        Text(
          '${diff >= 0 ? '+' : ''}${diff.toStringAsFixed(1)}',
          style: TextStyle(color: color, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}

/// ミニチャート。タップでメインチャート画面へ。
class _MiniChartCard extends StatelessWidget {
  final List<Candle> daily;
  final VoidCallback onTap;

  const _MiniChartCard({required this.daily, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('直近30日', style: Theme.of(context).textTheme.labelMedium),
                  const Spacer(),
                  Icon(
                    Icons.open_in_full,
                    size: 16,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 100,
                width: double.infinity,
                child: daily.isEmpty
                    ? Center(
                        child: Text(
                          'まだ記録がありません',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      )
                    : CustomPaint(
                        painter: _SparklinePainter(
                          candles: daily.length > 30
                              ? daily.sublist(daily.length - 30)
                              : daily,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 直近の終値を描く軽量スパークライン。
class _SparklinePainter extends CustomPainter {
  final List<Candle> candles;
  final Color color;

  _SparklinePainter({required this.candles, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (candles.length < 2) return;
    final minV = candles.map((c) => c.close).reduce(min);
    final maxV = candles.map((c) => c.close).reduce(max);
    final range = max(maxV - minV, 1e-6);

    double xFor(int i) => i / (candles.length - 1) * size.width;
    double yFor(double v) => (maxV - v) / range * (size.height - 8) + 4;

    final path = Path()..moveTo(xFor(0), yFor(candles.first.close));
    for (var i = 1; i < candles.length; i++) {
      path.lineTo(xFor(i), yFor(candles[i].close));
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    // 面のグラデーションで「チャートらしさ」を出す
    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.25), color.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );

    // 最新値の点
    canvas.drawCircle(
      Offset(xFor(candles.length - 1), yFor(candles.last.close)),
      3,
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter old) =>
      old.candles != candles || old.color != color;
}
