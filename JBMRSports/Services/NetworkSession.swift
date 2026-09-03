import Foundation

enum NetworkSession {
    static let shared: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(
            memoryCapacity: 8 * 1024 * 1024,
            diskCapacity: 32 * 1024 * 1024,
            diskPath: "jbmr_url_cache"
        )
        config.requestCachePolicy = .useProtocolCachePolicy
        config.timeoutIntervalForRequest = 25
        return URLSession(configuration: config)
    }()
}
