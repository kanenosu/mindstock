import '../models/models.dart';
import '../l10n.dart';
import 'chart_calculator.dart';

enum AiSummaryStyle {
  balanced,
  compact,
  encouraging,
  neutral;

  String get key => switch (this) {
    AiSummaryStyle.balanced => 'balanced',
    AiSummaryStyle.compact => 'compact',
    AiSummaryStyle.encouraging => 'encouraging',
    AiSummaryStyle.neutral => 'neutral',
  };

  static AiSummaryStyle parse(String value) => switch (value) {
    'compact' => AiSummaryStyle.compact,
    'encouraging' => AiSummaryStyle.encouraging,
    'neutral' => AiSummaryStyle.neutral,
    _ => AiSummaryStyle.balanced,
  };
}

/// 1週間のまとめ。週足のローソクをタップした時や振り返り画面で表示する。
///
/// AIを使わずローカル集計だけで毎週自動生成される。
/// 「押し付けない」原則（仕様書 §6）に従い、headline は評価ではなく
/// 事実に寄り添う一言にする。
class WeeklySummary {
  /// 週の開始日（月曜）。
  final DateTime weekStart;

  /// その週の変動合計（気分スコア分は含まない出来事ベース）。
  final double totalDelta;

  /// 記録した日数。
  final int entryDays;

  /// 空白（平穏）日数。
  final int calmDays;

  /// プラスに終わった日数。
  final int upDays;

  /// マイナスに終わった日数。
  final int downDays;

  /// 週でいちばん大きかったポジティブの出来事。
  final LifeEvent? best;

  /// 週でいちばん大きかったネガティブの出来事。
  final LifeEvent? worst;

  /// 節目（マイルストーン）があったか。
  final bool hasMilestone;

  /// 週を一言で表すヘッドライン。
  final String headline;

  const WeeklySummary({
    required this.weekStart,
    required this.totalDelta,
    required this.entryDays,
    required this.calmDays,
    required this.upDays,
    required this.downDays,
    required this.best,
    required this.worst,
    required this.hasMilestone,
    required this.headline,
  });

  DateTime get weekEnd => weekStart.add(const Duration(days: 6));

  /// [anyDayInWeek] を含む週（月曜始まり）のまとめを計算する。
  static WeeklySummary compute(
    DateTime anyDayInWeek,
    Map<String, DiaryEntry> entries, {
    AppI18n? i18n,
    AiSummaryStyle style = AiSummaryStyle.balanced,
  }) {
    final weekStart = DateTime(
      anyDayInWeek.year,
      anyDayInWeek.month,
      anyDayInWeek.day,
    ).subtract(Duration(days: anyDayInWeek.weekday - 1));

    double total = 0;
    var entryDays = 0;
    var upDays = 0;
    var downDays = 0;
    LifeEvent? best;
    LifeEvent? worst;
    var hasMilestone = false;

    for (var i = 0; i < 7; i++) {
      final day = weekStart.add(Duration(days: i));
      final entry = entries[ChartCalculator.dateKey(day)];
      if (entry == null) continue;
      entryDays++;

      var dayTotal = 0.0;
      for (final e in entry.events) {
        dayTotal += e.delta;
        if (e.kind == EventKind.milestone) hasMilestone = true;
        if (e.isPositive && (best == null || e.weight > best.weight)) {
          best = e;
        }
        if (!e.isPositive && (worst == null || e.weight > worst.weight)) {
          worst = e;
        }
      }
      if (entry.moodScore != null) {
        dayTotal += ChartCalculator.moodDelta(entry.moodScore!);
      }
      total += dayTotal;
      if (dayTotal >= 0) {
        upDays++;
      } else {
        downDays++;
      }
    }

    return WeeklySummary(
      weekStart: weekStart,
      totalDelta: total,
      entryDays: entryDays,
      calmDays: 7 - entryDays,
      upDays: upDays,
      downDays: downDays,
      best: best,
      worst: worst,
      hasMilestone: hasMilestone,
      headline: _headline(
        total: total,
        entryDays: entryDays,
        best: best,
        worst: worst,
        hasMilestone: hasMilestone,
        style: style,
        i18n: i18n ?? const AppI18n('ja'),
      ),
    );
  }

  static String _headline({
    required double total,
    required int entryDays,
    required LifeEvent? best,
    required LifeEvent? worst,
    required bool hasMilestone,
    required AiSummaryStyle style,
    required AppI18n i18n,
  }) {
    if (entryDays == 0) {
      return style == AiSummaryStyle.compact
          ? i18n.tr('summary_no_records_compact')
          : style == AiSummaryStyle.encouraging
          ? i18n.tr('summary_no_records_encouraging')
          : style == AiSummaryStyle.neutral
          ? i18n.tr('summary_no_records_neutral')
          : i18n.tr('summary_no_records');
    }
    if (hasMilestone) {
      final milestone = (best != null && best.kind == EventKind.milestone)
          ? best
          : worst;
      if (milestone != null) {
        return switch (style) {
          AiSummaryStyle.compact => i18n.tr(
            'summary_milestone_compact',
            args: {'name': milestone.name},
          ),
          AiSummaryStyle.encouraging => i18n.tr(
            'summary_milestone_encouraging',
            args: {'name': milestone.name},
          ),
          AiSummaryStyle.neutral => i18n.tr(
            'summary_milestone_neutral',
            args: {'name': milestone.name},
          ),
          AiSummaryStyle.balanced => i18n.tr(
            'summary_milestone',
            args: {'name': milestone.name},
          ),
        };
      }
    }
    if (total >= 3) {
      return best != null
          ? switch (style) {
              AiSummaryStyle.compact => i18n.tr(
                'summary_up_with_name_compact',
                args: {'name': best.name},
              ),
              AiSummaryStyle.encouraging => i18n.tr(
                'summary_up_with_name_encouraging',
                args: {'name': best.name},
              ),
              AiSummaryStyle.neutral => i18n.tr(
                'summary_up_with_name_neutral',
                args: {'name': best.name},
              ),
              AiSummaryStyle.balanced => i18n.tr(
                'summary_up_with_name',
                args: {'name': best.name},
              ),
            }
          : switch (style) {
              AiSummaryStyle.compact => i18n.tr('summary_up_plain_compact'),
              AiSummaryStyle.encouraging => i18n.tr(
                'summary_up_plain_encouraging',
              ),
              AiSummaryStyle.neutral => i18n.tr('summary_up_plain_neutral'),
              AiSummaryStyle.balanced => i18n.tr('summary_up_plain'),
            };
    }
    if (total <= -3) {
      return best != null
          ? switch (style) {
              AiSummaryStyle.compact => i18n.tr(
                'summary_down_with_name_compact',
                args: {'name': best.name},
              ),
              AiSummaryStyle.encouraging => i18n.tr(
                'summary_down_with_name_encouraging',
                args: {'name': best.name},
              ),
              AiSummaryStyle.neutral => i18n.tr(
                'summary_down_with_name_neutral',
                args: {'name': best.name},
              ),
              AiSummaryStyle.balanced => i18n.tr(
                'summary_down_with_name',
                args: {'name': best.name},
              ),
            }
          : switch (style) {
              AiSummaryStyle.compact => i18n.tr('summary_down_plain_compact'),
              AiSummaryStyle.encouraging => i18n.tr(
                'summary_down_plain_encouraging',
              ),
              AiSummaryStyle.neutral => i18n.tr('summary_down_plain_neutral'),
              AiSummaryStyle.balanced => i18n.tr('summary_down_plain'),
            };
    }
    return switch (style) {
      AiSummaryStyle.compact => i18n.tr('summary_flat_compact'),
      AiSummaryStyle.encouraging => i18n.tr('summary_flat_encouraging'),
      AiSummaryStyle.neutral => i18n.tr('summary_flat_neutral'),
      AiSummaryStyle.balanced => i18n.tr('summary_flat'),
    };
  }
}
