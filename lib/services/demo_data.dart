import 'dart:math';

import '../logic/chart_calculator.dart';
import '../models/models.dart';
import 'diary_analyzer.dart';

/// デモデータ生成器。
///
/// チャートの良さ（谷があるから成長が見える、仕様書 §6）を
/// 記録ゼロの状態でも確認できるように、過去約4ヶ月分の
/// サンプル日記を生成する。中盤に「どん底の谷」と回復の軌跡を仕込む。
/// シード固定なので何度投入しても同じデータになる。
///
/// 採点は実際の解析（AI／オフライン）と同じ [OfflineScoring] のスケールで
/// 作るので、サンプルと実データのチャートの迫力が揃う（改善点§3）。
class DemoDataGenerator {
  static const int days = 120;

  /// (本文テンプレート, 出来事名, 種別, baseImportance 1〜100)
  static const _positivePool = [
    ('友人とご飯に行って笑いっぱなしだった。', '友人と食事', EventKind.daily, 10.0),
    ('仕事で提案が通った。準備した甲斐があった。', '提案が通った', EventKind.daily, 14.0),
    ('朝ランニングをして気分が良かった。', '朝ラン', EventKind.mood, 5.0),
    ('読みたかった本を読み終えた。', '読書を完走', EventKind.daily, 6.0),
    ('上司に褒められた。素直に嬉しい。', '褒められた', EventKind.daily, 9.0),
    ('久しぶりに実家に帰ってゆっくりした。', '帰省', EventKind.daily, 8.0),
    ('新しいカフェを見つけた。コーヒーが最高。', 'カフェ開拓', EventKind.mood, 4.0),
    ('筋トレを1ヶ月続けられている。', '筋トレ継続', EventKind.daily, 8.0),
  ];

  static const _negativePool = [
    ('仕事でミスをして落ち込んだ。', '仕事のミス', EventKind.daily, 10.0),
    ('よく眠れなくて一日中だるかった。', '寝不足', EventKind.mood, 5.0),
    ('友人と些細なことで言い合いになった。', '友人と口論', EventKind.daily, 10.0),
    ('電車が遅延して大事な予定に遅れた。', '遅刻', EventKind.daily, 6.0),
    ('体調を崩して寝込んだ。', '体調不良', EventKind.daily, 16.0),
    ('何もやる気が出ない一日だった。', '無気力', EventKind.mood, 7.0),
  ];

  /// 谷とその回復のシナリオ（今日から何日前, 本文, 出来事, 種別, 方向, baseImportance）
  static const _arc = [
    (
      75,
      '長く関わったプロジェクトが打ち切りになった。頭が真っ白だ。',
      'プロジェクト打ち切り',
      EventKind.milestone,
      false,
      60.0,
    ),
    (72, '何も手につかない。夜も眠れない。', '眠れない日々', EventKind.mood, false, 12.0),
    (68, '信頼していた先輩が会社を去った。心細い。', '先輩の退職', EventKind.daily, false, 22.0),
    (60, '休みを取って海を見に行った。少しだけ息ができた気がする。', '海を見に行った', EventKind.daily, true, 8.0),
    (52, '小さなタスクを一つ片付けた。それだけで今日は十分。', '小さな一歩', EventKind.daily, true, 6.0),
    (45, '新しいチームでの初仕事。緊張したが悪くなかった。', '新チーム始動', EventKind.daily, true, 14.0),
    (
      30,
      '新しいプロジェクトの提案が採用された。あの経験が活きた。',
      '提案採用',
      EventKind.milestone,
      true,
      55.0,
    ),
    (14, 'ふと気づいたら、あの頃より随分と楽に呼吸ができている。', '回復の実感', EventKind.mood, true, 12.0),
  ];

  /// 過去 [days] 日分のエントリーを生成する。
  static List<DiaryEntry> generate({DateTime? today}) {
    final now = today ?? DateTime.now();
    final end = DateTime(now.year, now.month, now.day);
    final random = Random(42);
    final entries = <String, DiaryEntry>{};

    for (var ago = days - 1; ago >= 0; ago--) {
      final date = end.subtract(Duration(days: ago));
      final key = ChartCalculator.dateKey(date);

      // 谷のシナリオ日はそちらを優先
      final scripted = _arc.where((a) => a.$1 == ago).toList();
      if (scripted.isNotEmpty) {
        final s = scripted.first;
        entries[key] = DiaryEntry(
          date: key,
          text: s.$2,
          events: [
            _event(
              name: s.$3,
              kind: s.$4,
              isPositive: s.$5,
              baseImportance: s.$6,
              random: random,
            ),
          ],
        );
        continue;
      }

      // 空白日も作る（空白＝平穏、を見せるため）
      if (random.nextDouble() < 0.35) continue;

      // 谷の期間(75〜50日前)はネガティブ寄り、それ以外は少しポジティブ寄り
      final inValley = ago <= 75 && ago >= 50;
      final positiveProb = inValley ? 0.3 : 0.65;

      final count = 1 + random.nextInt(2);
      final events = <LifeEvent>[];
      final texts = <String>[];
      for (var i = 0; i < count; i++) {
        if (random.nextDouble() < positiveProb) {
          final p = _positivePool[random.nextInt(_positivePool.length)];
          texts.add(p.$1);
          events.add(
            _event(
              name: p.$2,
              kind: p.$3,
              isPositive: true,
              baseImportance: p.$4,
              random: random,
            ),
          );
        } else {
          final n = _negativePool[random.nextInt(_negativePool.length)];
          texts.add(n.$1);
          events.add(
            _event(
              name: n.$2,
              kind: n.$3,
              isPositive: false,
              baseImportance: n.$4,
              random: random,
            ),
          );
        }
      }

      entries[key] = DiaryEntry(
        date: key,
        text: texts.join('\n'),
        moodScore: random.nextDouble() < 0.3
            ? (random.nextDouble() * 10).roundToDouble()
            : null,
        events: events,
      );
    }
    return entries.values.toList();
  }

  /// baseImportance に ±20% のゆらぎを与え、[OfflineScoring] の式で
  /// 実データと同じスケールの変動値を持つ出来事を作る。
  static LifeEvent _event({
    required String name,
    required EventKind kind,
    required bool isPositive,
    required double baseImportance,
    required Random random,
  }) {
    final varied = baseImportance * (0.8 + random.nextDouble() * 0.4);
    return LifeEvent(
      name: name,
      kind: kind,
      isPositive: isPositive,
      weight: OfflineScoring.weightFor(
        baseImportance: varied,
        kind: kind,
        isPositive: isPositive,
      ),
    );
  }
}
