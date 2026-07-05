import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'logic/chart_calculator.dart';
import 'models/models.dart';
import 'services/database_service.dart';
import 'services/demo_data.dart';
import 'services/diary_analyzer.dart';
import 'services/transcription_service.dart';

final databaseProvider = Provider<DatabaseService>((ref) => DatabaseService());

/// Claude APIキー（設定画面から保存）。
final apiKeyProvider = AsyncNotifierProvider<ApiKeyNotifier, String>(
  ApiKeyNotifier.new,
);

class ApiKeyNotifier extends AsyncNotifier<String> {
  static const _prefKey = 'claude_api_key';

  @override
  Future<String> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefKey) ?? '';
  }

  Future<void> save(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, key.trim());
    state = AsyncData(key.trim());
  }
}

/// APIキーが設定されていれば Claude API、なければ端末内の簡易解析。
/// モード切替のUIは持たない — キーの有無で自動的に決まる。
final analyzerProvider = Provider<DiaryAnalyzer>((ref) {
  final apiKey = ref.watch(apiKeyProvider).valueOrNull ?? '';
  if (apiKey.isNotEmpty) return ClaudeDiaryAnalyzer(apiKey: apiKey);
  return DemoDiaryAnalyzer();
});

/// OpenAI APIキー（Whisper音声入力用。設定画面から保存）。
final openAiApiKeyProvider = AsyncNotifierProvider<OpenAiApiKeyNotifier, String>(
  OpenAiApiKeyNotifier.new,
);

class OpenAiApiKeyNotifier extends AsyncNotifier<String> {
  static const _prefKey = 'openai_api_key';

  @override
  Future<String> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefKey) ?? '';
  }

  Future<void> save(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, key.trim());
    state = AsyncData(key.trim());
  }
}

/// 音声入力（Whisper）の文字起こしサービス。
final transcriptionServiceProvider = Provider<TranscriptionService>((ref) {
  final apiKey = ref.watch(openAiApiKeyProvider).valueOrNull ?? '';
  return WhisperTranscriptionService(apiKey: apiKey);
});

/// 全エントリー。date('yyyy-MM-dd') → DiaryEntry。
final entriesProvider =
    AsyncNotifierProvider<EntriesNotifier, Map<String, DiaryEntry>>(
      EntriesNotifier.new,
    );

class EntriesNotifier extends AsyncNotifier<Map<String, DiaryEntry>> {
  @override
  Future<Map<String, DiaryEntry>> build() =>
      ref.read(databaseProvider).loadAll();

  /// コア体験: 書く → AIが即採点 → 即反映（確認画面なし、仕様書 §3）。
  ///
  /// 保存は解析を待たずに行い、解析が終わったら出来事だけ差し替える。
  /// 解析に失敗してもデモ解析で必ずチャートに反映する。
  /// [date] を過去日にすれば「日付を選んでエントリー」になる。
  Future<void> submitDiary({
    required DateTime date,
    required String text,
    double? moodScore,
  }) async {
    final key = ChartCalculator.dateKey(date);
    final current = state.valueOrNull ?? {};
    final existing = current[key];

    // 1. まず本文と気分を保存（書いたら終わり、を最速で成立させる）
    var entry = DiaryEntry(
      date: key,
      text: text,
      moodScore: moodScore,
      events: existing?.events ?? const [],
    );
    await _save(entry);

    // 2. AI解析（失敗時はデモ解析にフォールバック）
    if (text.trim().isNotEmpty) {
      final recent = _recentEntries(before: key);
      List<LifeEvent> events;
      try {
        events = await ref.read(analyzerProvider).analyze(text, recent);
      } catch (_) {
        events = await DemoDiaryAnalyzer().analyze(text, recent);
      }
      entry = entry.copyWith(events: events);
      await _save(entry);
    }
  }

  /// 編集画面からの出来事の微調整・手動追加（仕様書 §3 オプション機能）。
  Future<void> updateEvents(String dateKey, List<LifeEvent> events) async {
    final entry = state.valueOrNull?[dateKey];
    if (entry == null) return;
    await _save(entry.copyWith(events: events));
  }

  Future<void> deleteEntry(String dateKey) async {
    await ref.read(databaseProvider).delete(dateKey);
    final map = Map<String, DiaryEntry>.from(state.valueOrNull ?? {})
      ..remove(dateKey);
    state = AsyncData(map);
  }

  /// デモデータ投入（谷→回復の軌跡入り・約4ヶ月分）。同日の既存データは上書き。
  Future<void> seedDemoData() async {
    final db = ref.read(databaseProvider);
    final map = Map<String, DiaryEntry>.from(state.valueOrNull ?? {});
    for (final entry in DemoDataGenerator.generate()) {
      await db.upsert(entry);
      map[entry.date] = entry;
    }
    state = AsyncData(map);
  }

  /// 全データ削除（デモのやり直し用）。
  Future<void> clearAll() async {
    await ref.read(databaseProvider).deleteAll();
    state = const AsyncData({});
  }

  Future<void> _save(DiaryEntry entry) async {
    await ref.read(databaseProvider).upsert(entry);
    final map = Map<String, DiaryEntry>.from(state.valueOrNull ?? {});
    map[entry.date] = entry;
    state = AsyncData(map);
  }

  List<DiaryEntry> _recentEntries({required String before}) {
    final all = (state.valueOrNull ?? {}).values.toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return all.where((e) => e.date.compareTo(before) < 0).take(7).toList();
  }
}

/// 日足ローソク（空白日も平穏な足として埋まる）。
final dailyCandlesProvider = Provider<List<Candle>>((ref) {
  final entries = ref.watch(entriesProvider).valueOrNull ?? {};
  return ChartCalculator.dailyCandles(entries);
});

/// 週足ローソク。
final weeklyCandlesProvider = Provider<List<Candle>>((ref) {
  return ChartCalculator.weeklyCandles(ref.watch(dailyCandlesProvider));
});
