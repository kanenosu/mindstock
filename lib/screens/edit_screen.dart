import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../l10n.dart';
import '../providers.dart';
import '../theme.dart';

/// 編集画面（仕様書 §7 副次画面 / §3 微調整オプション）。
///
/// メイン導線には出さない。カレンダー／振り返りから該当日を開いた時だけ入る。
/// - AIが抽出した出来事をカードで並べる
/// - スライダーで重み調整（0〜10）、プラス/マイナスで方向反転
/// - 右端に変動値をリアルタイム表示
/// - 「＋手動追加」でAIの見逃しを補完
/// 保存時に再計算され、その日のローソク足が更新される。
class EditScreen extends ConsumerStatefulWidget {
  final String dateKey;

  const EditScreen({super.key, required this.dateKey});

  @override
  ConsumerState<EditScreen> createState() => _EditScreenState();
}

class _EditScreenState extends ConsumerState<EditScreen> {
  late List<LifeEvent> _events;

  @override
  void initState() {
    super.initState();
    final entry = ref.read(entriesProvider).valueOrNull?[widget.dateKey];
    _events = List.of(entry?.events ?? const []);
  }

  Future<void> _save() async {
    await ref
        .read(entriesProvider.notifier)
        .updateEvents(widget.dateKey, _events);
    if (mounted) Navigator.of(context).pop();
  }

  void _addManual() async {
    final i18n = context.i18n;
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(i18n.tr('add_event')),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: i18n.tr('event_example')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(i18n.tr('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(i18n.tr('edit_add')),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    setState(() {
      _events.add(
        LifeEvent(
          name: name,
          kind: EventKind.daily,
          isPositive: true,
          weight: 2,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    final parsed = DateTime.parse(widget.dateKey);
    final date = i18n.date(
      parsed,
      jaPattern: 'M月d日 (E)',
      enPattern: 'MMM d (EEE)',
    );
    final total = _events.fold<double>(0, (sum, e) => sum + e.delta);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          i18n.tr('edit_title', args: {'date': date}),
        ),
        actions: [
          TextButton(onPressed: _save, child: Text(i18n.tr('edit_save'))),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  i18n.tr('edit_total'),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                Text(
                  '${total >= 0 ? '+' : ''}${total.toStringAsFixed(1)}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: total >= 0 ? AppColors.bull : AppColors.bear,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _events.isEmpty
                ? Center(child: Text(i18n.tr('edit_empty')))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _events.length,
                    itemBuilder: (context, i) => _EventCard(
                      event: _events[i],
                      onChanged: (e) => setState(() => _events[i] = e),
                      onDeleted: () => setState(() => _events.removeAt(i)),
                    ),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addManual,
        tooltip: i18n.tr('edit_add'),
        child: const Icon(Icons.add),
      ),
    );
  }
}

/// 出来事カード（検証済みUI、仕様書 §3）。
class _EventCard extends StatelessWidget {
  final LifeEvent event;
  final ValueChanged<LifeEvent> onChanged;
  final VoidCallback onDeleted;

  const _EventCard({
    required this.event,
    required this.onChanged,
    required this.onDeleted,
  });

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    final color = event.isPositive ? AppColors.bull : AppColors.bear;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
        child: Column(
          children: [
            Row(
              children: [
                _kindBadge(context),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    event.name,
                    style: Theme.of(context).textTheme.titleSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // 変動値のリアルタイム表示（右端）
                Text(
                  '${event.isPositive ? '+' : '-'}${event.weight.toStringAsFixed(1)}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: onDeleted,
                ),
              ],
            ),
            Row(
              children: [
                // プラス/マイナス反転（AIの読み違え対策）
                IconButton(
                  icon: Icon(
                    event.isPositive
                        ? Icons.add_circle_outline
                        : Icons.remove_circle_outline,
                    color: color,
                  ),
                  tooltip: i18n.tr('edit_flip'),
                  onPressed: () =>
                      onChanged(event.copyWith(isPositive: !event.isPositive)),
                ),
                Expanded(
                  child: Builder(
                    builder: (context) {
                      // AI採点(baseImportance×倍率)は日常〜人生の節目まで
                      // 幅が広いため、現在値に応じて上限を可変にする。
                      final sliderMax = math.max(20.0, event.weight * 1.2);
                      return Slider(
                        value: event.weight.clamp(0, sliderMax),
                        min: 0,
                        max: sliderMax,
                        label: event.weight.toStringAsFixed(1),
                        activeColor: color,
                        onChanged: (v) => onChanged(event.copyWith(weight: v)),
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _kindBadge(BuildContext context) {
    final i18n = context.i18n;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        i18n.eventKindLabel(event.kind),
        style: Theme.of(context).textTheme.labelSmall,
      ),
    );
  }
}
