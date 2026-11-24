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
    applySavedAppearance()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// Make UIKit follow the theme chosen inside the app, not the one chosen in
  /// Settings.
  ///
  /// The launch screen is drawn by UIKit before a single line of Dart runs, so
  /// it cannot ask the app which theme is in use; left alone it follows the
  /// system appearance. For somebody running the app in dark while the phone
  /// is in light, that meant a bright flash on every cold start before the
  /// Flutter frame arrived - and this app's users are the ones least well
  /// served by being flashed at.
  ///
  /// Setting the override on the window makes the launch screen's named colour
  /// resolve to the app's own choice, and keeps every other UIKit surface
  /// (share sheets, the keyboard, permission alerts) in agreement with it.
  ///
  /// The flag is written by SettingsProvider through shared_preferences, which
  /// stores Dart keys under a `flutter.` prefix. Absent on a first launch, and
  /// the default is light - the same default Dart uses, so the two agree
  /// before anybody has chosen anything.
  private func applySavedAppearance() {
    let style: UIUserInterfaceStyle = Appearance.isDark ? .dark : .light
    // On a scene-based app there is usually no window yet at this point, so
    // SceneDelegate does the one that matters. This covers the window the
    // Flutter app delegate owns, and anything already on screen.
    for scene in UIApplication.shared.connectedScenes {
      Appearance.apply(to: scene)
    }
    window?.overrideUserInterfaceStyle = style
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
