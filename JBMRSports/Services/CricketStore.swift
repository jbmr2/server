import Foundation
import Combine

#if canImport(FirebaseCore)
import FirebaseCore
#endif

@MainActor
final class CricketStore: ObservableObject {
    static let shared = CricketStore()

    @Published private(set) var tournaments: [APITournament] = []
    @Published private(set) var featuredMatches: [FeaturedMatch] = []
    @Published private(set) var scheduleMatches: [ScheduleMatch] = []
    @Published private(set) var scheduleDates: [String] = []
    @Published private(set) var tournamentCards: [LeagueTile] = []
    @Published private(set) var highlightClips: [HighlightClip] = []
    @Published private(set) var shortClips: [ShortClip] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var dataSource: String = ""
    @Published private(set) var adsEnabled = true

    private(set) var cachedFeed: FirebaseOTTFeed?
    private var lastRefreshAt: Date?
    private var metaListener = OTTMetaLiveListener()
    private var liveScorePoller = CrickAPILiveScorePoller()
    private var lastSilentRefreshAt: Date?
    private var liveScoreSignatures: [String: String] = [:]

    private init() {
        loadCachedIfNeeded()
    }

    var liveMatches: [FeaturedMatch] {
        featuredMatches.filter(\.isLive)
    }

    var primaryLiveMatch: FeaturedMatch? {
        liveMatches.first(where: { $0.videoURL != nil }) ?? liveMatches.first ?? featuredMatches.first
    }

    func featuredMatch(id: String) -> FeaturedMatch? {
        if let hit = featuredMatches.first(where: { $0.id == id }) {
            return hit
        }
        for tournament in tournaments {
            guard let match = tournament.matches.first(where: { $0.matchId == id }) else { continue }
            return MatchMapper.featured(match: match, tournament: tournament)
        }
        if let schedule = scheduleMatches.first(where: { $0.id == id }) {
            return featured(from: schedule)
        }
        return nil
    }

    func playbackURL(forMatchId matchId: String) -> URL? {
        if let url = featuredMatch(id: matchId)?.videoURL { return url }
        guard let feed = cachedFeed,
              let (_, firebaseMatch) = FirebaseOTTClient.findMatch(matchId: matchId, in: feed) else {
            return nil
        }
        let live = firebaseMatch.liveUrl?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !live.isEmpty, let url = CrickAPI.absoluteURL(from: live) { return url }
        let highlight = firebaseMatch.highlightUrl?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return CrickAPI.absoluteURL(from: highlight)
    }

    func featured(from schedule: ScheduleMatch) -> FeaturedMatch {
        featuredMatches.first(where: { $0.id == schedule.id })
            ?? FeaturedMatch(
                id: schedule.id,
                league: schedule.tournament,
                year: "2026",
                home: schedule.homeName,
                away: schedule.awayName,
                timeLabel: schedule.timeLabel,
                imageName: "HeroMatch",
                isLive: schedule.status == .live,
                homeShort: schedule.homeCode,
                awayShort: schedule.awayCode,
                imageURL: schedule.thumbnailURL,
                homeLogoURL: schedule.homeLogoURL,
                awayLogoURL: schedule.awayLogoURL,
                tournamentLogoURL: schedule.tournamentLogoURL,
                scoreLabel: schedule.scoreLabel ?? "",
                matchSeq: schedule.matchSeq
            )
    }

    var tournamentHighlightRails: [TournamentHighlightRail] {
        var rails: [TournamentHighlightRail] = []

        for tile in tournamentCards {
            guard let tournament = tournaments.first(where: { $0.tournamentId == tile.id }) else { continue }
            var clips: [HighlightClip] = []
            var seen = Set<String>()

            for clip in highlightClips where clip.tournamentId == tile.id {
                let key = clip.matchId ?? clip.id
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                clips.append(clip)
            }

            for match in tournament.matches {
                let raw = match.highlightUrl?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !raw.isEmpty else { continue }
                let status = match.status.lowercased()
                guard status == "completed" || status == "finished" else { continue }
                guard let videoURL = CrickAPI.absoluteURL(from: raw) else { continue }
                guard !seen.contains(match.matchId) else { continue }
                seen.insert(match.matchId)

                let homeCode = Self.teamCode(match.team1.shortName, name: match.team1.name)
                let awayCode = Self.teamCode(match.team2.shortName, name: match.team2.name)
                let result = match.result?.summaryText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                clips.append(
                    HighlightClip(
                        id: "match-hl-\(match.matchId)",
                        tag: "MATCH HIGHLIGHT",
                        duration: "",
                        title: "\(match.team1.name) vs \(match.team2.name)",
                        meta: tournament.name,
                        imageName: "HeroStadiumNight",
                        category: .all,
                        minutesLabel: "",
                        videoURL: videoURL,
                        matchId: match.matchId,
                        tournamentId: tournament.tournamentId,
                        homeTeam: match.team1.name,
                        awayTeam: match.team2.name,
                        homeCode: homeCode,
                        awayCode: awayCode,
                        matchSeq: match.matchSeq,
                        resultLine: result
                    )
                )
            }

            guard !clips.isEmpty else { continue }
            rails.append(TournamentHighlightRail(id: tile.id, name: tile.title, clips: clips))
        }

        return rails
    }

    func loadCachedIfNeeded() {
        guard featuredMatches.isEmpty, scheduleMatches.isEmpty else { return }
        guard let data = FeedCache.loadData() else { return }
        guard let feed = try? JSONDecoder().decode(FirebaseOTTFeed.self, from: data) else { return }
        cachedFeed = feed
        ingest(feed: feed, source: "Cache", updatedAt: FeedCache.modifiedAt())
    }

    func refresh(force: Bool = false, silent: Bool = false) async {
        if !force,
           let lastRefreshAt,
           Date().timeIntervalSince(lastRefreshAt) < 25,
           !featuredMatches.isEmpty || !scheduleMatches.isEmpty {
            return
        }

        let hadData = !featuredMatches.isEmpty || !scheduleMatches.isEmpty
        if !silent {
            isLoading = true
            if !hadData {
                errorMessage = nil
            }
        }
        defer {
            if !silent {
                isLoading = false
            }
        }

        do {
            let (feed, data) = try await FirebaseOTTClient.fetchFeedWithData()
            FeedCache.save(data)
            cachedFeed = feed
            ingest(feed: feed, source: silent ? "Firebase Live" : "Firebase", updatedAt: Date())
            lastRefreshAt = Date()
        } catch is CancellationError {
            return
        } catch {
            if !hadData && tournaments.isEmpty && featuredMatches.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func ingest(feed: FirebaseOTTFeed, source: String, updatedAt: Date? = nil) {
        applyAdsSetting(from: feed)
        let apiTournaments = FirebaseOTTClient.toAPITournaments(feed)
        if apiTournaments.isEmpty {
            tournaments = []
            featuredMatches = []
            scheduleMatches = []
            tournamentCards = []
            highlightClips = []
            shortClips = []
            if source != "Cache" {
                errorMessage = "Matches couldn’t be loaded. Pull down to retry."
            }
            return
        }

        let cleaned = Self.sanitize(apiTournaments)
        if cleaned.isEmpty {
            tournaments = []
            featuredMatches = []
            scheduleMatches = []
            tournamentCards = []
            if source != "Cache" {
                errorMessage = "No tournaments to show yet. Pull down to retry."
            }
            return
        }

        var enriched = cleaned
        Self.mergeHighlightURLs(feed: feed, tournaments: &enriched)
        tournaments = enriched
        let slides = apply(enriched)
        if source == "Firebase Live", !featuredMatches.isEmpty {
            featuredMatches = mergeFeaturedPreservingOrder(old: featuredMatches, new: slides)
        } else {
            featuredMatches = slides
        }
        dataSource = source
        lastUpdated = updatedAt ?? Date()
        errorMessage = nil

        let slidesForPreload = slides
        Task {
            await HeroFrameCache.shared.preload(matches: slidesForPreload)
        }

        highlightClips = FirebaseOTTClient.toAPIHighlights(feed)
            .map(Self.mapHighlight)
            .map { Self.enrichHighlight($0, tournaments: tournaments) }
        shortClips = FirebaseOTTClient.toShortClips(feed)
        updateLiveFeedPolling()
        updateLiveScorePolling()
    }

    private func updateLiveScorePolling() {
        var seen = Set<String>()
        var targets: [CrickAPILiveScorePoller.Target] = []
        for match in scheduleMatches where match.status == .live {
            guard seen.insert(match.id).inserted else { continue }
            targets.append(CrickAPILiveScorePoller.Target(id: match.id, matchSeq: match.matchSeq))
        }
        for match in featuredMatches where match.isLive {
            guard seen.insert(match.id).inserted else { continue }
            targets.append(CrickAPILiveScorePoller.Target(id: match.id, matchSeq: match.matchSeq))
        }
        guard !targets.isEmpty else {
            liveScorePoller.stop()
            liveScoreSignatures = [:]
            return
        }
        liveScorePoller.start(matches: targets) { [weak self] matchId, api in
            self?.patchLiveScores(matchId: matchId, from: api)
        }
    }

    /// Call after Firebase bootstrap + first feed load so meta listener + live scores start.
    func ensureLiveUpdatesRunning() {
        updateLiveFeedPolling()
        updateLiveScorePolling()
    }

    private func patchLiveScores(matchId: String, from api: APICompleteMatch) {
        let mapped = MatchDetailMapper.map(api)
        let signature = "\(mapped.scoreLabel)|\(mapped.status)|\(api.ballByBall.count)"
        if liveScoreSignatures[matchId] == signature { return }
        liveScoreSignatures[matchId] = signature

        let statusLine = api.matchInfo.result?.summaryText ?? mapped.scoreLabel
        let teamScores = inningsScoresFromDetail(mapped)

        if let idx = featuredMatches.firstIndex(where: { $0.id == matchId }) {
            var match = featuredMatches[idx]
            if !mapped.scoreLabel.isEmpty { match.scoreLabel = mapped.scoreLabel }
            if !statusLine.isEmpty { match.statusLine = statusLine }
            if let home = teamScores.home { match.homeInningsScore = home }
            if let away = teamScores.away { match.awayInningsScore = away }
            featuredMatches[idx] = match
        }

        if let idx = scheduleMatches.firstIndex(where: { $0.id == matchId }) {
            var row = scheduleMatches[idx]
            if !mapped.scoreLabel.isEmpty { row.scoreLabel = mapped.scoreLabel }
            scheduleMatches[idx] = row
        }
    }

    private func inningsScoresFromDetail(_ detail: MatchDetail) -> (home: String?, away: String?) {
        var home: String?
        var away: String?
        let homeShort = detail.homeShort.lowercased()
        let awayShort = detail.awayShort.lowercased()
        let homeName = detail.homeName.lowercased()
        let awayName = detail.awayName.lowercased()

        for inn in detail.innings {
            let short = inn.teamShort.lowercased()
            let name = inn.teamName.lowercased()
            if short == homeShort || name == homeName {
                home = inn.summaryLabel
            } else if short == awayShort || name == awayName {
                away = inn.summaryLabel
            }
        }
        if home == nil, let first = detail.innings.first { home = first.summaryLabel }
        if away == nil, detail.innings.count > 1 { away = detail.innings[1].summaryLabel }
        return (home, away)
    }

    private func updateLiveFeedPolling() {
        #if canImport(FirebaseCore)
        guard FirebaseApp.app() != nil else { return }
        #endif
        guard !liveMatches.isEmpty else {
            metaListener.stop()
            return
        }
        guard !metaListener.isRunning else { return }
        metaListener.start { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if let last = self.lastSilentRefreshAt,
                   Date().timeIntervalSince(last) < 4 {
                    return
                }
                self.lastSilentRefreshAt = Date()
                await self.refresh(force: true, silent: true)
            }
        }
    }

    /// Silent refresh par hero carousel order / page reset na ho.
    private func mergeFeaturedPreservingOrder(old: [FeaturedMatch], new: [FeaturedMatch]) -> [FeaturedMatch] {
        guard !old.isEmpty else { return new }
        let newById = Dictionary(uniqueKeysWithValues: new.map { ($0.id, $0) })
        let merged = old.compactMap { newById[$0.id] }
        if merged.isEmpty { return new }
        let oldIds = Set(old.map(\.id))
        let appended = new.filter { !oldIds.contains($0.id) }
        return merged + appended
    }

    private func applyAdsSetting(from feed: FirebaseOTTFeed) {
        let enabled = feed.settings?.adsEnabled != false
        adsEnabled = enabled
        AdMobService.shared.isAdsAllowed = enabled
    }

    private static func enrichHighlight(_ clip: HighlightClip, tournaments: [APITournament]) -> HighlightClip {
        guard let matchId = clip.matchId else { return clip }
        for tournament in tournaments {
            guard let match = tournament.matches.first(where: { $0.matchId == matchId }) else { continue }
            let result = match.result?.summaryText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return HighlightClip(
                id: clip.id,
                tag: clip.tag,
                duration: clip.duration,
                title: clip.title,
                meta: clip.meta.isEmpty ? tournament.name : clip.meta,
                imageName: clip.imageName,
                category: clip.category,
                minutesLabel: clip.minutesLabel,
                videoURL: clip.videoURL,
                matchId: clip.matchId,
                tournamentId: clip.tournamentId ?? tournament.tournamentId,
                homeTeam: match.team1.name,
                awayTeam: match.team2.name,
                homeCode: teamCode(match.team1.shortName, name: match.team1.name),
                awayCode: teamCode(match.team2.shortName, name: match.team2.name),
                matchSeq: match.matchSeq,
                resultLine: result
            )
        }
        return clip
    }

    private static func teamCode(_ short: String?, name: String) -> String {
        let trimmed = short?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty { return trimmed }
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return parts.map { String($0.prefix(1)) }.joined().uppercased()
        }
        return String(name.prefix(3)).uppercased()
    }

    private static func mapHighlight(_ h: APIHighlight) -> HighlightClip {
        let category: HighlightCategory = {
            switch h.type.lowercased() {
            case "sixes": return .boundaries
            case "wicket", "wicket_bowler": return .wickets
            case "catch": return .catches
            default: return .all
            }
        }()
        let title = h.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let matchId = Self.highlightMatchId(from: h.id, explicit: h.matchId)
        return HighlightClip(
            id: h.id,
            tag: h.type.replacingOccurrences(of: "_", with: " ").uppercased(),
            duration: "",
            title: (title?.isEmpty == false ? title! : (h.tournamentName ?? "Match Highlight")),
            meta: h.tournamentName ?? h.playerName ?? "",
            imageName: "HeroStadiumNight",
            category: category,
            minutesLabel: "",
            videoURL: CrickAPI.absoluteURL(from: h.url),
            matchId: matchId,
            tournamentId: h.tournamentId
        )
    }

    private static func highlightMatchId(from id: String, explicit: String?) -> String? {
        if let explicit, !explicit.isEmpty { return explicit }
        let prefix = "hl-match-"
        if id.hasPrefix(prefix) {
            let matchId = String(id.dropFirst(prefix.count))
            return matchId.isEmpty ? nil : matchId
        }
        return nil
    }

    private static func mergeHighlightURLs(feed: FirebaseOTTFeed, tournaments: inout [APITournament]) {
        guard let highlights = feed.highlights else { return }
        var urlsByMatchId: [String: String] = [:]
        for (key, highlight) in highlights {
            guard highlight.fromAdmin == true else { continue }
            let url = highlight.url?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !url.isEmpty else { continue }
            guard let matchId = highlightMatchId(from: highlight.id ?? key, explicit: nil) else { continue }
            urlsByMatchId[matchId] = url
        }
        guard !urlsByMatchId.isEmpty else { return }

        tournaments = tournaments.map { tournament in
            var updated = tournament
            updated.matches = tournament.matches.map { match in
                var copy = match
                guard let url = urlsByMatchId[match.matchId] else { return copy }
                let existing = copy.highlightUrl?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if existing.isEmpty {
                    copy.highlightUrl = url
                }
                return copy
            }
            return updated
        }
    }

    /// Drop empty/test tournaments and duplicate JW-vs-URF style repeats.
    private static func sanitize(_ input: [APITournament]) -> [APITournament] {
        let junkNames: Set<String> = ["balls", "test", "dummy", "demo"]
        return input.compactMap { tournament in
            let name = tournament.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let type = (tournament.type ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if tournament.tournamentId == "demo-jbmr" { return nil }
            if name.isEmpty || junkNames.contains(name.lowercased()) { return nil }
            if type == "balls" { return nil }

            var seen = Set<String>()
            let matches = tournament.matches.filter { match in
                if Self.isTestTeam(match.team1) || Self.isTestTeam(match.team2) { return false }
                let t1 = match.team1.name.trimmingCharacters(in: .whitespacesAndNewlines)
                let t2 = match.team2.name.trimmingCharacters(in: .whitespacesAndNewlines)
                if t1.isEmpty || t2.isEmpty { return false }
                let status = normalizedStatus(match.status)
                let key = "\(t1.lowercased())|\(t2.lowercased())|\(status)"
                if seen.contains(key) { return false }
                seen.insert(key)
                return true
            }
            guard !matches.isEmpty else { return nil }
            return APITournament(
                tournamentId: tournament.tournamentId,
                name: tournament.name,
                logoUrl: tournament.logoUrl,
                location: tournament.location,
                startDate: tournament.startDate,
                endDate: tournament.endDate,
                type: tournament.type,
                format: tournament.format,
                matches: matches
            )
        }
    }

    private static let testTeamTokens: Set<String> = [
        "jw", "urf", "ace"
    ]

    private static func isTestTeam(_ team: APITeam) -> Bool {
        let name = team.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let short = (team.shortName ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return testTeamTokens.contains(name) || testTeamTokens.contains(short)
    }

    private static func normalizedStatus(_ status: String) -> String {
        switch status.lowercased() {
        case "live": return "live"
        case "completed", "finished": return "completed"
        default: return "upcoming"
        }
    }

    private func apply(_ apiTournaments: [APITournament]) -> [FeaturedMatch] {
        var featured: [FeaturedMatch] = []
        var schedule: [ScheduleMatch] = []
        var dayKeys = Set<String>()

        for tournament in apiTournaments {
            for match in tournament.matches {
                featured.append(MatchMapper.featured(match: match, tournament: tournament))
                let scheduleItem = MatchMapper.schedule(match: match, tournament: tournament)
                schedule.append(scheduleItem)
                dayKeys.insert(scheduleItem.dayKey)
            }
        }

        featured.sort { a, b in
            let rank: (FeaturedMatch) -> Int = {
                switch $0.heroState {
                case .live: return 0
                case .upcoming: return 1
                case .completed: return 2
                }
            }
            let ra = rank(a), rb = rank(b)
            if ra != rb { return ra < rb }
            return a.timeLabel < b.timeLabel
        }

        schedule.sort { ($0.scheduledAt ?? .distantPast) > ($1.scheduledAt ?? .distantPast) }

        var scheduleSeen = Set<String>()
        let uniqueSchedule = schedule.filter { item in
            let key = "\(item.homeName.lowercased())|\(item.awayName.lowercased())|\(item.status)"
            if scheduleSeen.contains(key) { return false }
            scheduleSeen.insert(key)
            return true
        }

        let live = uniqueFeatured(featured.filter { $0.heroState == .live })
        let upcoming = uniqueFeatured(featured.filter { $0.heroState == .upcoming })
        let highlightSlides = uniqueFeatured(featured.filter(\.isMatchHighlightSlide))
        scheduleMatches = uniqueSchedule
        scheduleDates = dayKeys.sorted()
        tournamentCards = apiTournaments.map {
            LeagueTile(
                id: $0.tournamentId,
                title: $0.name,
                imageName: "LeagueIPL",
                duration: $0.type ?? "T20",
                imageURL: CrickAPI.absoluteURL(from: $0.logoUrl)
            )
        }
        var slides: [FeaturedMatch] = []
        var seen = Set<String>()
        for item in live + Array(upcoming.prefix(3)) + highlightSlides {
            guard seen.insert(item.id).inserted else { continue }
            slides.append(item)
            if slides.count >= 6 { break }
        }
        return slides
    }

    private func uniqueFeatured(_ matches: [FeaturedMatch]) -> [FeaturedMatch] {
        var seen = Set<String>()
        return matches.filter { match in
            let stateKey = match.isMatchHighlightSlide ? "highlight" : String(describing: match.heroState)
            let key = "\(match.home.lowercased())|\(match.away.lowercased())|\(stateKey)"
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }
    }

    func pointsTable(forMatchId matchId: String) -> [PointsTableRow] {
        guard let seed = scheduleMatches.first(where: { $0.id == matchId }) else { return [] }
        let tournamentMatches = scheduleMatches.filter { $0.tournament == seed.tournament }
        return Self.computePointsTable(from: tournamentMatches)
    }

    static func computePointsTable(from matches: [ScheduleMatch]) -> [PointsTableRow] {
        var map: [String: (name: String, code: String, played: Int, won: Int, lost: Int)] = [:]
        for m in matches where m.status == .completed {
            for (name, code) in [(m.homeName, m.homeCode), (m.awayName, m.awayCode)] {
                var entry = map[name] ?? (name, code, 0, 0, 0)
                entry.played += 1
                map[name] = entry
            }
            if let summary = m.resultSummary?.lowercased() {
                for key in map.keys {
                    let code = map[key]!.code.lowercased()
                    if summary.contains(key.lowercased())
                        || summary.hasPrefix("\(code) ")
                        || summary.contains("\(code) won") {
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
}

enum MatchMapper {
    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_IN")
        f.dateFormat = "h:mm a"
        return f
    }()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_IN")
        f.dateFormat = "EEE d MMM"
        return f
    }()

    static func parseDate(_ string: String?) -> Date? {
        guard let string else { return nil }
        return isoFractional.date(from: string) ?? iso.date(from: string)
    }

    static func featured(match: APIMatch, tournament: APITournament) -> FeaturedMatch {
        let scheduled = parseDate(match.scheduledAt)
        let year = yearString(from: tournament.startDate) ?? "2026"
        let status = match.status.lowercased()
        let isLive = status == "live" || status == "in progress" || status == "inprogress"
        let isCompleted = status == "completed" || status == "finished"

        let score = scoreLine(from: match.innings)
        let statusLine: String = {
            if let summary = match.result?.summaryText, !summary.isEmpty { return summary }
            if !score.isEmpty { return score }
            if let venue = match.venue { return venue }
            return tournament.location ?? ""
        }()

        let timeLabel: String = {
            if isLive { return "Live Now" }
            if isCompleted { return match.result?.summaryText ?? "Completed" }
            guard let scheduled else { return match.stage ?? "Upcoming" }
            return "\(dayKey(for: scheduled)), \(timeFormatter.string(from: scheduled))"
        }()

        let badge: String = {
            if isLive { return "LIVE MATCH" }
            if isCompleted { return "RESULT" }
            return "UPCOMING"
        }()

        let imageURL = CrickAPI.absoluteURL(from: match.thumbnailUrl)
        let teamScores = inningsScores(match: match)
        let highlightURL = CrickAPI.absoluteURL(from: match.highlightUrl)
        let hasHighlight = !(match.highlightUrl ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && highlightURL != nil
        let isHighlightSlide = isCompleted && hasHighlight

        return FeaturedMatch(
            id: match.matchId,
            league: tournament.name,
            year: year,
            home: match.team1.name,
            away: match.team2.name,
            timeLabel: timeLabel,
            imageName: isLive ? "LiveCricket" : "HeroMatch",
            isLive: isLive,
            badge: isHighlightSlide ? "MATCH HIGHLIGHT" : badge,
            subtitle: match.stage ?? tournament.type ?? "",
            durationLabel: tournament.type ?? "T20",
            statusLine: statusLine,
            videoURL: CrickAPI.absoluteURL(from: match.liveUrl) ?? highlightURL,
            homeShort: match.team1.shortName ?? "",
            awayShort: match.team2.shortName ?? "",
            imageURL: imageURL,
            homeLogoURL: CrickAPI.absoluteURL(from: match.team1.logoUrl),
            awayLogoURL: CrickAPI.absoluteURL(from: match.team2.logoUrl),
            homeThemeColor: match.team1.themeColor,
            awayThemeColor: match.team2.themeColor,
            tournamentLogoURL: CrickAPI.absoluteURL(from: tournament.logoUrl),
            scoreLabel: score.isEmpty ? (isLive ? "LIVE" : "") : score,
            homeInningsScore: teamScores.0,
            awayInningsScore: teamScores.1,
            matchSeq: match.matchSeq,
            isMatchHighlightSlide: isHighlightSlide
        )
    }

    static func schedule(match: APIMatch, tournament: APITournament) -> ScheduleMatch {
        let scheduled = parseDate(match.scheduledAt)
        let status: ScheduleMatch.Status = {
            switch match.status.lowercased() {
            case "live": return .live
            case "completed", "finished": return .completed
            default: return .upcoming
            }
        }()

        let timeLabel: String = {
            if status == .live { return "LIVE" }
            if status == .completed { return match.result?.summaryText ?? "Completed" }
            guard let scheduled else { return "TBD" }
            let key = dayKey(for: scheduled)
            if key == "Today" || key == "Tomorrow" {
                return "\(key) • \(timeFormatter.string(from: scheduled))"
            }
            return "\(dayFormatter.string(from: scheduled)) • \(timeFormatter.string(from: scheduled))"
        }()

        let day: String = {
            if status == .live { return "Live" }
            guard let scheduled else { return "Upcoming" }
            return dayKey(for: scheduled)
        }()

        let teamScores = inningsScores(match: match)

        return ScheduleMatch(
            id: match.matchId,
            tournament: tournament.name,
            homeCode: match.team1.shortName ?? String(match.team1.name.prefix(3)).uppercased(),
            awayCode: match.team2.shortName ?? String(match.team2.name.prefix(3)).uppercased(),
            homeName: match.team1.name,
            awayName: match.team2.name,
            timeLabel: timeLabel,
            venue: match.venue ?? tournament.location ?? "",
            status: status,
            sport: .cricket,
            dayKey: day,
            scheduledAt: scheduled,
            homeLogoURL: CrickAPI.absoluteURL(from: match.team1.logoUrl),
            awayLogoURL: CrickAPI.absoluteURL(from: match.team2.logoUrl),
            tournamentLogoURL: CrickAPI.absoluteURL(from: tournament.logoUrl),
            thumbnailURL: CrickAPI.absoluteURL(from: match.thumbnailUrl),
            scoreLabel: scoreLine(from: match.innings),
            resultSummary: match.result?.summaryText,
            matchSeq: match.matchSeq,
            matchLabel: match.stage ?? "Match",
            watchAtTime: scheduled.map { timeFormatter.string(from: $0) } ?? "",
            homeStatus: teamScores.0,
            awayStatus: teamScores.1
        )
    }

    private static func inningsScores(match: APIMatch) -> (String, String) {
        let t1 = match.team1.name.lowercased()
        let t2 = match.team2.name.lowercased()
        let s1 = (match.team1.shortName ?? "").lowercased()
        let s2 = (match.team2.shortName ?? "").lowercased()
        var home = ""
        var away = ""
        for inn in match.innings.sorted(by: { ($0.inningsNumber ?? 0) < ($1.inningsNumber ?? 0) }) {
            let line = compactInningsScore(inn)
            guard !line.isEmpty else { continue }
            let n = (inn.teamName ?? "").lowercased()
            let s = (inn.teamShortName ?? "").lowercased()
            if (!s1.isEmpty && (s == s1 || n.contains(s1))) || n == t1 || n.contains(t1) {
                home = line
            } else if (!s2.isEmpty && (s == s2 || n.contains(s2))) || n == t2 || n.contains(t2) {
                away = line
            } else if home.isEmpty {
                home = line
            } else {
                away = line
            }
        }
        return (home, away)
    }

    private static func compactInningsScore(_ inn: APIInnings) -> String {
        guard inn.runs != nil || inn.wickets != nil else { return "" }
        let runs = inn.runs ?? 0
        let wickets = inn.wickets ?? 0
        let overs = inn.overs ?? 0
        let oversText: String = {
            if overs == 0 { return "\(runs)/\(wickets)" }
            return "\(runs)/\(wickets) (\(CricketOvers.format(overs)))"
        }()
        return oversText
    }

    private static func scoreLine(from innings: [APIInnings]) -> String {
        guard let last = innings.sorted(by: { ($0.inningsNumber ?? 0) < ($1.inningsNumber ?? 0) }).last else {
            return ""
        }
        let team = last.teamShortName ?? last.teamName ?? ""
        let runs = last.runs ?? 0
        let wickets = last.wickets ?? 0
        let overs = last.overs ?? 0
        let oversText = CricketOvers.format(overs)
        return "\(team) \(runs)/\(wickets) (\(oversText) Ov)"
    }

    private static func yearString(from startDate: String?) -> String? {
        guard let date = parseDate(startDate) else { return nil }
        let y = Calendar.current.component(.year, from: date)
        return String(y)
    }

    private static func dayKey(for date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInTomorrow(date) { return "Tomorrow" }
        return dayFormatter.string(from: date)
    }
}
