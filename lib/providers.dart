import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config/monetization.dart';
import 'logic/chart_calculator.dart';
import 'logic/weekly_summary.dart';
import 'models/models.dart';
import 'services/backup_service.dart';
import 'services/database_service.dart';
import 'services/diary_analyzer.dart';
import 'services/iap_service.dart';
import 'services/rewarded_ad_service.dart';
import 'services/transcription_service.dart';

/// 汎用: SharedPreferences に文字列を1つ保存するだけの Notifier。
abstract class _PrefStringNotifier extends AsyncNotifier<String> {
  String get prefKey;

  @override
  Future<String> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(prefKey) ?? '';
  }

  Future<void> save(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefKey, value.trim());
    state = AsyncData(value.trim());
  }
}

final databaseProvider = Provider<DatabaseService>((ref) => DatabaseService());

/// OpenAI APIキー（音声入力Whisper用）。
final openAiApiKeyProvider =
    AsyncNotifierProvider<OpenAiApiKeyNotifier, String>(
      OpenAiApiKeyNotifier.new,
    );

class OpenAiApiKeyNotifier extends _PrefStringNotifier {
  @override
  String get prefKey => 'openai_api_key';
}

/// 解析バックエンドのURL（マネタイズ本番構成）。設定されていれば、
/// 開発者のキーを持つサーバー経由で解析する（アプリにキーを埋め込まない）。
///
/// リリースビルドでは `--dart-define=BACKEND_URL=https://...` で焼き込む。
/// 保存された値があればそちらを優先（開発中の差し替え用）。
final backendUrlProvider = AsyncNotifierProvider<BackendUrlNotifier, String>(
  BackendUrlNotifier.new,
);

class BackendUrlNotifier extends _PrefStringNotifier {
  /// ビルド時に焼き込む既定のバックエンドURL。
  static const _envDefault = String.fromEnvironment('BACKEND_URL');

  @override
  String get prefKey => 'backend_url';

  @override
  Future<String> build() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(prefKey);
    // 保存値が無ければビルド時のBACKEND_URLを使う。
    return (saved == null || saved.isEmpty) ? _envDefault : saved;
  }
}

/// バックエンドの `APP_SHARED_SECRET` と同じ値をビルド時に焼き込む
/// （`--dart-define=APP_SHARED_SECRET=...`）。無認証よりはマシという
/// 暫定策であり、Play Integrity/App Checkの代替にはならない点に注意。
const _kAppSharedSecret = String.fromEnvironment('APP_SHARED_SECRET');

/// 解析器の選択。
/// - バックエンドURLが設定されていれば、開発者のキーを持つサーバー経由で
///   解析する（本番・ポイント制）。リリースビルドでは
///   `--dart-define=BACKEND_URL=https://...` で焼き込む。
///   AI解析キーはアプリに埋め込まず、必ずサーバー側に置く。
/// - 未設定（主に開発ビルド）は端末内の簡易解析にフォールバックする。
final analyzerProvider = Provider<DiaryAnalyzer>((ref) {
  final backendUrl = ref.watch(backendUrlProvider).valueOrNull ?? '';
  if (backendUrl.isNotEmpty) {
    return BackendDiaryAnalyzer(
      baseUrl: backendUrl,
      appSecret: _kAppSharedSecret,
    );
  }
  // バックエンド未設定時（開発ビルド等）は端末内の簡易解析。
  return DemoDiaryAnalyzer();
});

/// ポイント残高（マネタイズ）。AI解析1回で[Monetization.analysisCost]消費し、
/// 広告視聴・課金で補充する。初回は[Monetization.initialPoints]付与。
final pointsProvider = AsyncNotifierProvider<PointsNotifier, int>(
  PointsNotifier.new,
);

class PointsNotifier extends AsyncNotifier<int> {
  static const _prefKey = 'points_balance';

  @override
  Future<int> build() async {
    final prefs = await SharedPreferences.getInstance();
    // 初回起動時だけ初期ポイントを付与する。
    if (!prefs.containsKey(_prefKey)) {
      await prefs.setInt(_prefKey, Monetization.initialPoints);
      return Monetization.initialPoints;
    }
    return prefs.getInt(_prefKey) ?? Monetization.initialPoints;
  }

  Future<void> _set(int value) async {
    final clamped = value < 0 ? 0 : value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefKey, clamped);
    state = AsyncData(clamped);
  }

  /// [n]ポイント消費する。足りなければ何もせず false を返す。
  Future<bool> spend(int n) async {
    final current = state.valueOrNull ?? 0;
    if (current < n) return false;
    await _set(current - n);
    return true;
  }

  /// [n]ポイント補充する（広告報酬・課金）。
  Future<void> add(int n) async {
    await _set((state.valueOrNull ?? 0) + n);
  }
}

/// リワード広告サービス（広告視聴でポイント獲得）。
final rewardedAdServiceProvider = Provider<RewardedAdService>((ref) {
  final service = RewardedAdService();
  ref.onDispose(service.dispose);
  return service;
});

/// アプリ内課金サービス（ポイントパック購入）。
/// 購入成立時に自動でポイントを付与する。
final iapServiceProvider = Provider<IapService>((ref) {
  final service = IapService();
  ref.onDispose(service.dispose);
  service.init(
    onGrant: (points) => ref.read(pointsProvider.notifier).add(points),
  );
  return service;
});

/// Googleログイン + Driveバックアップ。
final backupServiceProvider = Provider<BackupService>((ref) => BackupService());

/// 最後にDriveへバックアップした日時（ISO8601文字列。手動・自動共通）。
final lastBackupAtProvider =
    AsyncNotifierProvider<LastBackupAtNotifier, String>(
      LastBackupAtNotifier.new,
    );

class LastBackupAtNotifier extends _PrefStringNotifier {
  @override
  String get prefKey => 'last_backup_at';
}

/// 自動バックアップの間隔。前回からこれ以上経っていれば起動時に実行する。
const kAutoBackupInterval = Duration(days: 7);

/// 起動時の自動バックアップ（改善点§6）。
///
/// Googleにログイン済みで、前回バックアップから[kAutoBackupInterval]以上
/// 経っている場合だけ、静かにDriveへ退避する。未ログイン・記録ゼロ・
/// 失敗時は何もしない（ユーザーの操作を一切邪魔しない）。
/// 「機種変更で全部消えた」を防ぐための保険。
Future<void> maybeAutoBackup(WidgetRef ref) async {
  try {
    final backup = ref.read(backupServiceProvider);
    final account = await backup.signInSilently();
    if (account == null) return; // 未ログインなら何もしない

    final entries = await ref.read(entriesProvider.future);
    if (entries.isEmpty) return;

    final lastIso = await ref.read(lastBackupAtProvider.future);
    final last = DateTime.tryParse(lastIso);
    if (last != null && DateTime.now().difference(last) < kAutoBackupInterval) {
      return; // まだ間隔が空いていない
    }

    await backup.backup(entries.values);
    await ref
        .read(lastBackupAtProvider.notifier)
        .save(DateTime.now().toIso8601String());
  } catch (_) {
    // 自動バックアップは失敗しても静かに諦める。
  }
}

/// 初回チュートリアルを見終わったか。
final onboardingDoneProvider = AsyncNotifierProvider<OnboardingNotifier, bool>(
  OnboardingNotifier.new,
);

class OnboardingNotifier extends AsyncNotifier<bool> {
  static const _prefKey = 'onboarding_done';

  @override
  Future<bool> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefKey) ?? false;
  }

  Future<void> complete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, true);
    state = const AsyncData(true);
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

  /// 記録を削除する。削除した [DiaryEntry] を返すので、UI側で
  /// 「元に戻す」（[restoreEntry]）に渡せる（改善点§5）。
  Future<DiaryEntry?> deleteEntry(String dateKey) async {
    final removed = state.valueOrNull?[dateKey];
    await ref.read(databaseProvider).delete(dateKey);
    final map = Map<String, DiaryEntry>.from(state.valueOrNull ?? {})
      ..remove(dateKey);
    state = AsyncData(map);
    return removed;
  }

  /// 削除の取り消し（スナックバーの「元に戻す」から呼ぶ）。
  Future<void> restoreEntry(DiaryEntry entry) => _save(entry);

  /// 全データ削除。
  Future<void> clearAll() async {
    await ref.read(databaseProvider).deleteAll();
    state = const AsyncData({});
  }

  /// バックアップからの復元（同日の既存データは上書き）。
  Future<int> importEntries(List<DiaryEntry> entries) async {
    final db = ref.read(databaseProvider);
    final map = Map<String, DiaryEntry>.from(state.valueOrNull ?? {});
    for (final entry in entries) {
      await db.upsert(entry);
      map[entry.date] = entry;
    }
    state = AsyncData(map);
    return entries.length;
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

/// 通知欄に出す週次レポート（完結した週のみ、新しい順・最大12件）。
final weeklyReportsProvider = Provider<List<WeeklySummary>>((ref) {
  final entries = ref.watch(entriesProvider).valueOrNull ?? {};
  if (entries.isEmpty) return const [];

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final thisMonday = today.subtract(Duration(days: today.weekday - 1));

  final firstDate = DateTime.parse(
    entries.keys.reduce((a, b) => a.compareTo(b) <= 0 ? a : b),
  );
  final firstMonday = firstDate.subtract(Duration(days: firstDate.weekday - 1));

  final reports = <WeeklySummary>[];
  // 直近の完結した週（先週）から過去へ
  var weekStart = thisMonday.subtract(const Duration(days: 7));
  while (!weekStart.isBefore(firstMonday) && reports.length < 12) {
    final summary = WeeklySummary.compute(weekStart, entries);
    if (summary.entryDays > 0) reports.add(summary);
    weekStart = weekStart.subtract(const Duration(days: 7));
  }
  return reports;
});

/// 通知欄を最後に開いた時点の最新レポート週（既読管理）。
final notificationsLastSeenProvider =
    AsyncNotifierProvider<NotificationsLastSeenNotifier, String>(
      NotificationsLastSeenNotifier.new,
    );

class NotificationsLastSeenNotifier extends _PrefStringNotifier {
  @override
  String get prefKey => 'notifications_last_seen';
}

/// 未読の週次レポート数（ベルのバッジ表示用）。
final unreadNotificationsProvider = Provider<int>((ref) {
  final reports = ref.watch(weeklyReportsProvider);
  final lastSeen = ref.watch(notificationsLastSeenProvider).valueOrNull ?? '';
  return reports
      .where(
        (r) => ChartCalculator.dateKey(r.weekStart).compareTo(lastSeen) > 0,
      )
      .length;
});
