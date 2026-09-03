import SwiftUI
import UIKit

struct HomeView: View {
    @Binding var tab: AppTab
    @Binding var showSearch: Bool
    @Binding var path: NavigationPath
    @EnvironmentObject private var store: CricketStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var page = 0
    @State private var heroAutoplayGeneration = 0
    @State private var heroInteractionPauseUntil: Date = .distantPast

    private var featured: [FeaturedMatch] { store.featuredMatches }

    private var activeFeatured: FeaturedMatch? {
        guard !featured.isEmpty else { return nil }
        return featured[min(page, featured.count - 1)]
    }

    /// Figma pill borders: IPL orange, ICC green, Asia blue, BBL green, CPL red, 100 purple
    private let chipBorders: [Color] = [
        Color(red: 1, green: 0.502, blue: 0),
        Color(red: 0.2, green: 0.698, blue: 0.302),
        Color(red: 0.2, green: 0.502, blue: 0.898),
        Color(red: 0.2, green: 0.8, blue: 0.4),
        Color(red: 0.898, green: 0.2, blue: 0.302),
        Color(red: 0.502, green: 0.302, blue: 0.8)
    ]

    /// Home content rails — consistent typography & card sizing
    private enum HomeMetrics {
        static let sectionTitleSize: CGFloat = 17
        static let sectionActionSize: CGFloat = 13
        static let sectionTopPadding: CGFloat = 20
        static let sectionBottomPadding: CGFloat = 16
        static let railSpacing: CGFloat = 12
        static let thumbWidth: CGFloat = 220
        static let thumbHeight: CGFloat = 124
        static let thumbRadius: CGFloat = 10
        static let cardTitleSize: CGFloat = 14
        static let cardMetaSize: CGFloat = 12
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                if store.isLoading && featured.isEmpty {
                    ProgressView()
                        .tint(Theme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                }

                if let error = store.errorMessage, featured.isEmpty {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.muted)
                        .padding(.horizontal, 16)
                }

                heroCarousel

                if !store.tournamentCards.isEmpty {
                    popularChipsSection
                }

                if !store.highlightClips.isEmpty {
                    topHighlightsSection
                }

                ForEach(Array(store.tournamentHighlightRails.enumerated()), id: \.element.id) { index, rail in
                    highlightRail(
                        title: rail.name,
                        clips: rail.clips,
                        background: index.isMultiple(of: 2) ? Theme.background : Theme.backgroundAlt,
                        onTitleTap: {
                            path.append(AppNavigationRoute.tournament(rail.id))
                        }
                    )
                }
            }
            .padding(.bottom, 24)
        }
        .refreshable { await store.refresh(force: true) }
        .background(
            LinearGradient(
                colors: [Theme.background, Theme.backgroundAlt],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            AppHeader(onAvatar: { tab = .profile })
                .background(Theme.background)
        }
        .navigationDestination(for: AppNavigationRoute.self) { route in
            switch route {
            case .match(let id):
                if let match = store.featuredMatch(id: id) {
                    MatchCenterView(match: match, tab: $tab, showSearch: $showSearch)
                } else {
                    Text("Match unavailable")
                        .foregroundStyle(Theme.muted)
                }
            case .tournament(let id):
                TournamentDetailView(tournamentId: id, tab: $tab, showSearch: $showSearch)
            }
        }
        .onChange(of: featured.count) { _, _ in
            if page >= featured.count { page = 0 }
            restartHeroAutoplay()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                restartHeroAutoplay()
            }
        }
    }

    // MARK: - Hero autoplay (5.5s static slides · 12s highlight preview)

    private enum HeroCarouselTiming {
        static let advanceInterval: Duration = .seconds(5.5)
        static let highlightPreviewInterval: Duration = .seconds(12)
        static let pauseAfterSwipe: TimeInterval = 8
        static let transition: Animation = .easeInOut(duration: 0.45)
    }

    private func restartHeroAutoplay() {
        heroAutoplayGeneration += 1
    }

    private func heroAutoplayLoop(generation: Int) async {
        while !Task.isCancelled {
            let sleepDuration = await MainActor.run { () -> Duration in
                guard generation == heroAutoplayGeneration else { return HeroCarouselTiming.advanceInterval }
                let current = featured.isEmpty ? nil : featured[min(page, featured.count - 1)]
                return current?.isMatchHighlightSlide == true
                    ? HeroCarouselTiming.highlightPreviewInterval
                    : HeroCarouselTiming.advanceInterval
            }

            try? await Task.sleep(for: sleepDuration)
            guard !Task.isCancelled else { return }

            let shouldAdvance = await MainActor.run { () -> Bool in
                guard generation == heroAutoplayGeneration else { return false }
                guard scenePhase == .active else { return false }
                guard featured.count > 1 else { return false }
                guard Date() >= heroInteractionPauseUntil else { return false }
                return true
            }
            guard shouldAdvance else { continue }

            await MainActor.run {
                withAnimation(HeroCarouselTiming.transition) {
                    page = (page + 1) % featured.count
                }
            }
        }
    }

    private func pauseHeroAutoplay(afterSwipe: Bool = false) {
        if afterSwipe {
            heroInteractionPauseUntil = Date().addingTimeInterval(HeroCarouselTiming.pauseAfterSwipe)
        } else {
            heroInteractionPauseUntil = .distantFuture
        }
    }

    // MARK: - Hero carousel

    private let heroCardHeight: CGFloat = 488
    private let heroSlideHeight: CGFloat = 548

    private var heroCarousel: some View {
        VStack(spacing: 0) {
            if featured.isEmpty {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Theme.card)
                    .frame(height: heroCardHeight)
                    .overlay {
                        Text("No featured matches")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Theme.muted)
                    }
            } else {
                GeometryReader { geo in
                    let cardWidth = min(geo.size.width, 358)

                    TabView(selection: $page) {
                        ForEach(Array(featured.enumerated()), id: \.element.heroSlideKey) { index, match in
                            VStack(spacing: 0) {
                                FigmaHeroCard(match: match, isActive: page == index) {
                                    path.append(AppNavigationRoute.match(match.id))
                                }
                                .frame(width: cardWidth, height: heroCardHeight)

                                FigmaHeroSlideCTA(match: match) {
                                    path.append(AppNavigationRoute.match(match.id))
                                }
                                .padding(.top, 10)
                            }
                            .frame(width: cardWidth)
                            .frame(maxWidth: .infinity)
                            .id(match.heroSlideKey)
                            .frame(width: geo.size.width, height: heroSlideHeight)
                            .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .contentMargins(.horizontal, 0, for: .scrollContent)
                    .frame(width: geo.size.width, height: heroSlideHeight)
                    .clipped()
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 8)
                            .onChanged { _ in pauseHeroAutoplay() }
                            .onEnded { _ in pauseHeroAutoplay(afterSwipe: true) }
                    )
                    .task(id: heroAutoplayGeneration) {
                        await heroAutoplayLoop(generation: heroAutoplayGeneration)
                    }
                }
                .frame(height: heroSlideHeight)
                .overlay {
                    if store.isLoading {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color.black.opacity(0.25))
                            .frame(maxWidth: 358)
                            .frame(height: heroCardHeight)
                            .overlay {
                                ProgressView()
                                    .tint(Theme.accent)
                            }
                            .allowsHitTesting(false)
                    }
                }

                if featured.count > 1 {
                    FigmaPageDots(count: featured.count, index: page)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear { restartHeroAutoplay() }
    }

    // MARK: - Popular tournament chips

    private var popularChipsSection: some View {
        VStack(alignment: .leading, spacing: HomeMetrics.railSpacing) {
            homeSectionHeader(title: "Popular Tournaments") {
                tab = .schedule
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(store.tournamentCards.enumerated()), id: \.element.id) { index, tile in
                        let border = chipBorders[index % chipBorders.count]
                        Button {
                            openTournament(tile)
                        } label: {
                            Text(chipLabel(tile.title))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .padding(.horizontal, 14)
                                .frame(height: 36)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Theme.card)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .stroke(border, lineWidth: 1.5)
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.top, HomeMetrics.sectionTopPadding)
        .padding(.bottom, HomeMetrics.sectionBottomPadding)
        .background(Theme.background)
    }

    private func chipLabel(_ title: String) -> String {
        let parts = title.split(separator: " ")
        if let last = parts.last, last.allSatisfy(\.isNumber), parts.count > 1 {
            return parts.dropLast().map { String($0.prefix(1)) }.joined().uppercased()
        }
        return String(title.prefix(8))
    }

    // MARK: - Top Highlights

    private var topHighlightsSection: some View {
        highlightRail(
            title: "Top Highlights",
            clips: store.highlightClips,
            background: Theme.backgroundAlt
        )
    }

    private func homeSectionHeader(title: String, action: (() -> Void)? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: HomeMetrics.sectionTitleSize, weight: .bold))
                .foregroundStyle(.white)
            Spacer(minLength: 8)
            if let action {
                Button("View All", action: action)
                    .font(.system(size: HomeMetrics.sectionActionSize, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
        }
        .padding(.horizontal, 16)
    }

    private func highlightRail(
        title: String,
        clips: [HighlightClip],
        background: Color,
        onTitleTap: (() -> Void)? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: HomeMetrics.railSpacing) {
            homeSectionHeader(title: title, action: onTitleTap)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(clips) { clip in
                        MediaThumbCard(
                            title: clip.cardTitle,
                            subtitle: clip.cardSubtitle,
                            duration: clip.duration,
                            imageName: clip.imageName,
                            imageURL: nil,
                            videoURL: clip.videoURL,
                            thumbWidth: HomeMetrics.thumbWidth,
                            thumbHeight: HomeMetrics.thumbHeight,
                            thumbRadius: HomeMetrics.thumbRadius
                        ) {
                            openHighlight(clip)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.top, HomeMetrics.sectionTopPadding)
        .padding(.bottom, HomeMetrics.sectionBottomPadding)
        .background(background)
    }

    private func openHighlight(_ clip: HighlightClip) {
        if let matchId = clip.matchId {
            path.append(AppNavigationRoute.match(matchId))
            return
        }
        if let url = clip.videoURL {
            UIApplication.shared.open(url)
        }
    }

    private func openTournament(_ tile: LeagueTile) {
        if let rail = store.tournamentHighlightRails.first(where: { $0.id == tile.id }),
           let first = rail.clips.first {
            openHighlight(first)
            return
        }
        path.append(AppNavigationRoute.tournament(tile.id))
    }
}

// MARK: - Media thumb card (16:9 highlight rail)

struct MediaThumbCard: View {
    let title: String
    var subtitle: String = ""
    var duration: String = ""
    var imageName: String = "HeroStadiumNight"
    var imageURL: URL? = nil
    var videoURL: URL? = nil
    var thumbWidth: CGFloat = 220
    var thumbHeight: CGFloat = 124
    var thumbRadius: CGFloat = 10
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .topLeading) {
                    Group {
                        if videoURL != nil {
                            HeroVideoFrameBackground(url: videoURL) {
                                CoverImage(name: imageName, url: imageURL)
                            }
                        } else {
                            CoverImage(name: imageName, url: imageURL)
                        }
                    }
                    .frame(width: thumbWidth, height: thumbHeight)
                    .clipped()

                    LinearGradient(
                        colors: [.clear, .black.opacity(0.45)],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                    .frame(width: thumbWidth, height: thumbHeight)

                    if !duration.isEmpty {
                        Text(duration)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(.black.opacity(0.72)))
                            .padding(8)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    }

                    Image(systemName: "play.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(.black.opacity(0.55)))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .padding(10)
                }
                .frame(width: thumbWidth, height: thumbHeight)
                .clipShape(RoundedRectangle(cornerRadius: thumbRadius, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.mutedSoft)
                            .lineLimit(1)
                    }
                }
                .frame(width: thumbWidth, alignment: .leading)
            }
            .frame(width: thumbWidth)
        }
        .buttonStyle(.plain)
    }
}

struct FigmaHeroCard: View {
    let match: FeaturedMatch
    var isActive: Bool = false
    var onOpen: () -> Void

    private enum Typography {
        static let leagueSize: CGFloat = 14
        static let detailSize: CGFloat = 14
    }

    private let cardHeight: CGFloat = 488
    private let thumbHeight: CGFloat = 350
    private let textHeight: CGFloat = 138
    private let highlightTextHeight: CGFloat = 138

    var body: some View {
        if match.isMatchHighlightSlide {
            highlightCard
        } else {
            standardCard
        }
    }

    private var standardCard: some View {
        VStack(spacing: 0) {
            FigmaHeroThumbnail(match: match)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(height: thumbHeight)
                .clipped()

            standardTextBlock
        }
        .frame(maxWidth: 358)
        .frame(height: cardHeight)
        .background(Color(red: 8 / 255, green: 9 / 255, blue: 12 / 255))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onTapGesture(perform: onOpen)
    }

    private var highlightCard: some View {
        VStack(spacing: 0) {
            FigmaHeroHighlightThumbnail(match: match, isActive: isActive)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(height: thumbHeight)
                .clipped()

            highlightTextBlock
        }
        .frame(maxWidth: 358)
        .frame(height: cardHeight)
        .background(Color(red: 8 / 255, green: 9 / 255, blue: 12 / 255))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onTapGesture(perform: onOpen)
    }

    private var highlightTextBlock: some View {
        VStack(spacing: 0) {
            stackedTeamNames(vsColor: HeroHighlightStyle.accent)

            HeroHighlightMetaBar(meta: highlightMetaLine)
                .padding(.top, 10)

            if !highlightResultLabel.isEmpty {
                Text(highlightResultLabel)
                    .font(.system(size: Typography.detailSize, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 6)
            } else if !scoreSummaryLabel.isEmpty {
                Text(scoreSummaryLabel)
                    .font(.system(size: Typography.detailSize, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: highlightTextHeight, alignment: .top)
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var highlightMetaLine: String {
        var parts: [String] = []
        if let seq = match.matchSeq {
            parts.append("Match \(seq)")
        }
        parts.append("\(shortLeagueName(match.league)) \(match.year)")
        return parts.joined(separator: ", ")
    }

    private func displayTeamName(_ name: String, code: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed.uppercased()
        }
        return code.uppercased()
    }

    private func stackedTeamNames(vsColor: Color) -> some View {
        VStack(spacing: 0) {
            Text(displayTeamName(match.home, code: match.homeCode))
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.65)
                .frame(maxWidth: .infinity)

            Text("vs")
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(vsColor)
                .padding(.vertical, 1)

            Text(displayTeamName(match.away, code: match.awayCode))
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.65)
                .frame(maxWidth: .infinity)
        }
    }

    private var highlightResultLabel: String {
        HeroText.sanitize(match.statusLine)
    }

    private var scoreSummaryLabel: String {
        let home = match.homeInningsScore.trimmingCharacters(in: .whitespacesAndNewlines)
        let away = match.awayInningsScore.trimmingCharacters(in: .whitespacesAndNewlines)
        if home.isEmpty && away.isEmpty { return "" }
        if home.isEmpty { return away }
        if away.isEmpty { return home }
        return "\(home)  •  \(away)"
    }

    private var standardTextBlock: some View {
        VStack(spacing: 0) {
            stackedTeamNames(vsColor: Theme.accent)

            Text(heroLeagueLabel)
                .font(.system(size: Typography.leagueSize, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)

            if !heroDetailLabel.isEmpty {
                Text(heroDetailLabel)
                    .font(.system(size: Typography.detailSize, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: textHeight, alignment: .top)
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .clipped()
    }

    private var heroLeagueLabel: String {
        let short = shortLeagueName(match.league)
        if let seq = match.matchSeq {
            return "\(short) \(match.year)  •  Match \(seq)"
        }
        return "\(short) \(match.year)"
    }

    private var heroDetailLabel: String {
        var parts: [String] = []
        if let stage = stageLabel {
            parts.append(stage)
        }
        let subtitle = HeroText.sanitize(match.heroSubtitleLine)
        if !subtitle.isEmpty {
            parts.append(subtitle)
        }
        return parts.joined(separator: "  •  ")
    }

    private var stageLabel: String? {
        let stage = match.subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stage.isEmpty, stage.lowercased() != "t20", stage.lowercased() != "odi" else { return nil }
        return stage
    }

    private func shortLeagueName(_ name: String) -> String {
        let words = name.split(separator: " ")
        if words.count <= 3 { return name }
        return words.prefix(3).joined(separator: " ")
    }
}

private enum HeroHighlightStyle {
    static let accent = Color(red: 0.96, green: 0.58, blue: 0.08)
    static let barFill = Color(red: 10 / 255, green: 18 / 255, blue: 42 / 255)
}

private struct HeroHighlightMetaBar: View {
    let meta: String

    var body: some View {
        HStack(spacing: 8) {
            Text("HIGHLIGHTS")
                .font(.system(size: 11, weight: .bold))
                .tracking(0.4)
                .foregroundStyle(.white)

            Rectangle()
                .fill(Color.white.opacity(0.35))
                .frame(width: 1, height: 14)

            Text(meta.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(0.3)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(HeroHighlightStyle.barFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(HeroHighlightStyle.accent, lineWidth: 1.5)
        )
    }
}

struct FigmaHeroSlideCTA: View {
    let match: FeaturedMatch
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Spacer(minLength: 0)

                if showsPlayIcon {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.22))
                            .frame(width: 34, height: 34)
                        Image(systemName: "play.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .offset(x: 1.5)
                    }
                }

                Text(match.heroActionLabel)
                    .font(.system(size: 15, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(.white)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(fillColor)
            )
        }
        .buttonStyle(.plain)
    }

    private var showsPlayIcon: Bool {
        match.isMatchHighlightSlide || match.isLive
    }

    private var fillColor: Color {
        if match.isMatchHighlightSlide {
            return Theme.accent
        }
        switch match.heroState {
        case .live:
            return Color(red: 0.94, green: 0.36, blue: 0.05)
        case .upcoming:
            return Color(red: 0.82, green: 0.52, blue: 0.08)
        case .completed:
            return Color(red: 0.14, green: 0.62, blue: 0.38)
        }
    }
}

struct FigmaPageDots: View {
    let count: Int
    let index: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<max(count, 1), id: \.self) { i in
                Capsule()
                    .fill(i == index ? Theme.accent : Color.white.opacity(0.55))
                    .frame(width: i == index ? 20 : 6, height: 6)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 20)
        .padding(.top, 6)
    }
}

// MARK: - Hero palette + ambient glow

private enum HeroMatchPalette {
    enum Side { case home, away }

    static func home(for match: FeaturedMatch) -> Color {
        Color.fromHex(match.homeThemeColor, fallback: fallback(for: match.homeCode, side: .home))
    }

    static func away(for match: FeaturedMatch) -> Color {
        Color.fromHex(match.awayThemeColor, fallback: fallback(for: match.awayCode, side: .away))
    }

    static func fallback(for code: String, side: Side) -> Color {
        let key = code.uppercased()
        if key.contains("MSD") { return Color(red: 0 / 255, green: 75 / 255, blue: 141 / 255) }
        if key.contains("KP") { return Color(red: 181 / 255, green: 84 / 255, blue: 24 / 255) }
        if key.contains("KK") { return Color(red: 128 / 255, green: 18 / 255, blue: 34 / 255) }
        if key.contains("RA") { return Color(red: 20 / 255, green: 110 / 255, blue: 72 / 255) }
        return side == .home
            ? Color(red: 13 / 255, green: 43 / 255, blue: 110 / 255)
            : Color(red: 59 / 255, green: 26 / 255, blue: 0)
    }
}

private struct HeroSlideLinearAura: View {
    let match: FeaturedMatch
    var extendsIntoHeader: Bool = false

    private var homeColor: Color { HeroMatchPalette.home(for: match) }
    private var awayColor: Color { HeroMatchPalette.away(for: match) }
    private let thumbHeight: CGFloat = 350

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                LinearGradient(
                    colors: [homeColor, awayColor],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .opacity(0.26)

                LinearGradient(
                    colors: extendsIntoHeader
                        ? [
                            Theme.background.opacity(0.2),
                            .clear,
                            .clear,
                            Theme.background.opacity(0.88)
                        ]
                        : [
                            Theme.background.opacity(0.55),
                            .clear,
                            Theme.background.opacity(0.15),
                            Theme.background.opacity(0.92)
                        ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .frame(height: extendsIntoHeader ? thumbHeight + 44 : thumbHeight)

            if !extendsIntoHeader {
                Spacer(minLength: 0)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Hero thumbnail (team gradient + logos + validated poster)

private enum HeroText {
    static func sanitize(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = trimmed.unicodeScalars.filter { scalar in
            if scalar.value == 0xFFFD { return false }
            if CharacterSet.controlCharacters.contains(scalar) { return false }
            return scalar.isASCII || CharacterSet.alphanumerics.contains(scalar)
                || CharacterSet.whitespaces.contains(scalar)
                || "•-–—/.,()'\"".unicodeScalars.contains(scalar)
        }
        return String(String.UnicodeScalarView(filtered))
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct FigmaHeroThumbnail: View {
    let match: FeaturedMatch

    private var homeColor: Color { HeroMatchPalette.home(for: match) }
    private var awayColor: Color { HeroMatchPalette.away(for: match) }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [homeColor, awayColor],
                startPoint: .leading,
                endPoint: .trailing
            )

            HStack(spacing: 0) {
                HeroTeamMark(url: match.homeLogoURL, code: match.homeCode)
                HeroTeamMark(url: match.awayLogoURL, code: match.awayCode)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 24)

            HeroRemoteThumbnail(url: match.imageURL)

            LinearGradient(
                colors: [
                    Color.black.opacity(0.12),
                    Color.clear,
                    Color(red: 8 / 255, green: 9 / 255, blue: 12 / 255).opacity(0.88)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .clipped()
    }
}

private struct FigmaHeroHighlightThumbnail: View {
    let match: FeaturedMatch
    let isActive: Bool

    private var homeColor: Color { HeroMatchPalette.home(for: match) }
    private var awayColor: Color { HeroMatchPalette.away(for: match) }

    var body: some View {
        ZStack {
            if match.videoURL != nil {
                HeroHighlightPreviewVideo(url: match.videoURL, isActive: isActive) {
                    LinearGradient(colors: [homeColor, awayColor], startPoint: .leading, endPoint: .trailing)
                }
            } else {
                HeroVideoFrameBackground(url: match.videoURL) {
                    LinearGradient(colors: [homeColor, awayColor], startPoint: .leading, endPoint: .trailing)
                }
            }

            LinearGradient(
                colors: [
                    Color.black.opacity(0.15),
                    Color.clear,
                    Color(red: 8 / 255, green: 9 / 255, blue: 12 / 255).opacity(0.75)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }
}

private struct HeroHighlightPreviewVideo<Fallback: View>: View {
    let url: URL?
    let isActive: Bool
    @ViewBuilder var fallback: () -> Fallback
    @StateObject private var playback: StreamPlayback

    init(url: URL?, isActive: Bool, @ViewBuilder fallback: @escaping () -> Fallback) {
        self.url = url
        self.isActive = isActive
        self.fallback = fallback
        _playback = StateObject(
            wrappedValue: StreamPlayback(url: url, autoplay: false, looping: true, muted: true)
        )
    }

    var body: some View {
        ZStack {
            if playback.hasMedia, playback.isReady || playback.isPlaying {
                StreamVideoLayer(player: playback.player, videoGravity: .resizeAspectFill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                fallback()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .clipped()
        .onAppear { syncPlayback() }
        .onChange(of: isActive) { _, _ in syncPlayback() }
        .onChange(of: url) { _, _ in
            playback.replace(url: url, autoplay: isActive)
        }
        .onDisappear { playback.pause() }
    }

    private func syncPlayback() {
        guard playback.hasMedia else { return }
        if isActive {
            playback.play()
        } else {
            playback.pause()
            playback.seek(fraction: 0)
        }
    }
}

private struct HeroTeamMark: View {
    let url: URL?
    let code: String

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width * 0.78, geo.size.height * 0.82, 132)
            ZStack {
                if let url {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        default:
                            fallbackMark
                        }
                    }
                } else {
                    fallbackMark
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.22), lineWidth: 1.5)
            )
            .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private var fallbackMark: some View {
        Circle()
            .fill(Color.white.opacity(0.08))
            .overlay {
                Text(String(code.prefix(3)).uppercased())
                    .font(.system(size: 22, weight: .black))
                    .foregroundStyle(.white.opacity(0.85))
            }
    }
}

private struct HeroRemoteThumbnail: View {
    let url: URL?

    @State private var image: UIImage?

    /// Admin placeholder posters are tiny (~10 KB) and render as empty glyph boxes.
    private let minValidBytes = 20_000

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .opacity(0.72)
            }
        }
        .task(id: url) {
            await load()
        }
    }

    private func load() async {
        image = nil
        guard let url else { return }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return }
            guard data.count >= minValidBytes, let uiImage = UIImage(data: data) else { return }
            await MainActor.run { image = uiImage }
        } catch {
            await MainActor.run { image = nil }
        }
    }
}
