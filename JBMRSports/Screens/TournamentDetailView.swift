import SwiftUI

struct TournamentDetailView: View {
    let tournamentId: String
    @Binding var tab: AppTab
    @Binding var showSearch: Bool
    @EnvironmentObject private var store: CricketStore
    @Environment(\.dismiss) private var dismiss

    @State private var section: DetailSection = .matches
    @State private var filter: MatchFilter = .all
    @State private var selectedMatch: FeaturedMatch?

    enum DetailSection: String, CaseIterable {
        case matches = "Matches"
        case points = "Points Table"
        case stats = "Stats"
        case teams = "Teams"
    }

    enum MatchFilter: String, CaseIterable {
        case all = "All"
        case live = "Live"
        case upcoming = "Upcoming"
        case completed = "Completed"
    }

    private var tournament: APITournament? {
        store.tournaments.first { $0.tournamentId == tournamentId }
    }

    private var matches: [ScheduleMatch] {
        store.scheduleMatches.filter { $0.tournament == tournament?.name }
    }

    private var filteredMatches: [ScheduleMatch] {
        switch filter {
        case .all: return matches
        case .live: return matches.filter { $0.status == .live }
        case .upcoming: return matches.filter { $0.status == .upcoming }
        case .completed: return matches.filter { $0.status == .completed }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    if let tournament {
                        banner(tournament)
                    }
                    tabNav
                    switch section {
                    case .matches:
                        filterRow
                        matchList
                    case .points:
                        pointsTable
                    case .stats:
                        statsBlock
                    case .teams:
                        teamsBlock
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

    // MARK: - Header (48pt)

    private var header: some View {
        AppHeader(
            onLogo: { dismiss() },
            onAvatar: { tab = .profile }
        )
    }

    // MARK: - Banner

    private func banner(_ t: APITournament) -> some View {
        let teamCount = uniqueTeams.count
        let matchCount = matches.count
        let format = t.type ?? t.format ?? "T20"
        let ongoing = matches.contains { $0.status == .live } || matches.contains { $0.status == .upcoming }

        return VStack(spacing: 8) {
            tournamentLogo(url: CrickAPI.absoluteURL(from: t.logoUrl), title: t.name)
                .frame(width: 48, height: 48)

            Text(t.name)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Text(dateRange(start: t.startDate, end: t.endDate))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.mutedSoft)

            Text("\(teamCount) Teams  •  \(matchCount) Matches  •  \(format)")
                .font(.system(size: 10))
                .foregroundStyle(Theme.mutedSoft)

            HStack(spacing: 4) {
                Circle().fill(Theme.accent).frame(width: 6, height: 6)
                Text(ongoing ? "ONGOING" : "COMPLETED")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Capsule().fill(Theme.accent.opacity(0.15)))
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Theme.border, lineWidth: 1)
                )
        )
        .padding(.horizontal, 0)
    }

    // MARK: - Tabs

    private var tabNav: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 20) {
                ForEach(DetailSection.allCases, id: \.self) { item in
                    Button {
                        section = item
                    } label: {
                        VStack(spacing: 4) {
                            Text(item.rawValue)
                                .font(.system(size: 13, weight: section == item ? .semibold : .medium))
                                .foregroundStyle(section == item ? Theme.accent : Theme.mutedSoft)
                            RoundedRectangle(cornerRadius: 1)
                                .fill(section == item ? Theme.accent : .clear)
                                .frame(width: 50, height: 2)
                        }
                        .frame(width: 100)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .frame(height: 42)
    }

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(MatchFilter.allCases, id: \.self) { item in
                    let active = filter == item
                    Button {
                        filter = item
                    } label: {
                        Text(item.rawValue)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(active ? Theme.background : Theme.mutedSoft)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 5)
                            .background(
                                Capsule().fill(active ? Theme.accent : .clear)
                            )
                            .overlay(
                                Capsule().stroke(active ? Color.clear : Theme.border, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
        .frame(height: 38)
    }

    // MARK: - Match list

    private var matchList: some View {
        LazyVStack(spacing: 12) {
            if filteredMatches.isEmpty {
                Text("No matches")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)
            } else {
                ForEach(filteredMatches) { match in
                    Button {
                        selectedMatch = featured(from: match)
                    } label: {
                        TournamentMatchCard(match: match)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Points / Stats / Teams

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
            .padding(.vertical, 10)

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
                            .foregroundStyle(Theme.accent)
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(index % 2 == 0 ? Theme.card : Theme.background)
                }
            }
        }
        .padding(.top, 8)
    }

    private var statsBlock: some View {
        let live = matches.filter { $0.status == .live }.count
        let up = matches.filter { $0.status == .upcoming }.count
        let done = matches.filter { $0.status == .completed }.count
        return VStack(spacing: 12) {
            statRow("Total Matches", "\(matches.count)")
            statRow("Live", "\(live)")
            statRow("Upcoming", "\(up)")
            statRow("Completed", "\(done)")
            statRow("Teams", "\(uniqueTeams.count)")
        }
        .padding(16)
        .padding(.top, 8)
    }

    private func statRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.mutedSoft)
            Spacer()
            Text(value)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Theme.border, lineWidth: 1)
                )
        )
    }

    private var teamsBlock: some View {
        LazyVStack(spacing: 10) {
            ForEach(uniqueTeams, id: \.name) { team in
                HStack(spacing: 12) {
                    teamLogo(code: team.code, url: team.logo, size: 36)
                    Text(team.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Theme.card)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Theme.border, lineWidth: 1)
                        )
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
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
        // Fix losses = played - won
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

    private func dateRange(start: String?, end: String?) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_IN")
        f.dateFormat = "MMM d"
        let fYear = DateFormatter()
        fYear.locale = Locale(identifier: "en_IN")
        fYear.dateFormat = "MMM d, yyyy"

        let s = MatchMapper.parseDate(start)
        let e = MatchMapper.parseDate(end)
        if let s, let e {
            let sy = Calendar.current.component(.year, from: s)
            let ey = Calendar.current.component(.year, from: e)
            if sy == ey {
                return "\(f.string(from: s)) – \(fYear.string(from: e))"
            }
            return "\(fYear.string(from: s)) – \(fYear.string(from: e))"
        }
        if let s { return fYear.string(from: s) }
        return "Season 2026"
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

    private func tournamentLogo(url: URL?, title: String) -> some View {
        let initials = title.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
        return ZStack {
            Circle().fill(Theme.accent.opacity(0.25))
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        Text(initials.uppercased())
                            .font(.system(size: 14, weight: .black))
                            .foregroundStyle(Theme.accent)
                    }
                }
                .clipShape(Circle())
            } else {
                Text(initials.uppercased())
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(Theme.accent)
            }
        }
    }

    private func teamLogo(code: String, url: URL?, size: CGFloat) -> some View {
        ZStack {
            Circle().fill(Color(white: 0.16))
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        Text(code)
                            .font(.system(size: size * 0.28, weight: .heavy))
                            .foregroundStyle(.white)
                    }
                }
                .clipShape(Circle())
            } else {
                Text(code)
                    .font(.system(size: size * 0.28, weight: .heavy))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Match card (Figma 358×~125, radius 12)

struct TournamentMatchCard: View {
    let match: ScheduleMatch

    private let secondary = Color(red: 0.749, green: 0.749, blue: 0.780) // #BFBFC7

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(topMeta)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.mutedSoft)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if match.status == .live {
                    Text("● LIVE")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Theme.liveRed))
                }
            }

            teamRow(
                name: match.homeName,
                code: match.homeCode,
                logo: match.homeLogoURL,
                status: match.homeStatus,
                emphasized: true
            )
            teamRow(
                name: match.awayName,
                code: match.awayCode,
                logo: match.awayLogoURL,
                status: match.awayStatus.isEmpty && match.status != .upcoming
                    ? (match.status == .live ? "Yet to bat" : "")
                    : match.awayStatus,
                emphasized: false
            )

            HStack {
                Text(footerLeft)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(footerLeftColor)
                Spacer()
                Text(footerRight)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.mutedSoft)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Theme.border, lineWidth: 1)
                )
        )
    }

    private var topMeta: String {
        let label = match.matchLabel
        if match.venue.isEmpty { return label }
        return "\(label)  •  \(match.venue)"
    }

    private var footerLeft: String {
        switch match.status {
        case .live:
            return match.homeStatus.isEmpty ? "Live" : "\(match.homeCode) batting"
        case .upcoming:
            return "Upcoming"
        case .completed:
            return match.resultSummary ?? "Completed"
        }
    }

    private var footerLeftColor: Color {
        switch match.status {
        case .live: return Color(red: 0.20, green: 0.80, blue: 0.40)
        case .upcoming: return Theme.mutedSoft
        case .completed: return Theme.accent
        }
    }

    private var footerRight: String {
        guard let date = match.scheduledAt else { return match.timeLabel }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_IN")
        if Calendar.current.isDateInToday(date) {
            f.dateFormat = "'Today,' h:mm a"
        } else if Calendar.current.isDateInTomorrow(date) {
            f.dateFormat = "'Tomorrow,' h:mm a"
        } else {
            f.dateFormat = "MMM d, yyyy"
        }
        return f.string(from: date)
    }

    private func teamRow(name: String, code: String, logo: URL?, status: String, emphasized: Bool) -> some View {
        HStack(spacing: 8) {
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
            .frame(width: 24, height: 24)

            Text(name)
                .font(.system(size: 13, weight: emphasized ? .semibold : .medium))
                .foregroundStyle(emphasized ? .white : secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 4)

            if !status.isEmpty {
                Text(status)
                    .font(.system(size: 13, weight: emphasized ? .bold : .medium))
                    .foregroundStyle(emphasized ? .white : secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(height: 24)
    }
}
