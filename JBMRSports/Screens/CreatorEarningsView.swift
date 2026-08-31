import SwiftUI

struct CreatorEarningsView: View {
    @Environment(\.dismiss) private var dismiss

    private let cardBg = Color(red: 0.07, green: 0.086, blue: 0.125)

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                profileCard
                earningsCard
                Text("No earnings activity yet")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .background(Color(red: 0.039, green: 0.047, blue: 0.063).ignoresSafeArea())
        .safeAreaInset(edge: .top, spacing: 0) {
            header
                .background(Color(red: 0.039, green: 0.047, blue: 0.063))
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        AppHeader(onLogo: { dismiss() }, showsAvatar: false)
            .padding(.vertical, 8)
    }

    private var profileCard: some View {
        HStack(spacing: 12) {
            Image("UserAvatar")
                .resizable()
                .scaledToFill()
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 28))

            VStack(alignment: .leading, spacing: 6) {
                Text("Your Creator Profile")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                Text("Publish shorts to start earning")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(red: 0.56, green: 0.61, blue: 0.68))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(cardBg))
    }

    private var earningsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("TOTAL EARNINGS")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(red: 0.56, green: 0.61, blue: 0.68))
            Text("₹0")
                .font(.system(size: 32, weight: .heavy))
                .foregroundStyle(Theme.accent)
            Text("This Month: ₹0")
                .font(.system(size: 13))
                .foregroundStyle(Color(red: 0.82, green: 0.84, blue: 0.89))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(cardBg)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.accent, lineWidth: 1))
        )
    }
}
