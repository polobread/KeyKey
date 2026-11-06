import UIKit
import KeyKeyEngine

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    #if DEBUG && targetEnvironment(simulator)
    func application(
        _ application: UIApplication,
        shouldAllowExtensionPointIdentifier extensionPointIdentifier: UIApplication.ExtensionPointIdentifier
    ) -> Bool {
        // Isolate UIKit's native keyboard from third-party extensions when
        // diagnosing a simulator input-mode transition crash.
        extensionPointIdentifier != .keyboard
            || !ProcessInfo.processInfo.arguments.contains("-KeyKeyNativeKeyboardOnly")
    }
    #endif
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    #if DEBUG && targetEnvironment(simulator) && compiler(>=6.4)
    private var geometryProbe: AnyObject?
    #endif

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = SetupViewController()
        window.makeKeyAndVisible()
        self.window = window
        #if KEYKEY_TYPOGRAPHY_MEASUREMENT
        let arguments = ProcessInfo.processInfo.arguments
        let request = arguments.firstIndex(of: "-KeyKeyTypographyMeasurement")
            .flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
        UserDefaults(suiteName: KeyboardPreferenceStore.appGroupIdentifier)?
            .set(request, forKey: "keykeyTypographyMeasurementRequest")
        #endif
        #if DEBUG && targetEnvironment(simulator) && compiler(>=6.4)
        if #available(iOS 27.1, *) {
            let defaults = UserDefaults(suiteName: KeyboardPreferenceStore.appGroupIdentifier)
            let enabled = ProcessInfo.processInfo.arguments.contains("-KeyKeyGeometryProbe")
            defaults?.set(enabled, forKey: SimulatorGeometryProbe.preferenceKey)
            if enabled { geometryProbe = SimulatorGeometryProbe(view: window, scope: "app") }
        }
        #endif
    }
}
