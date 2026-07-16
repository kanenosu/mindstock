import 'package:flutter_test/flutter_test.dart';
import 'package:mindstock/models/models.dart';
import 'package:mindstock/services/diary_analyzer.dart';

void main() {
  group('HeuristicDiaryAnalyzer', () {
    final analyzer = HeuristicDiaryAnalyzer();

    test('ポジティブ・ネガティブの出来事を抽出する', () async {
      final events = await analyzer.analyze('試験に合格した。でも少し疲れた。', []);
      expect(events, isNotEmpty);
      expect(events.any((e) => e.isPositive), isTrue);
      expect(events.any((e) => !e.isPositive), isTrue);
    });

    test('損失回避: 同じ基礎点ならネガティブが重くなる', () async {
      final pos = await analyzer.analyze('嬉しいことがあった', []);
      final neg = await analyzer.analyze('辛いことがあった', []);
      // 基礎点: 嬉しい2.0 / 辛い2.5 → 損失回避1.4倍で 3.5
      expect(neg.first.weight, greaterThan(pos.first.weight * 1.3));
    });

    test('何も引っかからなくても記録自体を小さな日常として残す', () async {
      final events = await analyzer.analyze('今日はごはんを食べた。', []);
      expect(events, hasLength(1));
      expect(events.first.kind, EventKind.daily);
      expect(events.first.weight, lessThanOrEqualTo(1));
    });

    test('最大4件まで', () async {
      final events = await analyzer.analyze('嬉しい。楽しい。最高。幸せ。感謝。ありがとう。成功した。', []);
      expect(events.length, lessThanOrEqualTo(4));
    });
  });

  test('強化したプロンプトに決意を排除する具体例と判定基準が含まれる', () {
    expect(kAnalyzerSystemPrompt, contains('「これから毎日走る」'));
    expect(
      kAnalyzerSystemPrompt,
      contains('〜たい / 〜しよう / 〜するつもり / 〜になる / 〜がんばる'),
    );
    expect(kAnalyzerSystemPrompt, contains('「強い男になると決めた。」'));
  });

  group('LifeEvent', () {
    test('delta は方向×重み', () {
      const e = LifeEvent(
        name: 'x',
        kind: EventKind.mood,
        isPositive: false,
        weight: 3,
      );
      expect(e.delta, -3);
      expect(e.copyWith(isPositive: true).delta, 3);
    });

    test('JSON round-trip', () {
      const e = LifeEvent(
        name: '合格',
        kind: EventKind.milestone,
        isPositive: true,
        weight: 8.5,
      );
      final restored = LifeEvent.fromJson(e.toJson());
      expect(restored.name, e.name);
      expect(restored.kind, e.kind);
      expect(restored.isPositive, e.isPositive);
      expect(restored.weight, e.weight);
    });
  });
}
