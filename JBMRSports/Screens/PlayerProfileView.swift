import SwiftUI

struct PlayerProfileView: View {
    @Binding var tab: AppTab
    @Binding var showSearch: Bool
    @EnvironmentObject private var downloadLibrary: DownloadLibraryStore
    @EnvironmentObject private var authStore: AuthStore

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 14) {
                    Image("UserAvatar")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 64, height: 64)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Theme.accent.opacity(0.5), lineWidth: 1.5))

                    VStack(alignment: .leading, spacing: 6) {
                        Text(authStore.displayName)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                        Text(authStore.phoneLabel)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.muted)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)

                VStack(spacing: 0) {
                    menuNav(icon: "bookmark", title: "My Watchlist") {
                        WatchlistView(tab: $tab, showSearch: $showSearch)
                    }
                    menuNav(icon: "clock.arrow.circlepath", title: "Watch History") {
                        WatchHistoryView(tab: $tab, showSearch: $showSearch)
                    }
                    menuNav(icon: "arrow.down.circle", title: "Downloads") {
                        MyLibraryView()
                            .environmentObject(downloadLibrary)
                    }
                    menuNav(icon: "video", title: "My Reels") {
                        MyLibraryView()
                            .environmentObject(downloadLibrary)
                    }
                    menuNav(icon: "gearshape", title: "App Settings") {
                        SettingsView()
                    }
                    menuNav(icon: "questionmark.circle", title: "Help & Support") {
                        HelpSupportView()
                    }

                    Button {
                        authStore.signOut()
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Theme.liveRed)
                                .frame(width: 22)
                            Text("Log Out")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Theme.liveRed)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 52)
                    }
                    .buttonStyle(.plain)
                }

                Text("JBMR Sports OTT \(AppInfo.versionLabel)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.mutedSoft)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 28)
                    .padding(.bottom, 24)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            AppHeader(onAvatar: { tab = .profile }, onSearch: { showSearch = true })
                .background(Theme.background)
        }
    }

    private func menuRow(icon: String, title: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 22)
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.35))
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
        }
    }

    private func menuNav<D: View>(icon: String, title: String, @ViewBuilder destination: () -> D) -> some View {
        NavigationLink {
            destination()
        } label: {
            menuRow(icon: icon, title: title)
        }
        .buttonStyle(.plain)
    }
}
