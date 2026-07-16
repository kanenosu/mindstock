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

  /// 初回付与ポイント（ユーザー指定: 最初は3ポイントのみ）。
  static const int initialPoints = 3;

  /// AI解析1回あたりのコスト。
  static const int analysisCost = 1;

  /// 広告1本を見て得られるポイント。
  static const int rewardPerAd = 1;

  // ── AdMob ────────────────────────────────────────────────
  // 既定は Google 公式の「テスト用ID」。これなら審査・課金なしで動作確認でき、
  // 誤クリックでもポリシー違反にならない。リリース前に必ず本番IDへ差し替える。
  // 本番IDは https://apps.admob.com でアプリと広告ユニットを作って取得する。

  /// AdMob アプリID（AndroidManifest / Info.plist にも同じ値を入れること）。
  static String get admobAppId => Platform.isAndroid
      ? 'ca-app-pub-3940256099942544~3347511713' // Android テスト用
      : 'ca-app-pub-3940256099942544~1458002511'; // iOS テスト用

  /// リワード広告ユニットID。
  static String get rewardedAdUnitId => Platform.isAndroid
      ? 'ca-app-pub-3940256099942544/5224354917' // Android テスト用
      : 'ca-app-pub-3940256099942544/1712485313'; // iOS テスト用

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
