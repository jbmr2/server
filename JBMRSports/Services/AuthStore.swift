import FirebaseAuth
import Foundation

@MainActor
final class AuthStore: ObservableObject {
    static let shared = AuthStore()

    @Published private(set) var signedIn = false
    @Published private(set) var phone = ""
    @Published private(set) var uid = ""
    @Published private(set) var displayName = "JBMR User"
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var verificationID: String?
    private var authListener: AuthStateDidChangeListenerHandle?

    private init() {
        authListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.apply(user: user)
            }
        }
    }

    var phoneLabel: String {
        let digits = phone.filter(\.isWholeNumber)
        guard digits.count == 10 else { return phone.isEmpty ? "Signed in" : phone }
        return "+91 \(digits.prefix(5)) \(digits.suffix(5))"
    }

    func sendOTP(phone raw: String) async {
        let digits = raw.filter(\.isWholeNumber)
        guard digits.count == 10 else {
            errorMessage = "10 digit mobile number enter karo"
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let e164 = "+91\(digits)"
            verificationID = try await PhoneAuthProvider.provider()
                .verifyPhoneNumber(e164, uiDelegate: PhoneAuthUIDelegate.shared)
        } catch {
            errorMessage = friendlyAuthError(error)
        }
    }

    func verifyOTP(_ code: String) async -> Bool {
        let digits = code.filter(\.isWholeNumber)
        guard digits.count == 6 else {
            errorMessage = "6 digit OTP enter karo"
            return false
        }
        guard let verificationID else {
            errorMessage = "Pehle OTP request karo"
            return false
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let credential = PhoneAuthProvider.provider()
                .credential(withVerificationID: verificationID, verificationCode: digits)
            let result = try await Auth.auth().signIn(with: credential)
            try await FirestoreUserService.shared.upsertCurrentUser()
            apply(user: result.user)
            self.verificationID = nil
            return true
        } catch {
            errorMessage = friendlyAuthError(error)
            return false
        }
    }

    func signOut() {
        do {
            try Auth.auth().signOut()
            verificationID = nil
            apply(user: nil)
        } catch {
            errorMessage = friendlyAuthError(error)
        }
    }

    func clearError() {
        errorMessage = nil
    }

    private func apply(user: User?) {
        signedIn = user != nil
        uid = user?.uid ?? ""
        let national = user?.phoneNumber?
            .filter(\.isWholeNumber)
            .suffix(10)
            .map(String.init)
            .joined() ?? ""
        phone = national
        displayName = national.count >= 4 ? "User ••••\(national.suffix(4))" : "JBMR User"
    }

    private func friendlyAuthError(_ error: Error) -> String {
        let nsError = error as NSError
        if let code = AuthErrorCode(rawValue: nsError.code) {
            switch code {
            case .invalidPhoneNumber:
                return "Galat mobile number"
            case .invalidVerificationCode:
                return "Galat OTP — dubara try karo"
            case .sessionExpired:
                return "OTP expire ho gaya — naya OTP lo"
            case .tooManyRequests:
                return "Bahut zyada tries — thodi der baad try karo"
            case .networkError:
                return "Network error — internet check karo"
            case .missingAppCredential, .invalidAppCredential:
                return FirebaseBootstrap.configurationIssue
                    ?? "Firebase app setup incomplete — GoogleService-Info.plist check karo"
            default:
                break
            }
        }
        return error.localizedDescription
    }
}
