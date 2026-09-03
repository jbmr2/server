import SwiftUI

struct WatchlistView: View {
    @EnvironmentObject private var userLibrary: UserLibraryStore
    @EnvironmentObject private var cricketStore: CricketStore
    @Binding var tab: AppTab
    @Binding var showSearch: Bool

    var body: some View {
        Group {
            if userLibrary.watchlist.isEmpty {
                emptyState("No watchlist yet", subtitle: "Search se match bookmark karo")
            } else {
                List {
                    ForEach(userLibrary.watchlist) { item in
                        if let match = cricketStore.featuredMatch(id: item.matchId) {
                            NavigationLink {
                                MatchCenterView(match: match, tab: $tab, showSearch: $showSearch)
                            } label: {
                                watchRow(title: item.title, meta: "Saved match")
                            }
                            .listRowBackground(Theme.card)
                        } else {
                            watchRow(title: item.title, meta: "Match unavailable")
                                .listRowBackground(Theme.card)
                        }
                    }
                    .onDelete { indexSet in
                        for idx in indexSet {
                            userLibrary.removeFromWatchlist(matchId: userLibrary.watchlist[idx].matchId)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("My Watchlist")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func watchRow(title: String, meta: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
            Text(meta)
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
        }
        .padding(.vertical, 4)
    }

    private func emptyState(_ title: String, subtitle: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "bookmark")
                .font(.system(size: 40))
                .foregroundStyle(Theme.muted)
            Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
            Text(subtitle).font(.system(size: 13)).foregroundStyle(Theme.muted)
            Spacer()
        }
    }
}

struct WatchHistoryView: View {
    @EnvironmentObject private var userLibrary: UserLibraryStore
    @EnvironmentObject private var cricketStore: CricketStore
    @Binding var tab: AppTab
    @Binding var showSearch: Bool

    var body: some View {
        Group {
            if userLibrary.watchHistory.isEmpty {
                emptyState("No watch history", subtitle: "Koi match dekho — yahan dikhega")
            } else {
                List {
                    ForEach(userLibrary.watchHistory) { item in
                        if let match = cricketStore.featuredMatch(id: item.matchId) {
                            NavigationLink {
                                MatchCenterView(match: match, tab: $tab, showSearch: $showSearch)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.title)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(.white)
                                    Text(item.viewedAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.system(size: 12))
                                        .foregroundStyle(Theme.muted)
                                }
                                .padding(.vertical, 4)
                            }
                            .listRowBackground(Theme.card)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Watch History")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func emptyState(_ title: String, subtitle: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 40))
                .foregroundStyle(Theme.muted)
            Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
            Text(subtitle).font(.system(size: 13)).foregroundStyle(Theme.muted)
            Spacer()
        }
    }
}

struct SettingsView: View {
    @AppStorage("jbmr_auto_play") private var autoPlay = true
    @AppStorage("jbmr_live_alerts") private var liveAlerts = true
    @AppStorage("jbmr_wifi_only") private var wifiOnly = false

    var body: some View {
        Form {
            Toggle("Auto-play videos", isOn: $autoPlay)
            Toggle("Live match alerts", isOn: $liveAlerts)
            Toggle("Wi-Fi only streaming", isOn: $wifiOnly)
            Text("Settings are saved on this device.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("App Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SubscriptionView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("JBMR Sports Premium")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                Text("₹99/month")
                    .font(.system(size: 28, weight: .black))
                    .foregroundStyle(Theme.accent)
                featureRow("Ad-free live cricket")
                featureRow("HD streams & ball-by-ball clips")
                featureRow("Unlimited reel exports")
                Text("Coming soon on App Store")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.accent.opacity(0.15)))
                    .padding(.top, 8)
            }
            .padding(20)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Subscription & Plans")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func featureRow(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Theme.accent)
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.9))
        }
    }
}

struct HelpSupportView: View {
    var body: some View {
        List {
            linkRow("Email support", url: "mailto:support@jbmrsports.com")
            linkRow("Website", url: "https://jbmrsports.com")
            linkRow("Privacy Policy", url: "https://jbmrsports.com/privacy")
            linkRow("Terms of Service", url: "https://jbmrsports.com/terms")
            Text("For live match issues, pull down to refresh on Home or Match Center.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
                .listRowBackground(Theme.card)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Help & Support")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func linkRow(_ title: String, url: String) -> some View {
        Button {
            if let link = URL(string: url) {
                UIApplication.shared.open(link)
            }
        } label: {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.accent)
        }
        .listRowBackground(Theme.card)
    }
}
