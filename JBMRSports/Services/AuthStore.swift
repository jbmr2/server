import CryptoKit
import FirebaseAuth
import Foundation
import UIKit

enum AuthPhase: Equatable {
    case signedOut
    case needsPinSetup
    case locked
    case unlocked
}

@MainActor
final class AuthStore: ObservableObject {
    static let shared = AuthStore()

    @Published private(set) var phase: AuthPhase = .signedOut
    @Published private(set) var signedIn = false
    @Published private(set) var phone = ""
    @Published private(set) var uid = ""
    @Published private(set) var displayName = "JBMR User"
    @Published private(set) var avatarData: Data?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published private(set) var otpPending = false
    @Published private(set) var otpSending = false
    @Published private(set) var apnsReady = false

    private var verificationID: String?
    private var authListener: AuthStateDidChangeListenerHandle?
    private var apnsFailed = false
    private var lastAPNSToken: Data?
    private var skipLockOnce = false
    private var pinSessionActive = false
    private var pendingLoginPhone = ""
    private let pinDefaults = UserDefaults(suiteName: "in.jbmrsports.ott.pin") ?? .standard
    private let pinHashKey = "jbmr.pin.hash"
    private let pinUidKey = "jbmr.pin.uid"
    private let pinPhoneKey = "jbmr.pin.phone"
    private let displayNameKey = "jbmr.displayName"

    var initials: String {
        let parts = displayName.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first.map(String.init) }.joined()
        if letters.count >= 1 { return letters.uppercased() }
        let digits = phone.filter(\.isWholeNumber)
        return digits.suffix(2).isEmpty ? "JB" : String(digits.suffix(2))
    }

    var savedPinPhone: String {
        pinDefaults.string(forKey: pinPhoneKey) ?? ""
    }

    var hasPin: Bool {
        if !(pinDefaults.string(forKey: pinHashKey) ?? "").isEmpty {
            if uid.isEmpty { return true }
            if let storedUid = pinDefaults.string(forKey: pinUidKey), storedUid == uid { return true }
        }
        let national = phone.count == 10 ? phone : savedPinPhone
        if national.count == 10, let hash = pinDefaults.string(forKey: Self.phoneHashKey(national)), !hash.isEmpty {
            return true
        }
        return false
    }

    func hasPinForPhone(_ raw: String) -> Bool {
        let digits = raw.filter(\.isWholeNumber)
        guard digits.count == 10 else { return false }
        if let keyed = pinDefaults.string(forKey: Self.phoneHashKey(digits)), !keyed.isEmpty {
            return true
        }
        return savedPinPhone == digits && !(pinDefaults.string(forKey: pinHashKey) ?? "").isEmpty
    }

    private init() {
        applyGuestUser()
        loadAvatarFromDisk()
        if let saved = pinDefaults.string(forKey: displayNameKey), !saved.trimmingCharacters(in: .whitespaces).isEmpty {
            displayName = saved
        }
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

    func markAPNSReady(token: Data? = nil) {
        if let token {
            lastAPNSToken = token
            PhoneAuthAPNs.apply(token)
        }
        apnsReady = true
        apnsFailed = false
    }

    func markAPNSFailed() {
        apnsFailed = true
    }

    func prepareForOTP() {
        if let token = lastAPNSToken {
            PhoneAuthAPNs.apply(token)
            apnsReady = true
            return
        }
        UIApplication.shared.registerForRemoteNotifications()
    }

    private func waitForAPNS(timeoutSeconds: Double) async {
        if apnsReady { return }
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while !apnsReady && Date() < deadline {
            try? await Task.sleep(nanoseconds: 80_000_000)
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
            errorMessage = "Enter a 10-digit mobile number"
            otpPending = false
            return false
        }
        pendingLoginPhone = digits

        otpSending = true
        errorMessage = nil
        defer { otpSending = false }

        prepareForOTP()
        if lastAPNSToken == nil {
            await waitForAPNS(timeoutSeconds: 20)
        }

        do {
            Auth.auth().settings?.isAppVerificationDisabledForTesting = false
            if let token = lastAPNSToken {
                PhoneAuthAPNs.apply(token)
            }
            let e164 = "+91\(digits)"
            let id = try await PhoneAuthProvider.provider()
                .verifyPhoneNumber(e164, uiDelegate: PhoneAuthUIDelegate.shared)
            guard !id.isEmpty else {
                errorMessage = "Couldn’t send OTP — check the number and try again"
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
            errorMessage = "Enter the 6-digit OTP"
            return false
        }

        if verificationID == nil {
            let deadline = Date().addingTimeInterval(25)
            while verificationID == nil && otpSending && Date() < deadline {
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
        }
        guard let verificationID else {
            errorMessage = "OTP isn’t ready yet — wait a moment, then tap Verify"
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
            skipLockOnce = true
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
        lockSession()
    }

    func lockSession() {
        pinSessionActive = false
        verificationID = nil
        otpPending = false
        errorMessage = nil
        setPhase(.signedOut)
    }

    func signOutCompletely() {
        pinSessionActive = false
        do {
            try Auth.auth().signOut()
        } catch {
            NSLog("JBMR signOut: %@", error.localizedDescription)
        }
        verificationID = nil
        otpPending = false
        applyGuestUser()
    }

    @discardableResult
    func savePin(_ pin: String, confirm: String) async -> Bool {
        let digits = pin.filter(\.isWholeNumber)
        let confirmDigits = confirm.filter(\.isWholeNumber)
        guard digits.count == 4 else {
            errorMessage = "Enter a 4-digit PIN"
            return false
        }
        guard digits == confirmDigits else {
            errorMessage = "PIN does not match — try again"
            return false
        }
        guard !uid.isEmpty else {
            errorMessage = "Sign in with OTP first, then create a PIN"
            return false
        }
        let national = nationalPhone(Auth.auth().currentUser?.phoneNumber) 
            ?? (phone.isEmpty ? pendingLoginPhone : phone)
        guard national.count == 10 else {
            errorMessage = "Couldn’t save PIN — phone number missing. Try OTP again."
            return false
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        let hash = Self.hashPin(digits, uid: uid)
        persistPin(hash: hash, uid: uid, phone: national)
        do {
            try await FirestoreUserService.shared.savePinHash(hash, phone: national)
            try await FirestoreUserService.shared.savePhonePinLookup(uid: uid, phone: national, hash: hash)
        } catch {
            NSLog("JBMR PIN profile save failed: %@", error.localizedDescription)
        }
        pinDefaults.synchronize()
        setPhase(.unlocked)
        return true
    }

    func unlockWithPin(_ pin: String, phone rawPhone: String = "") async -> Bool {
        let digits = pin.filter(\.isWholeNumber)
        let phoneDigits = rawPhone.filter(\.isWholeNumber)
        let checkPhone = phoneDigits.count == 10 ? phoneDigits : (phone.isEmpty ? savedPinPhone : phone)
        guard checkPhone.count == 10 else {
            errorMessage = "Enter a 10-digit mobile number"
            return false
        }
        guard digits.count == 4 else {
            errorMessage = "Enter a 4-digit PIN"
            return false
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        var storedUid = pinDefaults.string(forKey: Self.phoneUidKey(checkPhone))
            ?? pinDefaults.string(forKey: pinUidKey)
            ?? uid
        var storedHash = pinDefaults.string(forKey: Self.phoneHashKey(checkPhone))
            ?? pinDefaults.string(forKey: pinHashKey)

        if storedHash == nil || storedUid.isEmpty {
            if let remote = try? await FirestoreUserService.shared.fetchPinForPhone(checkPhone) {
                storedUid = remote.uid
                storedHash = remote.hash
            }
        }

        if let storedHash, !storedUid.isEmpty {
            if storedHash == Self.hashPin(digits, uid: storedUid) {
                completePinUnlock(uid: storedUid, phone: checkPhone, hash: storedHash)
                return true
            }
            errorMessage = "Incorrect PIN"
            return false
        }

        do {
            if let remote = try await FirestoreUserService.shared.verifyPinLogin(phone: checkPhone, pin: digits) {
                let hash = Self.hashPin(digits, uid: remote.uid)
                completePinUnlock(uid: remote.uid, phone: checkPhone, hash: hash)
                return true
            }
        } catch {
            errorMessage = error.localizedDescription
            return false
        }

        errorMessage = "No PIN found for this number. Use the OTP tab to create one."
        return false
    }

    private func completePinUnlock(uid: String, phone: String, hash: String) {
        persistPin(hash: hash, uid: uid, phone: phone)
        self.uid = uid
        self.phone = phone
        displayName = storedDisplayName(fallbackPhone: phone)
        pinSessionActive = true
        errorMessage = nil
        setPhase(.unlocked)
    }

    func clearError() {
        errorMessage = nil
    }

    func resetOTPFlow() {
        verificationID = nil
        otpPending = false
        otpSending = false
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
        pinSessionActive = true
        setPhase(.unlocked)
    }
    #endif

    private func apply(user: User?) {
        if let user {
            pinSessionActive = false
            uid = user.uid
            let national = user.phoneNumber?
                .filter(\.isWholeNumber)
                .suffix(10)
                .map(String.init)
                .joined() ?? ""
            phone = national
            displayName = storedDisplayName(fallbackPhone: national)
            let unlock = skipLockOnce
            skipLockOnce = false
            Task {
                await refreshPhase(preferUnlock: unlock)
                await loadRemoteDisplayName()
            }
            return
        }
        if pinSessionActive { return }
        applyGuestUser()
    }

    @discardableResult
    func updateDisplayName(_ name: String) async -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            errorMessage = "Name must be at least 2 characters"
            return false
        }
        displayName = trimmed
        pinDefaults.set(trimmed, forKey: displayNameKey)
        pinDefaults.synchronize()
        do {
            try await FirestoreUserService.shared.updateDisplayName(trimmed)
        } catch {
            NSLog("JBMR profile name save failed: %@", error.localizedDescription)
        }
        return true
    }

    func setAvatarJPEG(_ data: Data) {
        avatarData = data
        try? data.write(to: Self.avatarFileURL, options: .atomic)
    }

    func clearAvatar() {
        avatarData = nil
        try? FileManager.default.removeItem(at: Self.avatarFileURL)
    }

    private func storedDisplayName(fallbackPhone: String) -> String {
        if let saved = pinDefaults.string(forKey: displayNameKey)?.trimmingCharacters(in: .whitespacesAndNewlines),
           saved.count >= 2 {
            return saved
        }
        return fallbackPhone.count >= 4 ? "User ••••\(fallbackPhone.suffix(4))" : "JBMR User"
    }

    private func loadRemoteDisplayName() async {
        do {
            if let profile = try await FirestoreUserService.shared.fetchCurrentUserProfile() {
                let name = profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                if name.count >= 2, !name.hasPrefix("User •") {
                    displayName = name
                    pinDefaults.set(name, forKey: displayNameKey)
                }
            }
        } catch {
            NSLog("JBMR profile fetch failed: %@", error.localizedDescription)
        }
    }

    private func loadAvatarFromDisk() {
        avatarData = try? Data(contentsOf: Self.avatarFileURL)
    }

    private static var avatarFileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("jbmr-profile-avatar.jpg")
    }

    private func refreshPhase(preferUnlock: Bool) async {
        await loadPinFromProfileIfNeeded()
        if hasPin {
            setPhase(preferUnlock ? .unlocked : .signedOut)
        } else {
            setPhase(.needsPinSetup)
        }
    }

    private func persistPin(hash: String, uid: String, phone: String) {
        pinDefaults.set(hash, forKey: pinHashKey)
        pinDefaults.set(uid, forKey: pinUidKey)
        if phone.count == 10 {
            pinDefaults.set(phone, forKey: pinPhoneKey)
            pinDefaults.set(hash, forKey: Self.phoneHashKey(phone))
            pinDefaults.set(uid, forKey: Self.phoneUidKey(phone))
            if self.phone.isEmpty { self.phone = phone }
        }
        pinDefaults.synchronize()
    }

    private static func phoneHashKey(_ phone: String) -> String { "jbmr.pin.hash.\(phone)" }
    private static func phoneUidKey(_ phone: String) -> String { "jbmr.pin.uid.\(phone)" }

    private func nationalPhone(_ raw: String?) -> String? {
        let digits = (raw ?? "").filter(\.isWholeNumber)
        guard digits.count >= 10 else { return nil }
        return String(digits.suffix(10))
    }

    private func loadPinFromProfileIfNeeded() async {
        if hasPin { return }
        let national = nationalPhone(Auth.auth().currentUser?.phoneNumber)
            ?? (phone.count == 10 ? phone : savedPinPhone)

        if national.count == 10,
           let localHash = pinDefaults.string(forKey: Self.phoneHashKey(national)), !localHash.isEmpty {
            let localUid = pinDefaults.string(forKey: Self.phoneUidKey(national)) ?? uid
            persistPin(hash: localHash, uid: localUid.isEmpty ? uid : localUid, phone: national)
            return
        }

        if let remote = try? await FirestoreUserService.shared.fetchPinHash(), !remote.isEmpty, !uid.isEmpty {
            persistPin(hash: remote, uid: uid, phone: national)
            if national.count == 10 {
                try? await FirestoreUserService.shared.savePhonePinLookup(uid: uid, phone: national, hash: remote)
            }
            return
        }

        if national.count == 10,
           let lookup = try? await FirestoreUserService.shared.fetchPinForPhone(national) {
            persistPin(hash: lookup.hash, uid: lookup.uid, phone: national)
        }
    }

    private func setPhase(_ newPhase: AuthPhase) {
        phase = newPhase
        signedIn = newPhase == .unlocked
    }

    private static func hashPin(_ pin: String, uid: String) -> String {
        let payload = "jbmr-pin-v1|\(uid)|\(pin)"
        let digest = SHA256.hash(data: Data(payload.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func applyGuestUser() {
        signedIn = false
        uid = ""
        phone = ""
        displayName = "Guest"
        phase = .signedOut
    }

    private func friendlyAuthError(_ error: Error) -> String {
        let nsError = error as NSError
        if let code = AuthErrorCode(rawValue: nsError.code) {
            switch code {
            case .invalidPhoneNumber:
                return "Invalid mobile number"
            case .invalidVerificationCode:
                return "Incorrect OTP — try again"
            case .sessionExpired:
                return "OTP expired — request a new code"
            case .tooManyRequests:
                return "Too many attempts — try again later"
            case .networkError:
                return "Network error — check your internet connection"
            case .webContextCancelled:
                return "Couldn’t send OTP. Wait a few seconds and tap Get OTP again."
            case .missingAppCredential, .invalidAppCredential:
                return "Couldn’t send OTP — wait a few seconds and tap Get OTP again"
            case .missingClientIdentifier:
                return "Couldn’t send OTP — tap Get OTP again"
            case .quotaExceeded:
                return "SMS limit reached — try again later"
            case .captchaCheckFailed:
                return "Couldn’t send OTP — wait a few seconds and tap Get OTP again"
            case .internalError:
                #if targetEnvironment(simulator)
                return "SMS isn’t delivered in Simulator — use a Firebase test number or Dev Login"
                #else
                return "Couldn’t send SMS. Check your connection and try again."
                #endif
            case .appNotAuthorized:
                return "This app isn’t authorized for phone sign-in"
            default:
                break
            }
        }
        let message = error.localizedDescription
        if message.localizedCaseInsensitiveContains("billing") {
            return "Phone sign-in is temporarily unavailable. Try PIN login or try again later."
        }
        if message.contains("API_KEY_IOS_APP_BLOCKED")
            || message.contains("iosBundleId")
            || message.contains("PERMISSION_DENIED")
            || nsError.domain.contains("FIRAuthErrorDomain") && message.contains("blocked") {
            return "Sign-in is blocked for this app build. Please try again later."
        }
        return message
    }
}
