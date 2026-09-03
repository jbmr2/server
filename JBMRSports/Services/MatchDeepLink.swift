import Foundation

enum MatchDeepLink {
    private static let webHost = "jbmrsports.com"
    private static let customScheme = "jbmrsports"

    enum Route: Equatable {
        case match(String)
        case tournament(String)
    }

    static func appOpenURL(matchId: String) -> URL {
        URL(string: "\(customScheme)://match/\(matchId)")!
    }

    static func matchURL(matchId: String) -> URL {
        URL(string: "https://\(webHost)/match/\(matchId)")!
    }

    static func tournamentURL(tournamentId: String) -> URL {
        URL(string: "https://\(webHost)/tournament/\(tournamentId)")!
    }

    static func shareMessage(title: String, url: URL) -> String {
        "\(title)\n\(url.absoluteString)"
    }

    static func parse(_ url: URL) -> Route? {
        if url.scheme?.lowercased() == customScheme {
            return parseCustom(url)
        }
        if ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            return parseWeb(url)
        }
        return nil
    }

    private static func parseCustom(_ url: URL) -> Route? {
        let parts = url.path.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return nil }
        switch parts[0].lowercased() {
        case "match":
            let id = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            return id.isEmpty ? nil : .match(id)
        case "tournament":
            let id = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            return id.isEmpty ? nil : .tournament(id)
        default:
            return nil
        }
    }

    private static func parseWeb(_ url: URL) -> Route? {
        let host = (url.host ?? "").lowercased()
        guard host == webHost || host == "www.\(webHost)" else { return nil }

        let parts = url.path.split(separator: "/").map(String.init)
        guard let head = parts.first?.lowercased(), parts.count >= 2 else { return nil }
        let id = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return nil }

        switch head {
        case "match": return .match(id)
        case "tournament": return .tournament(id)
        default: return nil
        }
    }
}

@MainActor
final class DeepLinkRouter: ObservableObject {
    static let shared = DeepLinkRouter()

    @Published private(set) var pendingRoute: MatchDeepLink.Route?

    private init() {}

    func handle(url: URL) {
        guard let route = MatchDeepLink.parse(url) else { return }
        pendingRoute = route
    }

    func clear() {
        pendingRoute = nil
    }
}
