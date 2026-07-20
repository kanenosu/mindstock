import 'dart:io';

/// マネタイズ（ポイント制・広告・課金）の設定を1か所にまとめる。
///
/// 仕組み: AI解析は1回につき[analysisCost]ポイント消費する。初回は
/// [initialPoints]ポイントだけ付与され、以降は広告視聴（[rewardPerAd]）や
/// 課金でポイントを補充する。広告・課金の収益は開発者に入る。
///
/// AI解析キーはアプリに埋め込めない（抜き取られる）ため、解析は
/// バックエンド経由で行う（[Monetization]とは別に backend/ を参照）。
class Monetization {
  Monetization._();

  /// 初回付与ポイント（ユーザー指定: 最初は7ポイント）。
  static const int initialPoints = 7;

  /// AI解析1回あたりのコスト。
  static const int analysisCost = 1;

  /// 広告1本を見て得られるポイント。
  static const int rewardPerAd = 1;

  // ── AdMob ────────────────────────────────────────────────
  // 本番ID設定済み（2026-07-17、apps.admob.com の「MindStock」アプリ）。
  // AndroidManifest.xml / ios/Runner/Info.plist にも同じ値を入れてある。
  // 注意: AdMobアカウントの支払いプロファイルが未設定のため、アプリの審査は
  // まだ開始されていない（審査完了までは広告配信が制限される）。

  /// AdMob アプリID（AndroidManifest / Info.plist にも同じ値を入れること）。
  static String get admobAppId => Platform.isAndroid
      ? 'ca-app-pub-6090469963212290~6476073694' // Android 本番
      : 'ca-app-pub-6090469963212290~4824200815'; // iOS 本番

  /// リワード広告ユニットID。
  static String get rewardedAdUnitId => Platform.isAndroid
      ? 'ca-app-pub-6090469963212290/6284502008' // Android 本番
      : 'ca-app-pub-6090469963212290/8527521967'; // iOS 本番

  /// 本番IDを設定済みか（テストIDのままならバナー等で警告表示に使える）。
  static bool get usingTestAdIds => admobAppId.contains('3940256099942544');

  // ── 課金（IAP: ポイントパック） ─────────────────────────────
  // ストア商品IDは Play Console / App Store Connect で「消費型アイテム」として
  // 同じIDで登録する必要がある（登録するまで購入は動作しない）。
  // 付与ポイントは productToPoints で対応づける。

  static const Map<String, int> productToPoints = {
    'points_10': 10,
    'points_50': 50,
    'points_150': 150,
  };

  static Set<String> get productIds => productToPoints.keys.toSet();
}
