import SwiftUI

struct ExploreView: View {
    @Binding var tab: AppTab
    @Binding var showSearch: Bool
    @Binding var path: NavigationPath
    @EnvironmentObject private var store: CricketStore
    @State private var scrollToToday = false
    @State private var showDatePicker = false
    @State private var pickedDate = Date()

    private var filteredMatches: [ScheduleMatch] {
        store.scheduleMatches
    }

    private var tournamentGroups: [(String, [ScheduleMatch])] {
        let grouped = Dictionary(grouping: filteredMatches, by: \.tournament)
        return grouped
            .map { name, matches in
                let sorted = matches.sorted { lhs, rhs in
                    let rank: (ScheduleMatch) -> Int = {
                        switch $0.status {
                        case .live: return 0
                        case .upcoming: return 1
                        case .completed: return 2
                        }
                    }
                    let lr = rank(lhs), rr = rank(rhs)
                    if lr != rr { return lr < rr }
                    return (lhs.scheduledAt ?? .distantFuture) < (rhs.scheduledAt ?? .distantFuture)
                }
                return (name, sorted)
            }
            .sorted { lhs, rhs in
                let lLive = lhs.1.contains { $0.status == .live }
                let rLive = rhs.1.contains { $0.status == .live }
                if lLive != rLive { return lLive && !rLive }
                return lhs.0 < rhs.0
            }
    }

    private var hasLive: Bool {
        filteredMatches.contains { $0.status == .live }
    }

    private var todayLabel: String {
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        return "Today \(f.string(from: Date()))"
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        dateHeader
                            .id("today")

                        if store.isLoading && filteredMatches.isEmpty {
                            ProgressView().tint(Theme.accent)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 40)
                        } else if tournamentGroups.isEmpty {
                            Text("No matches scheduled")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Theme.muted)
                                .padding(.horizontal, 16)
                                .padding(.top, 24)
                        } else {
                            ForEach(tournamentGroups, id: \.0) { tournament, matches in
                                FigmaTournamentGroup(
                                    tournament: tournament,
                                    matches: matches,
                                    onHeader: {
                                        if let id = store.tournaments.first(where: { $0.name == tournament })?.tournamentId {
                                            path.append(AppNavigationRoute.tournament(id))
                                        }
                                    },
                                    onSelect: { match in
                                        path.append(AppNavigationRoute.match(match.id))
                                    }
                                )
                                Color.clear.frame(height: 16)
                            }
                        }

                        Color.clear.frame(height: 80)
                    }
                }
                .onChange(of: scrollToToday) { _, go in
                    guard go else { return }
                    withAnimation { proxy.scrollTo("today", anchor: .top) }
                    scrollToToday = false
                }
            }

            // Figma Today FAB: 12pt ExtraBold, px 20 / py 10, radius 20
            Button {
                scrollToToday = true
            } label: {
                Text("Today")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Theme.accent))
            }
            .buttonStyle(.plain)
            .padding(.trailing, 24)
            .padding(.bottom, 16)
        }
        .refreshable { await store.refresh() }
        .background(Theme.background.ignoresSafeArea())
        .safeAreaInset(edge: .top, spacing: 0) {
            AppHeader(onAvatar: { tab = .profile })
                .background(Theme.background)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Theme.border).frame(height: 1)
                }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: AppNavigationRoute.self) { route in
            switch route {
            case .match(let id):
                if let match = resolveMatch(id: id) {
                    MatchCenterView(match: match, tab: $tab, showSearch: $showSearch)
                } else {
                    Text("Match unavailable")
                        .foregroundStyle(Theme.muted)
                }
            case .tournament(let id):
                TournamentDetailView(tournamentId: id, tab: $tab, showSearch: $showSearch)
            }
        }
        .sheet(isPresented: $showDatePicker) {
            NavigationStack {
                DatePicker("Schedule date", selection: $pickedDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .padding()
                    .navigationTitle("Jump to date")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") {
                                scrollToToday = true
                                showDatePicker = false
                            }
                        }
                    }
            }
            .presentationDetents([.medium])
        }
    }

    private var dateHeader: some View {
        HStack {
            Text(todayLabel)
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(.white)
            Spacer()
            if hasLive {
                HStack(spacing: 6) {
                    Circle().fill(Theme.accent).frame(width: 6, height: 6)
                    Text("Live Now")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.accent)
                }
            }
            Button { showDatePicker = true } label: {
                Image(systemName: "calendar")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Theme.card))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.card)
    }

    private func resolveMatch(id: String) -> FeaturedMatch? {
        if let existing = store.featuredMatches.first(where: { $0.id == id }) {
            return existing
        }
        guard let schedule = store.scheduleMatches.first(where: { $0.id == id }) else { return nil }
        return featured(from: schedule)
    }

    private func featured(from match: ScheduleMatch) -> FeaturedMatch {
        store.featuredMatches.first(where: { $0.id == match.id })
            ?? FeaturedMatch(
                id: match.id,
                league: match.tournament,
                year: "2026",
                home: match.homeName,
                away: match.awayName,
                timeLabel: match.timeLabel,
                imageName: "HeroMatch",
                isLive: match.status == .live,
                homeShort: match.homeCode,
                awayShort: match.awayCode,
                imageURL: match.thumbnailURL,
                homeLogoURL: match.homeLogoURL,
                awayLogoURL: match.awayLogoURL,
                tournamentLogoURL: match.tournamentLogoURL,
                scoreLabel: match.scoreLabel ?? "",
                matchSeq: match.matchSeq
            )
    }
}

// MARK: - Tournament group (Figma vertical list)

struct FigmaTournamentGroup: View {
    let tournament: String
    let matches: [ScheduleMatch]
    var onHeader: (() -> Void)? = nil
    var onSelect: (ScheduleMatch) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                onHeader?()
            } label: {
                HStack(spacing: 4) {
                    Text(tournament.uppercased())
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(">")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.mutedSoft)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)

            ForEach(matches) { match in
                Button {
                    onSelect(match)
                } label: {
                    FigmaScheduleMatchRow(match: match)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
            }
        }
        .padding(.top, 4)
    }
}

struct FigmaScheduleMatchRow: View {
    let match: ScheduleMatch

    private var homeScore: String {
        if !match.homeStatus.isEmpty { return match.homeStatus }
        guard let label = match.scoreLabel, !label.isEmpty else { return "" }
        return label
    }

    private var awayScore: String { match.awayStatus }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                statusPill
                Spacer(minLength: 8)
                Text(metaRight)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(red: 0.50, green: 0.50, blue: 0.55))
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
            }

            VStack(alignment: .leading, spacing: 12) {
                teamRow(name: match.homeName, code: match.homeCode, logo: match.homeLogoURL, score: homeScore)
                teamRow(name: match.awayName, code: match.awayCode, logo: match.awayLogoURL, score: awayScore)
            }

            if !statusLine.isEmpty {
                Text(statusLine)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.accent)
            }

            if !venueLine.isEmpty {
                Text(venueLine)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(red: 0.50, green: 0.50, blue: 0.55))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.card)
        )
    }

    @ViewBuilder
    private var statusPill: some View {
        let text: String = {
            switch match.status {
            case .live: return "LIVE"
            case .upcoming: return "UPCOMING"
            case .completed: return "COMPLETED"
            }
        }()
        Text(text)
            .font(.system(size: 11, weight: .heavy))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(match.status == .live ? Theme.liveRed : Color(white: 0.22))
            )
    }

    private var metaRight: String {
        switch match.status {
        case .live:
            return match.matchLabel == "Match" ? match.timeLabel : match.matchLabel
        case .upcoming:
            let time = match.watchAtTime.isEmpty ? match.timeLabel : match.watchAtTime
            return [dayHint, time].filter { !$0.isEmpty }.joined(separator: " • ")
        case .completed:
            return match.timeLabel == (match.resultSummary ?? "") ? "" : match.timeLabel
        }
    }

    private var statusLine: String {
        if match.status == .completed, let summary = match.resultSummary, !summary.isEmpty {
            return summary
        }
        if match.status == .live,
           match.homeStatus.isEmpty,
           match.awayStatus.isEmpty,
           let score = match.scoreLabel, !score.isEmpty {
            return score
        }
        if match.status == .upcoming, match.matchLabel != "Match", !match.matchLabel.isEmpty {
            return match.matchLabel
        }
        return ""
    }

    private var venueLine: String {
        match.venue
    }

    private var dayHint: String {
        guard let date = match.scheduledAt else { return match.dayKey }
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInTomorrow(date) { return "Tomorrow" }
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        return f.string(from: date)
    }

    private func teamRow(name: String, code: String, logo: URL?, score: String) -> some View {
        HStack(spacing: 12) {
            teamLogo(code: code, logo: logo)
            Text(name)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 8)
            if !score.isEmpty {
                Text(score)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }

    private func teamLogo(code: String, logo: URL?) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color(red: 0.14, green: 0.15, blue: 0.19))
            if let logo {
                AsyncImage(url: logo) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        Text(code)
                            .font(.system(size: 7, weight: .heavy))
                            .foregroundStyle(.white)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
            } else {
                Text(code)
                    .font(.system(size: 7, weight: .heavy))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            }
        }
        .frame(width: 20, height: 14)
    }
}
