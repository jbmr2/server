import SwiftUI

struct SplashView: View {
    var onFinished: () -> Void

    @State private var progress: CGFloat = 0.08

    var body: some View {
        ZStack {
            Color(red: 8 / 255, green: 9 / 255, blue: 14 / 255).ignoresSafeArea()

            RadialGradient(
                colors: [
                    Theme.accent.opacity(0.22),
                    Theme.accent.opacity(0.05),
                    .clear
                ],
                center: .center,
                startRadius: 8,
                endRadius: 220
            )
            .allowsHitTesting(false)

            Image("SplashStadium")
                .resizable()
                .scaledToFit()
                .frame(width: 280)
                .opacity(0.12)
                .offset(y: 90)
                .allowsHitTesting(false)

            VStack(spacing: 12) {
                BrandLogo(size: 36)
                Text("LIVE CRICKET & MORE")
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(1.6)
                    .foregroundStyle(Theme.muted)
            }
            .offset(y: -80)

            VStack {
                Spacer()
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 140, height: 3)
                    Capsule()
                        .fill(Theme.accent)
                        .frame(width: 140 * progress, height: 3)
                }
                .padding(.bottom, 72)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.4)) {
                progress = 1
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                onFinished()
            }
        }
    }
}
