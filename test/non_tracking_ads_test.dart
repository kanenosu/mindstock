import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:google_mobile_ads/src/ad_instance_manager.dart';
import 'package:google_mobile_ads/src/ump/user_messaging_codec.dart';
import 'package:mindstock/services/ad_consent_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'iOS identifier protection precedes UMP and SDK initialization',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final ads = MethodChannel(
        'plugins.flutter.io/google_mobile_ads',
        StandardMethodCodec(AdMessageCodec()),
      );
      final ump = MethodChannel(
        'plugins.flutter.io/google_mobile_ads/ump',
        StandardMethodCodec(UserMessagingCodec()),
      );
      final calls = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(ads, (call) async {
        // The plugin's channel handshake does not initialize the native ad SDK.
        if (call.method == '_init') return null;
        calls.add(call);
        if (call.method == 'MobileAds#initialize')
          return InitializationStatus({});
        return null;
      });
      messenger.setMockMethodCallHandler(ump, (call) async {
        calls.add(call);
        if (call.method == 'ConsentInformation#canRequestAds') return true;
        return null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(ads, null);
        messenger.setMockMethodCallHandler(ump, null);
      });

      final service = AdConsentService.forTesting(isIOS: true);
      final initialized = service.initialize();
      await Future<void>.delayed(Duration.zero);
      expect(
        calls,
        isEmpty,
        reason: 'Every path must wait for the startup gate',
      );
      service.openPrivacyGate();
      expect(await initialized, isTrue);

      expect(calls.first.method, 'MobileAds#updateRequestConfiguration');
      expect(calls.first.arguments['tagForUnderAgeOfConsent'], 1);
      expect(calls.first.arguments['maxAdContentRating'], 'G');
      expect(calls[1].method, 'MobileAds#setSameAppKeyEnabled');
      expect(calls[1].arguments['isEnabled'], false);
      final consent = calls.singleWhere(
        (call) => call.method == 'ConsentInformation#requestConsentInfoUpdate',
      );
      expect(
        (consent.arguments['params'] as ConsentRequestParameters)
            .tagForUnderAgeOfConsent,
        isTrue,
      );
      expect(calls.last.method, 'MobileAds#initialize');
      final count = calls.length;
      expect(await service.canRequestAds(), isTrue);
      expect(
        calls.length,
        count,
        reason: 'Repeated callers share initialization',
      );
    },
  );

  test('native startup also suppresses IDFA and has no ATT request', () {
    final native = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    expect(native, isNot(contains('requestTrackingAuthorization')));
    expect(native, contains('configuration.tagForUnderAgeOfConsent = true'));
    expect(native, contains('setPublisherFirstPartyIDEnabled(false)'));
    expect(
      native,
      contains('publisherPrivacyPersonalizationState = .disabled'),
    );
    expect(
      File('ios/Runner/Info.plist').readAsStringSync(),
      isNot(contains('NSUserTrackingUsageDescription')),
    );
    expect(
      File('lib/services/rewarded_ad_service.dart').readAsStringSync(),
      contains('AdRequest(nonPersonalizedAds: true)'),
    );
  });
}
