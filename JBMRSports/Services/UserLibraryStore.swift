import Foundation

struct WatchHistoryEntry: Identifiable, Codable, Hashable {
    let matchId: String
    var title: String
    var viewedAt: Date

    var id: String { matchId }
}

struct WatchlistEntry: Identifiable, Codable, Hashable {
    let matchId: String
    var title: String
    var addedAt: Date

    var id: String { matchId }
}

private struct UserLibraryIndex: Codable {
    var history: [WatchHistoryEntry] = []
    var watchlist: [WatchlistEntry] = []
}

@MainActor
final class UserLibraryStore: ObservableObject {
    static let shared = UserLibraryStore()

    @Published private(set) var watchHistory: [WatchHistoryEntry] = []
    @Published private(set) var watchlist: [WatchlistEntry] = []
    @Published var toastMessage: String?

    private let indexURL: URL

    private init() {
        let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        indexURL = root.appendingPathComponent("user-library.json")
        loadIndex()
    }

    func isWatchlisted(matchId: String) -> Bool {
        watchlist.contains { $0.matchId == matchId }
    }

    func recordWatch(matchId: String, title: String) {
        var list = watchHistory.filter { $0.matchId != matchId }
        list.insert(WatchHistoryEntry(matchId: matchId, title: title, viewedAt: Date()), at: 0)
        watchHistory = Array(list.prefix(50))
        saveIndex()
    }

    @discardableResult
    func toggleWatchlist(matchId: String, title: String) -> Bool {
        if let idx = watchlist.firstIndex(where: { $0.matchId == matchId }) {
            watchlist.remove(at: idx)
            toastMessage = "Watchlist se hata diya"
            saveIndex()
            return false
        }
        watchlist.insert(WatchlistEntry(matchId: matchId, title: title, addedAt: Date()), at: 0)
        toastMessage = "Watchlist mein add ho gaya"
        saveIndex()
        return true
    }

    func removeFromWatchlist(matchId: String) {
        watchlist.removeAll { $0.matchId == matchId }
        saveIndex()
    }

    func clearToast() {
        toastMessage = nil
    }

    private func loadIndex() {
        guard let data = try? Data(contentsOf: indexURL),
              let index = try? JSONDecoder().decode(UserLibraryIndex.self, from: data) else { return }
        watchHistory = index.history
        watchlist = index.watchlist
    }

    private func saveIndex() {
        let index = UserLibraryIndex(history: watchHistory, watchlist: watchlist)
        guard let data = try? JSONEncoder().encode(index) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }
}
