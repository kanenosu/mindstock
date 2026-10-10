import Flutter
import GoogleMobileAds
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Apply the same protective treatment to every iOS user without collecting
    // age. Configure before plugin registration or any ad SDK initialization.
    // TFUA suppresses IDFA even after authorization in an older app version.
    let configuration = MobileAds.shared.requestConfiguration
    configuration.tagForUnderAgeOfConsent = true
    configuration.setPublisherFirstPartyIDEnabled(false)
    configuration.publisherPrivacyPersonalizationState = .disabled
    configuration.maxAdContentRating = .general
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
