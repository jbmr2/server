import FirebaseAuth
import FirebaseCore
import UIKit
import UserNotifications

enum OrientationManager {
    static var lock: UIInterfaceOrientationMask = .portrait

    static func enableLandscape() {
        lock = [.portrait, .landscapeLeft, .landscapeRight]
        rotate(to: .landscapeRight)
    }

    static func restorePortrait() {
        rotate(to: .portrait)
        lock = .portrait
    }

    private static func rotate(to orientation: UIInterfaceOrientation) {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
            ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return }

        let mask: UIInterfaceOrientationMask = {
            switch orientation {
            case .landscapeLeft: return .landscapeLeft
            case .landscapeRight: return .landscapeRight
            default: return .portrait
            }
        }()

        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }

        if let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController {
            root.setNeedsUpdateOfSupportedInterfaceOrientations()
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseApp.configure()
        FirebaseBootstrap.validateConfiguration()
        DispatchQueue.main.async {
            AuthStore.shared.attachAuthListenerIfNeeded()
            FirebaseRealtime.configure()
        }
        UNUserNotificationCenter.current().delegate = self
        registerForPhoneAuthNotifications(application)
        configurePhoneAuthForSimulatorIfNeeded()
        return true
    }

    private func registerForPhoneAuthNotifications(_ application: UIApplication) {
        // Phone Auth silent push ke liye permission popup zaroori nahi — seedha register karo.
        application.registerForRemoteNotifications()
    }

    private func configurePhoneAuthForSimulatorIfNeeded() {
        #if DEBUG
        #if targetEnvironment(simulator)
        Auth.auth().settings?.isAppVerificationDisabledForTesting = true
        NSLog("JBMR Phone Auth: simulator testing mode ON — Firebase test number + fixed OTP use karo")
        #endif
        #endif
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        #if DEBUG
        Auth.auth().setAPNSToken(deviceToken, type: .sandbox)
        #else
        Auth.auth().setAPNSToken(deviceToken, type: .prod)
        #endif
        NSLog("JBMR APNs token registered for Phone Auth")
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        NSLog("JBMR APNs registration failed: %@", error.localizedDescription)
    }

    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        if Auth.auth().canHandle(url) {
            return true
        }
        Task { @MainActor in
            DeepLinkRouter.shared.handle(url: url)
        }
        return false
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        if Auth.auth().canHandleNotification(userInfo) {
            completionHandler(.noData)
            return
        }
        completionHandler(.noData)
    }

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        OrientationManager.lock
    }

    func application(
        _ application: UIApplication,
        continue userActivity: NSUserActivity,
        restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
    ) -> Bool {
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
              let url = userActivity.webpageURL else { return false }
        Task { @MainActor in
            DeepLinkRouter.shared.handle(url: url)
        }
        return true
    }
}
