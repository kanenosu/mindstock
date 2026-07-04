import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// iOSのセグメンテッドコントロール風のピルセレクタ。
/// 選択中の項目に白いピルがスライドして重なる。
class PillSelector<T> extends StatelessWidget {
  final List<T> items;
  final T selected;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;

  const PillSelector({
    super.key,
    required this.items,
    required this.selected,
    required this.labelOf,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final index = items.indexOf(selected);
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = constraints.maxWidth / items.length;
        return Container(
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.ink.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                left: index * itemWidth + 3,
                top: 3,
                bottom: 3,
                width: itemWidth - 6,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(9),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.ink.withValues(alpha: 0.12),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  for (final item in items)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          if (item == selected) return;
                          HapticFeedback.selectionClick();
                          onChanged(item);
                        },
                        child: Center(
                          child: AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 180),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: item == selected
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                              color: item == selected
                                  ? AppColors.ink
                                  : AppColors.inkSoft,
                            ),
                            child: Text(labelOf(item)),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
