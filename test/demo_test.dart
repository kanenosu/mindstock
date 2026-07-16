import 'package:flutter_test/flutter_test.dart';
import 'package:mindstock/models/models.dart';
import 'package:mindstock/services/demo_data.dart';
import 'package:mindstock/services/diary_analyzer.dart';

void main() {
  group('DemoDiaryAnalyzer', () {
    final analyzer = DemoDiaryAnalyzer();

    test('文単位で出来事を抽出し、名前は文から切り出す', () async {
      final events = await analyzer.analyze('試験に合格した。夜は友達と祝杯をあげて楽しかった。', []);
      expect(events, isNotEmpty);
      expect(events.length, lessThanOrEqualTo(4));
      // 名前は15文字以内
      for (final e in events) {
        expect(e.name.length, lessThanOrEqualTo(15));
      }
    });

    test('節目キーワードは milestone として大きめに採点', () async {
      final events = await analyzer.analyze('第一志望に合格した。嬉しい。', []);
      final milestone = events.where((e) => e.kind == EventKind.milestone);
      expect(milestone, isNotEmpty);
      expect(milestone.first.weight, greaterThanOrEqualTo(4));
    });

    test('損失回避: ネガティブ文が重めに採点される', () async {
      final pos = await analyzer.analyze('嬉しいことがあった', []);
      final neg = await analyzer.analyze('辛いことがあった', []);
      expect(neg.first.weight, greaterThan(pos.first.weight));
    });

    test('快楽順応: 似た出来事が続くと点数が減衰する', () async {
      final first = await analyzer.analyze('バイトで褒められた', []);
      final past = [
        DiaryEntry(date: '2026-01-01', text: '', events: first),
        DiaryEntry(date: '2026-01-02', text: '', events: first),
      ];
      final third = await analyzer.analyze('バイトで褒められた', past);
      expect(third.first.weight, lessThan(first.first.weight));
    });

    test('何も引っかからなくても記録自体を小さな日常として残す', () async {
      final events = await analyzer.analyze('今日はごはんを食べた', []);
      expect(events, hasLength(1));
      expect(events.first.weight, lessThanOrEqualTo(1));
    });
  });

  group('DemoDataGenerator', () {
    test('シード固定で決定的に生成される', () {
      final today = DateTime(2026, 7, 4);
      final a = DemoDataGenerator.generate(today: today);
      final b = DemoDataGenerator.generate(today: today);
      expect(a.length, b.length);
      expect(a.first.date, b.first.date);
      expect(a.first.text, b.first.text);
    });

    test('約4ヶ月分・空白日込みで生成され、谷のシナリオを含む', () {
      final entries = DemoDataGenerator.generate(today: DateTime(2026, 7, 4));
      // 空白日があるので日数より少ない
      expect(entries.length, lessThan(DemoDataGenerator.days));
      expect(entries.length, greaterThan(DemoDataGenerator.days ~/ 2));
      // 谷のシナリオ（節目のネガティブ）が含まれる
      final milestones = entries
          .expand((e) => e.events)
          .where((e) => e.kind == EventKind.milestone);
      expect(milestones.any((e) => !e.isPositive), isTrue);
      expect(milestones.any((e) => e.isPositive), isTrue);
    });
  });
}
