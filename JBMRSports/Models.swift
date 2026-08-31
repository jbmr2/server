import Foundation
import SwiftUI

enum Sport: String, CaseIterable, Identifiable {
    case cricket

    var id: String { rawValue }

    var label: String { "Cricket" }
}

enum AppNavigationRoute: Hashable {
    case match(String)
    case tournament(String)
}

struct FeaturedMatch: Identifiable, Hashable {
    let id: String
    let league: String
    let year: String
    let home: String
    let away: String
    let timeLabel: String
    let imageName: String
    let isLive: Bool
    var badge: String = "FULL MATCH HIGHLIGHTS"
    var subtitle: String = ""
    var durationLabel: String = "29m"
    var statusLine: String = ""
    var videoURL: URL? = nil
    var homeShort: String = ""
    var awayShort: String = ""
    var imageURL: URL? = nil
    var homeLogoURL: URL? = nil
    var awayLogoURL: URL? = nil
    var homeThemeColor: String? = nil
    var awayThemeColor: String? = nil
    var tournamentLogoURL: URL? = nil
    var scoreLabel: String = ""
    var homeInningsScore: String = ""
    var awayInningsScore: String = ""
    var matchSeq: Int? = nil
    var isMatchHighlightSlide: Bool = false

    var heroSlideKey: String {
        isMatchHighlightSlide ? "highlight-\(id)" : id
    }

    var homeCode: String {
        if !homeShort.isEmpty { return homeShort }
        return Self.code(for: home)
    }
    var awayCode: String {
        if !awayShort.isEmpty { return awayShort }
        return Self.code(for: away)
    }
    var vsLabel: String { "\(homeCode) vs \(awayCode)" }
    var seriesLabel: String { "\(league), \(year)" }
    var metaLine: String {
        let base = "\(league) \(year)"
        return durationLabel.isEmpty ? base : "\(base) • \(durationLabel)"
    }
    var ctaTitle: String {
        if isMatchHighlightSlide { return "WATCH HIGHLIGHT" }
        switch heroState {
        case .live: return "WATCH LIVE"
        case .upcoming: return "SET REMINDER"
        case .completed: return "WATCH HIGHLIGHTS"
        }
    }

    var heroActionLabel: String {
        if isMatchHighlightSlide { return "WATCH NOW" }
        switch heroState {
        case .live: return "WATCH LIVE"
        case .upcoming: return "UPCOMING"
        case .completed: return "COMPLETED"
        }
    }

    var heroSubtitleLine: String {
        switch heroState {
        case .live:
            return scoreLabel.isEmpty ? "Live Now" : scoreLabel
        case .upcoming:
            return timeLabel
        case .completed:
            let line = statusLine.trimmingCharacters(in: .whitespacesAndNewlines)
            return line.isEmpty ? "Match Finished" : line
        }
    }

    enum HeroState { case live, upcoming, completed }

    var heroState: HeroState {
        if isLive { return .live }
        if badge == "RESULT" { return .completed }
        return .upcoming
    }

    private static func code(for name: String) -> String {
        switch name {
        case "Mumbai Indians": return "MI"
        case "Chennai Super Kings": return "CSK"
        case "Royal Challengers": return "RCB"
        case "Kolkata Knight Riders": return "KKR"
        case "Gujarat Titans": return "GT"
        case "Rajasthan Royals": return "RR"
        case "Lucknow Super Giants": return "LSG"
        case "Delhi Capitals": return "DC"
        case "Punjab Kings": return "PBKS"
        case "Sunrisers Hyderabad": return "SRH"
        case "India": return "IND"
        case "Australia": return "AUS"
        case "West Indies": return "WI"
        default:
            let parts = name.split(separator: " ")
            if parts.count >= 2 {
                return parts.map { String($0.prefix(1)) }.joined().uppercased()
            }
            return String(name.prefix(3)).uppercased()
        }
    }
}

enum TournamentBadge: Hashable {
    case live(Int)
    case upcoming(Int)
    case matches(Int)
    case replaysOnly

    var text: String {
        switch self {
        case .live(let n): return "\(n) LIVE MATCHES"
        case .upcoming(let n): return "\(n) UPCOMING"
        case .matches(let n): return "\(n) MATCHES"
        case .replaysOnly: return "REPLAYS ONLY"
        }
    }

    var fill: Color {
        switch self {
        case .live: return Theme.accent
        case .upcoming: return Theme.accentDeep
        case .matches, .replaysOnly: return Color(white: 0.22)
        }
    }

    var foreground: Color {
        switch self {
        case .live, .upcoming: return .white
        case .matches, .replaysOnly: return Color(white: 0.78)
        }
    }
}

struct Tournament: Identifiable, Hashable {
    let id: String
    let name: String
    let imageName: String
    let badge: TournamentBadge
    let sport: Sport
}

enum HighlightCategory: String, CaseIterable, Identifiable {
    case all, boundaries, wickets, catches

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "All Clips"
        case .boundaries: return "💥 Boundaries"
        case .wickets: return "☝️ Wickets"
        case .catches: return "👐 Best Catches"
        }
    }
}

struct HighlightClip: Identifiable, Hashable {
    let id: String
    let tag: String
    let duration: String
    let title: String
    let meta: String
    let imageName: String
    let category: HighlightCategory
    let minutesLabel: String
    var videoURL: URL? = nil
    var matchId: String? = nil
    var tournamentId: String? = nil
    var homeTeam: String = ""
    var awayTeam: String = ""
    var homeCode: String = ""
    var awayCode: String = ""
    var matchSeq: Int? = nil
    var resultLine: String = ""

    var cardTitle: String {
        let home = railTeamLabel(code: homeCode, name: homeTeam)
        let away = railTeamLabel(code: awayCode, name: awayTeam)
        if !home.isEmpty, !away.isEmpty {
            return "\(home) vs \(away)"
        }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().contains(" vs ") { return trimmed }
        return trimmed.isEmpty ? "Match Highlight" : trimmed
    }

    var cardSubtitle: String {
        var parts: [String] = []
        if let seq = matchSeq {
            parts.append("Match \(seq)")
        }
        let result = resultLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if !result.isEmpty {
            parts.append(result)
        } else {
            let metaLine = meta.trimmingCharacters(in: .whitespacesAndNewlines)
            if !metaLine.isEmpty { parts.append(metaLine) }
        }
        return parts.joined(separator: " • ")
    }

    private func railTeamLabel(code: String, name: String) -> String {
        let short = code.trimmingCharacters(in: .whitespacesAndNewlines)
        if !short.isEmpty { return short.uppercased() }
        let cleaned = name
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return "" }
        let upper = cleaned.uppercased()
        if upper.count <= 14 { return upper }
        let words = upper.split(separator: " ").map(String.init)
        if words.count >= 2 { return "\(words[0]) \(words[1])" }
        return String(upper.prefix(14))
    }
}

struct TournamentHighlightRail: Identifiable, Hashable {
    let id: String
    let name: String
    let clips: [HighlightClip]
}

struct CommentaryItem: Identifiable, Hashable {
    enum Kind: Hashable { case six, run, wicket, other }
    let id: String
    let over: String
    let result: String
    let kind: Kind
    let body: String

    var resultColor: Color {
        switch kind {
        case .six: Theme.sixGreen
        case .wicket: Theme.liveRed
        case .run, .other: Theme.muted
        }
    }
}

struct BatterRow: Identifiable, Hashable {
    let id: String
    let name: String
    let dismissal: String
    let isBatting: Bool
    let runs: Int
    let balls: Int
    let fours: Int
    let sixes: Int
    let strikeRate: Double
}

enum OverBallKind: Hashable {
    case run(Int)
    case boundary(Int)
    case wicket
    case wide
    case noBall

    var label: String {
        switch self {
        case .run(let n), .boundary(let n): return "\(n)"
        case .wicket: return "W"
        case .wide: return "Wd"
        case .noBall: return "Nb"
        }
    }
}

struct OverBall: Identifiable, Hashable {
    let id: String
    let kind: OverBallKind
}

enum DeliveryResult: Hashable {
    case runs(Int)
    case four
    case six
    case wicket

    var label: String {
        switch self {
        case .runs(let n): return "\(n)"
        case .four: return "4"
        case .six: return "6"
        case .wicket: return "W"
        }
    }

    var fill: Color {
        switch self {
        case .four: return Theme.sixGreen
        case .six: return Theme.magenta
        case .wicket: return Theme.liveRed
        case .runs: return Color(white: 0.28)
        }
    }
}

struct BallDelivery: Identifiable, Hashable {
    let id: String
    let ballLabel: String
    let result: DeliveryResult
    let batsman: String
    let summary: String
    let imageName: String
    var videoURL: URL? = nil
}

struct MatchOver: Identifiable, Hashable {
    let id: Int
    let number: Int
    let displayIndex: Int
    let bowler: String
    let deliveries: [BallDelivery]

    var title: String { "Over \(displayIndex + 1)" }
}

struct BowlerRow: Identifiable, Hashable {
    let id: String
    let name: String
    let overs: String
    let maidens: Int
    let runs: Int
    let wickets: Int
    let economy: Double
    let isBowling: Bool
}

struct InningsBar: Identifiable, Hashable {
    let id: String
    let scoreLabel: String
    let runs: Int
    let opponent: String
    var isHighlight: Bool { runs >= 50 }
}

struct SquadPlayer: Identifiable, Hashable {
    let id: String
    let name: String
    let role: String
    var imageURL: URL? = nil

    var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first.map(String.init) }.joined()
        return letters.isEmpty ? String(name.prefix(2)).uppercased() : letters.uppercased()
    }
}


struct ScheduleMatch: Identifiable, Hashable {
    enum Status: Hashable {
        case live, upcoming, completed
        var label: String {
            switch self {
            case .live: return "LIVE"
            case .upcoming: return "UPCOMING"
            case .completed: return "RESULT"
            }
        }
        var color: Color {
            switch self {
            case .live: return Theme.liveRed
            case .upcoming: return Color(red: 0.96, green: 0.62, blue: 0.04)
            case .completed: return Color(red: 0.20, green: 0.70, blue: 0.40)
            }
        }
    }

    let id: String
    let tournament: String
    let homeCode: String
    let awayCode: String
    let homeName: String
    let awayName: String
    let timeLabel: String
    let venue: String
    let status: Status
    let sport: Sport
    let dayKey: String
    var scheduledAt: Date? = nil
    var homeLogoURL: URL? = nil
    var awayLogoURL: URL? = nil
    var tournamentLogoURL: URL? = nil
    var thumbnailURL: URL? = nil
    var scoreLabel: String? = nil
    var resultSummary: String? = nil
    var matchSeq: Int? = nil
    var matchLabel: String = "Match"
    var watchAtTime: String = ""
    var homeStatus: String = ""
    var awayStatus: String = ""
}

struct ShortClip: Identifiable, Hashable {
    let id: String
    let creator: String
    let caption: String
    let matchTag: String
    let audio: String
    let likes: String
    let comments: String
    let shares: String
    let imageName: String
    let isVerified: Bool
    var videoURL: URL? = nil
}

struct ReelClipItem: Identifiable, Hashable {
    let id: String
    let ballLabel: String
    let result: String
    let resultIsBoundary: Bool
    let match: String
    let duration: String
    let imageName: String
    var videoURL: URL? = nil
}

struct LeagueTile: Identifiable, Hashable {
    let id: String
    let title: String
    let imageName: String
    let duration: String
    var imageURL: URL? = nil
}

struct PointsTableRow: Identifiable, Hashable {
    let id: String
    let rank: Int
    let teamCode: String
    let teamName: String
    let played: Int
    let won: Int
    let lost: Int
    let nrr: String
    let points: Int
    var isHighlighted: Bool = false
}
