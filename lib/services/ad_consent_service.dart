import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Google UMPで広告同意を確認してからMobile Ads SDKを初期化する。
///
/// EEA/UK等ではAdMob側で公開したメッセージが自動表示される。規制対象外、
/// またはメッセージ不要の場合はフォームを出さずに広告を利用できる。
class AdConsentService {
  AdConsentService._();

  static final instance = AdConsentService._();

  Future<bool>? _initialization;
  bool _mobileAdsInitialized = false;

  Future<bool> initialize() => _initialization ??= _initialize();

  Future<bool> _initialize() async {
    try {
      final completer = Completer<void>();
      ConsentInformation.instance.requestConsentInfoUpdate(
        ConsentRequestParameters(tagForUnderAgeOfConsent: false),
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
        _mobileAdsInitialized = true;
        await MobileAds.instance.initialize();
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
      return completer.future;
    } catch (error) {
      return error.toString();
    }
  }
}
