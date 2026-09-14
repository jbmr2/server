import Foundation

enum LiveMatchSync {
    /// Admin app: CrickDB API se Firebase tak minimum interval.
    static let adminAPIPollIntervalNanoseconds: UInt64 = 5_000_000_000

    /// OTT live score — minimum gap between API fetches (watchdog / crash se bachne ke liye).
    static let liveMatchPollIntervalNanoseconds: UInt64 = 2_000_000_000

    /// Home / schedule list — sirf summary ke liye.
    static let homeFeedPollIntervalNanoseconds: UInt64 = 20_000_000_000
}
