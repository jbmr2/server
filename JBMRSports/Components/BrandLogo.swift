import SwiftUI

struct BrandLogo: View {
    var size: CGFloat = 22
    var accent: Color = Theme.accent

    var body: some View {
        HStack(spacing: 6) {
            Text("JBMR")
                .foregroundStyle(.white)
            Text("SPORTS")
                .foregroundStyle(accent)
        }
        .font(.system(size: size, weight: .bold))
        .accessibilityLabel("JBMR Sports")
    }
}

struct UserAvatarButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ProfileAvatarView(size: 30)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Profile")
    }
}

struct AppHeader: View {
    var onLogo: (() -> Void)? = nil
    var onAvatar: (() -> Void)? = nil
    var onSearch: (() -> Void)? = nil
    var showsAvatar: Bool = true

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let onLogo {
                    Button(action: onLogo) {
                        BrandLogo(size: 18)
                    }
                    .buttonStyle(.plain)
                } else {
                    BrandLogo(size: 18)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let onSearch {
                Button(action: onSearch) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Search")
            }

            if showsAvatar, let onAvatar {
                UserAvatarButton(action: onAvatar)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
    }
}

struct SectionHeaderRow: View {
    var title: String
    var titleSize: CGFloat = 24
    var actionTitle: String = "View All"
    var actionColor: Color = Theme.accentBright
    var action: (() -> Void)?

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: titleSize, weight: .black))
                .foregroundStyle(.white)
            Spacer()
            if let action {
                Button(actionTitle, action: action)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(actionColor)
            }
        }
        .padding(.horizontal, 16)
    }
}

struct PageDots: View {
    let count: Int
    let index: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<max(count, 1), id: \.self) { i in
                Capsule()
                    .fill(i == index ? Theme.accent : Color(white: 0.32))
                    .frame(width: i == index ? 18 : 6, height: 6)
            }
        }
    }
}

struct CoverImage: View {
    let name: String
    var url: URL? = nil
    var showLoading: Bool = true

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        Image(name).resizable().scaledToFill()
                    case .empty:
                        if showLoading {
                            ZStack {
                                Color(white: 0.12)
                                ProgressView().tint(Theme.accent)
                            }
                        } else {
                            Color.clear
                        }
                    @unknown default:
                        Image(name).resizable().scaledToFill()
                    }
                }
            } else {
                Image(name)
                    .resizable()
                    .scaledToFill()
            }
        }
    }
}

/// Team + tournament logos as a match poster when CrickDB has no thumbnail.
struct LogoMatchBackdrop: View {
    var homeLogo: URL?
    var awayLogo: URL?
    var homeCode: String
    var awayCode: String

    var body: some View {
        GeometryReader { geo in
            let w = max(geo.size.width, 1)
            let h = max(geo.size.height, 1)
            let logoSize = min(w * 0.26, 108)
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 10 / 255, green: 12 / 255, blue: 18 / 255),
                        Color(red: 12 / 255, green: 22 / 255, blue: 32 / 255),
                        Color(red: 8 / 255, green: 8 / 255, blue: 12 / 255)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                HStack(spacing: 20) {
                    teamBadge(url: homeLogo, code: homeCode, size: logoSize)
                    Text("VS")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(2)
                        .foregroundStyle(Color.white.opacity(0.45))
                    teamBadge(url: awayLogo, code: awayCode, size: logoSize)
                }
                .offset(y: -h * 0.08)
            }
            .frame(width: w, height: h)
            .clipped()
        }
    }

    private func teamBadge(url: URL?, code: String, size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.06))
            Circle()
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit()
                    case .empty:
                        ProgressView().tint(Theme.accent).scaleEffect(0.7)
                    default:
                        Text(String(code.prefix(3)))
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
                .frame(width: size * 0.7, height: size * 0.7)
            } else {
                Text(String(code.prefix(3)))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .frame(width: size, height: size)
    }
}

struct MatchArtwork: View {
    let match: FeaturedMatch

    var body: some View {
        LogoMatchBackdrop(
            homeLogo: match.homeLogoURL,
            awayLogo: match.awayLogoURL,
            homeCode: match.homeCode,
            awayCode: match.awayCode
        )
    }
}
