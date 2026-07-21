import 'dart:async';

import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../config/monetization.dart';

/// リワード広告（AdMob）の読み込み・表示を扱うサービス。
///
/// 広告を最後まで見ると報酬（ポイント）が得られる。広告収益は開発者に入る。
/// 既定のIDはGoogle公式のテスト用なので、審査前でも安全に動作確認できる。
/// リリース前に [Monetization] のIDを本番に差し替えること。
class RewardedAdService {
  RewardedAd? _ad;
  bool _loading = false;

  /// 広告の準備ができているか。
  bool get isReady => _ad != null;

  /// 広告を事前読み込みする（表示前・表示後に呼んで次に備える）。
  void preload() {
    if (_loading || _ad != null) return;
    _loading = true;
    RewardedAd.load(
      adUnitId: Monetization.rewardedAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _ad = ad;
          _loading = false;
        },
        onAdFailedToLoad: (error) {
          _ad = null;
          _loading = false;
        },
      ),
    );
  }

  /// 広告を表示し、報酬を得られたら true を返す。
  /// 未準備・失敗時は false（呼び出し側でポイントは付与しない）。
  ///
  /// 注意: `ad.show()` の返すFutureは「表示を開始した」時点で完了してしまい、
  /// ユーザーが見終わる（`onUserEarnedReward` が呼ばれる）のを待たない。
  /// そのため「広告が閉じられた」(`onAdDismissedFullScreenContent`) まで
  /// Completerで待ってから結果を確定させる。
  Future<bool> showAndEarn() async {
    final ad = _ad;
    if (ad == null) {
      preload();
      return false;
    }
    _ad = null; // 1回で使い切る

    final completer = Completer<bool>();
    var earned = false;

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        preload(); // 次の広告を仕込む
        if (!completer.isCompleted) completer.complete(earned);
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        preload();
        if (!completer.isCompleted) completer.complete(false);
      },
    );

    await ad.show(
      onUserEarnedReward: (_, reward) {
        earned = true;
      },
    );
    return completer.future;
  }

  void dispose() {
    _ad?.dispose();
    _ad = null;
  }
}
