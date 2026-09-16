import SwiftUI
import UIKit

struct ProfileAvatarView: View {
    var size: CGFloat = 64
    @ObservedObject private var authStore = AuthStore.shared

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Theme.accent.opacity(0.95), Color(red: 0.55, green: 0.05, blue: 0.28)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            if let data = authStore.avatarData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(Theme.accent, lineWidth: max(1.5, size / 28)))
        .accessibilityLabel("Profile")
    }
}
