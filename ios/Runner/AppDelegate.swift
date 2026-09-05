import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Without this, iOS delivers a local notification but shows nothing while
    // the app is in the FOREGROUND, and a tap does not route back into Dart.
    // Since foregrounded is exactly how anyone tests a two-minute reminder,
    // the absence of this line reads as "notifications do not work on iPhone"
    // even when scheduling is perfectly healthy. Android has no equivalent
    // requirement, which is why the two platforms appeared to disagree.
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // The real IANA zone, e.g. "Europe/London" or "Asia/Kathmandu".
    //
    // Dart cannot read this. NotificationService used to guess it by scanning
    // the tz database for the first zone whose CURRENT offset matched the
    // device, which on a +01:00 device picks Africa/Algiers out of 24
    // candidates - right offset today, no DST, so every reminder shifts by an
    // hour when BST ends and can be computed into the past. iOS silently drops
    // a trigger in the past; Android does not, which is the whole reason the
    // two platforms disagreed.
    // The messenger comes via a registrar: FlutterImplicitEngineBridge exposes
    // pluginRegistry, not a binaryMessenger of its own.
    guard let registrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "OurMyndTimeZone") else { return }

    let channel = FlutterMethodChannel(
      name: "com.ourmynd.app/timezone",
      binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      if call.method == "localTimeZone" {
        result(TimeZone.current.identifier)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
