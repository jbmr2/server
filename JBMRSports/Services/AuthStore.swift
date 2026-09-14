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
    @Published private(set) var otpPending = false

    private var verificationID: String?
    private var authListener: AuthStateDidChangeListenerHandle?

    private init() {
        applyGuestUser()
    }

    /// Call after `FirebaseApp.configure()` (AppDelegate).
    func attachAuthListenerIfNeeded() {
        guard authListener == nil else { return }
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

    @discardableResult
    func sendOTP(phone raw: String) async -> Bool {
        let digits = raw.filter(\.isWholeNumber)
        guard digits.count == 10 else {
            errorMessage = "10 digit mobile number enter karo"
            otpPending = false
            return false
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let e164 = "+91\(digits)"
            let id = try await PhoneAuthProvider.provider()
                .verifyPhoneNumber(e164, uiDelegate: PhoneAuthUIDelegate.shared)
            guard !id.isEmpty else {
                errorMessage = "OTP request fail — reCAPTCHA complete karo ya Firebase config check karo"
                otpPending = false
                verificationID = nil
                return false
            }
            verificationID = id
            otpPending = true
            return true
        } catch {
            otpPending = false
            verificationID = nil
            errorMessage = friendlyAuthError(error)
            NSLog("JBMR sendOTP failed: %@", String(describing: error))
            return false
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
            do {
                try await FirestoreUserService.shared.upsertCurrentUser()
            } catch {
                NSLog("JBMR Firestore profile save failed: %@", error.localizedDescription)
            }
            apply(user: result.user)
            self.verificationID = nil
            otpPending = false
            return true
        } catch {
            errorMessage = friendlyAuthError(error)
            NSLog("JBMR verifyOTP failed: %@", String(describing: error))
            return false
        }
    }

    func signOut() {
        do {
            try Auth.auth().signOut()
        } catch {
            NSLog("JBMR signOut: %@", error.localizedDescription)
        }
        verificationID = nil
        otpPending = false
        applyGuestUser()
    }

    func clearError() {
        errorMessage = nil
    }

    func resetOTPFlow() {
        verificationID = nil
        otpPending = false
        clearError()
    }

    #if DEBUG
    var isRunningOnSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    /// Simulator par real SMS/APNs nahi aata — dev preview ke liye.
    func signInSimulatorDev() {
        guard isRunningOnSimulator else { return }
        verificationID = nil
        otpPending = false
        errorMessage = nil
        signedIn = true
        uid = "simulator-dev"
        phone = "9876543210"
        displayName = "Simulator User"
    }
    #endif

    private func apply(user: User?) {
        if let user {
            signedIn = true
            uid = user.uid
            let national = user.phoneNumber?
                .filter(\.isWholeNumber)
                .suffix(10)
                .map(String.init)
                .joined() ?? ""
            phone = national
            displayName = national.count >= 4 ? "User ••••\(national.suffix(4))" : "JBMR User"
            return
        }
        applyGuestUser()
    }

    private func applyGuestUser() {
        signedIn = true
        uid = "guest"
        phone = ""
        displayName = "Guest"
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
                return """
                APNs verify fail — Firebase mein .p8 key check karo:
                Key ID G3JV437LC2, Team ID SJ536RSC6J, app in.jbmrsports.ott
                """
            case .missingClientIdentifier:
                return """
                App verify fail — APNs key Firebase mein save hui? App band karke dubara kholo.
                Agar phir bhi error: Google Cloud → API key restrictions check karo.
                """
            case .quotaExceeded:
                return "SMS limit cross — Firebase Blaze plan enable karo ya test number add karo"
            case .captchaCheckFailed:
                return "reCAPTCHA fail — dubara OTP request karo"
            case .webContextCancelled:
                return "Verification cancel ho gayi — dubara try karo"
            case .internalError:
                #if targetEnvironment(simulator)
                return "Simulator par SMS nahi aata — Firebase test number use karo ya Dev Login dabao"
                #else
                return "Firebase Phone Auth error — Blaze plan enable karo (real SMS ke liye) ya test number add karo"
                #endif
            case .appNotAuthorized:
                return "App authorized nahi — Firebase Console mein Phone provider enable karo"
            default:
                break
            }
        }
        let message = error.localizedDescription
        if message.localizedCaseInsensitiveContains("billing") {
            return "Firebase Blaze plan chahiye real SMS ke liye — ya test phone number use karo"
        }
        if message.contains("API_KEY_IOS_APP_BLOCKED")
            || message.contains("iosBundleId")
            || message.contains("PERMISSION_DENIED")
            || nsError.domain.contains("FIRAuthErrorDomain") && message.contains("blocked") {
            return """
            Google API key block ho rahi hai.
            Google Cloud Console → API key → iOS apps → bundle ID add karo: in.jbmrsports.ott
            """
        }
        return message
    }
}
