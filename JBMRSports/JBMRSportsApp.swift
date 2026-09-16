import FirebaseAuth
import FirebaseCore
import SwiftUI

@main
struct JBMRSportsApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let cricketStore = CricketStore.shared
    private let reelStore = ReelStudioStore.shared
    private let downloadLibrary = DownloadLibraryStore.shared
    @ObservedObject private var authStore = AuthStore.shared
    private let userLibrary = UserLibraryStore.shared
    @State private var showSplash = false

    private var screenshotMode: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-ScreenshotMode")
        #else
        false
        #endif
    }

    private func applyScreenshotLaunchRouteIfNeeded() {
        #if DEBUG
        guard screenshotMode else { return }
        let args = ProcessInfo.processInfo.arguments
        if let idx = args.firstIndex(of: "-ScreenshotMatchID"), args.indices.contains(idx + 1) {
            DeepLinkRouter.shared.handle(url: MatchDeepLink.appOpenURL(matchId: args[idx + 1]))
            return
        }
        if let idx = args.firstIndex(of: "-ScreenshotTab"), args.indices.contains(idx + 1) {
            let tab = args[idx + 1].lowercased()
            if let url = URL(string: "jbmrsports://tab/\(tab)") {
                DeepLinkRouter.shared.handle(url: url)
            }
        }
        #endif
    }

    init() {
        Theme.applyTabBarAppearance()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if showSplash {
                    SplashView {
                        withAnimation(.easeInOut(duration: 0.35)) {
                            showSplash = false
                        }
                    }
                } else if authStore.phase == .needsPinSetup && !screenshotMode {
                    SetPinView()
                } else if authStore.phase != .unlocked && !screenshotMode {
                    LoginView()
                } else {
                    RootTabView()
                        .environmentObject(cricketStore)
                        .environmentObject(reelStore)
                        .environmentObject(downloadLibrary)
                        .environmentObject(authStore)
                        .environmentObject(userLibrary)
                        .environmentObject(DeepLinkRouter.shared)
                }
            }
            .preferredColorScheme(.dark)
            .task {
                _ = NetworkMonitor.shared
                applyScreenshotLaunchRouteIfNeeded()
                await cricketStore.refresh(force: true)
                cricketStore.ensureLiveUpdatesRunning()
            }
            .onOpenURL { url in
                if FirebaseApp.app() != nil, Auth.auth().canHandle(url) { return }
                DeepLinkRouter.shared.handle(url: url)
            }
        }
    }
}
