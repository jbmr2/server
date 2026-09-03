import FirebaseCore
import UIKit

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

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseBootstrap.validateConfiguration()
        FirebaseApp.configure()
        return true
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
