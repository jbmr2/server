import SwiftUI

struct LoginView: View {
    @ObservedObject private var authStore = AuthStore.shared

    @State private var mobile = ""
    @State private var otp = ""
    @State private var pin = ""
    @State private var otpSent = false
    @State private var loginMethod = "pin"
    @State private var showLegal = false
    @State private var autoVerifyStarted = false
    @State private var resendAvailableAt: Date?
    private let otpResendCooldown: TimeInterval = 120

    private let loginBg = Color(red: 8 / 255, green: 9 / 255, blue: 14 / 255)
    private let fieldBG = Color(red: 18 / 255, green: 19 / 255, blue: 26 / 255)
    private let muted = Color(red: 142 / 255, green: 146 / 255, blue: 158 / 255)

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                Image("LoginStadium")
                    .resizable()
                    .scaledToFill()
                    .frame(height: 320)
                    .clipped()
                LinearGradient(
                    colors: [loginBg.opacity(0), loginBg],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 320)

                BrandLogo(size: 28)
                    .padding(.top, 68)
            }
            .frame(height: 320)
            .frame(maxWidth: .infinity)
            .clipped()

            VStack(alignment: .leading, spacing: 8) {
                Text("Login or Sign Up")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
                Text(loginMethod == "pin"
                     ? "Sign in with your 10-digit mobile number and 4-digit PIN. New users can use the OTP tab."
                     : otpStatusText)
                    .font(.system(size: 14))
                    .foregroundStyle(muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 8)

            HStack(spacing: 0) {
                methodTab("PIN", id: "pin")
                methodTab("OTP", id: "otp")
            }
            .padding(4)
            .background(fieldBG)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 24)
            .padding(.top, 16)

            VStack(spacing: 16) {
                if loginMethod == "otp" {
                    if !otpSent {
                        phoneField
                    } else {
                        TextField("6-digit OTP", text: $otp)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(.white)
                            .tint(Theme.accent)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                            .frame(height: 56)
                            .background(fieldBackground)
                            .onChange(of: otp) { _, newValue in
                                otp = String(newValue.filter(\.isWholeNumber).prefix(6))
                                if otp.count == 6, !authStore.isLoading, !autoVerifyStarted {
                                    autoVerifyStarted = true
                                    Task { await submit() }
                                }
                            }

                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            let remaining = resendSecondsLeft(at: context.date)
                            HStack {
                                Button("Change number") {
                                    otpSent = false
                                    otp = ""
                                    autoVerifyStarted = false
                                    resendAvailableAt = nil
                                    authStore.resetOTPFlow()
                                }
                                Spacer()
                                Button {
                                    Task { await resendOTP() }
                                } label: {
                                    Text(remaining > 0
                                         ? "Resend in \(resendClock(remaining))"
                                         : (authStore.otpSending ? "Sending…" : "Resend OTP"))
                                }
                                .disabled(remaining > 0 || authStore.otpSending)
                                .foregroundStyle(remaining > 0 ? muted : Theme.accent)
                            }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                        }
                    }
                } else {
                    phoneField
                    SecureField("4-digit PIN", text: $pin)
                        .keyboardType(.numberPad)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .frame(height: 56)
                        .background(fieldBackground)
                        .onChange(of: pin) { _, newValue in
                            pin = String(newValue.filter(\.isWholeNumber).prefix(4))
                        }
                    Text("New here? Switch to the OTP tab to create a PIN.")
                        .font(.system(size: 12))
                        .foregroundStyle(muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    Task { await submit() }
                } label: {
                    Group {
                        if authStore.isLoading || authStore.otpSending {
                            ProgressView().tint(.white)
                        } else {
                            Text(primaryTitle)
                                .font(.system(size: 16, weight: .bold))
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Theme.accent)
                    )
                    .shadow(color: Theme.accent.opacity(0.2), radius: 8, y: 8)
                }
                .buttonStyle(.plain)
                .disabled(authStore.isLoading || authStore.otpSending)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)

            #if DEBUG
            if authStore.isRunningOnSimulator {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Simulator: SMS is not delivered. Use a Firebase test phone number, or tap Dev Login below.")
                        .font(.system(size: 11))
                        .foregroundStyle(muted)

                    Button("Continue on Simulator (Dev)") {
                        authStore.signInSimulatorDev()
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
            }
            #endif

            Spacer(minLength: 0)

            Text(.init("By continuing, you agree to our [Terms of Service](https://jbmrsports.com/terms) & [Privacy Policy](https://jbmrsports.com/privacy)"))
                .font(.system(size: 11))
                .foregroundStyle(muted)
                .tint(Theme.accent)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.top, 40)
                .padding(.bottom, 32)
                .onTapGesture { showLegal = true }
        }
        .background(loginBg.ignoresSafeArea())
        .sheet(isPresented: $showLegal) {
            LegalSheet()
        }
        .alert("Login", isPresented: Binding(
            get: { authStore.errorMessage != nil },
            set: { if !$0 { authStore.clearError() } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(authStore.errorMessage ?? "")
        }
        .onAppear {
            if mobile.isEmpty {
                mobile = authStore.phone.isEmpty ? authStore.savedPinPhone : authStore.phone
            }
        }
    }

    private var otpStatusText: String {
        if !otpSent { return "Sign in with PIN, or request an OTP for a new number." }
        if authStore.otpSending { return "Sending OTP… enter the 6-digit code from SMS." }
        return "OTP sent to +91 \(mobile)"
    }

    private var primaryTitle: String {
        if loginMethod == "pin" { return "Sign in with PIN" }
        return otpSent ? "Verify & Continue" : "Get OTP"
    }

    private var phoneField: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Text("🇮🇳")
                    .font(.system(size: 18))
                Text("+91")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            }
            Rectangle()
                .fill(Color.white.opacity(0.18))
                .frame(width: 1, height: 20)
            TextField("98765 43210", text: $mobile)
                .keyboardType(.numberPad)
                .textContentType(.telephoneNumber)
                .font(.system(size: 15))
                .foregroundStyle(.white)
                .tint(Theme.accent)
                .disabled(loginMethod == "pin" && authStore.isLoading)
                .onChange(of: mobile) { _, newValue in
                    mobile = String(newValue.filter(\.isWholeNumber).prefix(10))
                }
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .background(fieldBackground)
    }

    private func methodTab(_ title: String, id: String) -> some View {
        Button {
            loginMethod = id
            authStore.clearError()
        } label: {
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(loginMethod == id ? .white : muted)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(loginMethod == id ? Theme.accent : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }

    private func submit() async {
        if loginMethod == "pin" {
            let ok = await authStore.unlockWithPin(pin, phone: mobile)
            if !ok { pin = "" }
            return
        }
        if !otpSent {
            let ok = await authStore.sendOTP(phone: mobile)
            otpSent = ok
            if ok { startResendCooldown() }
            return
        }
        let ok = await authStore.verifyOTP(otp)
        if ok { otp = "" }
    }

    private func startResendCooldown() {
        resendAvailableAt = Date().addingTimeInterval(otpResendCooldown)
    }

    private func resendSecondsLeft(at date: Date = Date()) -> Int {
        guard let until = resendAvailableAt else { return 0 }
        return max(0, Int(until.timeIntervalSince(date).rounded(.up)))
    }

    private func resendClock(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func resendOTP() async {
        guard resendSecondsLeft() == 0, !authStore.otpSending else { return }
        otp = ""
        autoVerifyStarted = false
        let ok = await authStore.sendOTP(phone: mobile)
        if ok {
            startResendCooldown()
        }
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(fieldBG)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Theme.accent, lineWidth: 1.5)
            )
    }
}
