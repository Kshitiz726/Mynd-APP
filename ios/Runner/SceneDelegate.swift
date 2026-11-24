import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {

  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    NSLog("[scene] willConnectTo — SceneDelegate is live")
    super.scene(scene, willConnectTo: session, options: connectionOptions)

    // The theme the user chose inside the app, applied to the window that has
    // just been created.
    //
    // The app delegate sets this too, but on a scene-based app there is no
    // window yet when didFinishLaunching runs, so that call has nothing to
    // apply it to on a cold start. This is the one that actually catches the
    // launch screen, which is still on screen at this point.
    Appearance.apply(to: scene)

    // A cold launch delivers the URL here rather than through
    // scene:openURLContexts:, so the same forwarding has to happen on this path
    // or a callback that starts the app is lost.
    if !connectionOptions.urlContexts.isEmpty {
      self.scene(scene, openURLContexts: connectionOptions.urlContexts)
    }
  }

  /// Hands OAuth (and any other) callback URLs to the plugins that still use
  /// the pre-UIScene app lifecycle.
  ///
  /// This app adopts UIScene (see UIApplicationSceneManifest in Info.plist), so
  /// iOS delivers incoming URLs here rather than to
  /// `application:openURL:options:` on the app delegate. FlutterSceneDelegate
  /// forwards them on, but only to plugins registered for UIWindowScene
  /// callbacks — and google_sign_in is not one of them yet; it still implements
  /// the deprecated application callback, which is what the
  /// "FLTGoogleSignInPlugin uses deprecated application lifecycle events"
  /// warning on every launch is telling us.
  ///
  /// The visible symptom of the gap: Google's redirect back into the app
  /// (com.googleusercontent.apps.<client-id>://) was dropped on the floor, so
  /// GIDSignIn's completion never fired, `signIn()` never returned, and the
  /// consent window hung there instead of taking you into the app.
  ///
  /// Forwarding to the app delegate restores the legacy path for every such
  /// plugin, not just Google — Stripe's hosted-checkout return URL comes back
  /// the same way.
  override func scene(
    _ scene: UIScene,
    openURLContexts URLContexts: Set<UIOpenURLContext>
  ) {
    NSLog("[scene] openURLContexts fired with \(URLContexts.count) url(s)")
    super.scene(scene, openURLContexts: URLContexts)

    let application = UIApplication.shared
    for context in URLContexts {
      NSLog("[scene] forwarding callback URL: \(context.url.scheme ?? "?")://…")
      _ = application.delegate?.application?(
        application,
        open: context.url,
        options: [:]
      )
    }
  }
}

/// Where the app's chosen appearance is read from.
///
/// One place, because two copies of "which key holds dark mode" is how the
/// launch screen and the app end up disagreeing. See SettingsProvider: the
/// flag is written through shared_preferences, which prefixes Dart keys with
/// `flutter.`.
enum Appearance {
  static var isDark: Bool {
    UserDefaults.standard.bool(forKey: "flutter.om_dark_mode")
  }

  static func apply(to scene: UIScene) {
    guard let windowScene = scene as? UIWindowScene else { return }
    let style: UIUserInterfaceStyle = isDark ? .dark : .light
    for window in windowScene.windows {
      window.overrideUserInterfaceStyle = style
    }
  }
}
