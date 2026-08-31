import SwiftUI

struct LiveMatchView: View {
    @Binding var tab: AppTab
    @Binding var showSearch: Bool
    @EnvironmentObject private var store: CricketStore

    var body: some View {
        Group {
            if store.isLoading && store.featuredMatches.isEmpty {
                ProgressView()
                    .tint(Theme.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.background)
            } else if let liveMatch = store.primaryLiveMatch {
                MatchCenterView(
                    match: liveMatch,
                    tab: $tab,
                    showSearch: $showSearch,
                    embedsInTab: true
                )
                .id(liveMatch.id)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "sportscourt")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(Theme.muted)
                    Text("No live matches right now")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Pull to refresh or check Explore")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.background)
            }
        }
        .task {
            if store.featuredMatches.isEmpty {
                await store.refresh()
            }
        }
    }
}
