import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Google UMPで広告同意を確認してからMobile Ads SDKを初期化する。
///
/// EEA/UK等ではAdMob側で公開したメッセージが自動表示される。規制対象外、
/// またはメッセージ不要の場合はフォームを出さずに広告を利用できる。
class AdConsentService {
  AdConsentService._() : _isIOS = Platform.isIOS;

  @visibleForTesting
  AdConsentService.forTesting({required bool isIOS}) : _isIOS = isIOS;

  static final instance = AdConsentService._();

  final bool _isIOS;

  final Completer<void> _privacyGate = Completer<void>();
  Future<bool>? _initialization;
  bool _mobileAdsInitialized = false;

  /// 最初の画面の表示が完了するまで、どの呼び出し経路からも
  /// UMP / Mobile Adsを起動させない。SettingsScreenなどが先に生成されても、
  /// ここで待機するため起動順の競合が起きない。
  void openPrivacyGate() {
    if (!_privacyGate.isCompleted) _privacyGate.complete();
  }

  Future<bool> initialize() => _initialization ??= _initialize();

  Future<bool> _initialize() async {
    try {
      await _privacyGate.future;
      // 年齢情報は収集せず、iOSの全利用者にTFUAの保護を適用する。
      // SDKの起動前に設定し、過去の版でATTを許可済みでもIDFAを送信しない。
      await MobileAds.instance.updateRequestConfiguration(
        RequestConfiguration(
          maxAdContentRating: MaxAdContentRating.g,
          // TFUA explicitly suppresses IDFA; retain until the SDK's replacement
          // has the same documented identifier-suppression guarantee.
          // ignore: deprecated_member_use
          tagForUnderAgeOfConsent: _isIOS ? 1 : null,
        ),
      );
      await MobileAds.instance.setSameAppKeyEnabled(false);
      final completer = Completer<void>();
      ConsentInformation.instance.requestConsentInfoUpdate(
        ConsentRequestParameters(tagForUnderAgeOfConsent: _isIOS),
        completer.complete,
        (error) {
          debugPrint(
            'Ad consent update failed (${error.errorCode}): ${error.message}',
          );
          completer.complete();
        },
      );
      await completer.future;

      await ConsentForm.loadAndShowConsentFormIfRequired((error) {
        if (error != null) {
          debugPrint(
            'Ad consent form failed (${error.errorCode}): ${error.message}',
          );
        }
      });

      final allowed = await ConsentInformation.instance.canRequestAds();
      if (allowed && !_mobileAdsInitialized) {
        await MobileAds.instance.initialize();
        _mobileAdsInitialized = true;
      }
      return allowed;
    } catch (error, stackTrace) {
      debugPrint('Ad consent initialization failed: $error\n$stackTrace');
      return false;
    }
  }

  Future<bool> canRequestAds() => initialize();

  Future<bool> privacyOptionsRequired() async {
    await initialize();
    return await ConsentInformation.instance
            .getPrivacyOptionsRequirementStatus() ==
        PrivacyOptionsRequirementStatus.required;
  }

  /// プライバシー選択画面を表示する。成功時はnull、失敗時は説明を返す。
  Future<String?> showPrivacyOptions() async {
    try {
      await initialize();
      final completer = Completer<String?>();
      await ConsentForm.showPrivacyOptionsForm((error) {
        completer.complete(
          error == null ? null : '${error.errorCode}: ${error.message}',
        );
      });
      return await completer.future;
    } catch (error) {
      return error.toString();
    }
  }
}
