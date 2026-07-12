import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../logic/chart_calculator.dart';
import '../models/models.dart';
import '../providers.dart';
import '../theme.dart';

/// 日記用カレンダー。
///
/// 記録がある日には 緑●（トータルでプラス）/ 赤●（マイナス）のドットが付き、
/// 日付をタップするとその日にすぐ移動できる。
/// 普段はコンパクトな1週間表示、シェブロンで月表示に展開する。
/// 未来の日付は選べない。
class DiaryCalendar extends ConsumerStatefulWidget {
  final DateTime selected;
  final ValueChanged<DateTime> onSelect;

  const DiaryCalendar({
    super.key,
    required this.selected,
    required this.onSelect,
  });

  @override
  ConsumerState<DiaryCalendar> createState() => _DiaryCalendarState();
}

class _DiaryCalendarState extends ConsumerState<DiaryCalendar> {
  bool _expanded = false;

  /// 表示の基準日。週モードならこの日を含む週、月モードならこの日の月を表示。
  late DateTime _anchor = widget.selected;

  @override
  void didUpdateWidget(covariant DiaryCalendar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected != oldWidget.selected) _anchor = widget.selected;
  }

  DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  void _shift(int direction) {
    HapticFeedback.selectionClick();
    setState(() {
      _anchor = _expanded
          ? DateTime(_anchor.year, _anchor.month + direction)
          : _anchor.add(Duration(days: 7 * direction));
    });
  }

  @override
  Widget build(BuildContext context) {
    final entries = ref.watch(entriesProvider).valueOrNull ?? {};

    return Card(
      // 横スワイプで週/月を送れる（シェブロンと同じ操作）
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragEnd: (details) {
          final velocity = details.primaryVelocity ?? 0;
          if (velocity < -200) _shift(1);
          if (velocity > 200) _shift(-1);
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          child: Column(
            children: [
              _headerRow(context),
              const SizedBox(height: 4),
              _weekdayRow(context),
              const SizedBox(height: 4),
              AnimatedSize(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: _expanded
                    ? _monthGrid(context, entries)
                    : _weekRow(context, entries),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _headerRow(BuildContext context) {
    return Row(
      children: [
        const SizedBox(width: 4),
        Text(
          DateFormat('yyyy年M月', 'ja').format(_anchor),
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(width: 4),
        // 今日へ戻るショートカット（今日以外を見ている時だけ表示）
        if (!DateUtils.isSameDay(widget.selected, _today) ||
            !DateUtils.isSameMonth(_anchor, _today))
          TextButton(
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            onPressed: () {
              HapticFeedback.selectionClick();
              setState(() => _anchor = _today);
              widget.onSelect(_today);
            },
            child: const Text('今日', style: TextStyle(fontSize: 12)),
          ),
        const Spacer(),
        _navButton(Icons.chevron_left, () => _shift(-1)),
        _navButton(Icons.chevron_right, () => _shift(1)),
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: AnimatedRotation(
            turns: _expanded ? 0.5 : 0,
            duration: const Duration(milliseconds: 200),
            child: const Icon(Icons.expand_more, size: 20),
          ),
          tooltip: _expanded ? '週表示にする' : '月表示にする',
          onPressed: () {
            HapticFeedback.selectionClick();
            setState(() => _expanded = !_expanded);
          },
        ),
      ],
    );
  }

  Widget _navButton(IconData icon, VoidCallback onTap) => IconButton(
    visualDensity: VisualDensity.compact,
    icon: Icon(icon, size: 20, color: AppColors.inkSoft),
    onPressed: onTap,
  );

  Widget _weekdayRow(BuildContext context) {
    const labels = ['月', '火', '水', '木', '金', '土', '日'];
    return Row(
      children: [
        for (final label in labels)
          Expanded(
            child: Center(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppColors.inkSoft,
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// コンパクト表示: 基準日を含む1週間（月曜始まり）。
  Widget _weekRow(BuildContext context, Map<String, DiaryEntry> entries) {
    final monday = _anchor.subtract(Duration(days: _anchor.weekday - 1));
    return Row(
      children: [
        for (var i = 0; i < 7; i++)
          Expanded(
            child: _dayCell(context, monday.add(Duration(days: i)), entries),
          ),
      ],
    );
  }

  /// 月表示: その月の全週（月初を含む週 〜 月末を含む週）。
  Widget _monthGrid(BuildContext context, Map<String, DiaryEntry> entries) {
    final first = DateTime(_anchor.year, _anchor.month, 1);
    final firstMonday = first.subtract(Duration(days: first.weekday - 1));
    final lastDay = DateTime(_anchor.year, _anchor.month + 1, 0);
    final weeks = (lastDay.difference(firstMonday).inDays + 1) / 7;

    return Column(
      children: [
        for (var w = 0; w < weeks.ceil(); w++)
          Row(
            children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: _dayCell(
                    context,
                    firstMonday.add(Duration(days: w * 7 + i)),
                    entries,
                    dimOutsideMonth: true,
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Widget _dayCell(
    BuildContext context,
    DateTime day,
    Map<String, DiaryEntry> entries, {
    bool dimOutsideMonth = false,
  }) {
    final isFuture = day.isAfter(_today);
    final isSelected = DateUtils.isSameDay(day, widget.selected);
    final isToday = DateUtils.isSameDay(day, _today);
    final outsideMonth = dimOutsideMonth && day.month != _anchor.month;

    final entry = entries[ChartCalculator.dateKey(day)];
    final total = entry?.events.fold<double>(0, (sum, e) => sum + e.delta);

    final textColor = isSelected
        ? Colors.white
        : isFuture || outsideMonth
        ? AppColors.inkSoft.withValues(alpha: 0.35)
        : AppColors.ink;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: isFuture
          ? null
          : () {
              HapticFeedback.selectionClick();
              setState(() => _anchor = day);
              widget.onSelect(day);
            },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isSelected ? AppColors.inkButton : Colors.transparent,
                shape: BoxShape.circle,
                border: isToday && !isSelected
                    ? Border.all(color: AppColors.accent, width: 1.5)
                    : null,
              ),
              child: Text(
                '${day.day}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected || isToday
                      ? FontWeight.w800
                      : FontWeight.w600,
                  color: textColor,
                ),
              ),
            ),
            const SizedBox(height: 2),
            // 記録ドット: 緑● = プラスの日 / 赤● = マイナスの日
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: total == null
                    ? Colors.transparent
                    : total >= 0
                    ? AppColors.bull
                    : AppColors.bear,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
