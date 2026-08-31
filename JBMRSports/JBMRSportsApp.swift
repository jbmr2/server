import SwiftUI

@main
struct JBMRSportsApp: App {
    @StateObject private var cricketStore = CricketStore.shared
    @StateObject private var reelStore = ReelStudioStore.shared
    @StateObject private var downloadLibrary = DownloadLibraryStore.shared
    @AppStorage("hasSignedIn") private var hasSignedIn = false
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
                } else if hasSignedIn {
                    RootTabView()
                        .environmentObject(cricketStore)
                        .environmentObject(reelStore)
                        .environmentObject(downloadLibrary)
                        .task {
                            await cricketStore.refresh()
                        }
                } else {
                    LoginView {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            hasSignedIn = true
                        }
                    }
                }
            }
            .preferredColorScheme(.dark)
        }
    }
}
