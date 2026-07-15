import 'dart:convert';

/// 出来事の種別。AIが自動判定する3分類（仕様書 §3）。
enum EventKind {
  /// 日常 — 一時的な揺れ
  daily,

  /// 気分 — 一時的な小さな揺れ
  mood,

  /// 節目／マイルストーン — 比較的大きな点数として反映
  milestone;

  String get label => switch (this) {
    EventKind.daily => '日常',
    EventKind.mood => '気分',
    EventKind.milestone => '節目',
  };

  static EventKind fromName(String name) => EventKind.values.firstWhere(
    (e) => e.name == name,
    orElse: () => EventKind.daily,
  );
}

/// 日記から抽出された1つの出来事。
class LifeEvent {
  final String name;
  final EventKind kind;

  /// 方向。true = プラス。編集画面のプラス/マイナスボタンで反転できる。
  final bool isPositive;

  /// 重み（変動値の絶対値）。編集画面のスライダーで調整できる。
  /// AI解析ではchange = 方向×baseImportance×durationMultiplier×moodMultiplier×1.5
  /// の絶対値が入るため、日常の小さな出来事(1未満)から人生の節目(200超)まで幅がある。
  final double weight;

  const LifeEvent({
    required this.name,
    required this.kind,
    required this.isPositive,
    required this.weight,
  });

  /// チャートへの変動値。
  double get delta => (isPositive ? 1 : -1) * weight;

  LifeEvent copyWith({
    String? name,
    EventKind? kind,
    bool? isPositive,
    double? weight,
  }) => LifeEvent(
    name: name ?? this.name,
    kind: kind ?? this.kind,
    isPositive: isPositive ?? this.isPositive,
    weight: weight ?? this.weight,
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'kind': kind.name,
    'isPositive': isPositive,
    'weight': weight,
  };

  factory LifeEvent.fromJson(Map<String, dynamic> json) => LifeEvent(
    name: json['name'] as String? ?? '',
    kind: EventKind.fromName(json['kind'] as String? ?? 'daily'),
    isPositive: json['isPositive'] as bool? ?? true,
    weight: (json['weight'] as num?)?.toDouble().clamp(0, 300) ?? 0,
  );
}

/// 1日の日記エントリー（仕様書 §9 データモデル）。
class DiaryEntry {
  /// 'yyyy-MM-dd' 形式の日付キー。
  final String date;
  final String text;

  /// 気分スライダー値 0〜10（任意）。
  final double? moodScore;
  final List<LifeEvent> events;

  const DiaryEntry({
    required this.date,
    this.text = '',
    this.moodScore,
    this.events = const [],
  });

  DateTime get dateTime => DateTime.parse(date);

  DiaryEntry copyWith({
    String? text,
    double? moodScore,
    List<LifeEvent>? events,
  }) => DiaryEntry(
    date: date,
    text: text ?? this.text,
    moodScore: moodScore ?? this.moodScore,
    events: events ?? this.events,
  );

  Map<String, dynamic> toDbMap() => {
    'date': date,
    'text': text,
    'mood_score': moodScore,
    'events_json': jsonEncode(events.map((e) => e.toJson()).toList()),
  };

  factory DiaryEntry.fromDbMap(Map<String, dynamic> map) {
    final rawEvents = jsonDecode(map['events_json'] as String? ?? '[]');
    return DiaryEntry(
      date: map['date'] as String,
      text: map['text'] as String? ?? '',
      moodScore: (map['mood_score'] as num?)?.toDouble(),
      events: (rawEvents as List)
          .map((e) => LifeEvent.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// ローソク足1本分の値（仕様書 §5）。
class Candle {
  /// 期間の開始日。
  final DateTime date;
  final double open;
  final double high;
  final double low;
  final double close;

  /// この期間に日記の記録があるか（false = 空白日・平穏な日）。
  final bool hasEntry;

  const Candle({
    required this.date,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    this.hasEntry = false,
  });

  bool get isBullish => close >= open;
}
