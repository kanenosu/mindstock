import AppTrackingTransparency
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private static let privacyChannelName = "com.kanenosu.mindstock/privacy"
  private var pendingTrackingAuthorizationResults: [FlutterResult] = []
  private var isRequestingTrackingAuthorization = false

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let channel = FlutterMethodChannel(
      name: Self.privacyChannelName,
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "requestTrackingAuthorization" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.requestTrackingAuthorization(result: result)
    }
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    requestTrackingAuthorizationIfPossible()
  }

  private func requestTrackingAuthorization(result: @escaping FlutterResult) {
    guard #available(iOS 14, *) else {
      result("notRequired")
      return
    }

    switch ATTrackingManager.trackingAuthorizationStatus {
    case .notDetermined:
      pendingTrackingAuthorizationResults.append(result)
      requestTrackingAuthorizationIfPossible()
    case .authorized:
      result("authorized")
    case .denied:
      result("denied")
    case .restricted:
      result("restricted")
    @unknown default:
      result("unknown")
    }
  }

  private func requestTrackingAuthorizationIfPossible() {
    guard #available(iOS 14, *),
          !pendingTrackingAuthorizationResults.isEmpty,
          !isRequestingTrackingAuthorization,
          UIApplication.shared.applicationState == .active else {
      return
    }

    isRequestingTrackingAuthorization = true
    ATTrackingManager.requestTrackingAuthorization { [weak self] status in
      DispatchQueue.main.async {
        guard let self else { return }
        let statusName: String
        switch status {
        case .authorized:
          statusName = "authorized"
        case .denied:
          statusName = "denied"
        case .restricted:
          statusName = "restricted"
        case .notDetermined:
          statusName = "notDetermined"
        @unknown default:
          statusName = "unknown"
        }

        let results = self.pendingTrackingAuthorizationResults
        self.pendingTrackingAuthorizationResults.removeAll()
        self.isRequestingTrackingAuthorization = false
        results.forEach { $0(statusName) }
      }
    }
  }
}
