import SwiftUI

struct SetPinView: View {
    @ObservedObject private var authStore = AuthStore.shared
    @State private var pin = ""
    @State private var confirm = ""
    @State private var step = 0

    var body: some View {
        PinScaffold(
            title: step == 0 ? "Create a 4-digit PIN" : "Confirm your PIN",
            subtitle: step == 0
                ? "Use this PIN the next time you sign in"
                : "Enter the same PIN again",
            value: step == 0 ? $pin : $confirm,
            primaryTitle: step == 0 ? "Continue" : "Save PIN",
            isLoading: authStore.isLoading,
            onPrimary: {
                if step == 0 {
                    guard pin.count == 4 else {
                        authStore.errorMessage = "Enter a 4-digit PIN"
                        return
                    }
                    step = 1
                    return
                }
                Task { await authStore.savePin(pin, confirm: confirm) }
            }
        )
    }
}

struct PinUnlockView: View {
    @ObservedObject private var authStore = AuthStore.shared
    @State private var pin = ""

    var body: some View {
        PinScaffold(
            title: "Sign in with PIN",
            subtitle: authStore.phoneLabel,
            value: $pin,
            primaryTitle: "Unlock",
            isLoading: authStore.isLoading,
            onPrimary: {
                Task {
                    let ok = await authStore.unlockWithPin(pin)
                    if !ok { pin = "" }
                }
            },
            footer: {
                Button("Use OTP or another number") {
                    authStore.signOutCompletely()
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .padding(.top, 16)
            }
        )
    }
}

private struct PinScaffold<Footer: View>: View {
    let title: String
    let subtitle: String
    @Binding var value: String
    let primaryTitle: String
    var isLoading: Bool
    let onPrimary: () -> Void
    @ViewBuilder var footer: () -> Footer

    private let loginBg = Color(red: 8 / 255, green: 9 / 255, blue: 14 / 255)
    private let fieldBG = Color(red: 18 / 255, green: 19 / 255, blue: 26 / 255)
    private let muted = Color(red: 142 / 255, green: 146 / 255, blue: 158 / 255)

    init(
        title: String,
        subtitle: String,
        value: Binding<String>,
        primaryTitle: String,
        isLoading: Bool,
        onPrimary: @escaping () -> Void,
        @ViewBuilder footer: @escaping () -> Footer
    ) {
        self.title = title
        self.subtitle = subtitle
        self._value = value
        self.primaryTitle = primaryTitle
        self.isLoading = isLoading
        self.onPrimary = onPrimary
        self.footer = footer
    }

    var body: some View {
        VStack(spacing: 0) {
            BrandLogo(size: 28)
                .padding(.top, 72)
                .padding(.bottom, 36)

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)

            SecureField("••••", text: $value)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .frame(height: 56)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(fieldBG)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Theme.accent, lineWidth: 1.5)
                        )
                )
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .onChange(of: value) { _, newValue in
                    value = String(newValue.filter(\.isWholeNumber).prefix(4))
                }

            Button(action: onPrimary) {
                Group {
                    if isLoading {
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
            }
            .buttonStyle(.plain)
            .disabled(isLoading || value.count != 4)
            .padding(.horizontal, 24)
            .padding(.top, 16)

            footer()

            Spacer(minLength: 0)
        }
        .background(loginBg.ignoresSafeArea())
        .alert("PIN", isPresented: Binding(
            get: { AuthStore.shared.errorMessage != nil },
            set: { if !$0 { AuthStore.shared.clearError() } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(AuthStore.shared.errorMessage ?? "")
        }
    }
}

extension PinScaffold where Footer == EmptyView {
    init(
        title: String,
        subtitle: String,
        value: Binding<String>,
        primaryTitle: String,
        isLoading: Bool,
        onPrimary: @escaping () -> Void
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            value: value,
            primaryTitle: primaryTitle,
            isLoading: isLoading,
            onPrimary: onPrimary,
            footer: { EmptyView() }
        )
    }
}
