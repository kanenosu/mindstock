import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/models.dart';

/// 日記文章 → 出来事の構造化データ を抽出するインターフェース。
abstract interface class DiaryAnalyzer {
  /// [text] を解析して出来事リストを返す。
  /// [recentEntries] は快楽順応の判定材料として渡す直近の日記（新しい順）。
  Future<List<LifeEvent>> analyze(String text, List<DiaryEntry> recentEntries);
}

/// 採点プロンプト（仕様書 §4 プロンプト設計の核）。Claude / ChatGPT で共通。
///
/// スコアリング自体に以下を織り込む:
/// 1. 出来事の客観的重要度
/// 2. 快楽順応 — 直近の日記を渡し、似た出来事が続けば点数を下げる
/// 3. 損失回避 — ネガティブは 1.3〜1.5 倍重く採点する
const kAnalyzerSystemPrompt = '''
あなたは日記アプリの解析エンジンです。ユーザーの日記本文から「出来事」を抽出し、
人生チャート（株価のようなチャート）への変動値を採点します。

採点ルール:
1. 出来事の客観的な重要度を判定する（合格・失恋級 = 大、日常の小さな喜び = 小）。
   ただし判定するのは客観的な性質と重要度のレンジまで。本人の主観的な感じ方を勝手に決めつけない。
2. 快楽順応: 「直近の日記」に似た出来事が繰り返し登場している場合、今回の点数を意図的に下げる。
   例: 「またバイトで褒められた」が3回目なら、1回目より明確に低く採点する。
3. 損失回避: 同じ重要度でも、ネガティブな出来事はポジティブより1.3〜1.5倍重く採点する。

出力ルール:
- 1日あたり最大4件まで。重要なものから抽出する。
- name は日本語で15文字以内の短い名詞句。
- kind: "daily"(日常の出来事) / "mood"(気分・感情の揺れ) / "milestone"(人生の節目)。
- isPositive: 出来事の方向。
- weight: 0〜10 の実数。日常の小さな出来事は 0.5〜2、普通の出来事は 2〜4、
  大きな出来事は 4〜7、人生の節目級は 7〜10 を目安にする。
- 出来事が読み取れない場合は空の配列を返す。
''';

/// 直近の日記（快楽順応の判定材料）込みのユーザーメッセージを組み立てる。
String buildAnalyzerUserMessage(String text, List<DiaryEntry> recentEntries) {
  final recent = recentEntries
      .take(7)
      .map((e) => '- ${e.date}: ${_summarizeEntry(e)}')
      .join('\n');
  return '直近の日記（快楽順応の判定に使うこと）:\n'
      '${recent.isEmpty ? '（なし）' : recent}\n\n'
      '今日の日記本文:\n$text';
}

String _summarizeEntry(DiaryEntry e) {
  if (e.events.isNotEmpty) {
    return e.events
        .map((ev) => '${ev.name}(${ev.isPositive ? '+' : '-'}${ev.weight})')
        .join(', ');
  }
  final t = e.text.replaceAll('\n', ' ');
  return t.length > 40 ? '${t.substring(0, 40)}…' : t;
}

/// 解析結果JSONの events 配列を LifeEvent に変換する（両プロバイダー共通）。
List<LifeEvent> parseAnalyzerEvents(dynamic parsed) {
  if (parsed is! Map<String, dynamic>) return const [];
  return ((parsed['events'] as List?) ?? const [])
      .whereType<Map<String, dynamic>>()
      .map(LifeEvent.fromJson)
      .take(4)
      .toList();
}

/// Claude API による解析（仕様書 §4 プロンプト設計の核）。
///
/// スコアリング自体に以下を織り込む:
/// 1. 出来事の客観的重要度
/// 2. 快楽順応 — 直近の日記を渡し、似た出来事が続けば点数を下げる
/// 3. 損失回避 — ネガティブは 1.3〜1.5 倍重く採点する
class ClaudeDiaryAnalyzer implements DiaryAnalyzer {
  static const _endpoint = 'https://api.anthropic.com/v1/messages';
  static const _model = 'claude-haiku-4-5';

  final String apiKey;
  final http.Client _client;

  ClaudeDiaryAnalyzer({required this.apiKey, http.Client? client})
    : _client = client ?? http.Client();

  static const _outputSchema = {
    'type': 'object',
    'properties': {
      'events': {
        'type': 'array',
        'items': {
          'type': 'object',
          'properties': {
            'name': {'type': 'string'},
            'kind': {
              'type': 'string',
              'enum': ['daily', 'mood', 'milestone'],
            },
            'isPositive': {'type': 'boolean'},
            'weight': {'type': 'number'},
          },
          'required': ['name', 'kind', 'isPositive', 'weight'],
          'additionalProperties': false,
        },
      },
    },
    'required': ['events'],
    'additionalProperties': false,
  };

  @override
  Future<List<LifeEvent>> analyze(
    String text,
    List<DiaryEntry> recentEntries,
  ) async {
    final response = await _client.post(
      Uri.parse(_endpoint),
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
      },
      body: jsonEncode({
        'model': _model,
        'max_tokens': 2048,
        'system': kAnalyzerSystemPrompt,
        'output_config': {
          'format': {'type': 'json_schema', 'schema': _outputSchema},
        },
        'messages': [
          {
            'role': 'user',
            'content': buildAnalyzerUserMessage(text, recentEntries),
          },
        ],
      }),
    );

    if (response.statusCode != 200) {
      throw AnalyzerException(
        'Claude API error ${response.statusCode}: ${response.body}',
      );
    }

    final body = jsonDecode(utf8.decode(response.bodyBytes));
    if (body['stop_reason'] == 'refusal') {
      // 安全上の理由で解析できなかった日はイベント無しとして扱う。
      return const [];
    }

    final textBlock = (body['content'] as List).firstWhere(
      (b) => b['type'] == 'text',
      orElse: () => null,
    );
    if (textBlock == null) return const [];

    return parseAnalyzerEvents(jsonDecode(textBlock['text'] as String));
  }
}

/// OpenAI Chat Completions (ChatGPT) による解析。
/// プロンプトはClaude版と共通で、JSONモードで構造化出力を受け取る。
class OpenAiDiaryAnalyzer implements DiaryAnalyzer {
  static const _endpoint = 'https://api.openai.com/v1/chat/completions';
  static const _model = 'gpt-4o-mini';

  final String apiKey;
  final http.Client _client;

  OpenAiDiaryAnalyzer({required this.apiKey, http.Client? client})
    : _client = client ?? http.Client();

  @override
  Future<List<LifeEvent>> analyze(
    String text,
    List<DiaryEntry> recentEntries,
  ) async {
    final response = await _client.post(
      Uri.parse(_endpoint),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode({
        'model': _model,
        'response_format': {'type': 'json_object'},
        'messages': [
          {
            'role': 'system',
            'content':
                '$kAnalyzerSystemPrompt\n'
                '必ず {"events": [{"name","kind","isPositive","weight"}, ...]} '
                'の形のJSONオブジェクトのみを出力すること。',
          },
          {
            'role': 'user',
            'content': buildAnalyzerUserMessage(text, recentEntries),
          },
        ],
      }),
    );

    if (response.statusCode != 200) {
      throw AnalyzerException(
        'OpenAI API error ${response.statusCode}: ${response.body}',
      );
    }

    final body = jsonDecode(utf8.decode(response.bodyBytes));
    final content =
        body['choices']?[0]?['message']?['content'] as String? ?? '{}';
    return parseAnalyzerEvents(jsonDecode(content));
  }
}

/// デモ解析器（API不要）。
///
/// Claude APIを使わずに「AIが解析した風」の結果を返す。
/// 文単位で出来事を抽出し、名前は文そのものから切り出すので
/// キーワードの羅列より本物の解析に近い見た目になる。
/// 快楽順応（似た出来事の減衰）と損失回避（ネガティブ1.4倍）も
/// 本実装と同じ思想でシミュレートする。
class DemoDiaryAnalyzer implements DiaryAnalyzer {
  /// 損失回避: ネガティブを1.4倍重く見る（仕様書 §4）。
  static const _lossAversion = 1.4;

  /// 快楽順応: 直近に似た出来事が1回あるごとに0.7倍に減衰。
  static const _adaptationDecay = 0.7;

  static const _milestoneWords = [
    '合格', '不合格', '内定', '退職', '転職', '失恋', '結婚', '離婚',
    '出産', '入学', '卒業', '引っ越し', '昇進', '起業',
  ];

  @override
  Future<List<LifeEvent>> analyze(
    String text,
    List<DiaryEntry> recentEntries,
  ) async {
    final sentences = text
        .split(RegExp(r'[。！!？?\n]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    final scored = <LifeEvent>[];
    for (final sentence in sentences) {
      final event = _scoreSentence(sentence);
      if (event != null) scored.add(_applyAdaptation(event, recentEntries));
    }

    scored.sort((a, b) => b.weight.compareTo(a.weight));
    if (scored.isEmpty && text.trim().isNotEmpty) {
      scored.add(
        const LifeEvent(
          name: '日記を書いた',
          kind: EventKind.daily,
          isPositive: true,
          weight: 0.5,
        ),
      );
    }
    return scored.take(4).toList();
  }

  LifeEvent? _scoreSentence(String sentence) {
    double positive = 0;
    double negative = 0;
    for (final e in HeuristicDiaryAnalyzer._positiveWords.entries) {
      if (sentence.contains(e.key)) positive += e.value;
    }
    for (final e in HeuristicDiaryAnalyzer._negativeWords.entries) {
      if (sentence.contains(e.key)) negative += e.value;
    }
    if (positive == 0 && negative == 0) return null;

    final isPositive = positive >= negative;
    var weight = (isPositive ? positive : negative * _lossAversion).clamp(
      0.5,
      10.0,
    );

    final isMilestone = _milestoneWords.any(sentence.contains);
    final kind = isMilestone
        ? EventKind.milestone
        : (weight <= 2 ? EventKind.mood : EventKind.daily);
    if (isMilestone) weight = weight.clamp(4.0, 10.0);

    // 名前は文の先頭から切り出す（AIが要約した風の見た目）
    final name = sentence.length <= 15 ? sentence : sentence.substring(0, 15);
    return LifeEvent(
      name: name,
      kind: kind,
      isPositive: isPositive,
      weight: double.parse(weight.toStringAsFixed(1)),
    );
  }

  /// 快楽順応: 直近の日記に似た名前の出来事があれば減衰させる。
  LifeEvent _applyAdaptation(LifeEvent event, List<DiaryEntry> recent) {
    final prefix = event.name.length <= 4
        ? event.name
        : event.name.substring(0, 4);
    var count = 0;
    for (final entry in recent) {
      for (final past in entry.events) {
        if (past.name.startsWith(prefix)) count++;
      }
    }
    if (count == 0) return event;
    final decayed = event.weight *
        List.filled(count, _adaptationDecay).fold<double>(1, (a, b) => a * b);
    return event.copyWith(
      weight: double.parse(decayed.clamp(0.3, 10.0).toStringAsFixed(1)),
    );
  }
}

/// APIキー未設定・オフライン時のフォールバック。
/// 簡易的なキーワード採点で「書けば必ずチャートに反映される」体験を守る。
class HeuristicDiaryAnalyzer implements DiaryAnalyzer {
  static const _positiveWords = {
    '嬉しい': 2.0,
    'うれしい': 2.0,
    '楽しい': 2.0,
    'たのしい': 2.0,
    '合格': 6.0,
    '内定': 6.0,
    '昇進': 5.0,
    '褒められ': 2.5,
    '成功': 3.0,
    '達成': 3.0,
    '最高': 2.5,
    '好き': 1.5,
    '幸せ': 2.5,
    'ありがとう': 1.5,
    '感謝': 1.5,
  };

  static const _negativeWords = {
    '辛い': 2.5,
    'つらい': 2.5,
    '悲しい': 2.5,
    'かなしい': 2.5,
    '失恋': 6.0,
    '不合格': 5.0,
    '退職': 4.0,
    '失敗': 3.0,
    '怒られ': 2.5,
    '疲れた': 1.5,
    '最悪': 3.0,
    '不安': 2.0,
    '嫌': 1.5,
    'いや': 1.0,
    '病気': 3.5,
  };

  /// 損失回避: ネガティブを1.4倍重く見る（仕様書 §4）。
  static const _lossAversion = 1.4;

  @override
  Future<List<LifeEvent>> analyze(
    String text,
    List<DiaryEntry> recentEntries,
  ) async {
    final events = <LifeEvent>[];

    for (final entry in _positiveWords.entries) {
      if (text.contains(entry.key)) {
        events.add(
          LifeEvent(
            name: entry.key,
            kind: entry.value >= 4 ? EventKind.milestone : EventKind.mood,
            isPositive: true,
            weight: entry.value,
          ),
        );
      }
    }
    for (final entry in _negativeWords.entries) {
      if (text.contains(entry.key)) {
        events.add(
          LifeEvent(
            name: entry.key,
            kind: entry.value >= 4 ? EventKind.milestone : EventKind.mood,
            isPositive: false,
            weight: (entry.value * _lossAversion).clamp(0, 10),
          ),
        );
      }
    }

    events.sort((a, b) => b.weight.compareTo(a.weight));
    if (events.isEmpty && text.trim().isNotEmpty) {
      // 何も引っかからなくても「記録した」事実を小さな日常として残す。
      events.add(
        const LifeEvent(
          name: '日記を書いた',
          kind: EventKind.daily,
          isPositive: true,
          weight: 0.5,
        ),
      );
    }
    return events.take(4).toList();
  }
}

class AnalyzerException implements Exception {
  final String message;
  AnalyzerException(this.message);
  @override
  String toString() => message;
}
