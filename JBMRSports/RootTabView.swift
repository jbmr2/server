import SwiftUI

struct RootTabView: View {
    @State private var tab: AppTab = .home
    @State private var homePath = NavigationPath()
    @State private var schedulePath = NavigationPath()
    @State private var showSearch = false
    @State private var showShorts = false
    @State private var showCreate = false
    @EnvironmentObject private var store: CricketStore
    @EnvironmentObject private var reelStore: ReelStudioStore
    @EnvironmentObject private var downloadLibrary: DownloadLibraryStore
    @EnvironmentObject private var deepLinkRouter: DeepLinkRouter
    @EnvironmentObject private var userLibrary: UserLibraryStore

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch tab {
                case .home:
                    NavigationStack(path: $homePath) {
                        HomeView(tab: $tab, showSearch: $showSearch, path: $homePath)
                    }
                case .schedule:
                    NavigationStack(path: $schedulePath) {
                        ExploreView(tab: $tab, showSearch: $showSearch, path: $schedulePath)
                    }
                case .create:
                    NavigationStack(path: $homePath) {
                        HomeView(tab: $tab, showSearch: $showSearch, path: $homePath)
                    }
                case .shorts:
                    NavigationStack {
                        ShortsView(tab: $tab, showSearch: $showSearch, onClose: {
                            tab = .home
                        })
                    }
                case .profile:
                    NavigationStack {
                        PlayerProfileView(tab: $tab, showSearch: $showSearch)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: 64)
            }

            FigmaTabBar(tab: $tab, reelClipCount: reelStore.clips.count, onCreate: {
                showCreate = true
            }, onReselect: popToRoot(for:))
        }
        .background(Theme.background.ignoresSafeArea())
        .sheet(isPresented: $showSearch) {
            SearchSheet(tab: $tab, showSearch: $showSearch)
                .environmentObject(store)
                .environmentObject(reelStore)
                .environmentObject(downloadLibrary)
                .environmentObject(userLibrary)
        }
        .sheet(isPresented: $showCreate) {
            NavigationStack {
                ReelStudioView()
            }
            .environmentObject(reelStore)
            .environmentObject(downloadLibrary)
        }
        .fullScreenCover(isPresented: $showShorts) {
            ShortsView(tab: $tab, showSearch: $showSearch, onClose: {
                showShorts = false
                tab = .home
            })
        }
        .onChange(of: tab) { _, newValue in
            if newValue == .create {
                showCreate = true
                tab = .home
            }
        }
        .onChange(of: deepLinkRouter.pendingRoute) { _, route in
            guard let route else { return }
            Task { await openDeepLink(route) }
        }
        .task {
            if let route = deepLinkRouter.pendingRoute {
                await openDeepLink(route)
            }
        }
    }

    @MainActor
    private func openDeepLink(_ route: MatchDeepLink.Route) async {
        if store.featuredMatches.isEmpty && store.scheduleMatches.isEmpty {
            await store.refresh()
        }

        switch route {
        case .match(let id):
            guard store.featuredMatch(id: id) != nil else {
                deepLinkRouter.clear()
                return
            }
            tab = .home
            homePath = NavigationPath()
            homePath.append(AppNavigationRoute.match(id))
        case .tournament(let id):
            guard store.tournaments.contains(where: { $0.tournamentId == id }) else {
                deepLinkRouter.clear()
                return
            }
            tab = .home
            homePath = NavigationPath()
            homePath.append(AppNavigationRoute.tournament(id))
        case .tab(let name):
            switch name {
            case "home": tab = .home
            case "schedule": tab = .schedule
            case "shorts": tab = .shorts
            case "profile", "reel": tab = .profile
            default: tab = .home
            }
        }

        deepLinkRouter.clear()
    }

    private func popToRoot(for tab: AppTab) {
        switch tab {
        case .home:
            homePath = NavigationPath()
        case .schedule:
            schedulePath = NavigationPath()
        default:
            break
        }
    }
}

/// Figma bottom nav: 390×64, icons 20, labels 10, center + 44 circle.
struct FigmaTabBar: View {
    @Binding var tab: AppTab
    var reelClipCount: Int = 0
    var onCreate: () -> Void
    var onReselect: (AppTab) -> Void = { _ in }

    private let inactive = Color(red: 0.557, green: 0.604, blue: 0.651) // #8E9AA6

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Theme.border)
                .frame(height: 1)

            HStack {
                tabButton(.home, title: "Home", systemImage: "house")
                Spacer(minLength: 0)
                tabButton(.schedule, title: "Schedule", systemImage: "calendar")
                Spacer(minLength: 0)

                Button(action: onCreate) {
                    ZStack(alignment: .topTrailing) {
                        Text("+")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 22)
                                    .fill(tab == .shorts ? Theme.magenta : Theme.accent)
                            )

                        if reelClipCount > 0 {
                            Text("\(reelClipCount)")
                                .font(.system(size: 10, weight: .heavy))
                                .foregroundStyle(.white)
                                .frame(minWidth: 18, minHeight: 18)
                                .background(Circle().fill(Theme.liveRed))
                                .offset(x: 6, y: -4)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Create")

                Spacer(minLength: 0)
                tabButton(.shorts, title: "Shorts", systemImage: "play.rectangle.on.rectangle", activeColor: Theme.magenta)
                Spacer(minLength: 0)
                tabButton(.profile, title: "Profile", systemImage: "person")
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 8)
            .frame(height: 63)
        }
        .frame(height: 64)
        .background(Color(red: 0.031, green: 0.035, blue: 0.047).ignoresSafeArea(edges: .bottom))
    }

    private func tabButton(_ value: AppTab, title: String, systemImage: String, activeColor: Color = Theme.accent) -> some View {
        let active = tab == value
        return Button {
            if tab == value {
                onReselect(value)
            }
            tab = value
        } label: {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 20, height: 20)
                Text(title)
                    .font(.system(size: 10, weight: active ? .semibold : .medium))
            }
            .foregroundStyle(active ? activeColor : inactive)
            .frame(width: 60)
        }
        .buttonStyle(.plain)
    }
}

struct SearchSheet: View {
    @Binding var tab: AppTab
    @Binding var showSearch: Bool
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: CricketStore
    @EnvironmentObject private var reelStore: ReelStudioStore
    @EnvironmentObject private var downloadLibrary: DownloadLibraryStore
    @EnvironmentObject private var userLibrary: UserLibraryStore
    @State private var query = ""

    private var results: [FeaturedMatch] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return store.featuredMatches }
        return store.featuredMatches.filter {
            $0.home.localizedCaseInsensitiveContains(q)
                || $0.away.localizedCaseInsensitiveContains(q)
                || $0.league.localizedCaseInsensitiveContains(q)
                || $0.vsLabel.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if results.isEmpty {
                    Text(query.isEmpty ? "No matches loaded" : "No matches found")
                        .foregroundStyle(Theme.muted)
                        .listRowBackground(Theme.card)
                } else {
                    ForEach(results) { match in
                        HStack(spacing: 8) {
                            NavigationLink {
                                MatchCenterView(match: match, tab: $tab, showSearch: $showSearch)
                                    .environmentObject(store)
                                    .environmentObject(reelStore)
                                    .environmentObject(downloadLibrary)
                                    .environmentObject(userLibrary)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(match.vsLabel)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(.white)
                                    Text(match.seriesLabel)
                                        .font(.system(size: 12))
                                        .foregroundStyle(Theme.muted)
                                }
                            }
                            Button {
                                _ = userLibrary.toggleWatchlist(matchId: match.id, title: match.vsLabel)
                            } label: {
                                Image(systemName: userLibrary.isWatchlisted(matchId: match.id) ? "bookmark.fill" : "bookmark")
                                    .foregroundStyle(userLibrary.isWatchlisted(matchId: match.id) ? Theme.accent : Theme.muted)
                            }
                            .buttonStyle(.plain)
                        }
                        .listRowBackground(Theme.card)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Matches, teams, tournaments")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    RootTabView()
        .environmentObject(CricketStore.shared)
        .environmentObject(ReelStudioStore.shared)
        .environmentObject(DownloadLibraryStore.shared)
        .environmentObject(DeepLinkRouter.shared)
        .environmentObject(AuthStore.shared)
        .environmentObject(UserLibraryStore.shared)
}
