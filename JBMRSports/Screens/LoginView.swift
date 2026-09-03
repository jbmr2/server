import SwiftUI

struct LoginView: View {
    var onSignedIn: (String) -> Void

    @State private var mobile = ""
    @State private var otp = ""
    @State private var otpSent = false
    @State private var showLegal = false
    @State private var errorMessage: String?

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
                Text(otpSent ? "Verify OTP" : "Login or Sign Up")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
                Text(otpSent ? "+91 \(mobile) par OTP bheja gaya (demo: 123456)" : "Enter your mobile number to get started")
                    .font(.system(size: 14))
                    .foregroundStyle(muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 8)

            VStack(spacing: 16) {
                if !otpSent {
                    HStack(spacing: 12) {
                        HStack(spacing: 8) {
                            Text("🇮🇳")
                                .font(.system(size: 18))
                            Text("+91")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.7))
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
                            .onChange(of: mobile) { _, newValue in
                                mobile = String(newValue.filter(\.isWholeNumber).prefix(10))
                            }
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 56)
                    .background(fieldBackground)
                } else {
                    TextField("6-digit OTP", text: $otp)
                        .keyboardType(.numberPad)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white)
                        .tint(Theme.accent)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .frame(height: 56)
                        .background(fieldBackground)
                        .onChange(of: otp) { _, newValue in
                            otp = String(newValue.filter(\.isWholeNumber).prefix(6))
                        }

                    Button("Change number") {
                        otpSent = false
                        otp = ""
                        errorMessage = nil
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    if !otpSent {
                        let digits = mobile.filter(\.isWholeNumber)
                        guard digits.count == 10 else {
                            errorMessage = "10 digit mobile number enter karo"
                            return
                        }
                        errorMessage = nil
                        otpSent = true
                    } else {
                        guard otp.count == 6 else {
                            errorMessage = "6 digit OTP enter karo"
                            return
                        }
                        guard otp == "123456" else {
                            errorMessage = "Galat OTP — demo ke liye 123456 use karo"
                            return
                        }
                        errorMessage = nil
                        onSignedIn(mobile.filter(\.isWholeNumber))
                    }
                } label: {
                    Text(otpSent ? "Verify & Continue" : "Get OTP")
                        .font(.system(size: 16, weight: .bold))
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
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)

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
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
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
