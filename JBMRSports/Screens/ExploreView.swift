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

    private var liveCount: Int {
        filteredMatches.filter { $0.status == .live }.count
    }

    private var todayDayName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: Date())
    }

    private var todayDateLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        return formatter.string(from: Date())
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
                            scheduleEmptyState
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
                            }
                        }

                        Color.clear.frame(height: 96)
                    }
                }
                .onChange(of: scrollToToday) { _, go in
                    guard go else { return }
                    withAnimation { proxy.scrollTo("today", anchor: .top) }
                    scrollToToday = false
                }
            }

            todayFAB
        }
        .refreshable { await store.refresh(force: true) }
        .background(Theme.background.ignoresSafeArea())
        .safeAreaInset(edge: .top, spacing: 0) {
            AppHeader(onAvatar: { tab = .profile })
                .background(Theme.background)
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

    private var scheduleEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Theme.muted.opacity(0.6))
            Text("No matches scheduled")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
            Text("Check back soon for upcoming fixtures")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
        .padding(.horizontal, 24)
    }

    private var todayFAB: some View {
        Button {
            scrollToToday = true
        } label: {
            HStack(spacing: 6) {
                Text("Today")
                    .font(.system(size: 13, weight: .bold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(Color(red: 22 / 255, green: 24 / 255, blue: 30 / 255))
                    .shadow(color: .black.opacity(0.45), radius: 12, y: 4)
            )
            .overlay(
                Capsule()
                    .stroke(
                        LinearGradient(
                            colors: [Theme.accent.opacity(0.5), Color.white.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .padding(.trailing, 20)
        .padding(.bottom, 20)
    }

    private var dateHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(todayDayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                        .textCase(.uppercase)
                        .tracking(0.6)

                    Text(todayDateLabel)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)
                }

                Spacer(minLength: 8)

                HStack(spacing: 8) {
                    if hasLive {
                        liveNowPill
                    }
                    calendarPill
                }
            }

            if !filteredMatches.isEmpty {
                HStack(spacing: 6) {
                    Text("\(filteredMatches.count) matches")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.muted)

                    if liveCount > 0 {
                        Text("•")
                            .foregroundStyle(Theme.muted.opacity(0.5))
                        Text("\(liveCount) live")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Theme.liveRed)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var liveNowPill: some View {
        Button {
            scrollToToday = true
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(Theme.liveRed)
                    .frame(width: 7, height: 7)
                    .shadow(color: Theme.liveRed.opacity(0.8), radius: 4)

                Text("Live Now")
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Theme.liveRed.opacity(0.14))
                    .overlay(Capsule().stroke(Theme.liveRed.opacity(0.35), lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
    }

    private var calendarPill: some View {
        Button { showDatePicker = true } label: {
            HStack(spacing: 5) {
                Image(systemName: "calendar")
                    .font(.system(size: 11, weight: .semibold))
                Text("Calendar")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.06))
                    .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
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

// MARK: - Tournament group

struct FigmaTournamentGroup: View {
    let tournament: String
    let matches: [ScheduleMatch]
    var onHeader: (() -> Void)? = nil
    var onSelect: (ScheduleMatch) -> Void

    private var tournamentLogo: URL? {
        matches.first?.tournamentLogoURL
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                onHeader?()
            } label: {
                HStack(spacing: 10) {
                    tournamentLogoView

                    VStack(alignment: .leading, spacing: 2) {
                        Text(tournament)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        Text("\(matches.count) \(matches.count == 1 ? "match" : "matches")")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.muted)
                    }

                    Spacer(minLength: 4)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.mutedSoft)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)

            Rectangle()
                .fill(Theme.border)
                .frame(height: 1)
                .padding(.horizontal, 14)

            VStack(spacing: 0) {
                ForEach(Array(matches.enumerated()), id: \.element.id) { index, match in
                    Button {
                        onSelect(match)
                    } label: {
                        FigmaScheduleMatchRow(match: match)
                    }
                    .buttonStyle(.plain)

                    if index < matches.count - 1 {
                        Rectangle()
                            .fill(Theme.border.opacity(0.7))
                            .frame(height: 1)
                            .padding(.leading, 14)
                    }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Theme.border, lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private var tournamentLogoView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.06))
            if let tournamentLogo {
                AsyncImage(url: tournamentLogo) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        Image(systemName: "trophy.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.accent.opacity(0.7))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.accent.opacity(0.7))
            }
        }
        .frame(width: 36, height: 36)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

// MARK: - Match row

struct FigmaScheduleMatchRow: View {
    let match: ScheduleMatch

    private let teamSecondary = Color(red: 0.749, green: 0.749, blue: 0.780)

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if match.status == .live {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Theme.liveRed)
                    .frame(width: 3)
                    .padding(.vertical, 4)
            }

            VStack(alignment: .leading, spacing: 10) {
                teamLine(
                    name: match.homeName,
                    code: match.homeCode,
                    logo: match.homeLogoURL,
                    score: match.homeStatus,
                    emphasized: match.status != .upcoming || !match.homeStatus.isEmpty
                )
                teamLine(
                    name: match.awayName,
                    code: match.awayCode,
                    logo: match.awayLogoURL,
                    score: match.awayStatus,
                    emphasized: false
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 6) {
                statusBadge

                Text(statusDetail)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
                    .minimumScaleFactor(0.8)
            }
            .frame(width: 88, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(
            match.status == .live
                ? Theme.liveRed.opacity(0.04)
                : Color.clear
        )
        .contentShape(Rectangle())
    }

    private var statusDetail: String {
        switch match.status {
        case .live:
            return match.scoreLabel ?? "In progress"
        case .upcoming:
            if !match.watchAtTime.isEmpty { return match.watchAtTime }
            return match.timeLabel
        case .completed:
            if let result = match.resultSummary, !result.isEmpty {
                return result
            }
            return match.timeLabel
        }
    }

    private var statusBadge: some View {
        Group {
            switch match.status {
            case .live:
                HStack(spacing: 4) {
                    Circle()
                        .fill(.white)
                        .frame(width: 5, height: 5)
                    Text("LIVE")
                        .font(.system(size: 10, weight: .black))
                        .tracking(0.4)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Theme.liveRed))

            case .upcoming:
                Text("UPCOMING")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.3)
                    .foregroundStyle(Color(red: 0.96, green: 0.72, blue: 0.28))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color(red: 0.96, green: 0.62, blue: 0.04).opacity(0.14))
                            .overlay(
                                Capsule().stroke(Color(red: 0.96, green: 0.62, blue: 0.04).opacity(0.35), lineWidth: 1)
                            )
                    )

            case .completed:
                Text("COMPLETED")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.3)
                    .foregroundStyle(Color(red: 0.55, green: 0.82, blue: 0.65))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color(red: 0.20, green: 0.70, blue: 0.40).opacity(0.12))
                            .overlay(
                                Capsule().stroke(Color(red: 0.20, green: 0.70, blue: 0.40).opacity(0.28), lineWidth: 1)
                            )
                    )
            }
        }
    }

    private func teamLine(name: String, code: String, logo: URL?, score: String, emphasized: Bool) -> some View {
        HStack(spacing: 10) {
            teamFlag(code: code, logo: logo)

            Text(name)
                .font(.system(size: 14, weight: emphasized ? .semibold : .medium))
                .foregroundStyle(emphasized ? .white : teamSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 4)

            if !score.isEmpty {
                Text(score)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(emphasized ? .white : teamSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
    }

    private func teamFlag(code: String, logo: URL?) -> some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.08))
            if let logo {
                AsyncImage(url: logo) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        Text(String(code.prefix(2)).uppercased())
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
                .clipShape(Circle())
            } else {
                Text(String(code.prefix(2)).uppercased())
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .frame(width: 26, height: 26)
        .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
    }
}
