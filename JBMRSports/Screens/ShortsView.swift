import SwiftUI

struct ShortsView: View {
    @Binding var tab: AppTab
    @Binding var showSearch: Bool
    var onClose: (() -> Void)? = nil
    @EnvironmentObject private var store: CricketStore
    @State private var showStudio = false
    @State private var showEarnings = false
    @State private var activeId: String?
    @State private var category = 0

    private let categories = ["🔥 Trending", "⚡ 4s & 6s", "🎯 Wickets", "🏆 Best Catches"]

    private var shorts: [ShortClip] {
        store.shortClips
    }

    var body: some View {
        ZStack {
            Color(red: 10 / 255, green: 12 / 255, blue: 16 / 255).ignoresSafeArea()

            if shorts.isEmpty {
                emptyState
            } else {
                GeometryReader { geo in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 0) {
                            ForEach(shorts) { clip in
                                ShortReelPage(
                                    clip: clip,
                                    isActive: activeId == clip.id,
                                    category: $category,
                                    categories: categories,
                                    onEarn: { showEarnings = true }
                                )
                                .frame(width: geo.size.width, height: geo.size.height)
                                .id(clip.id)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollTargetBehavior(.paging)
                    .scrollPosition(id: $activeId)
                    .ignoresSafeArea()
                }
                .ignoresSafeArea()
            }

            VStack(spacing: 8) {
                topBar
                if let clip = shorts.first(where: { $0.id == activeId }) ?? shorts.first {
                    ShortProgressBar(clipId: clip.id)
                }
                Spacer()
            }
            .padding(.top, 8)
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            if store.shortClips.isEmpty {
                await store.refresh()
            }
            if activeId == nil {
                activeId = shorts.first?.id
            }
        }
        .onChange(of: shorts.map(\.id)) { _, ids in
            if activeId == nil || !(ids.contains(where: { $0 == activeId })) {
                activeId = ids.first
            }
        }
        .sheet(isPresented: $showStudio) {
            NavigationStack { ReelStudioView() }
        }
        .sheet(isPresented: $showEarnings) {
            NavigationStack { CreatorEarningsView() }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "play.rectangle.on.rectangle")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Theme.muted)
            Text("No shorts yet")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
            Text("Admin se ball video R2 pe upload karo — yahan vertical feed chalega")
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    private var topBar: some View {
        AppHeader(onAvatar: { tab = .profile })
            .padding(.top, 4)
    }
}

private struct ShortProgressBar: View {
    let clipId: String
    var body: some View {
        Capsule()
            .fill(Color.white.opacity(0.1))
            .frame(height: 4)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(Theme.accent)
                    .frame(width: 140, height: 4)
            }
            .padding(.horizontal, 16)
            .id(clipId)
    }
}

struct ShortReelPage: View {
    let clip: ShortClip
    var isActive: Bool
    @Binding var category: Int
    let categories: [String]
    var onEarn: () -> Void = {}
    @StateObject private var playback: StreamPlayback
    @State private var liked = false
    @State private var following = false
    @State private var showComments = false
    @State private var showShare = false

    init(
        clip: ShortClip,
        isActive: Bool,
        category: Binding<Int>,
        categories: [String],
        onEarn: @escaping () -> Void = {}
    ) {
        self.clip = clip
        self.isActive = isActive
        self._category = category
        self.categories = categories
        self.onEarn = onEarn
        _playback = StateObject(wrappedValue: StreamPlayback(url: clip.videoURL, autoplay: false, looping: true))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            StreamVideoLayer(player: playback.player, videoGravity: .resizeAspectFill)
                .ignoresSafeArea()

            if clip.videoURL == nil || (!playback.isPlaying && playback.progress < 0.02) {
                CoverImage(name: clip.imageName)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .allowsHitTesting(false)
            }

            LinearGradient(
                colors: [.clear, Color.black.opacity(0.8)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 260)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .allowsHitTesting(false)

            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { playback.toggle() }

            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 4) {
                        Image(systemName: "trophy.fill")
                            .font(.system(size: 11))
                        Text(clip.matchTag)
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Theme.accent.opacity(0.12))
                            .overlay(Capsule().stroke(Theme.accent, lineWidth: 1))
                    )

                    HStack(spacing: 6) {
                        Text(clip.creator)
                            .font(.system(size: 16, weight: .heavy))
                            .foregroundStyle(.white)
                        if clip.isVerified {
                            Image(systemName: "checkmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 14, height: 14)
                                .background(RoundedRectangle(cornerRadius: 7).fill(Theme.accentBright))
                        }
                    }

                    Text(clip.caption)
                        .font(.system(size: 14))
                        .foregroundStyle(Color(red: 0.82, green: 0.84, blue: 0.89))
                        .lineLimit(3)

                    HStack(spacing: 6) {
                        Image(systemName: "music.note")
                            .font(.system(size: 12))
                        Text(clip.audio)
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(Color(red: 0.56, green: 0.61, blue: 0.68))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            )
                    )

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(categories.enumerated()), id: \.offset) { i, label in
                                Button { category = i } label: {
                                    Text(label)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(
                                            Capsule()
                                                .fill(category == i ? Theme.accent.opacity(0.12) : Color.white.opacity(0.05))
                                                .overlay(
                                                    Capsule().stroke(category == i ? Theme.accent : .clear, lineWidth: 1)
                                                )
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 20) {
                    Button { following.toggle() } label: {
                        ZStack(alignment: .bottom) {
                            Image("UserAvatar")
                                .resizable()
                                .scaledToFill()
                                .frame(width: 52, height: 52)
                                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                            Image(systemName: following ? "checkmark" : "plus")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 18, height: 18)
                                .background(RoundedRectangle(cornerRadius: 9).fill(Theme.accent))
                                .offset(y: 6)
                        }
                        .padding(2)
                        .background(
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .stroke(Theme.accent, lineWidth: 2)
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 8)

                    sideButton(icon: "heart.fill", label: liked ? "Liked" : "Like", tint: liked ? Theme.liveRed : .white) {
                        liked.toggle()
                    }
                    sideButton(icon: "bubble.right", label: "Chat") { showComments = true }
                    sideButton(icon: "arrow.up.right", label: "Share") { showShare = true }

                    Button(action: onEarn) {
                        VStack(spacing: 4) {
                            Text("₹")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(Theme.accentBright)
                                .frame(width: 56, height: 56)
                                .background(
                                    Circle()
                                        .fill(Theme.accent.opacity(0.2))
                                        .overlay(Circle().stroke(Theme.accent, lineWidth: 1))
                                )
                            Text("EARNED")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Theme.accent)
                        }
                    }
                    .buttonStyle(.plain)

                    Button { following = true } label: {
                        Text("Follow")
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .frame(height: 44)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.accent))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 84)
        }
        .onChange(of: isActive) { _, active in
            if active { playback.play() } else { playback.pause() }
        }
        .onAppear {
            if isActive { playback.play() }
        }
        .onDisappear { playback.pause() }
        .sheet(isPresented: $showComments) {
            NavigationStack {
                List {
                    Text("Comments is clip pe jaldi aayenge")
                        .foregroundStyle(Theme.muted)
                }
                .navigationTitle("Comments")
                .toolbar { Button("Done") { showComments = false } }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showShare) {
            ShareSheet(items: {
                var items: [Any] = [clip.caption]
                if let url = clip.videoURL { items.append(url) }
                return items
            }())
        }
    }

    private func sideButton(icon: String, label: String, tint: Color = .white, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 56, height: 56)
                    .background(
                        Circle()
                            .fill(.ultraThinMaterial)
                            .overlay(Circle().stroke(Color.white.opacity(0.1), lineWidth: 1))
                    )
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
    }
}
