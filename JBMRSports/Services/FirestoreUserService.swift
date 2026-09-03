import FirebaseAuth
import FirebaseFirestore
import Foundation

struct FirestoreUserProfile: Codable, Equatable {
    let uid: String
    let phoneE164: String
    let phoneNational: String
    let createdAt: Date
    var lastLoginAt: Date
    var displayName: String
}

@MainActor
final class FirestoreUserService {
    static let shared = FirestoreUserService()

    private let db = Firestore.firestore()

    private init() {}

    func upsertCurrentUser() async throws {
        guard let user = Auth.auth().currentUser else { return }
        try await upsert(user: user)
    }

    func fetchCurrentUserProfile() async throws -> FirestoreUserProfile? {
        guard let uid = Auth.auth().currentUser?.uid else { return nil }
        let snapshot = try await db.collection("users").document(uid).getDocument()
        return try snapshot.data(as: FirestoreUserProfile.self)
    }

    private func upsert(user: User) async throws {
        let national = user.phoneNumber?
            .filter(\.isWholeNumber)
            .suffix(10)
            .map(String.init)
            .joined() ?? ""
        let e164 = user.phoneNumber ?? (national.isEmpty ? "" : "+91\(national)")
        let now = Date()
        let ref = db.collection("users").document(user.uid)
        let existing = try await ref.getDocument()

        if existing.exists, var profile = try? existing.data(as: FirestoreUserProfile.self) {
            profile.lastLoginAt = now
            try ref.setData(from: profile, merge: true)
            return
        }

        let profile = FirestoreUserProfile(
            uid: user.uid,
            phoneE164: e164,
            phoneNational: national,
            createdAt: now,
            lastLoginAt: now,
            displayName: national.count >= 4 ? "User ••••\(national.suffix(4))" : "JBMR User"
        )
        try ref.setData(from: profile)
    }
}
