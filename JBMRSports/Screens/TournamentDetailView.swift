import SwiftUI

struct TournamentDetailView: View {
    let tournamentId: String
    @Binding var tab: AppTab
    @Binding var showSearch: Bool
    @EnvironmentObject private var store: CricketStore
    @Environment(\.dismiss) private var dismiss

    @State private var section: DetailSection = .matches
    @State private var selectedMatch: FeaturedMatch?

    private let fanOrange = Color(red: 0.98, green: 0.45, blue: 0.09)
    private let heroPurple = Color(red: 0.28, green: 0.12, blue: 0.52)

    enum DetailSection: String, CaseIterable {
        case matches = "Matches"
        case videos = "Videos"
        case points = "Points Table"
    }

    private var tournament: APITournament? {
        store.tournaments.first { $0.tournamentId == tournamentId }
    }

    private var matches: [ScheduleMatch] {
        store.scheduleMatches.filter { $0.tournament == tournament?.name }
    }

    private var groupedMatches: [(String, [ScheduleMatch])] {
        let live = matches.filter { $0.status == .live }
        let upcoming = matches.filter { $0.status == .upcoming }
        let completed = matches.filter { $0.status == .completed }
        var groups: [(String, [ScheduleMatch])] = []
        if !live.isEmpty { groups.append(("Live", live)) }
        if !upcoming.isEmpty { groups.append(("Upcoming", upcoming)) }
        if !completed.isEmpty { groups.append(("Completed", completed)) }
        return groups
    }

    private var tournamentClips: [HighlightClip] {
        if let rail = store.tournamentHighlightRails.first(where: { $0.id == tournamentId }) {
            return rail.clips
        }
        return store.highlightClips.filter { $0.tournamentId == tournamentId }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    if let tournament {
                        heroBanner(tournament)
                    }
                    tabNav
                    switch section {
                    case .matches:
                        if let tournament {
                            matchesTournamentHeader(tournament)
                        }
                        matchList
                    case .videos:
                        videosList
                    case .points:
                        pointsTable
                    }
                }
                .padding(.bottom, 28)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $selectedMatch) { match in
            MatchCenterView(match: match, tab: $tab, showSearch: $showSearch)
        }
    }

    // MARK: - Header

    private var header: some View {
        AppHeader(
            onLogo: { dismiss() },
            onAvatar: { tab = .profile }
        )
    }

    // MARK: - Hero

    private func heroBanner(_ t: APITournament) -> some View {
        let format = t.type ?? t.format ?? "T20"
        let year = tournamentYear(from: t.startDate)
        let heroImage = matches.compactMap(\.thumbnailURL).first
        let hasLive = matches.contains { $0.status == .live }

        return VStack(spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                Group {
                    if let heroImage {
                        AsyncImage(url: heroImage) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().scaledToFill()
                            default:
                                heroGradient
                            }
                        }
                    } else {
                        heroGradient
                    }
                }
                .frame(height: 220)
                .frame(maxWidth: .infinity)
                .clipped()

                LinearGradient(
                    colors: [
                        heroPurple.opacity(0.92),
                        heroPurple.opacity(0.55),
                        Color(red: 8 / 255, green: 8 / 255, blue: 12 / 255).opacity(0.95)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 12) {
                        tournamentLogoBadge(url: CrickAPI.absoluteURL(from: t.logoUrl), title: t.name)

                        VStack(alignment: .leading, spacing: 6) {
                            Text(t.name)
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                                .minimumScaleFactor(0.8)

                            if !year.isEmpty {
                                Text(year)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.72))
                            }

                            HStack(spacing: 8) {
                                Text("CRICKET")
                                    .font(.system(size: 10, weight: .bold))
                                    .tracking(0.4)
                                    .foregroundStyle(.white.opacity(0.85))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule().fill(Color.white.opacity(0.14))
                                    )

                                Text("\(format)  •  \(dateRange(start: t.startDate, end: t.endDate))  •  \(matches.count) Matches")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.72))
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.8)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .frame(height: 220)

            if hasLive {
                Button {
                    openPrimaryMatch()
                } label: {
                    HStack(spacing: 12) {
                        Text("Watch Live on JBMR Sports")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)

                        Spacer(minLength: 8)

                        HStack(spacing: 6) {
                            Text("WATCH LIVE")
                                .font(.system(size: 12, weight: .black))
                                .italic()
                                .foregroundStyle(fanOrange)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(fanOrange)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(.white))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(fanOrange)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var heroGradient: some View {
        LinearGradient(
            colors: [heroPurple, Color(red: 0.10, green: 0.08, blue: 0.20)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Tabs

    private var tabNav: some View {
        HStack(spacing: 0) {
            ForEach(DetailSection.allCases, id: \.self) { item in
                Button {
                    section = item
                } label: {
                    VStack(spacing: 0) {
                        Text(item.rawValue)
                            .font(.system(size: 14, weight: section == item ? .bold : .medium))
                            .foregroundStyle(section == item ? .white : Theme.mutedSoft)
                            .padding(.vertical, 14)

                        Rectangle()
                            .fill(section == item ? fanOrange : Color.clear)
                            .frame(height: 3)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color(red: 14 / 255, green: 15 / 255, blue: 20 / 255))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.border).frame(height: 1)
        }
    }

    // MARK: - Matches

    private func matchesTournamentHeader(_ t: APITournament) -> some View {
        let format = t.type ?? t.format ?? "T20"
        let liveCount = matches.filter { $0.status == .live }.count

        return HStack(spacing: 12) {
            tournamentLogoBadge(url: CrickAPI.absoluteURL(from: t.logoUrl), title: t.name)

            VStack(alignment: .leading, spacing: 3) {
                Text(t.name)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)

                HStack(spacing: 6) {
                    Text(format.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.3)
                        .foregroundStyle(fanOrange)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            Capsule().fill(fanOrange.opacity(0.14))
                        )

                    Text("\(matches.count) matches")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.muted)

                    if liveCount > 0 {
                        Text("•")
                            .foregroundStyle(Theme.muted.opacity(0.5))
                        Text("\(liveCount) live")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.liveRed)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Theme.card)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.border).frame(height: 1)
        }
    }

    private var matchList: some View {
        VStack(spacing: 0) {
            if groupedMatches.isEmpty {
                Text("No matches")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)
            } else {
                ForEach(groupedMatches, id: \.0) { title, sectionMatches in
                    VStack(spacing: 0) {
                        Text(title)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.top, 18)
                            .padding(.bottom, 8)

                        ForEach(Array(sectionMatches.enumerated()), id: \.element.id) { index, match in
                            Button {
                                selectedMatch = featured(from: match)
                            } label: {
                                FanCodeTournamentMatchRow(match: match, accent: fanOrange)
                            }
                            .buttonStyle(.plain)

                            if index < sectionMatches.count - 1 {
                                Rectangle()
                                    .fill(Theme.border.opacity(0.8))
                                    .frame(height: 1)
                                    .padding(.leading, 16)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Videos

    private var videosList: some View {
        VStack(spacing: 0) {
            if tournamentClips.isEmpty {
                Text("No videos yet")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)
            } else {
                Text("Highlights")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                    .padding(.bottom, 8)

                ForEach(Array(tournamentClips.enumerated()), id: \.element.id) { index, clip in
                    Button {
                        if let matchId = clip.matchId,
                           let schedule = matches.first(where: { $0.id == matchId }) {
                            selectedMatch = featured(from: schedule)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Theme.card)
                                Image(systemName: "play.fill")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(fanOrange)
                            }
                            .frame(width: 72, height: 48)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(clip.cardTitle)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .lineLimit(2)
                                Text(clip.cardSubtitle)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Theme.muted)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)

                    if index < tournamentClips.count - 1 {
                        Rectangle()
                            .fill(Theme.border.opacity(0.8))
                            .frame(height: 1)
                            .padding(.leading, 16)
                    }
                }
            }
        }
    }

    // MARK: - Points

    private var pointsTable: some View {
        let rows = computedPoints
        return VStack(spacing: 0) {
            HStack {
                Text("#").frame(width: 28, alignment: .leading)
                Text("Team").frame(maxWidth: .infinity, alignment: .leading)
                Text("P").frame(width: 28)
                Text("W").frame(width: 28)
                Text("L").frame(width: 28)
                Text("Pts").frame(width: 36, alignment: .trailing)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.mutedSoft)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            if rows.isEmpty {
                Text("Points table will appear after results")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                    .padding(.top, 20)
            } else {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    HStack {
                        Text("\(index + 1)")
                            .frame(width: 28, alignment: .leading)
                            .foregroundStyle(Theme.mutedSoft)
                        Text(row.teamName)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .foregroundStyle(.white)
                        Text("\(row.played)").frame(width: 28)
                        Text("\(row.won)").frame(width: 28)
                        Text("\(row.lost)").frame(width: 28)
                        Text("\(row.points)")
                            .frame(width: 36, alignment: .trailing)
                            .foregroundStyle(fanOrange)
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(index % 2 == 0 ? Theme.card : Theme.background)

                    if index < rows.count - 1 {
                        Rectangle()
                            .fill(Theme.border.opacity(0.8))
                            .frame(height: 1)
                            .padding(.leading, 16)
                    }
                }
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Helpers

    private struct TeamInfo {
        let name: String
        let code: String
        let logo: URL?
    }

    private var uniqueTeams: [TeamInfo] {
        var seen = Set<String>()
        var result: [TeamInfo] = []
        for m in matches {
            for (name, code, logo) in [
                (m.homeName, m.homeCode, m.homeLogoURL),
                (m.awayName, m.awayCode, m.awayLogoURL)
            ] {
                if seen.insert(name).inserted {
                    result.append(TeamInfo(name: name, code: code, logo: logo))
                }
            }
        }
        return result.sorted { $0.name < $1.name }
    }

    private var computedPoints: [PointsTableRow] {
        var map: [String: (name: String, code: String, played: Int, won: Int, lost: Int)] = [:]
        for m in matches where m.status == .completed {
            for (name, code) in [(m.homeName, m.homeCode), (m.awayName, m.awayCode)] {
                var e = map[name] ?? (name, code, 0, 0, 0)
                e.played += 1
                map[name] = e
            }
            if let summary = m.resultSummary?.lowercased() {
                for key in map.keys {
                    if summary.contains(key.lowercased())
                        || summary.hasPrefix(map[key]!.code.lowercased() + " ")
                        || summary.contains(map[key]!.code.lowercased() + " won") {
                        map[key]?.won += 1
                        break
                    }
                }
            }
        }
        for key in map.keys {
            map[key]!.lost = max(0, map[key]!.played - map[key]!.won)
        }
        return map.values
            .map {
                PointsTableRow(
                    id: $0.code + $0.name,
                    rank: 0,
                    teamCode: $0.code,
                    teamName: $0.name,
                    played: $0.played,
                    won: $0.won,
                    lost: $0.lost,
                    nrr: "-",
                    points: $0.won * 2
                )
            }
            .sorted { $0.points == $1.points ? $0.won > $1.won : $0.points > $1.points }
    }

    private func tournamentYear(from start: String?) -> String {
        guard let date = MatchMapper.parseDate(start) else { return "" }
        return String(Calendar.current.component(.year, from: date))
    }

    private func dateRange(start: String?, end: String?) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_IN")
        f.dateFormat = "dd MMM"
        let fYear = DateFormatter()
        fYear.locale = Locale(identifier: "en_IN")
        fYear.dateFormat = "dd MMM, yyyy"

        let s = MatchMapper.parseDate(start)
        let e = MatchMapper.parseDate(end)
        if let s, let e {
            let sy = Calendar.current.component(.year, from: s)
            let ey = Calendar.current.component(.year, from: e)
            if sy == ey {
                return "\(f.string(from: s)) - \(fYear.string(from: e))"
            }
            return "\(fYear.string(from: s)) - \(fYear.string(from: e))"
        }
        if let s { return fYear.string(from: s) }
        return "Season 2026"
    }

    private func openPrimaryMatch() {
        if let live = matches.first(where: { $0.status == .live }) {
            selectedMatch = featured(from: live)
        } else if let upcoming = matches.first(where: { $0.status == .upcoming }) {
            selectedMatch = featured(from: upcoming)
        } else if let first = matches.first {
            selectedMatch = featured(from: first)
        }
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

    private func tournamentLogoBadge(url: URL?, title: String) -> some View {
        let initials = title.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
        return ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.white)
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit().padding(6)
                    default:
                        Text(initials.uppercased())
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(heroPurple)
                    }
                }
            } else {
                Text(initials.uppercased())
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(heroPurple)
            }
        }
        .frame(width: 44, height: 44)
    }
}

// MARK: - FanCode-style match row

struct FanCodeTournamentMatchRow: View {
    let match: ScheduleMatch
    let accent: Color

    private let secondary = Color(red: 0.749, green: 0.749, blue: 0.780)

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                Text(matchHeader)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.mutedSoft)

                teamRow(
                    name: match.homeName,
                    code: match.homeCode,
                    logo: match.homeLogoURL,
                    score: displayScore(match.homeStatus),
                    isWinner: isWinner(teamName: match.homeName, code: match.homeCode)
                )
                teamRow(
                    name: match.awayName,
                    code: match.awayCode,
                    logo: match.awayLogoURL,
                    score: displayScore(match.awayStatus),
                    isWinner: isWinner(teamName: match.awayName, code: match.awayCode)
                )

                if let summary = match.resultSummary, !summary.isEmpty {
                    Text(summary)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.mutedSoft)
                        .lineLimit(2)
                } else if match.status == .upcoming, !match.watchAtTime.isEmpty {
                    Text("Starts at \(match.watchAtTime)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.mutedSoft)
                }
            }

            Spacer(minLength: 0)

            Text(statusLabel)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.mutedSoft)
                .padding(.top, 18)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    private var matchHeader: String {
        var parts: [String] = []
        if let seq = match.matchSeq {
            parts.append("Match \(seq)")
        } else {
            parts.append(match.matchLabel)
        }
        if let date = formattedDate {
            parts.append(date)
        }
        return parts.joined(separator: "  •  ")
    }

    private var formattedDate: String? {
        guard let date = match.scheduledAt else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_IN")
        f.dateFormat = "MMM d, yyyy"
        return f.string(from: date)
    }

    private var statusLabel: String {
        switch match.status {
        case .live: return "Live"
        case .upcoming: return "Upcoming"
        case .completed: return "Completed"
        }
    }

    private func displayScore(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return trimmed
    }

    private func isWinner(teamName: String, code: String) -> Bool {
        guard match.status == .completed, let summary = match.resultSummary else { return false }
        let lower = summary.lowercased()
        let name = teamName.lowercased()
        let short = code.lowercased()

        if let beatRange = lower.range(of: " beat ") {
            let winner = String(lower[..<beatRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            if winner == short || winner == name || name.hasPrefix(winner) || winner.hasPrefix(short) {
                return true
            }
        }

        if lower.hasPrefix(short) || lower.hasPrefix(name) { return true }
        if lower.contains("\(name) won") || lower.contains("\(short) won") { return true }
        return false
    }

    private func teamRow(name: String, code: String, logo: URL?, score: String, isWinner: Bool) -> some View {
        HStack(spacing: 10) {
            teamLogo(code: code, logo: logo)

            Text(name)
                .font(.system(size: 14, weight: isWinner ? .bold : .medium))
                .foregroundStyle(isWinner ? .white : secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 4)

            HStack(spacing: 4) {
                if isWinner {
                    Image(systemName: "play.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(accent)
                        .rotationEffect(.degrees(-30))
                }
                if !score.isEmpty {
                    Text(score)
                        .font(.system(size: 13, weight: isWinner ? .bold : .semibold))
                        .foregroundStyle(isWinner ? .white : secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
        }
    }

    private func teamLogo(code: String, logo: URL?) -> some View {
        ZStack {
            Circle().fill(Color(white: 0.16))
            if let logo {
                AsyncImage(url: logo) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        Text(code)
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundStyle(.white)
                    }
                }
                .clipShape(Circle())
            } else {
                Text(code)
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            }
        }
        .frame(width: 26, height: 26)
    }
}

// Keep legacy card available for any other screens.
typealias TournamentMatchCard = FanCodeTournamentMatchRow

extension FanCodeTournamentMatchRow {
    init(match: ScheduleMatch) {
        self.match = match
        self.accent = Color(red: 0.98, green: 0.45, blue: 0.09)
    }
}
