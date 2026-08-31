import Foundation

enum CrickAPI {
    static let baseURL = URL(string: "https://crickdbmodule-api-144271912366.asia-south1.run.app")!
    static let mediaBaseURL = URL(string: "https://storage.googleapis.com/crickbuck")!

    static func absoluteURL(from path: String?) -> URL? {
        guard var raw = path?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        if raw.hasPrefix("//") {
            raw = "https:" + raw
        }
        if let url = httpURL(raw) {
            return url
        }
        let relative = raw.hasPrefix("/") ? String(raw.dropFirst()) : raw
        let encoded = relative.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? relative
        if encoded.hasPrefix("uploads/") {
            let rest = String(encoded.dropFirst("uploads/".count))
            if let gcs = URL(string: "https://storage.googleapis.com/crickbuck/\(rest)") {
                return gcs
            }
        }
        return URL(string: encoded, relativeTo: mediaBaseURL.appendingPathComponent(""))?.absoluteURL
            ?? URL(string: encoded, relativeTo: baseURL.appendingPathComponent(""))?.absoluteURL
    }

    private static func httpURL(_ raw: String) -> URL? {
        if let url = URL(string: raw), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            return url
        }
        if let encoded = raw.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed),
           let url = URL(string: encoded),
           let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            return url
        }
        return nil
    }
}

struct PublicTournamentsResponse: Decodable {
    let at: String?
    let count: Int?
    let tournaments: [APITournament]
}

struct APITournament: Decodable, Identifiable {
    let tournamentId: String
    let name: String
    let logoUrl: String?
    let location: String?
    let startDate: String?
    let endDate: String?
    let type: String?
    let format: String?
    var matches: [APIMatch]

    var id: String { tournamentId }
}

struct APIMatch: Decodable, Identifiable {
    let matchId: String
    let matchSeq: Int?
    let stage: String?
    let group: String?
    let team1: APITeam
    let team2: APITeam
    let venue: String?
    let scheduledAt: String?
    let startedAt: String?
    let endedAt: String?
    let status: String
    let thumbnailUrl: String?
    let result: APIMatchResult?
    let innings: [APIInnings]
    var liveUrl: String? = nil
    var highlightUrl: String? = nil

    var id: String { matchId }

    enum CodingKeys: String, CodingKey {
        case matchId, matchSeq, stage, group, team1, team2, venue
        case scheduledAt, startedAt, endedAt, status, thumbnailUrl, result, innings
        case liveUrl, highlightUrl
    }
}

struct APITeam: Decodable {
    let name: String
    let shortName: String?
    let logoUrl: String?
    let themeColor: String?
}

struct APIMatchResult: Decodable {
    let winnerName: String?
    let winnerShortName: String?
    let resultType: String?
    let margin: Int?
    let summaryText: String?
}

struct APIInnings: Decodable {
    let inningsNumber: Int?
    let teamName: String?
    let teamShortName: String?
    let runs: Int?
    let wickets: Int?
    let overs: Double?
}

// MARK: - Complete match (scorecard / ball-by-ball)

struct APICompleteMatch: Decodable {
    let matchInfo: APICompleteMatchInfo
    let innings: [APICompleteInnings]
    let battingStats: [APIBattingStat]
    let bowlingStats: [APIBowlingStat]
    let scoreboard: APIScoreboard?
    let fallOfWickets: [APIFallOfWicket]?
    let ballByBall: [APIBallEvent]

    enum CodingKeys: String, CodingKey {
        case matchInfo, innings, battingStats, bowlingStats, scoreboard, fallOfWickets, ballByBall
    }

    init(
        matchInfo: APICompleteMatchInfo,
        innings: [APICompleteInnings],
        battingStats: [APIBattingStat],
        bowlingStats: [APIBowlingStat],
        scoreboard: APIScoreboard?,
        fallOfWickets: [APIFallOfWicket]?,
        ballByBall: [APIBallEvent]
    ) {
        self.matchInfo = matchInfo
        self.innings = innings
        self.battingStats = battingStats
        self.bowlingStats = bowlingStats
        self.scoreboard = scoreboard
        self.fallOfWickets = fallOfWickets
        self.ballByBall = ballByBall
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        matchInfo = try c.decode(APICompleteMatchInfo.self, forKey: .matchInfo)
        innings = try c.decodeIfPresent([APICompleteInnings].self, forKey: .innings) ?? []
        battingStats = try c.decodeIfPresent([APIBattingStat].self, forKey: .battingStats) ?? []
        bowlingStats = try c.decodeIfPresent([APIBowlingStat].self, forKey: .bowlingStats) ?? []
        scoreboard = try c.decodeIfPresent(APIScoreboard.self, forKey: .scoreboard)
        fallOfWickets = try c.decodeIfPresent([APIFallOfWicket].self, forKey: .fallOfWickets)
        ballByBall = try c.decodeIfPresent([APIBallEvent].self, forKey: .ballByBall) ?? []
    }

    func mergingBallVideos(_ balls: [String: FirebaseBall]?) -> APICompleteMatch {
        guard let balls, !balls.isEmpty else { return self }
        let byId = balls
        var bySpot: [String: FirebaseBall] = [:]
        for b in balls.values {
            guard let inn = b.innings, let over = b.over, let ball = b.ball else { continue }
            let key = "\(inn)-\(over)-\(ball)"
            let hasVideo = !(b.videoUrl ?? "").isEmpty
            if bySpot[key] == nil || hasVideo {
                bySpot[key] = b
            }
        }
        let merged = ballByBall.map { event -> APIBallEvent in
            let fromId = event.id.isEmpty ? nil : byId[event.id]
            let fromSpot = bySpot["\(event.innings ?? 0)-\(event.overNumber ?? 0)-\(event.ballNumber ?? 0)"]
            let url = [fromId?.videoUrl, fromSpot?.videoUrl, event.videoUrl]
                .compactMap { $0 }
                .first { !$0.isEmpty }
            return event.withVideoURL(url)
        }
        return APICompleteMatch(
            matchInfo: matchInfo,
            innings: innings,
            battingStats: battingStats,
            bowlingStats: bowlingStats,
            scoreboard: scoreboard,
            fallOfWickets: fallOfWickets,
            ballByBall: merged
        )
    }
}

struct APICompleteMatchInfo: Decodable {
    let id: String
    let matchSeq: Int?
    let tournament: APICompleteTournament?
    let team1: APICompleteTeam
    let team2: APICompleteTeam
    let tossWinner: APICompleteTeam?
    let tossDecision: String?
    let firstBattingTeam: APICompleteTeam?
    let venue: String?
    let status: String
    let scheduledAt: String?
    let startedAt: String?
    let endedAt: String?
    let overs: Int?
    let result: APIMatchResult?
}

struct APICompleteTournament: Decodable {
    let id: String?
    let name: String?
    let logoUrl: String?
    let location: String?
    let ground: String?
    let type: String?
}

struct APICompleteTeam: Decodable {
    let id: String?
    let name: String
    let shortName: String?
    let logoUrl: String?
    let themeColor: String?
}

struct APICompleteInnings: Decodable {
    let id: String?
    let number: Int?
    let runs: Int?
    let wickets: Int?
    let overs: Double?
    let target: Int?
    let isCompleted: Bool?
    let battingTeamName: String?
    let battingTeamShortName: String?
    let battingTeam: APICompleteTeam?
}

struct APIBattingStat: Decodable {
    let playerId: String?
    let teamId: String?
    let playingSeqActual: Int?
    let runs: Int?
    let balls: Int?
    let fours: Int?
    let sixes: Int?
    let outType: String?
    let playerName: String?
    let playerRole: String?
    let playerShortName: String?
    let team: APICompleteTeam?
}

struct APIBowlingStat: Decodable {
    let playerId: String?
    let teamId: String?
    let overs: Double?
    let runsConceded: Int?
    let wickets: Int?
    let maidens: Int?
    let dotBalls: Int?
    let extras: Int?
    let player: APIPlayerMini?
    let team: APICompleteTeam?
}

struct APIPlayerMini: Decodable {
    let id: String?
    let name: String?
    let shortName: String?
    let role: String?
    let imageUrl: String?
}

struct APIScoreboard: Decodable {
    let innings1: APIScoreboardInnings?
    let innings2: APIScoreboardInnings?
}

struct APIScoreboardInnings: Decodable {
    let summary: APIInningsSummary?
    let batting: [APIScoreboardBatter]
    let bowling: [APIScoreboardBowler]
}

struct APIInningsSummary: Decodable {
    let runs: Int?
    let wickets: Int?
    let overs: Double?
}

struct APIScoreboardBatter: Decodable {
    let playerId: String?
    let playerName: String?
    let runs: Int?
    let balls: Int?
    let fours: Int?
    let sixes: Int?
    let outType: String?
    let strikeRate: Double?
}

struct APIScoreboardBowler: Decodable {
    let playerId: String?
    let playerName: String?
    let overs: Double?
    let runsConceded: Int?
    let wickets: Int?
    let maidens: Int?
    let extras: Int?
    let economy: Double?
}

struct APIFallOfWicket: Decodable {
    let playerName: String?
    let runs: Int?
    let overs: Double?
    let wicketNumber: Int?
}

struct APIBallEvent: Decodable {
    let id: String
    let innings: Int?
    let overNumber: Int?
    let ballNumber: Int?
    let batRuns: Int?
    let extraRuns: Int?
    let extraType: String?
    let isLegal: Bool?
    let wicket: Bool?
    let wicketType: String?
    let shotName: String?
    let striker: APIPlayerMini?
    let nonStriker: APIPlayerMini?
    let bowler: APIPlayerMini?
    let dismissedPlayer: APIPlayerMini?
    let videoUrl: String?
    let note: String?

    func withVideoURL(_ url: String?) -> APIBallEvent {
        APIBallEvent(
            id: id,
            innings: innings,
            overNumber: overNumber,
            ballNumber: ballNumber,
            batRuns: batRuns,
            extraRuns: extraRuns,
            extraType: extraType,
            isLegal: isLegal,
            wicket: wicket,
            wicketType: wicketType,
            shotName: shotName,
            striker: striker,
            nonStriker: nonStriker,
            bowler: bowler,
            dismissedPlayer: dismissedPlayer,
            videoUrl: url ?? videoUrl,
            note: note
        )
    }

    static func firebase(
        id: String,
        innings: Int?,
        over: Int?,
        ball: Int?,
        runs: Int?,
        isWicket: Bool,
        note: String?,
        videoUrl: String?,
        strikerName: String,
        nonStrikerName: String
    ) -> APIBallEvent {
        APIBallEvent(
            id: id,
            innings: innings,
            overNumber: over,
            ballNumber: ball,
            batRuns: runs,
            extraRuns: 0,
            extraType: nil,
            isLegal: true,
            wicket: isWicket,
            wicketType: isWicket ? "caught" : nil,
            shotName: nil,
            striker: APIPlayerMini(id: nil, name: strikerName, shortName: nil, role: nil, imageUrl: nil),
            nonStriker: APIPlayerMini(id: nil, name: nonStrikerName, shortName: nil, role: nil, imageUrl: nil),
            bowler: APIPlayerMini(id: nil, name: "Bowler", shortName: nil, role: nil, imageUrl: nil),
            dismissedPlayer: nil,
            videoUrl: videoUrl,
            note: note
        )
    }
}

struct PublicHighlightsResponse: Decodable {
    let count: Int?
    let highlights: [APIHighlight]
}

struct APIHighlight: Decodable, Identifiable {
    let id: String
    let type: String
    let url: String
    let title: String?
    let description: String?
    let matchId: String?
    let tournamentId: String?
    let tournamentName: String?
    let playerId: String?
    let playerName: String?
    let sortOrder: Int?
    let createdAt: String?
}

enum CrickAPIClient {
    static func fetchPublicTournaments(activeOnly: Bool = true) async throws -> [APITournament] {
        var components = URLComponents(url: CrickAPI.baseURL.appendingPathComponent("api/tournaments/list-public"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "activeOnly", value: activeOnly ? "true" : "false")]
        guard let url = components.url else { throw URLError(.badURL) }
        return try await get(url, as: PublicTournamentsResponse.self).tournaments
    }

    static func fetchPublicHighlights(limit: Int = 40) async throws -> [APIHighlight] {
        var components = URLComponents(
            url: CrickAPI.baseURL.appendingPathComponent("api/highlight-videos/list-public"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "limit", value: String(limit))]
        guard let url = components.url else { throw URLError(.badURL) }
        return try await get(url, as: PublicHighlightsResponse.self).highlights
    }

    /// Prefer `matchId` (unique). `matchSeq` alone can collide across tournaments.
    static func fetchCompleteMatch(matchId: String? = nil, matchSeq: Int? = nil) async throws -> APICompleteMatch {
        var components = URLComponents(url: CrickAPI.baseURL.appendingPathComponent("api/matches/complete-public"), resolvingAgainstBaseURL: false)!
        var items: [URLQueryItem] = []
        if let matchId, !matchId.isEmpty {
            items.append(URLQueryItem(name: "matchId", value: matchId))
        } else if let matchSeq {
            items.append(URLQueryItem(name: "matchSeq", value: String(matchSeq)))
        } else {
            throw URLError(.badURL)
        }
        components.queryItems = items
        guard let url = components.url else { throw URLError(.badURL) }
        return try await get(url, as: APICompleteMatch.self)
    }

    private static func get<T: Decodable>(_ url: URL, as type: T.Type) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(type, from: data)
    }
}
