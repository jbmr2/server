import Foundation

#if canImport(FirebaseDatabase)
import FirebaseDatabase

enum FirebaseRealtime {
    static let databaseURL = FirebaseOTT.databaseBase

    static var database: Database {
        Database.database(url: databaseURL)
    }

    static func configure() {
        database.isPersistenceEnabled = false
        database.goOnline()
    }
}

#else

enum FirebaseRealtime {
    static let databaseURL = FirebaseOTT.databaseBase
    static func configure() {}
}

#endif
