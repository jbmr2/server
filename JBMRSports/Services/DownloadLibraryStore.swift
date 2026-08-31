import Foundation

struct DownloadedBallItem: Identifiable, Codable, Hashable {
    let id: String
    var ballLabel: String
    var matchTitle: String
    var remoteURL: String
    var localFilename: String
    var downloadedAt: Date
}

struct SavedReelItem: Identifiable, Codable, Hashable {
    let id: String
    var title: String
    var localFilename: String
    var durationSeconds: Double
    var fileSizeBytes: Int64
    var clipCount: Int
    var savedAt: Date
}

private struct DownloadLibraryIndex: Codable {
    var balls: [DownloadedBallItem] = []
    var reels: [SavedReelItem] = []
}

@MainActor
final class DownloadLibraryStore: ObservableObject {
    static let shared = DownloadLibraryStore()

    @Published private(set) var ballItems: [DownloadedBallItem] = []
    @Published private(set) var reelItems: [SavedReelItem] = []
    @Published var downloadingBallIds: Set<String> = []
    @Published var toastMessage: String?

    private let fm = FileManager.default
    private let indexURL: URL

    private init() {
        let root = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("JBMRDownloads", isDirectory: true)
        try? fm.createDirectory(at: root.appendingPathComponent("balls", isDirectory: true), withIntermediateDirectories: true)
        try? fm.createDirectory(at: root.appendingPathComponent("reels", isDirectory: true), withIntermediateDirectories: true)
        indexURL = root.appendingPathComponent("library-index.json")
        loadIndex()
    }

    private var ballsDir: URL {
        fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("JBMRDownloads/balls", isDirectory: true)
    }

    private var reelsDir: URL {
        fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("JBMRDownloads/reels", isDirectory: true)
    }

    func isBallDownloaded(id: String) -> Bool {
        localBallURL(id: id) != nil
    }

    func localBallURL(id: String) -> URL? {
        guard let item = ballItems.first(where: { $0.id == id }) else { return nil }
        let url = ballsDir.appendingPathComponent(item.localFilename)
        return fm.fileExists(atPath: url.path) ? url : nil
    }

    func playbackURL(for delivery: BallDelivery) -> URL? {
        localBallURL(id: delivery.id) ?? delivery.videoURL
    }

    func localReelURL(id: String) -> URL? {
        guard let item = reelItems.first(where: { $0.id == id }) else { return nil }
        let url = reelsDir.appendingPathComponent(item.localFilename)
        return fm.fileExists(atPath: url.path) ? url : nil
    }

    func downloadBall(id: String, remoteURL: URL, ballLabel: String, matchTitle: String) async {
        if isBallDownloaded(id: id) {
            toastMessage = "Already downloaded ✓"
            return
        }
        if downloadingBallIds.contains(id) { return }
        downloadingBallIds.insert(id)
        defer { downloadingBallIds.remove(id) }

        do {
            try? fm.createDirectory(at: ballsDir, withIntermediateDirectories: true)
            var request = URLRequest(url: remoteURL)
            request.timeoutInterval = 180
            request.cachePolicy = .reloadIgnoringLocalCacheData
            toastMessage = "Downloading…"

            let (tempURL, response) = try await URLSession.shared.download(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                toastMessage = "Download fail (\(http.statusCode))"
                return
            }

            let extRaw = remoteURL.pathExtension.lowercased()
            let ext = ["mp4", "mov", "m4v"].contains(extRaw) ? extRaw : "mp4"
            let filename = "\(id.sanitizedFilename).\(ext)"
            let dest = ballsDir.appendingPathComponent(filename)
            if fm.fileExists(atPath: dest.path) {
                try fm.removeItem(at: dest)
            }
            try fm.moveItem(at: tempURL, to: dest)

            let item = DownloadedBallItem(
                id: id,
                ballLabel: ballLabel,
                matchTitle: matchTitle,
                remoteURL: remoteURL.absoluteString,
                localFilename: filename,
                downloadedAt: Date()
            )
            ballItems.removeAll { $0.id == id }
            ballItems.insert(item, at: 0)
            persist()
            toastMessage = "Downloaded ✓ — Profile → My Reels"
        } catch {
            toastMessage = error.localizedDescription
        }
    }

    @discardableResult
    func saveExportedReel(_ result: ReelExportResult) -> SavedReelItem? {
        let filename = "reel-\(UUID().uuidString).mp4"
        let dest = reelsDir.appendingPathComponent(filename)
        do {
            if fm.fileExists(atPath: dest.path) {
                try fm.removeItem(at: dest)
            }
            try fm.copyItem(at: result.fileURL, to: dest)
            let item = SavedReelItem(
                id: UUID().uuidString,
                title: result.title,
                localFilename: filename,
                durationSeconds: result.durationSeconds,
                fileSizeBytes: result.fileSizeBytes,
                clipCount: result.clipCount,
                savedAt: Date()
            )
            reelItems.insert(item, at: 0)
            persist()
            toastMessage = "Reel saved ✓ — Profile → My Reels"
            return item
        } catch {
            toastMessage = "Reel save failed"
            return nil
        }
    }

    func clearToast() {
        toastMessage = nil
    }

    private func loadIndex() {
        guard let data = try? Data(contentsOf: indexURL),
              let index = try? JSONDecoder().decode(DownloadLibraryIndex.self, from: data)
        else { return }
        ballItems = index.balls
        reelItems = index.reels
    }

    private func persist() {
        let index = DownloadLibraryIndex(balls: ballItems, reels: reelItems)
        guard let data = try? JSONEncoder().encode(index) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }
}

private extension String {
    var sanitizedFilename: String {
        replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
    }
}
