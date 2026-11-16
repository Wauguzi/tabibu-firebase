import Flutter
import UIKit
import UserNotifications
import firebase_app_check

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Lets local notifications show while the app is in the foreground.
    UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    // App Check reads its provider factory when Firebase is configured, and firebase_core
    // configures it as soon as it registers, ahead of App Check. Registering App Check first
    // installs its factory in time; otherwise every token comes from DeviceCheck.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "FirebaseAppCheckPluginFirst") {
      FirebaseAppCheckPlugin.register(with: registrar)
    }
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "HybridAiPlugin") {
      HybridAiPlugin.register(with: registrar)
    }
  }
}
