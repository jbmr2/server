import Foundation

enum FirebaseOTT {
    static let feedURL = URL(string: "https://ncrplt20-1c022-default-rtdb.asia-southeast1.firebasedatabase.app/ott.json")!
}

struct FirebaseOTTFeed: Decodable {
    let meta: Meta?
    let tournaments: [String: FirebaseTournament]?
    let highlights: [String: FirebaseHighlight]?

    struct Meta: Decodable {
        let source: String?
        let updatedAt: String?
        let note: String?
    }
}

struct FirebaseTournament: Decodable {
    let tournamentId: String?
    let name: String?
    let logoUrl: String?
    let location: String?
    let startDate: String?
    let endDate: String?
    let type: String?
    let format: String?
    let showOnOtt: Bool?
    let matches: [String: FirebaseMatch]?
}

struct FirebaseMatch: Decodable {
    let matchId: String?
    let matchSeq: Int?
    let stage: String?
    let venue: String?
    let scheduledAt: String?
    let status: String?
    let thumbnailUrl: String?
    let title: String?
    let liveUrl: String?
    let highlightUrl: String?
    let team1: FirebaseTeam?
    let team2: FirebaseTeam?
    let result: FirebaseResult?
    let innings: [FirebaseInnings]?
    let balls: [String: FirebaseBall]?
}

struct FirebaseBall: Decodable {
    let id: String?
    let innings: Int?
    let over: Int?
    let ball: Int?
    let runs: Int?
    let isWicket: Bool?
    let note: String?
    let videoUrl: String?
    let sortKey: Int?
}

struct FirebaseTeam: Decodable {
    let name: String?
    let shortName: String?
    let logoUrl: String?
    let themeColor: String?
}

struct FirebaseResult: Decodable {
    let summaryText: String?
    let winnerShortName: String?
}

struct FirebaseInnings: Decodable {
    let inningsNumber: Int?
    let teamName: String?
    let teamShortName: String?
    let runs: Int?
    let wickets: Int?
    let overs: Double?
}

struct FirebaseHighlight: Decodable {
    let id: String?
    let type: String?
    let url: String?
    let title: String?
    let description: String?
    let tournamentId: String?
    let tournamentName: String?
    let sortOrder: Int?
    let fromAdmin: Bool?
}

enum FirebaseOTTClient {
    static func fetchFeed() async throws -> FirebaseOTTFeed {
        var req = URLRequest(url: FirebaseOTT.feedURL)
        req.timeoutInterval = 25
        req.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        guard !data.isEmpty, data != Data("null".utf8) else {
            throw URLError(.cannotDecodeContentData)
        }
        return try JSONDecoder().decode(FirebaseOTTFeed.self, from: data)
    }

    static func fetchCompleteMatch(matchId: String) async throws -> APICompleteMatch? {
        guard !matchId.isEmpty,
              let url = URL(string: "https://ncrplt20-1c022-default-rtdb.asia-southeast1.firebasedatabase.app/ott/matchDetails/\(matchId).json")
        else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 25
        req.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        guard !data.isEmpty, data != Data("null".utf8) else { return nil }
        do {
            return try JSONDecoder().decode(APICompleteMatch.self, from: data)
        } catch {
            return nil
        }
    }

    static func findMatch(matchId: String, in feed: FirebaseOTTFeed) -> (FirebaseTournament, FirebaseMatch)? {
        for t in (feed.tournaments ?? [:]).values {
            if let m = t.matches?[matchId] { return (t, m) }
            if let m = (t.matches ?? [:]).values.first(where: { $0.matchId == matchId }) {
                return (t, m)
            }
        }
        return nil
    }

    static func toAPITournaments(_ feed: FirebaseOTTFeed) -> [APITournament] {
        var result: [APITournament] = []
        let tournaments = (feed.tournaments ?? [:]).values
            .filter { $0.showOnOtt != false }
            .filter { ($0.tournamentId ?? "") != "demo-jbmr" }
            .sorted { ($0.name ?? "") < ($1.name ?? "") }
        for t in tournaments {
            let matches = mapMatches(t.matches)
            result.append(
                APITournament(
                    tournamentId: t.tournamentId ?? UUID().uuidString,
                    name: t.name ?? "Tournament",
                    logoUrl: t.logoUrl,
                    location: t.location,
                    startDate: t.startDate,
                    endDate: t.endDate,
                    type: t.type,
                    format: t.format,
                    matches: matches
                )
            )
        }
        return result
    }

    private static func mapMatches(_ matches: [String: FirebaseMatch]?) -> [APIMatch] {
        let list = (matches ?? [:]).values.sorted { ($0.matchSeq ?? 0) < ($1.matchSeq ?? 0) }
        return list.map { m in
            let result: APIMatchResult? = {
                guard let r = m.result else { return nil }
                return APIMatchResult(
                    winnerName: nil,
                    winnerShortName: r.winnerShortName,
                    resultType: nil,
                    margin: nil,
                    summaryText: r.summaryText
                )
            }()
            let innings: [APIInnings] = (m.innings ?? []).map { inn in
                APIInnings(
                    inningsNumber: inn.inningsNumber,
                    teamName: inn.teamName,
                    teamShortName: inn.teamShortName,
                    runs: inn.runs,
                    wickets: inn.wickets,
                    overs: inn.overs
                )
            }
            return APIMatch(
                matchId: m.matchId ?? UUID().uuidString,
                matchSeq: m.matchSeq,
                stage: m.stage,
                group: nil,
                team1: APITeam(
                    name: m.team1?.name ?? "TBD",
                    shortName: m.team1?.shortName,
                    logoUrl: m.team1?.logoUrl,
                    themeColor: m.team1?.themeColor
                ),
                team2: APITeam(
                    name: m.team2?.name ?? "TBD",
                    shortName: m.team2?.shortName,
                    logoUrl: m.team2?.logoUrl,
                    themeColor: m.team2?.themeColor
                ),
                venue: m.venue,
                scheduledAt: m.scheduledAt,
                startedAt: nil,
                endedAt: nil,
                status: m.status ?? "scheduled",
                thumbnailUrl: m.thumbnailUrl,
                result: result,
                innings: innings,
                liveUrl: m.liveUrl,
                highlightUrl: m.highlightUrl
            )
        }
    }

    static func toAPIHighlights(_ feed: FirebaseOTTFeed) -> [APIHighlight] {
        (feed.highlights ?? [:]).values
            .filter { highlight in
                guard highlight.fromAdmin == true else { return false }
                let url = highlight.url ?? ""
                if url.isEmpty { return false }
                if url.contains("dQw4w9WgXcQ") { return false }
                if (highlight.tournamentId ?? "") == "demo-jbmr" { return false }
                return true
            }
            .sorted { ($0.sortOrder ?? 0) < ($1.sortOrder ?? 0) }
            .map {
                APIHighlight(
                    id: $0.id ?? UUID().uuidString,
                    type: $0.type ?? "match_highlight",
                    url: $0.url ?? "",
                    title: $0.title,
                    description: $0.description,
                    matchId: parseHighlightMatchId(id: $0.id ?? ""),
                    tournamentId: $0.tournamentId,
                    tournamentName: $0.tournamentName,
                    playerId: nil,
                    playerName: nil,
                    sortOrder: $0.sortOrder,
                    createdAt: nil
                )
            }
    }

    private static func parseHighlightMatchId(id: String) -> String? {
        let prefix = "hl-match-"
        guard id.hasPrefix(prefix) else { return nil }
        let matchId = String(id.dropFirst(prefix.count))
        return matchId.isEmpty ? nil : matchId
    }

    static func toShortClips(_ feed: FirebaseOTTFeed) -> [ShortClip] {
        var clips: [ShortClip] = []
        for t in (feed.tournaments ?? [:]).values where t.showOnOtt != false {
            let tName = t.name ?? "Tournament"
            for m in (t.matches ?? [:]).values {
                let home = m.team1?.shortName ?? m.team1?.name ?? "T1"
                let away = m.team2?.shortName ?? m.team2?.name ?? "T2"
                let vs = "\(home) vs \(away)"
                let tag = "From: \(vs) • \(tName)"
                let balls = (m.balls ?? [:]).values.sorted {
                    let a = ($0.innings ?? 0) * 10000 + ($0.over ?? 0) * 10 + ($0.ball ?? 0)
                    let b = ($1.innings ?? 0) * 10000 + ($1.over ?? 0) * 10 + ($1.ball ?? 0)
                    return a < b
                }
                let minOver = balls.compactMap(\.over).min() ?? 0
                for b in balls {
                    guard let raw = b.videoUrl, let url = CrickAPI.absoluteURL(from: raw) else { continue }
                    let over = CricketOvers.ballLabel(
                        overNumber: b.over ?? 0,
                        ballNumber: b.ball ?? 1,
                        minOverInInnings: minOver
                    )
                    let caption: String = {
                        if let note = b.note, !note.isEmpty { return note }
                        if b.isWicket == true { return "Wicket · Over \(over)" }
                        return "Over \(over) · \(b.runs ?? 0) run"
                    }()
                    clips.append(
                        ShortClip(
                            id: "\(m.matchId ?? "m")-\(b.id ?? over)-\(clips.count)",
                            creator: "@jbmr_sports",
                            caption: caption,
                            matchTag: tag,
                            audio: "Match audio",
                            likes: "",
                            comments: "",
                            shares: "",
                            imageName: "HeroStadiumNight",
                            isVerified: true,
                            videoURL: url
                        )
                    )
                }
            }
        }
        return clips
    }

    static func toCompleteMatch(tournament: FirebaseTournament, match: FirebaseMatch) -> APICompleteMatch {
        let team1Name = match.team1?.name ?? "Team A"
        let team2Name = match.team2?.name ?? "Team B"
        let ballEvents = mapBalls(match.balls, striker: team1Name, nonStriker: team2Name)
        let inningsList = mapInnings(match.innings, completed: match.status == "completed")
        let info = mapInfo(tournament: tournament, match: match, team1Name: team1Name, team2Name: team2Name)
        return APICompleteMatch(
            matchInfo: info,
            innings: inningsList,
            battingStats: [],
            bowlingStats: [],
            scoreboard: nil,
            fallOfWickets: nil,
            ballByBall: ballEvents
        )
    }

    private static func mapBalls(
        _ balls: [String: FirebaseBall]?,
        striker: String,
        nonStriker: String
    ) -> [APIBallEvent] {
        let entries = (balls ?? [:]).sorted { lhs, rhs in
            let a = (lhs.value.innings ?? 0) * 10000 + (lhs.value.over ?? 0) * 10 + (lhs.value.ball ?? 0)
            let b = (rhs.value.innings ?? 0) * 10000 + (rhs.value.over ?? 0) * 10 + (rhs.value.ball ?? 0)
            return a < b
        }
        return entries.map { key, b in
            APIBallEvent.firebase(
                id: b.id ?? key,
                innings: b.innings,
                over: b.over,
                ball: b.ball,
                runs: b.runs,
                isWicket: b.isWicket ?? false,
                note: b.note,
                videoUrl: b.videoUrl,
                strikerName: striker,
                nonStrikerName: nonStriker
            )
        }
    }

    private static func mapInnings(_ innings: [FirebaseInnings]?, completed: Bool) -> [APICompleteInnings] {
        (innings ?? []).map { inn in
            APICompleteInnings(
                id: "inn-\(inn.inningsNumber ?? 0)",
                number: inn.inningsNumber,
                runs: inn.runs,
                wickets: inn.wickets,
                overs: inn.overs,
                target: nil,
                isCompleted: completed,
                battingTeamName: inn.teamName,
                battingTeamShortName: inn.teamShortName,
                battingTeam: nil
            )
        }
    }

    private static func mapInfo(
        tournament: FirebaseTournament,
        match: FirebaseMatch,
        team1Name: String,
        team2Name: String
    ) -> APICompleteMatchInfo {
        let result: APIMatchResult? = match.result.map {
            APIMatchResult(
                winnerName: nil,
                winnerShortName: $0.winnerShortName,
                resultType: nil,
                margin: nil,
                summaryText: $0.summaryText
            )
        }
        return APICompleteMatchInfo(
            id: match.matchId ?? "unknown",
            matchSeq: match.matchSeq,
            tournament: APICompleteTournament(
                id: tournament.tournamentId,
                name: tournament.name,
                logoUrl: tournament.logoUrl,
                location: tournament.location,
                ground: match.venue,
                type: tournament.type
            ),
            team1: APICompleteTeam(
                id: nil,
                name: team1Name,
                shortName: match.team1?.shortName,
                logoUrl: match.team1?.logoUrl,
                themeColor: nil
            ),
            team2: APICompleteTeam(
                id: nil,
                name: team2Name,
                shortName: match.team2?.shortName,
                logoUrl: match.team2?.logoUrl,
                themeColor: nil
            ),
            tossWinner: nil,
            tossDecision: nil,
            firstBattingTeam: nil,
            venue: match.venue,
            status: match.status ?? "scheduled",
            scheduledAt: match.scheduledAt,
            startedAt: nil,
            endedAt: nil,
            overs: 20,
            result: result
        )
    }
}
