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

        if existing.exists {
            try await ref.updateData([
                "lastLoginAt": now,
                "phoneE164": e164,
                "phoneNational": national
            ])
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

    func fetchPinHash() async throws -> String? {
        guard let uid = Auth.auth().currentUser?.uid else { return nil }
        let snapshot = try await db.collection("users").document(uid).getDocument()
        return snapshot.data()?["pinHash"] as? String
    }

    func savePinHash(_ hash: String, phone: String? = nil) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        var payload: [String: Any] = [
            "pinHash": hash,
            "pinUpdatedAt": FieldValue.serverTimestamp()
        ]
        if let phone, phone.count == 10 {
            payload["phoneNational"] = phone
            payload["pinPhone"] = phone
        }
        try await db.collection("users").document(uid).setData(payload, merge: true)
    }

    func updateDisplayName(_ name: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        try await db.collection("users").document(uid).setData([
            "displayName": name,
            "profileUpdatedAt": FieldValue.serverTimestamp()
        ], merge: true)
    }

    func fetchPinForPhone(_ phone: String) async throws -> (uid: String, hash: String)? {
        let digits = phone.filter(\.isWholeNumber)
        guard digits.count == 10 else { return nil }
        let snapshot = try await db.collection("phonePins").document(digits).getDocument()
        guard snapshot.exists,
              let uid = snapshot.data()?["uid"] as? String, !uid.isEmpty,
              let hash = snapshot.data()?["pinHash"] as? String, !hash.isEmpty else {
            return nil
        }
        return (uid, hash)
    }

    func savePhonePinLookup(uid: String, phone: String, hash: String) async throws {
        guard phone.count == 10, !uid.isEmpty, !hash.isEmpty else { return }
        try await db.collection("phonePins").document(phone).setData([
            "uid": uid,
            "pinHash": hash,
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)
    }

    func deleteCurrentUserRecords(phone: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        try await db.collection("users").document(uid).delete()
        let digits = phone.filter(\.isWholeNumber)
        if digits.count == 10 {
            try await db.collection("phonePins").document(digits).delete()
        }
    }

    private static let functionsBase = "https://asia-southeast1-ncrplt20-1c022.cloudfunctions.net"

    func sendTwoFactorOtp(phone: String) async throws -> String {
        let json = try await postFunction("sendOtp", body: ["phone": phone])
        guard json["ok"] as? Bool == true, let session = json["sessionId"] as? String, !session.isEmpty else {
            throw NSError(
                domain: "JBMROtp",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: (json["error"] as? String) ?? "Couldn’t send OTP — try again"]
            )
        }
        return session
    }

    func verifyTwoFactorOtp(phone: String, otp: String, sessionId: String) async throws -> String {
        let json = try await postFunction("verifyOtp", body: [
            "phone": phone,
            "otp": otp,
            "sessionId": sessionId
        ])
        guard json["ok"] as? Bool == true, let token = json["token"] as? String, !token.isEmpty else {
            throw NSError(
                domain: "JBMROtp",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: (json["error"] as? String) ?? "Incorrect OTP — try again"]
            )
        }
        return token
    }

    private func postFunction(_ name: String, body: [String: String]) async throws -> [String: Any] {
        guard let url = URL(string: "\(Self.functionsBase)/\(name)") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 25
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code >= 200 && code < 300 { return json }
        let message = (json["error"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        throw NSError(
            domain: "JBMROtp",
            code: code,
            userInfo: [NSLocalizedDescriptionKey: (message?.isEmpty == false ? message! : "Request failed")]
        )
    }

    func verifyPinLogin(phone: String, pin: String) async throws -> (uid: String, phone: String)? {
        let digits = phone.filter(\.isWholeNumber)
        let pinDigits = pin.filter(\.isWholeNumber)
        guard digits.count == 10, pinDigits.count == 4 else { return nil }
        guard let url = URL(string: "https://asia-southeast1-ncrplt20-1c022.cloudfunctions.net/verifyPinLogin") else {
            return nil
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 20
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "phone": digits,
            "pin": pinDigits
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        if code == 200, json["ok"] as? Bool == true, let uid = json["uid"] as? String, !uid.isEmpty {
            return (uid, digits)
        }
        if let message = json["error"] as? String, !message.isEmpty {
            throw NSError(domain: "JBMRPin", code: code, userInfo: [NSLocalizedDescriptionKey: message])
        }
        return nil
    }
}
