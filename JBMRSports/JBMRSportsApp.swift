import SwiftUI

@main
struct JBMRSportsApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var cricketStore = CricketStore.shared
    @StateObject private var reelStore = ReelStudioStore.shared
    @StateObject private var downloadLibrary = DownloadLibraryStore.shared
    @StateObject private var authStore = AuthStore.shared
    @StateObject private var userLibrary = UserLibraryStore.shared
    @State private var showSplash = true

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
                } else if authStore.signedIn {
                    RootTabView()
                        .environmentObject(cricketStore)
                        .environmentObject(reelStore)
                        .environmentObject(downloadLibrary)
                        .environmentObject(authStore)
                        .environmentObject(userLibrary)
                        .environmentObject(DeepLinkRouter.shared)
                } else {
                    LoginView { phone in
                        authStore.signIn(phone: phone)
                    }
                }
            }
            .preferredColorScheme(.dark)
            .task {
                await cricketStore.refresh()
            }
            .onOpenURL { url in
                DeepLinkRouter.shared.handle(url: url)
            }
        }
    }
}
