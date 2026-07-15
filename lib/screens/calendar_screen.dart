import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../logic/chart_calculator.dart';
import '../models/models.dart';
import '../providers.dart';
import '../theme.dart';
import '../widgets/diary_calendar.dart';
import '../widgets/motion.dart';
import 'entry_screen.dart';
import 'review_screen.dart';

/// 記録画面（仕様書 §7-4）。
///
/// 上部にカレンダー（緑●/赤● = その日の記録）、
/// 下に月ごとにまとまった記録リスト。
/// カレンダーの日付タップ: 記録あり → 振り返り / なし → その日の日記を書く。
class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  DateTime _selected = DateTime.now();

  void _onSelectDate(DateTime date) {
    setState(() => _selected = date);
    final entries = ref.read(entriesProvider).valueOrNull ?? {};
    final hasEntry = entries.containsKey(ChartCalculator.dateKey(date));
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => hasEntry
            ? ReviewScreen(date: date)
            : EntryScreen(initialDate: date),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entries = ref.watch(entriesProvider).valueOrNull ?? {};
    final sorted = entries.values.toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    // 月ごとにグループ化（新しい月から）
    final groups = <String, List<DiaryEntry>>{};
    for (final entry in sorted) {
      final key = entry.date.substring(0, 7); // 'yyyy-MM'
      groups.putIfAbsent(key, () => []).add(entry);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('記録')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          FadeSlideIn(
            child: DiaryCalendar(selected: _selected, onSelect: _onSelectDate),
          ),
          const SizedBox(height: 16),
          if (sorted.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 48),
              child: Center(child: Text('まだ記録がありません')),
            )
          else
            for (final (gi, group) in groups.entries.indexed) ...[
              FadeSlideIn(
                delayMs: ((gi + 1) * 60).clamp(0, 300),
                child: _MonthSection(
                  monthKey: group.key,
                  entries: group.value,
                ),
              ),
              const SizedBox(height: 16),
            ],
        ],
      ),
    );
  }
}

/// 1ヶ月分のセクション（見出し + 月間合計 + 記録カード）。
class _MonthSection extends ConsumerWidget {
  final String monthKey; // 'yyyy-MM'
  final List<DiaryEntry> entries;

  const _MonthSection({required this.monthKey, required this.entries});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = DateTime.parse('$monthKey-01');
    final monthTotal = entries.fold<double>(
      0,
      (sum, e) => sum + e.events.fold<double>(0, (s, ev) => s + ev.delta),
    );
    final totalColor = monthTotal >= 0 ? AppColors.bull : AppColors.bear;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Row(
            children: [
              Text(
                DateFormat('yyyy年M月', 'ja').format(month),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${entries.length}件',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.inkSoft,
                ),
              ),
              const Spacer(),
              Text(
                '${monthTotal >= 0 ? '+' : ''}${monthTotal.toStringAsFixed(1)}',
                style: TextStyle(
                  color: totalColor,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (final (i, entry) in entries.indexed) ...[
                if (i > 0) const Divider(height: 1, indent: 20, endIndent: 20),
                _EntryTile(entry: entry),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _EntryTile extends ConsumerWidget {
  final DiaryEntry entry;

  const _EntryTile({required this.entry});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final total = entry.events.fold<double>(0, (sum, e) => sum + e.delta);
    final color = total >= 0 ? AppColors.bull : AppColors.bear;
    final preview = entry.text.replaceAll('\n', ' ');
    final day = entry.dateTime;

    // 左スワイプで削除（確認ダイアログ付き、iOS標準の操作感）
    return Dismissible(
      key: ValueKey(entry.date),
      direction: DismissDirection.endToStart,
      background: Container(
        color: AppColors.bear,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      confirmDismiss: (_) => _confirmDelete(context, ref),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        // 日付チップ（曜日+日）で一覧性を上げる
        leading: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                DateFormat('E', 'ja').format(day),
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              Text(
                '${day.day}',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: color,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
        title: Text(
          preview.isEmpty ? '気分だけ記録した日' : preview,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
        subtitle: entry.events.isEmpty
            ? null
            : Text(
                entry.events.map((e) => e.name).join(' / '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.inkSoft,
                ),
              ),
        trailing: Text(
          '${total >= 0 ? '+' : ''}${total.toStringAsFixed(1)}',
          style: TextStyle(color: color, fontWeight: FontWeight.w800),
        ),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ReviewScreen(date: day)),
        ),
        onLongPress: () => _confirmDelete(context, ref),
      ),
    );
  }

  /// 削除確認。削除を実行したら true を返す（Dismissible の判定にも使う）。
  Future<bool> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('この記録を削除しますか？'),
        content: Text(DateFormat('yyyy年M月d日', 'ja').format(entry.dateTime)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(entriesProvider.notifier).deleteEntry(entry.date);
    }
    return ok == true;
  }
}
