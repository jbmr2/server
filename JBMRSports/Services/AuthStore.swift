import Foundation

@MainActor
final class AuthStore: ObservableObject {
    static let shared = AuthStore()

    @Published private(set) var signedIn: Bool
    @Published private(set) var phone: String

    private let signedInKey = "hasSignedIn"
    private let phoneKey = "jbmr_user_phone"

    private init() {
        signedIn = UserDefaults.standard.bool(forKey: signedInKey)
        phone = UserDefaults.standard.string(forKey: phoneKey) ?? ""
    }

    var displayName: String {
        let digits = phone.filter(\.isWholeNumber)
        guard digits.count >= 4 else { return "JBMR User" }
        return "User ••••\(digits.suffix(4))"
    }

    var phoneLabel: String {
        let digits = phone.filter(\.isWholeNumber)
        guard digits.count == 10 else { return phone.isEmpty ? "Signed in" : phone }
        return "+91 \(digits.prefix(5)) \(digits.suffix(5))"
    }

    func signIn(phone: String) {
        let digits = phone.filter(\.isWholeNumber)
        self.phone = digits
        signedIn = true
        UserDefaults.standard.set(true, forKey: signedInKey)
        UserDefaults.standard.set(digits, forKey: phoneKey)
    }

    func signOut() {
        signedIn = false
        phone = ""
        UserDefaults.standard.set(false, forKey: signedInKey)
        UserDefaults.standard.removeObject(forKey: phoneKey)
    }
}
