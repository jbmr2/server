import Foundation

/// Persists the last successful `ott.json` payload for instant cold starts.
enum FeedCache {
    private static let fileName = "ott-feed-cache.json"

    private static var fileURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(fileName)
    }

    static func loadData() -> Data? {
        try? Data(contentsOf: fileURL)
    }

    static func save(_ data: Data) {
        try? data.write(to: fileURL, options: .atomic)
    }

    static func modifiedAt() -> Date? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path) else { return nil }
        return attrs[.modificationDate] as? Date
    }
}
