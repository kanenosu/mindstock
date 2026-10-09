import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// iOSのApp Tracking Transparency (ATT)を広告SDKより先に解決する。
///
/// iOSではネイティブ側が、アプリがアクティブになってからシステムの許可
/// ダイアログを表示する。ユーザーが許可・拒否のどちらを選んでも広告機能は
/// 続行できるが、回答が返るまではMobile Ads SDKを初期化しない。
class TrackingPermissionService {
  TrackingPermissionService._();

  static final instance = TrackingPermissionService._();
  static const _channel = MethodChannel('com.kanenosu.mindstock/privacy');

  Future<String> requestAuthorization() async {
    if (!Platform.isIOS) return 'notRequired';

    try {
      final status = await _channel.invokeMethod<String>(
        'requestTrackingAuthorization',
      );
      return status ?? 'unknown';
    } on PlatformException catch (error, stackTrace) {
      debugPrint('ATT request failed: $error\n$stackTrace');
      return 'error';
    } on MissingPluginException catch (error, stackTrace) {
      debugPrint('ATT bridge unavailable: $error\n$stackTrace');
      return 'error';
    }
  }
}
