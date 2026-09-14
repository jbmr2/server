import Foundation
import SwiftUI

@MainActor
final class MatchDetailStore: ObservableObject {
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var detail: MatchDetail?

    private var apiLiveListener = CrickAPILiveListener()
    private var feedProvider: (() -> FirebaseOTTFeed?)?
    private var activeListenerMatchId: String?
    private var activeTournamentId: String?
    private var lastLiveSignature = ""
    private var lastBallVideoSignature = ""
    private var lastAPI: APICompleteMatch?
    private var liveApplyTask: Task<Void, Never>?
    private var ballVideoPollTask: Task<Void, Never>?

    func load(matchId: String, matchSeq: Int?, feed: FirebaseOTTFeed?) async {
        let hadDetail = detail != nil
        isLoading = true
        if !hadDetail {
            errorMessage = nil
        }
        defer { isLoading = false }

        do {
            let resolvedFeed: FirebaseOTTFeed
            if let feed {
                resolvedFeed = feed
            } else if let data = FeedCache.loadData(),
                      let cached = try? JSONDecoder().decode(FirebaseOTTFeed.self, from: data) {
                resolvedFeed = cached
            } else {
                resolvedFeed = try await FirebaseOTTClient.fetchFeed()
            }

            let pair = FirebaseOTTClient.findMatch(matchId: matchId, in: resolvedFeed)
            activeTournamentId = pair?.0.tournamentId ?? apiTournamentId(from: pair)

            if let api = try? await CrickAPIClient.fetchLiveCompleteMatch(matchId: matchId, matchSeq: matchSeq) {
                activeTournamentId = api.matchInfo.tournament?.id ?? activeTournamentId
                lastAPI = api
                let ballVideos = await resolveBallVideos(matchId: matchId, api: api, feed: resolvedFeed)
                lastBallVideoSignature = ballVideoSignature(ballVideos)
                let mapped = await mapMatchDetail(api: api, ballVideos: ballVideos)
                detail = mapped
                errorMessage = nil
                return
            }

            if let uploaded = try? await FirebaseOTTClient.fetchCompleteMatch(matchId: matchId) {
                activeTournamentId = uploaded.matchInfo.tournament?.id ?? activeTournamentId
                let ballVideos = await resolveBallVideos(matchId: matchId, api: uploaded, feed: resolvedFeed)
                let mapped = await mapMatchDetail(api: uploaded, ballVideos: ballVideos)
                detail = mapped
                errorMessage = nil
                return
            }
            guard let pair else {
                if !hadDetail {
                    detail = nil
                    errorMessage = "Match Firebase mein nahi — Admin se tournament ON karo"
                }
                return
            }
            detail = MatchDetailMapper.map(FirebaseOTTClient.toCompleteMatch(tournament: pair.0, match: pair.1))
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            if !hadDetail {
                detail = nil
                errorMessage = "Match load nahi ho paya"
            }
        }
    }

    func startLiveListening(
        matchId: String,
        matchSeq: Int?,
        isLive: Bool,
        feedProvider: @escaping () -> FirebaseOTTFeed?
    ) {
        guard isLive else { return }
        guard activeListenerMatchId != matchId else { return }
        stopLiveListening()

        self.feedProvider = feedProvider
        self.activeListenerMatchId = matchId
        lastLiveSignature = ""
        lastBallVideoSignature = ""

        apiLiveListener.start(matchId: matchId, matchSeq: matchSeq) { [weak self] api in
            Task { @MainActor in
                self?.applyLiveMatch(api, matchId: matchId)
            }
        } onMatchEnded: { [weak self] in
            Task { @MainActor in
                self?.stopLiveListening()
            }
        }

        startBallVideoPolling(matchId: matchId)
    }

    func stopLiveListening() {
        liveApplyTask?.cancel()
        liveApplyTask = nil
        ballVideoPollTask?.cancel()
        ballVideoPollTask = nil
        apiLiveListener.stop()
        feedProvider = nil
        activeListenerMatchId = nil
        lastLiveSignature = ""
        lastBallVideoSignature = ""
        lastAPI = nil
    }

    func startLivePolling(
        matchId: String,
        matchSeq: Int? = nil,
        isLive: Bool,
        feedProvider: @escaping () -> FirebaseOTTFeed?
    ) {
        startLiveListening(matchId: matchId, matchSeq: matchSeq, isLive: isLive, feedProvider: feedProvider)
    }

    func stopLivePolling() {
        stopLiveListening()
    }

    private func applyLiveMatch(_ api: APICompleteMatch, matchId: String) {
        if let tid = api.matchInfo.tournament?.id, !tid.isEmpty {
            activeTournamentId = tid
        }
        lastAPI = api

        let scoreSignature = [
            api.matchInfo.status,
            "\(api.ballByBall.count)",
            api.ballByBall.last?.id ?? "",
        ].joined(separator: "|")

        liveApplyTask?.cancel()
        liveApplyTask = Task {
            let feed = feedProvider?()
            let ballVideos = await resolveBallVideos(matchId: matchId, api: api, feed: feed)
            let fullSignature = [scoreSignature, ballVideoSignature(ballVideos)].joined(separator: "|")
            guard fullSignature != lastLiveSignature else { return }
            lastLiveSignature = fullSignature
            lastBallVideoSignature = ballVideoSignature(ballVideos)

            let mapped = await mapMatchDetail(api: api, ballVideos: ballVideos)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.detail = mapped
                self.errorMessage = nil
            }
        }
    }

    /// Admin clip save hone par turant OTT update — score change ke bina bhi.
    private func startBallVideoPolling(matchId: String) {
        ballVideoPollTask?.cancel()
        ballVideoPollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await self?.pollBallVideos(matchId: matchId)
            }
        }
    }

    private func pollBallVideos(matchId: String) async {
        guard let api = lastAPI, Self.isLiveStatus(api.matchInfo.status) else { return }
        guard let tournamentId = activeTournamentId, !tournamentId.isEmpty else { return }
        guard let fresh = await FirebaseOTTClient.fetchBallVideos(tournamentId: tournamentId, matchId: matchId) else {
            return
        }
        let signature = ballVideoSignature(fresh)
        guard signature != lastBallVideoSignature else { return }
        lastBallVideoSignature = signature

        let mapped = await mapMatchDetail(api: api, ballVideos: fresh)
        guard !Task.isCancelled else { return }
        detail = mapped
    }

    private func resolveBallVideos(
        matchId: String,
        api: APICompleteMatch,
        feed: FirebaseOTTFeed?
    ) async -> [String: FirebaseBall]? {
        let tournamentId = api.matchInfo.tournament?.id
            ?? activeTournamentId
            ?? feed.flatMap { FirebaseOTTClient.findMatch(matchId: matchId, in: $0)?.0.tournamentId }

        if let tournamentId, !tournamentId.isEmpty,
           let fresh = await FirebaseOTTClient.fetchBallVideos(tournamentId: tournamentId, matchId: matchId),
           !fresh.isEmpty {
            return fresh
        }

        return feed.flatMap { FirebaseOTTClient.findMatch(matchId: matchId, in: $0)?.1.balls }
    }

    private func ballVideoSignature(_ balls: [String: FirebaseBall]?) -> String {
        guard let balls, !balls.isEmpty else { return "0" }
        let withVideo = balls.values.filter { !($0.videoUrl ?? "").isEmpty }
        let ids = withVideo.compactMap(\.id).sorted().joined(separator: ",")
        return "\(withVideo.count)|\(ids)"
    }

    private func apiTournamentId(from pair: (FirebaseTournament, FirebaseMatch)?) -> String? {
        pair?.0.tournamentId
    }

    private func mapMatchDetail(api: APICompleteMatch, ballVideos: [String: FirebaseBall]?) async -> MatchDetail {
        await Task.detached(priority: .userInitiated) {
            MatchDetailMapper.map(api.mergingBallVideos(ballVideos))
        }.value
    }

    private static func isLiveStatus(_ status: String) -> Bool {
        let s = status.lowercased()
        return s == "live" || s == "in progress"
    }

    static func isLiveMatchStatus(_ status: String) -> Bool {
        isLiveStatus(status)
    }
}

struct MatchDetail {
    let matchId: String
    let matchSeq: Int?
    let status: String
    let venue: String
    let tossLine: String
    let scoreLabel: String
    let homeName: String
    let awayName: String
    let homeShort: String
    let awayShort: String
    let innings: [MatchInningsDetail]
    let overs: [MatchOver]
    let commentary: [CommentaryItem]
    let strikerLabel: String
    let nonStrikerLabel: String
    let thisOver: [OverBall]
    let homeSquad: [SquadPlayer]
    let awaySquad: [SquadPlayer]
    let homeLogoURL: URL?
    let awayLogoURL: URL?
    let runRate: String
    let target: String
    let boundaries: String
    let dotBalls: String
}

struct MatchInningsDetail: Identifiable {
    let id: Int
    let number: Int
    let teamName: String
    let teamShort: String
    let summaryLabel: String
    let batting: [BatterRow]
    let bowling: [BowlerRow]
    let extras: String
    let total: String
}

enum MatchDetailMapper {
    static func map(_ api: APICompleteMatch) -> MatchDetail {
        let info = api.matchInfo
        let home = info.team1
        let away = info.team2
        let homeShort = home.shortName ?? String(home.name.prefix(3)).uppercased()
        let awayShort = away.shortName ?? String(away.name.prefix(3)).uppercased()

        let hasScoring = matchHasScoringData(api: api)
        let inningsDetails = buildInnings(api: api, home: home, away: away)
        let scoringBalls = hasScoring ? api.ballByBall : []
        let overs = buildOvers(from: scoringBalls)
        let commentary = buildCommentary(from: scoringBalls)
        let (striker, nonStriker, thisOver) = liveStrip(
            from: scoringBalls,
            batting: inningsDetails.last?.batting ?? [],
            status: info.status
        )

        let scoreLabel: String = {
            if let last = inningsDetails.last {
                return "\(last.teamShort) \(last.total)"
            }
            if let summary = info.result?.summaryText, !summary.isEmpty { return summary }
            return info.status.uppercased()
        }()

        let tossLine: String = {
            guard let toss = info.tossWinner else { return info.venue ?? "" }
            let decision = (info.tossDecision ?? "").uppercased()
            let choice = decision.isEmpty ? "" : " elected to \(decision.lowercased())"
            return "\(toss.shortName ?? toss.name) won the toss\(choice)"
        }()

        let (rr, target, boundaries, dots) = stats(api: api, innings: inningsDetails)

        let homeSquad = hasScoring
            ? squad(from: api, teamId: home.id, teamName: home.name, fallbackShort: homeShort)
            : []
        let awaySquad = hasScoring
            ? squad(from: api, teamId: away.id, teamName: away.name, fallbackShort: awayShort)
            : []
        let homeLogo = CrickAPI.absoluteURL(from: home.logoUrl)
        let awayLogo = CrickAPI.absoluteURL(from: away.logoUrl)

        return MatchDetail(
            matchId: info.id,
            matchSeq: info.matchSeq,
            status: info.status,
            venue: info.venue ?? info.tournament?.ground ?? info.tournament?.location ?? "",
            tossLine: tossLine,
            scoreLabel: scoreLabel,
            homeName: home.name,
            awayName: away.name,
            homeShort: homeShort,
            awayShort: awayShort,
            innings: inningsDetails,
            overs: overs,
            commentary: commentary,
            strikerLabel: striker,
            nonStrikerLabel: nonStriker,
            thisOver: thisOver,
            homeSquad: homeSquad,
            awaySquad: awaySquad,
            homeLogoURL: homeLogo,
            awayLogoURL: awayLogo,
            runRate: rr,
            target: target,
            boundaries: boundaries,
            dotBalls: dots
        )
    }

    private static func buildInnings(api: APICompleteMatch, home: APICompleteTeam, away: APICompleteTeam) -> [MatchInningsDetail] {
        guard matchHasScoringData(api: api) else { return [] }
        var result: [MatchInningsDetail] = []

        let boards: [(Int, APIScoreboardInnings?)] = [
            (1, api.scoreboard?.innings1),
            (2, api.scoreboard?.innings2)
        ]

        let completed = ["completed", "finished", "abandoned", "cancelled"].contains((api.matchInfo.status).lowercased())

        for (number, board) in boards {
            let meta = api.innings.first(where: { $0.number == number })
            let summary = board?.summary
            let runs = summary?.runs ?? meta?.runs ?? 0
            let wickets = summary?.wickets ?? meta?.wickets ?? 0
            let overs = summary?.overs ?? meta?.overs ?? 0

            let teamName = meta?.battingTeamName
                ?? meta?.battingTeam?.name
                ?? (number == 1 ? (api.matchInfo.firstBattingTeam?.name ?? home.name) : away.name)
            let teamShort = meta?.battingTeamShortName
                ?? meta?.battingTeam?.shortName
                ?? String(teamName.prefix(3)).uppercased()

            let battingSource = board?.batting ?? []
            guard summary != nil || !battingSource.isEmpty || meta != nil else { continue }

            let batting = battingSource.enumerated().compactMap { idx, row -> BatterRow? in
                let name = (row.playerName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let r = row.runs ?? 0
                let b = row.balls ?? 0
                if name.isEmpty || (name.lowercased() == "player" && r == 0 && b == 0) {
                    return nil
                }
                let sr = row.strikeRate ?? (b > 0 ? Double(r) * 100.0 / Double(b) : 0)
                let out = row.outType?.trimmingCharacters(in: .whitespacesAndNewlines)
                let isOut = !(out == nil || out?.isEmpty == true)
                return BatterRow(
                    id: row.playerId ?? "bat-\(number)-\(idx)",
                    name: name,
                    dismissal: isOut ? (out ?? "out") : "not out",
                    isBatting: completed ? false : !isOut,
                    runs: r,
                    balls: b,
                    fours: row.fours ?? 0,
                    sixes: row.sixes ?? 0,
                    strikeRate: sr
                )
            }

            let bowling = (board?.bowling ?? []).enumerated().map { idx, row -> BowlerRow in
                let oversVal = row.overs ?? 0
                let runs = row.runsConceded ?? 0
                let eco = row.economy ?? economy(overs: oversVal, runs: runs)
                return BowlerRow(
                    id: row.playerId ?? "bowl-\(number)-\(idx)",
                    name: row.playerName ?? "Bowler",
                    overs: formatOvers(oversVal),
                    maidens: row.maidens ?? 0,
                    runs: runs,
                    wickets: row.wickets ?? 0,
                    economy: eco,
                    isBowling: false
                )
            }

            let totalText = "\(runs)/\(wickets) (\(formatOvers(overs)) Ov)"
            let summaryLabel = "\(teamShort) — \(totalText)"

            result.append(
                MatchInningsDetail(
                    id: number,
                    number: number,
                    teamName: teamName,
                    teamShort: teamShort,
                    summaryLabel: summaryLabel,
                    batting: batting,
                    bowling: bowling,
                    extras: "—",
                    total: totalText
                )
            )
        }

        // Fallback: if scoreboard empty but battingStats exist (early innings)
        if result.isEmpty, !api.battingStats.isEmpty {
            let meta = api.innings.first
            let teamName = meta?.battingTeamName ?? home.name
            let teamShort = meta?.battingTeamShortName ?? home.shortName ?? "BAT"
            let runs = meta?.runs ?? 0
            let wickets = meta?.wickets ?? 0
            let overs = meta?.overs ?? 0
            let batting = api.battingStats.enumerated().map { idx, row -> BatterRow in
                let r = row.runs ?? 0
                let b = row.balls ?? 0
                let out = row.outType
                let isOut = !(out == nil || out?.isEmpty == true)
                return BatterRow(
                    id: row.playerId ?? "bat-f-\(idx)",
                    name: row.playerName ?? "Player",
                    dismissal: isOut ? (out ?? "out") : "not out",
                    isBatting: !isOut,
                    runs: r,
                    balls: b,
                    fours: row.fours ?? 0,
                    sixes: row.sixes ?? 0,
                    strikeRate: b > 0 ? Double(r) * 100.0 / Double(b) : 0
                )
            }
            let bowling = api.bowlingStats.enumerated().map { idx, row -> BowlerRow in
                let oversVal = row.overs ?? 0
                let runs = row.runsConceded ?? 0
                return BowlerRow(
                    id: row.playerId ?? "bowl-f-\(idx)",
                    name: row.player?.name ?? "Bowler",
                    overs: formatOvers(oversVal),
                    maidens: row.maidens ?? 0,
                    runs: runs,
                    wickets: row.wickets ?? 0,
                    economy: economy(overs: oversVal, runs: runs),
                    isBowling: false
                )
            }
            let totalText = "\(runs)/\(wickets) (\(formatOvers(overs)) Ov)"
            result.append(
                MatchInningsDetail(
                    id: 1,
                    number: 1,
                    teamName: teamName,
                    teamShort: teamShort,
                    summaryLabel: "\(teamShort) — \(totalText)",
                    batting: batting,
                    bowling: bowling,
                    extras: "—",
                    total: totalText
                )
            )
        }

        return result
    }

    private static func matchHasScoringData(api: APICompleteMatch) -> Bool {
        let status = api.matchInfo.status.lowercased()
        if ["live", "in progress", "completed", "finished"].contains(status) { return true }
        if let started = api.matchInfo.startedAt, !started.isEmpty { return true }
        if !api.ballByBall.isEmpty { return true }
        if !api.battingStats.isEmpty { return true }
        if api.scoreboard?.innings1?.batting.isEmpty == false { return true }
        if api.scoreboard?.innings2?.batting.isEmpty == false { return true }
        for inn in api.innings {
            if (inn.runs ?? 0) > 0 || (inn.wickets ?? 0) > 0 || (inn.overs ?? 0) > 0 { return true }
        }
        return false
    }

    private static func buildOvers(from balls: [APIBallEvent]) -> [MatchOver] {
        let minByInnings: [Int: Int] = Dictionary(grouping: balls, by: { $0.innings ?? 1 })
            .mapValues { events in events.compactMap(\.overNumber).min() ?? 0 }

        let grouped = Dictionary(grouping: balls) { event -> String in
            "\(event.innings ?? 0)-\(event.overNumber ?? 0)"
        }
        return grouped.values.compactMap { events -> MatchOver? in
            guard let sample = events.first else { return nil }
            let overNum = sample.overNumber ?? 0
            let innings = sample.innings ?? 1
            let minOver = minByInnings[innings] ?? 0
            let sorted = events.sorted { ($0.ballNumber ?? 0) < ($1.ballNumber ?? 0) }
            let bowler = sorted.last?.bowler?.name ?? "Bowler"
            let deliveries = sorted.enumerated().map { idx, event -> BallDelivery in
                BallDelivery(
                    id: "\(event.id)-\(idx)",
                    ballLabel: CricketOvers.ballLabel(
                        overNumber: event.overNumber ?? overNum,
                        ballNumber: event.ballNumber ?? 1,
                        minOverInInnings: minOver
                    ),
                    result: deliveryResult(event),
                    batsman: event.striker?.name ?? "Batter",
                    summary: event.note?.isEmpty == false ? (event.note ?? deliverySummary(event)) : deliverySummary(event),
                    imageName: "LiveCricket",
                    videoURL: CrickAPI.absoluteURL(from: event.videoUrl)
                )
            }
            let id = innings * 10_000 + overNum
            return MatchOver(
                id: id,
                number: overNum,
                displayIndex: CricketOvers.oversBefore(overNumber: overNum, minOverInInnings: minOver),
                bowler: bowler,
                deliveries: deliveries
            )
        }
        .sorted { $0.id < $1.id }
    }

    private static func buildCommentary(from balls: [APIBallEvent]) -> [CommentaryItem] {
        let minByInnings: [Int: Int] = Dictionary(grouping: balls, by: { $0.innings ?? 1 })
            .mapValues { events in events.compactMap(\.overNumber).min() ?? 0 }
        return balls.reversed().prefix(40).enumerated().map { idx, event in
            let minOver = minByInnings[event.innings ?? 1] ?? 0
            let label = CricketOvers.ballLabel(
                overNumber: event.overNumber ?? 0,
                ballNumber: event.ballNumber ?? 1,
                minOverInInnings: minOver
            )
            let result = deliveryResult(event)
            let kind: CommentaryItem.Kind = {
                switch result {
                case .six: return .six
                case .wicket: return .wicket
                case .four: return .run
                case .runs: return .run
                }
            }()
            return CommentaryItem(
                id: "c-\(event.id)-\(idx)",
                over: label,
                result: result.label,
                kind: kind,
                body: deliverySummary(event)
            )
        }
    }

    private static func liveStrip(from balls: [APIBallEvent], batting: [BatterRow], status: String) -> (String, String, [OverBall]) {
        let completed = ["completed", "finished", "abandoned", "cancelled"].contains(status.lowercased())
        if completed {
            return ("", "", [])
        }

        guard let last = balls.last else {
            let notOut = batting.filter(\.isBatting)
            let s = notOut.first.map { "\($0.name)*  \($0.runs)(\($0.balls))" } ?? "—"
            let n = notOut.dropFirst().first.map { "\($0.name)  \($0.runs)(\($0.balls))" } ?? "—"
            return (s, n, [])
        }

        // Only the last innings + last over (overNumber repeats across innings → was overflowing THIS OVER)
        let inningsNo = last.innings
        let over = last.overNumber ?? 0
        let overBalls = balls
            .filter { event in
                let sameOver = (event.overNumber ?? 0) == over
                let sameInnings = inningsNo == nil || event.innings == nil || event.innings == inningsNo
                return sameOver && sameInnings
            }
            .sorted { ($0.ballNumber ?? 0) < ($1.ballNumber ?? 0) }

        // Cap chips so UI never overflows (wides/no-balls can exceed 6)
        let chips: [OverBall] = overBalls.suffix(8).enumerated().map { idx, event in
            OverBall(id: "\(event.id)-\(idx)", kind: overBallKind(event))
        }

        let strikerName = last.striker?.name ?? "Striker"
        let nonName = last.nonStriker?.name ?? "Non-striker"
        let strikerStats = batting.first(where: { $0.name == strikerName })
        let nonStats = batting.first(where: { $0.name == nonName })
        let s = "\(strikerName)*  \(strikerStats?.runs ?? 0)(\(strikerStats?.balls ?? 0))"
        let n = "\(nonName)  \(nonStats?.runs ?? 0)(\(nonStats?.balls ?? 0))"
        return (s, n, chips)
    }

    private static func stats(api: APICompleteMatch, innings: [MatchInningsDetail]) -> (String, String, String, String) {
        let lastMeta = api.innings.sorted { ($0.number ?? 0) < ($1.number ?? 0) }.last
        let runs = Double(lastMeta?.runs ?? 0)
        let overs = lastMeta?.overs ?? 0
        let rr: String = {
            let dec = CricketOvers.decimal(overs)
            guard dec > 0 else { return "—" }
            return String(format: "%.1f", runs / dec)
        }()
        let target: String = {
            if let t = lastMeta?.target { return "\(t)" }
            if let first = api.innings.first(where: { $0.number == 1 }), (lastMeta?.number ?? 1) > 1 {
                return "\((first.runs ?? 0) + 1)"
            }
            return "—"
        }()
        let fours = innings.flatMap(\.batting).reduce(0) { $0 + $1.fours }
        let sixes = innings.flatMap(\.batting).reduce(0) { $0 + $1.sixes }
        let dots = api.bowlingStats.reduce(0) { $0 + ($1.dotBalls ?? 0) }
        return (rr, target, "\(fours + sixes)", dots > 0 ? "\(dots)" : "—")
    }

    private static func squad(from api: APICompleteMatch, teamId: String?, teamName: String, fallbackShort: String) -> [SquadPlayer] {
        var seen = Set<String>()
        var players: [SquadPlayer] = []

        for row in api.battingStats where row.team?.id == teamId || row.teamId == teamId {
            let id = row.playerId ?? row.playerName ?? UUID().uuidString
            guard seen.insert(id).inserted else { continue }
            players.append(
                SquadPlayer(
                    id: id,
                    name: row.playerName ?? "Player",
                    role: prettyRole(row.playerRole),
                    imageURL: nil
                )
            )
        }
        for row in api.bowlingStats where row.team?.id == teamId || row.teamId == teamId {
            let id = row.playerId ?? row.player?.id ?? row.player?.name ?? UUID().uuidString
            let image = CrickAPI.absoluteURL(from: row.player?.imageUrl)
            if let idx = players.firstIndex(where: { $0.id == id || $0.name.caseInsensitiveCompare(row.player?.name ?? "") == .orderedSame }) {
                if players[idx].imageURL == nil, image != nil {
                    players[idx] = SquadPlayer(
                        id: players[idx].id,
                        name: players[idx].name,
                        role: players[idx].role,
                        imageURL: image
                    )
                }
                continue
            }
            guard seen.insert(id).inserted else { continue }
            players.append(
                SquadPlayer(
                    id: id,
                    name: row.player?.name ?? "Player",
                    role: prettyRole(row.player?.role),
                    imageURL: image
                )
            )
        }

        if players.isEmpty {
            players = [SquadPlayer(id: "\(fallbackShort)-na", name: "\(teamName) squad", role: "TBD")]
        }
        return players
    }

    private static func prettyRole(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "Player" }
        switch raw.lowercased() {
        case "batsman", "batter": return "Batter"
        case "bowler": return "Bowler"
        case "allrounder", "all-rounder", "all rounder": return "All-rounder"
        case "wicketkeeper", "wicket-keeper", "wk": return "WK"
        default: return raw.capitalized
        }
    }

    private static func deliveryResult(_ event: APIBallEvent) -> DeliveryResult {
        if event.wicket == true { return .wicket }
        let runs = event.batRuns ?? 0
        if runs == 6 { return .six }
        if runs == 4 { return .four }
        return .runs(runs)
    }

    private static func overBallKind(_ event: APIBallEvent) -> OverBallKind {
        if event.wicket == true { return .wicket }
        let extra = (event.extraType ?? "").lowercased()
        if extra.contains("wide") { return .wide }
        if extra.contains("no") { return .noBall }
        let runs = event.batRuns ?? 0
        if runs == 4 || runs == 6 { return .boundary(runs) }
        return .run(runs)
    }

    private static func deliverySummary(_ event: APIBallEvent) -> String {
        let batter = event.striker?.name ?? "Batter"
        let bowler = event.bowler?.name ?? "Bowler"
        if event.wicket == true {
            let type = event.wicketType ?? "out"
            return "\(bowler) to \(batter) — WICKET (\(type))"
        }
        if let shot = event.shotName, !shot.isEmpty {
            let runs = event.batRuns ?? 0
            return "\(bowler) to \(batter) — \(runs) (\(shot))"
        }
        let runs = event.batRuns ?? 0
        let extra = event.extraType.map { " +\($0)" } ?? ""
        return "\(bowler) to \(batter) — \(runs)\(extra)"
    }

    private static func formatOvers(_ value: Double) -> String {
        CricketOvers.format(value)
    }

    private static func economy(overs: Double, runs: Int) -> Double {
        let dec = CricketOvers.decimal(overs)
        guard dec > 0 else { return 0 }
        return Double(runs) / dec
    }
}
