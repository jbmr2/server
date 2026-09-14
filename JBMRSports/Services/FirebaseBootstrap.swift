import FirebaseAuth
import FirebaseCore
import UIKit

enum FirebaseBootstrap {
    private static let legacyAdminAppID = "1:692709551364:ios:45bb82655a5626ab45f451"

    static func validateConfiguration() {
        if let issue = configurationIssue {
            NSLog("JBMR Firebase setup: %@", issue)
        }
    }

    static var configurationIssue: String? {
        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let dict = NSDictionary(contentsOfFile: path) as? [String: Any],
              let plistBundle = dict["BUNDLE_ID"] as? String,
              let appBundle = Bundle.main.bundleIdentifier else {
            return "GoogleService-Info.plist missing from app bundle"
        }

        if plistBundle != appBundle {
            return "Firebase bundle mismatch: plist=\(plistBundle), app=\(appBundle). Firebase Console se \(appBundle) ke liye naya iOS app add karo aur naya plist download karo."
        }

        if let appID = dict["GOOGLE_APP_ID"] as? String, appID == legacyAdminAppID {
            return "GoogleService-Info.plist abhi admin app (jbmrsportsott) ka hai. Firebase Console → Add iOS app → in.jbmrsports.ott → naya plist replace karo."
        }

        return nil
    }
}

final class PhoneAuthUIDelegate: NSObject, AuthUIDelegate {
    static let shared = PhoneAuthUIDelegate()

    func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)? = nil) {
        DispatchQueue.main.async { [weak self] in
            guard let presenter = self?.topViewController() else {
                completion?()
                return
            }
            if presenter.presentedViewController != nil {
                presenter.dismiss(animated: false) {
                    presenter.present(viewControllerToPresent, animated: flag, completion: completion)
                }
            } else {
                presenter.present(viewControllerToPresent, animated: flag, completion: completion)
            }
        }
    }

    func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
        DispatchQueue.main.async { [weak self] in
            self?.topViewController()?.dismiss(animated: flag, completion: completion)
        }
    }

    private func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive }

        for scene in scenes {
            if let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController {
                return Self.highestPresented(from: root)
            }
        }

        return UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.windows.first?.rootViewController }
            .first
            .map { Self.highestPresented(from: $0) }
    }

    private static func highestPresented(from controller: UIViewController) -> UIViewController {
        if let presented = controller.presentedViewController {
            return highestPresented(from: presented)
        }
        if let nav = controller as? UINavigationController, let visible = nav.visibleViewController {
            return highestPresented(from: visible)
        }
        if let tab = controller as? UITabBarController, let selected = tab.selectedViewController {
            return highestPresented(from: selected)
        }
        return controller
    }
}
