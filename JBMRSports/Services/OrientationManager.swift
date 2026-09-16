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
        Auth.auth().settings?.isAppVerificationDisabledForTesting = false
        FirebaseBootstrap.validateConfiguration()
        Task {
            try? await Auth.auth().initializeRecaptchaConfig()
        }
        DispatchQueue.main.async {
            AuthStore.shared.attachAuthListenerIfNeeded()
            FirebaseRealtime.configure()
        }
        UNUserNotificationCenter.current().delegate = self
        registerForPhoneAuthNotifications(application)
        return true
    }

    private func registerForPhoneAuthNotifications(_ application: UIApplication) {
        // Phone Auth silent push ke liye permission popup zaroori nahi — seedha register karo.
        application.registerForRemoteNotifications()
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        // Debug = sandbox, App Store = prod. Galat type pe silent push miss + 10s delay.
        PhoneAuthAPNs.apply(deviceToken)
        NSLog("JBMR APNs token registered for Phone Auth (%d bytes, type=%@)", deviceToken.count, "\(PhoneAuthAPNs.tokenType.rawValue)")
        Task { @MainActor in
            AuthStore.shared.markAPNSReady(token: deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        NSLog("JBMR APNs registration failed: %@", error.localizedDescription)
        Task { @MainActor in
            AuthStore.shared.markAPNSFailed()
        }
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
        return true
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

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if Auth.auth().canHandleNotification(notification.request.content.userInfo) {
            completionHandler([])
            return
        }
        completionHandler([])
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
        if Auth.auth().canHandle(url) {
            return true
        }
        Task { @MainActor in
            DeepLinkRouter.shared.handle(url: url)
        }
        return true
    }
}
