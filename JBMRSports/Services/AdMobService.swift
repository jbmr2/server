import UIKit

#if canImport(GoogleMobileAds)
import GoogleMobileAds

@MainActor
final class AdMobService: NSObject, ObservableObject {
    static let shared = AdMobService()

    @Published private(set) var isStarted = false
    private var didRequestStart = false
    var isAdsAllowed = true

    private override init() {
        super.init()
    }

    func startIfNeeded() {
        guard isAdsAllowed else { return }
        guard !isStarted, !didRequestStart else { return }
        guard Bundle.main.object(forInfoDictionaryKey: "GADApplicationIdentifier") is String else {
            NSLog("JBMR AdMob skipped: GADApplicationIdentifier missing")
            return
        }

        didRequestStart = true
        GADMobileAds.sharedInstance().start { [weak self] _ in
            Task { @MainActor in
                self?.isStarted = true
            }
        }
    }

    func markSDKStarted() {
        guard isAdsAllowed else { return }
        guard !isStarted else { return }
        didRequestStart = true
        isStarted = true
    }

    func start() {
        startIfNeeded()
    }

    static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive }

        for scene in scenes {
            if let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController {
                return highestPresented(from: root)
            }
        }
        return nil
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

#else

@MainActor
final class AdMobService: NSObject, ObservableObject {
    static let shared = AdMobService()
    @Published private(set) var isStarted = false
    var isAdsAllowed = true

    func startIfNeeded() {}

    func markSDKStarted() {
        isStarted = true
    }

    func start() {}

    static func topViewController() -> UIViewController? {
        nil
    }
}

#endif
