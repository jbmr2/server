import SwiftUI

struct MatchCenterView: View {
    let match: FeaturedMatch
    @Binding var tab: AppTab
    @Binding var showSearch: Bool
    var embedsInTab: Bool = false

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: CricketStore
    @EnvironmentObject private var reelStore: ReelStudioStore
    @EnvironmentObject private var downloadLibrary: DownloadLibraryStore
    @EnvironmentObject private var userLibrary: UserLibraryStore
    @State private var section: CenterSection = .scorecard
    @StateObject private var playback: StreamPlayback
    @StateObject private var detailStore = MatchDetailStore()
    @State private var selectedOver = 1
    @State private var selectedInning = 1
    @State private var showShare = false
    @State private var showFullscreen = false
    @State private var currentPlayURL: URL?

    init(match: FeaturedMatch, tab: Binding<AppTab>, showSearch: Binding<Bool>, embedsInTab: Bool = false) {
        self.match = match
        self._tab = tab
        self._showSearch = showSearch
        self.embedsInTab = embedsInTab
        _playback = StateObject(wrappedValue: StreamPlayback(url: match.videoURL, autoplay: true, looping: true))
        _currentPlayURL = State(initialValue: match.videoURL)
    }

    enum CenterSection: String, CaseIterable, Identifiable {
        case ballByBall = "Ball by Ball"
        case scorecard = "Scorecard"
        case commentary = "Commentary"
        case stats = "Stats"
        case squads = "Squads"
        case pointsTable = "Points Table"
        var id: String { rawValue }
    }

    private var detail: MatchDetail? { detailStore.detail }

    private var activeInning: MatchInningsDetail? {
        guard let detail else { return nil }
        return detail.innings.first(where: { $0.number == selectedInning }) ?? detail.innings.last
    }

    private var isMatchCompleted: Bool {
        if match.badge == "RESULT" || match.heroState == .completed { return true }
        let s = (detail?.status ?? "").lowercased()
        return ["completed", "finished", "abandoned", "cancelled"].contains(s)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                player
                if detailStore.isLoading && detail == nil {
                    ProgressView()
                        .tint(Theme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                } else if let error = detailStore.errorMessage, detail == nil {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                sectionTabs
                Group {
                    switch section {
                    case .ballByBall: ballByBallBlock
                    case .scorecard: scorecardBlock
                    case .commentary: commentaryBlock
                    case .stats: statsBlock
                    case .squads: squadsBlock
                    case .pointsTable: pointsTableBlock
                    }
                }
                .padding(.bottom, 28)
            }
        }
        .refreshable {
            await detailStore.load(matchId: match.id, matchSeq: match.matchSeq, feed: store.cachedFeed)
        }
        .background(Theme.background.ignoresSafeArea())
        .safeAreaInset(edge: .top, spacing: 0) {
            matchHeader
                .background(Theme.background)
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(!embedsInTab)
        .task(id: match.id) {
            userLibrary.recordWatch(matchId: match.id, title: match.vsLabel)
            await detailStore.load(matchId: match.id, matchSeq: match.matchSeq, feed: store.cachedFeed)
            if let last = detailStore.detail?.innings.last?.number {
                selectedInning = last
            }
            if let lastOver = detailStore.detail?.overs.last?.number {
                selectedOver = lastOver
            }
            let live = match.isLive || MatchDetailStore.isLiveMatchStatus(detailStore.detail?.status ?? "")
            detailStore.startLivePolling(matchId: match.id, isLive: live) { store.cachedFeed }
        }
        .onDisappear {
            detailStore.stopLivePolling()
        }
        .sheet(isPresented: $showShare) {
            ShareSheet(items: shareItems)
        }
        .fullScreenCover(item: Binding<IdentifiedURL?>(
            get: {
                guard showFullscreen else { return nil }
                return (currentPlayURL ?? match.videoURL).map { IdentifiedURL(url: $0) }
            },
            set: { (value: IdentifiedURL?) in
                showFullscreen = value != nil
            }
        )) { item in
            FullscreenPlayerView(url: item.url, title: match.vsLabel)
        }
        .overlay(alignment: .top) {
            if let toast = downloadLibrary.toastMessage {
                toastBanner(toast) { downloadLibrary.clearToast() }
                    .padding(.top, 56)
            } else if let toast = reelStore.toastMessage {
                toastBanner(toast) { reelStore.clearToast() }
                    .padding(.top, 56)
            } else if let toast = userLibrary.toastMessage {
                toastBanner(toast) { userLibrary.clearToast() }
                    .padding(.top, 56)
            }
        }
    }

    private var shareItems: [Any] {
        let webURL = MatchDeepLink.matchURL(matchId: match.id)
        let appURL = MatchDeepLink.appOpenURL(matchId: match.id)
        let message = MatchDeepLink.shareMessage(
            title: "Watch \(match.vsLabel) on JBMR Sports",
            url: webURL
        )
        return [message, appURL]
    }

    private func toastBanner(_ text: String, onClear: @escaping () -> Void) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Capsule().fill(Theme.accent.opacity(0.95)))
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    onClear()
                }
            }
    }

    // MARK: - Header

    private var matchHeader: some View {
        HStack(spacing: 8) {
            Button {
                if embedsInTab {
                    tab = .home
                } else {
                    dismiss()
                }
            } label: {
                BrandLogo(size: 18)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            Button {
                showShare = true
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Share match")

            UserAvatarButton { tab = .profile }
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(Theme.background)
    }

    // MARK: - Player

    private var isCurrentlyLive: Bool {
        if match.isLive { return true }
        return (detail?.status ?? "").lowercased() == "live"
    }

    private var playerScoreLabel: String {
        if let score = detail?.scoreLabel, !score.isEmpty { return score }
        if !match.scoreLabel.isEmpty { return match.scoreLabel }
        return match.vsLabel
    }

    private var playerStatusLabel: String {
        if isCurrentlyLive {
            if let rr = detail?.runRate, !rr.isEmpty, rr != "—" {
                return "RR \(rr)"
            }
            return "LIVE"
        }
        if isMatchCompleted {
            let result = detail?.innings.last?.total ?? match.statusLine
            return result.isEmpty ? "Completed" : result
        }
        return match.timeLabel
    }

    private var playerHeight: CGFloat {
        max(UIScreen.main.bounds.width * 9 / 16, 252)
    }

    private var player: some View {
        VStack(spacing: 0) {
            ZStack {
                StreamVideoLayer(player: playback.player, videoGravity: .resizeAspectFill)
                    .frame(height: playerHeight)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .allowsHitTesting(false)

                if !playback.isPlaying && playback.progress < 0.02 {
                    MatchArtwork(match: match)
                        .frame(height: playerHeight)
                        .frame(maxWidth: .infinity)
                        .clipped()
                        .allowsHitTesting(false)
                }

                LinearGradient(
                    colors: [.black.opacity(0.35), .clear, .black.opacity(0.75)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)

                VStack(spacing: 0) {
                    HStack {
                        if isCurrentlyLive {
                            HStack(spacing: 5) {
                                Circle().fill(.white).frame(width: 6, height: 6)
                                Text("LIVE")
                                    .font(.system(size: 11, weight: .heavy))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Theme.liveRed))
                        }
                        Spacer()
                        HStack(spacing: 8) {
                            Text("\(playback.currentLabel) / \(playback.durationLabel)")
                                .font(.system(size: 10, weight: .heavy))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(.black.opacity(0.5)))
                            Image(systemName: "eye.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(.black.opacity(0.45)))
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 10)

                    Spacer(minLength: 0)

                    HStack(spacing: 10) {
                        Button { playback.toggle() } label: {
                            Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        }
                        .buttonStyle(.plain)

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.25)).frame(height: 3)
                                Capsule()
                                    .fill(Theme.accent)
                                    .frame(width: geo.size.width * playback.progress, height: 3)
                            }
                            .frame(maxHeight: .infinity, alignment: .center)
                            .contentShape(Rectangle())
                            .highPriorityGesture(
                                DragGesture(minimumDistance: 0).onChanged { value in
                                    let f = min(max(value.location.x / max(geo.size.width, 1), 0), 1)
                                    playback.seek(fraction: f)
                                }
                            )
                        }
                        .frame(height: 18)
                        Text("1080p")
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 4).fill(.white.opacity(0.15)))
                        Button {
                            if currentPlayURL != nil || match.videoURL != nil {
                                showFullscreen = true
                            }
                        } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                        }
                        .buttonStyle(.plain)
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.001))
                }
            }
            .frame(height: playerHeight)

            matchInfoBar
        }
        .onDisappear { playback.pause() }
    }

    private var matchInfoBar: some View {
        HStack(spacing: 10) {
            Text(playerScoreLabel)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 8)

            Button {
                _ = userLibrary.toggleWatchlist(matchId: match.id, title: match.vsLabel)
            } label: {
                Image(systemName: userLibrary.isWatchlisted(matchId: match.id) ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(userLibrary.isWatchlisted(matchId: match.id) ? Theme.accent : Theme.muted)
            }
            .buttonStyle(.plain)

            if isCurrentlyLive {
                HStack(spacing: 5) {
                    Circle().fill(Theme.liveRed).frame(width: 6, height: 6)
                    Text(playerStatusLabel)
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(Theme.liveRed)
                }
            } else {
                Text(playerStatusLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.card)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Theme.border)
                .frame(height: 1)
        }
    }

    // MARK: - Tabs

    private var sectionTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(CenterSection.allCases) { item in
                    Button {
                        section = item
                    } label: {
                        VStack(spacing: 8) {
                            Text(item.rawValue)
                                .font(.system(size: 13, weight: section == item ? .bold : .medium))
                                .foregroundStyle(section == item ? Theme.accent : Theme.muted)
                                .padding(.horizontal, 12)
                            Rectangle()
                                .fill(section == item ? Theme.accent : Color.clear)
                                .frame(height: 2.5)
                        }
                        .padding(.top, 12)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
        }
    }

    // MARK: - Scorecard

    @ViewBuilder
    private var scorecardBlock: some View {
        if (detail?.innings.isEmpty ?? true), !isMatchCompleted {
            Text("Match starts soon — scorecard will appear when play begins")
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 16)
                .padding(.top, 12)
        } else {
            scorecardContent
        }
    }

    private var scorecardContent: some View {
        let inning = activeInning
        let battingTitle = "\((inning?.teamName ?? match.home).uppercased()) BATTING"
        let bowlingSide = inning.map { inn in
            inn.teamShort == (detail?.homeShort ?? match.homeCode)
                ? (detail?.awayName ?? match.away)
                : (detail?.homeName ?? match.home)
        } ?? match.away

        return VStack(alignment: .leading, spacing: 14) {
            inningsToggle
            if !isMatchCompleted {
                batsmenStrip
            }
            inningsSummary
            battingTable(
                title: battingTitle,
                rows: inning?.batting ?? [],
                extras: inning?.extras ?? "—",
                total: inning?.total ?? "—"
            )
            bowlingTable(
                title: "\(bowlingSide.uppercased()) BOWLING",
                rows: inning?.bowling ?? []
            )
        }
        .padding(.top, 12)
    }

    private var inningsToggle: some View {
        let options = detail?.innings.map(\.number) ?? [1, 2]
        return HStack(spacing: 8) {
            ForEach(options, id: \.self) { inn in
                Button { selectedInning = inn } label: {
                    Text("INN \(inn)")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            Capsule().fill(selectedInning == inn ? Theme.accent : Color(white: 0.16))
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
    }

    private var inningsSummary: some View {
        let label = activeInning.map { "INN \($0.number)" } ?? "INN \(selectedInning)"
        let text = activeInning?.summaryLabel
            ?? detail?.tossLine
            ?? "\(match.awayCode) — loading…"

        return HStack {
            Text(label)
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(Theme.accent)
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.muted)
                .lineLimit(2)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(white: 0.1), in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 16)
    }

    private var batsmenStrip: some View {
        let isCompleted: Bool = {
            let s = (detail?.status ?? "").lowercased()
            return !match.isLive && (s == "completed" || s == "finished" || match.badge == "RESULT")
        }()

        return HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(detail?.strikerLabel ?? "—")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(detail?.nonStrikerLabel ?? "—")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isCompleted {
                VStack(alignment: .trailing, spacing: 4) {
                    Text("RESULT")
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(0.6)
                        .foregroundStyle(Theme.muted)
                    Text(match.statusLine.isEmpty ? (detail?.scoreLabel ?? "Completed") : match.statusLine)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(2)
                        .frame(maxWidth: 150, alignment: .trailing)
                }
            } else {
                VStack(alignment: .trailing, spacing: 6) {
                    Text("THIS OVER")
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(0.6)
                        .foregroundStyle(Theme.muted)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 5) {
                            let balls = detail?.thisOver ?? []
                            if balls.isEmpty {
                                Text("—")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Theme.muted)
                            } else {
                                ForEach(balls) { ball in
                                    OverBallChip(ball: ball)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: 160, alignment: .trailing)
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func battingTable(title: String, rows: [BatterRow], extras: String, total: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 12, weight: .heavy))
                .tracking(0.4)
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                HStack {
                    Text("Batsman").frame(maxWidth: .infinity, alignment: .leading)
                    Text("R").frame(width: 28)
                    Text("B").frame(width: 28)
                    Text("4s").frame(width: 28)
                    Text("6s").frame(width: 28)
                    Text("SR").frame(width: 44, alignment: .trailing)
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)

                ForEach(rows) { row in
                    Divider().overlay(Color.white.opacity(0.06))
                    BatterRowView(row: row)
                }

                Divider().overlay(Color.white.opacity(0.08))
                HStack {
                    Text("Extras")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                    Spacer()
                    Text(extras)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

                Divider().overlay(Color.white.opacity(0.08))
                HStack {
                    Text("Total")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(.white)
                    Spacer()
                    Text(total)
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(Theme.accent)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 16)
        }
    }

    private func bowlingTable(title: String, rows: [BowlerRow]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 12, weight: .heavy))
                .tracking(0.4)
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .padding(.top, 6)

            VStack(spacing: 0) {
                HStack {
                    Text("Bowler").frame(maxWidth: .infinity, alignment: .leading)
                    Text("O").frame(width: 32)
                    Text("M").frame(width: 24)
                    Text("R").frame(width: 28)
                    Text("W").frame(width: 24)
                    Text("ECO").frame(width: 40, alignment: .trailing)
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)

                ForEach(rows) { row in
                    Divider().overlay(Color.white.opacity(0.06))
                    BowlerRowView(row: row)
                }
            }
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Other sections

    private var ballByBallBlock: some View {
        let overs = detail?.overs ?? []
        let current = overs.first(where: { $0.number == selectedOver }) ?? overs.last

        return VStack(alignment: .leading, spacing: 14) {
            inningsToggle
            inningsSummary

            if overs.isEmpty {
                Text("Ball-by-ball not available yet")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 16)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(overs) { over in
                            Button {
                                selectedOver = over.number
                            } label: {
                                Text(over.title)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(selectedOver == over.number ? .black : .white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(
                                        Capsule().fill(selectedOver == over.number ? Theme.accent : Color(white: 0.16))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }

                if let current {
                    HStack {
                        Text("Deliveries (Over \(current.number))")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                        Spacer()
                        Text("\(current.bowler) to bowl")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.muted)
                    }
                    .padding(.horizontal, 16)

                    VStack(spacing: 10) {
                        ForEach(current.deliveries) { delivery in
                            BallDeliveryCard(
                                delivery: delivery,
                                isDownloaded: downloadLibrary.isBallDownloaded(id: delivery.id),
                                isDownloading: downloadLibrary.downloadingBallIds.contains(delivery.id),
                                isInReel: reelStore.contains(id: delivery.id),
                                onPlay: {
                                    if let url = downloadLibrary.playbackURL(for: delivery) {
                                        currentPlayURL = url
                                        playback.replace(url: url, autoplay: true)
                                        section = .ballByBall
                                    } else {
                                        downloadLibrary.toastMessage = "Is ball pe video nahi hai"
                                    }
                                },
                                onDownload: {
                                    guard let remote = delivery.videoURL else {
                                        downloadLibrary.toastMessage = "Is ball pe video nahi hai"
                                        return
                                    }
                                    Task {
                                        await downloadLibrary.downloadBall(
                                            id: delivery.id,
                                            remoteURL: remote,
                                            ballLabel: delivery.ballLabel,
                                            matchTitle: match.vsLabel
                                        )
                                    }
                                },
                                onAddToReel: { item in
                                    reelStore.toggle(delivery: item, matchTitle: match.vsLabel)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
        .padding(.top, 14)
    }

    private var commentaryBlock: some View {
        let items = detail?.commentary ?? []
        return VStack(spacing: 10) {
            if items.isEmpty {
                Text("No commentary yet")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
            } else {
                ForEach(items) { item in
                    CommentaryCard(item: item)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    private var statsBlock: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                StatCard(label: "\(match.homeCode) Run Rate", value: detail?.runRate ?? "—", accent: true)
                StatCard(label: "Target", value: detail?.target ?? "—", accent: false)
            }
            HStack(spacing: 12) {
                StatCard(label: "Boundaries", value: detail?.boundaries ?? "—", accent: false)
                StatCard(label: "Dot Balls", value: detail?.dotBalls ?? "—", accent: true)
            }
            if let toss = detail?.tossLine, !toss.isEmpty {
                Text(toss)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let venue = detail?.venue, !venue.isEmpty {
                Text(venue)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    @ViewBuilder
    private var squadsBlock: some View {
        let homePlayers = detail?.homeSquad ?? []
        let awayPlayers = detail?.awaySquad ?? []
        if homePlayers.isEmpty && awayPlayers.isEmpty {
            Text("Squads will appear when the match starts")
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 16)
                .padding(.top, 14)
        } else {
            squadsContent(homePlayers: homePlayers, awayPlayers: awayPlayers)
        }
    }

    private func squadsContent(homePlayers: [SquadPlayer], awayPlayers: [SquadPlayer]) -> some View {
        let homeLogo = detail?.homeLogoURL ?? match.homeLogoURL
        let awayLogo = detail?.awayLogoURL ?? match.awayLogoURL
        let rowCount = max(homePlayers.count, awayPlayers.count)

        return VStack(spacing: 12) {
            // Header: team logos left | right
            HStack(spacing: 10) {
                squadTeamHeader(
                    name: detail?.homeShort ?? match.homeCode,
                    fullName: detail?.homeName ?? match.home,
                    logo: homeLogo,
                    alignment: .leading
                )
                Text("VS")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Theme.muted)
                squadTeamHeader(
                    name: detail?.awayShort ?? match.awayCode,
                    fullName: detail?.awayName ?? match.away,
                    logo: awayLogo,
                    alignment: .trailing
                )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Theme.border, lineWidth: 1)
                    )
            )

            // Players left | right rows
            VStack(spacing: 0) {
                ForEach(0..<max(rowCount, 1), id: \.self) { index in
                    HStack(alignment: .center, spacing: 8) {
                        if index < homePlayers.count {
                            squadPlayerCell(homePlayers[index], align: .leading)
                        } else {
                            Color.clear.frame(maxWidth: .infinity).frame(height: 52)
                        }

                        Rectangle()
                            .fill(Theme.border)
                            .frame(width: 1, height: 40)

                        if index < awayPlayers.count {
                            squadPlayerCell(awayPlayers[index], align: .trailing)
                        } else {
                            Color.clear.frame(maxWidth: .infinity).frame(height: 52)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)

                    if index < rowCount - 1 {
                        Divider().overlay(Color.white.opacity(0.06))
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Theme.border, lineWidth: 1)
                    )
            )
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    private func squadTeamHeader(
        name: String,
        fullName: String,
        logo: URL?,
        alignment: HorizontalAlignment
    ) -> some View {
        HStack(spacing: 8) {
            if alignment == .trailing { Spacer(minLength: 0) }
            if alignment == .leading {
                squadLogo(url: logo, fallback: name, size: 36)
            }
            VStack(alignment: alignment, spacing: 2) {
                Text(name)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(.white)
                Text(fullName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
            if alignment == .trailing {
                squadLogo(url: logo, fallback: name, size: 36)
            }
            if alignment == .leading { Spacer(minLength: 0) }
        }
        .frame(maxWidth: .infinity)
    }

    private func squadPlayerCell(_ player: SquadPlayer, align: HorizontalAlignment) -> some View {
        HStack(spacing: 8) {
            if align == .leading {
                squadLogo(url: player.imageURL, fallback: player.initials, size: 32)
            }
            VStack(alignment: align, spacing: 2) {
                Text(player.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(player.role)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: align == .leading ? .leading : .trailing)
            if align == .trailing {
                squadLogo(url: player.imageURL, fallback: player.initials, size: 32)
            }
        }
        .frame(maxWidth: .infinity, alignment: align == .leading ? .leading : .trailing)
        .frame(height: 52)
    }

    private func squadLogo(url: URL?, fallback: String, size: CGFloat) -> some View {
        ZStack {
            Circle().fill(Color(white: 0.16))
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        Text(String(fallback.prefix(3)).uppercased())
                            .font(.system(size: size * 0.28, weight: .heavy))
                            .foregroundStyle(.white)
                    case .empty:
                        ProgressView().scaleEffect(0.6).tint(Theme.accent)
                    @unknown default:
                        Text(String(fallback.prefix(3)).uppercased())
                            .font(.system(size: size * 0.28, weight: .heavy))
                            .foregroundStyle(.white)
                    }
                }
                .clipShape(Circle())
            } else {
                Text(String(fallback.prefix(3)).uppercased())
                    .font(.system(size: size * 0.28, weight: .heavy))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            }
        }
        .frame(width: size, height: size)
        .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
    }

    private var pointsTableBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("POINTS TABLE")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 16)

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Text("#").frame(width: 28, alignment: .leading)
                    Text("Team").frame(maxWidth: .infinity, alignment: .leading)
                    Text("P").frame(width: 28)
                    Text("W").frame(width: 28)
                    Text("L").frame(width: 28)
                    Text("NRR").frame(width: 48, alignment: .trailing)
                    Text("Pts").frame(width: 36, alignment: .trailing)
                }
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(white: 0.11))

                Text("Points table will appear when available")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .background(Color(white: 0.08))
            }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(red: 0.07, green: 0.075, blue: 0.10))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(white: 0.12), lineWidth: 1))
            )
            .padding(.horizontal, 12)
        }
        .padding(.top, 14)
    }
}

// MARK: - Rows & chips

struct BatterRowView: View {
    let row: BatterRow

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.isBatting ? "\(row.name)*" : row.name)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(row.isBatting ? Theme.accent : .white)
                Text(row.dismissal)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(row.isBatting ? Theme.accent.opacity(0.85) : Theme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            num(row.runs, bold: true)
            num(row.balls)
            num(row.fours)
            num(row.sixes)
            Text(String(format: "%.1f", row.strikeRate))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(row.isBatting ? Theme.accent : .white)
                .frame(width: 44, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func num(_ value: Int, bold: Bool = false) -> some View {
        Text("\(value)")
            .font(.system(size: 13, weight: bold ? .bold : .semibold))
            .foregroundStyle(row.isBatting ? Theme.accent : .white)
            .frame(width: 28)
    }
}

struct BowlerRowView: View {
    let row: BowlerRow

    var body: some View {
        HStack {
            Text(row.isBowling ? "\(row.name)*" : row.name)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(row.isBowling ? Theme.accent : .white)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(row.overs).frame(width: 32)
            Text("\(row.maidens)").frame(width: 24)
            Text("\(row.runs)").frame(width: 28)
            Text("\(row.wickets)").frame(width: 24)
            Text(String(format: "%.1f", row.economy))
                .frame(width: 40, alignment: .trailing)
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(row.isBowling ? Theme.accent : .white)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

struct OverBallChip: View {
    let ball: OverBall
    var large: Bool = false

    private var fill: Color {
        switch ball.kind {
        case .boundary: return Theme.accent
        case .wicket: return Theme.liveRed
        default: return Color(white: 0.2)
        }
    }

    private var foreground: Color {
        switch ball.kind {
        case .boundary: return .black
        default: return .white
        }
    }

    var body: some View {
        Text(ball.kind.label)
            .font(.system(size: large ? 13 : 11, weight: .heavy))
            .foregroundStyle(foreground)
            .frame(width: large ? 34 : 26, height: large ? 34 : 26)
            .background(Circle().fill(fill))
    }
}

struct BallDeliveryCard: View {
    let delivery: BallDelivery
    var isDownloaded: Bool = false
    var isDownloading: Bool = false
    var isInReel: Bool = false
    var onPlay: (() -> Void)? = nil
    var onDownload: (() -> Void)? = nil
    var onAddToReel: ((BallDelivery) -> Void)? = nil

    private var canPlay: Bool {
        isDownloaded || delivery.videoURL != nil
    }

    var body: some View {
        HStack(spacing: 10) {
            VStack(spacing: 6) {
                Text(delivery.ballLabel)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                Text(delivery.result.label)
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(delivery.result.fill))
            }
            .frame(width: 36)

            CoverImage(name: delivery.imageName)
                .frame(width: 56, height: 40)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(delivery.batsman)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(delivery.summary)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                if delivery.videoURL != nil || isDownloaded {
                    Text(isDownloaded ? "Downloaded" : "R2 video")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(isDownloaded ? Theme.sixGreen : Theme.accent)
                }
                if isInReel {
                    Text("In Reel")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.accentBright)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                Button {
                    onPlay?()
                } label: {
                    circleIcon(
                        "play.fill",
                        tint: canPlay ? Theme.accent : Theme.muted
                    )
                }
                .buttonStyle(.plain)

                if isDownloaded {
                    circleIcon("checkmark", tint: Theme.sixGreen)
                } else if isDownloading {
                    ProgressView()
                        .scaleEffect(0.8)
                        .frame(width: 36, height: 36)
                } else {
                    Button {
                        onDownload?()
                    } label: {
                        circleIcon(
                            "arrow.down.to.line",
                            tint: delivery.videoURL == nil ? Theme.muted : Theme.accent
                        )
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    onAddToReel?(delivery)
                } label: {
                    if isInReel {
                        circleIcon("checkmark", tint: Theme.accentBright, filled: true)
                    } else {
                        circleIcon(
                            "plus",
                            tint: delivery.videoURL == nil ? Theme.muted : Theme.accent
                        )
                    }
                }
                .buttonStyle(.plain)
            }
            .zIndex(2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            isInReel
                ? Theme.accent.opacity(0.08)
                : Theme.card,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            if isInReel {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Theme.accentBright.opacity(0.85), lineWidth: 1.5)
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isInReel)
        .animation(.easeInOut(duration: 0.2), value: isDownloaded)
    }

    private func circleIcon(_ name: String, tint: Color, filled: Bool = false) -> some View {
        Image(systemName: name)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(filled ? .white : tint)
            .frame(width: 36, height: 36)
            .contentShape(Rectangle())
            .background(
                Circle().fill(filled ? tint : Color(white: 0.16))
            )
    }
}

private struct IdentifiedURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

struct CommentaryCard: View {
    let item: CommentaryItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(item.over)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.accent)
                Spacer()
                Text(item.result)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(item.resultColor)
            }
            Text(item.body)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct StatCard: View {
    let label: String
    let value: String
    var accent: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Theme.mutedSoft)
            Text(value)
                .font(.system(size: 20, weight: .black))
                .foregroundStyle(accent ? Theme.accentBright : .white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(red: 0.071, green: 0.071, blue: 0.102))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(red: 0.145, green: 0.145, blue: 0.208), lineWidth: 1)
                )
        )
    }
}
