import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/models.dart';
import '../providers.dart';
import 'review_screen.dart';

/// カレンダー／一覧画面（仕様書 §7-4）。
///
/// 記録した日の一覧。各日を開くと振り返り → そこから編集画面に入れる。
class CalendarScreen extends ConsumerWidget {
  const CalendarScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(entriesProvider).valueOrNull ?? {};
    final sorted = entries.values.toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    return Scaffold(
      appBar: AppBar(title: const Text('記録一覧')),
      body: sorted.isEmpty
          ? const Center(child: Text('まだ記録がありません'))
          : ListView.separated(
              itemCount: sorted.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final entry = sorted[i];
                return _EntryTile(entry: entry);
              },
            ),
    );
  }
}

class _EntryTile extends ConsumerWidget {
  final DiaryEntry entry;

  const _EntryTile({required this.entry});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final total = entry.events.fold<double>(0, (sum, e) => sum + e.delta);
    final color = total >= 0 ? const Color(0xFF26A69A) : const Color(0xFFEF5350);
    final preview = entry.text.replaceAll('\n', ' ');

    return ListTile(
      title: Text(
        DateFormat('yyyy年M月d日 (E)', 'ja').format(entry.dateTime),
        style: Theme.of(context).textTheme.titleSmall,
      ),
      subtitle: preview.isEmpty
          ? null
          : Text(preview, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: Text(
        '${total >= 0 ? '+' : ''}${total.toStringAsFixed(1)}',
        style: TextStyle(color: color, fontWeight: FontWeight.bold),
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ReviewScreen(date: entry.dateTime),
        ),
      ),
      onLongPress: () => _confirmDelete(context, ref),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
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
  }
}
