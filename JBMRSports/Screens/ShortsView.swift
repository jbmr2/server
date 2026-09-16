import SwiftUI

struct ShortsView: View {
    @Binding var tab: AppTab
    @Binding var showSearch: Bool
    var onClose: (() -> Void)? = nil
    @EnvironmentObject private var store: CricketStore
    @State private var activeId: String?

    private var shorts: [ShortClip] {
        store.shortClips
    }

    var body: some View {
        VStack(spacing: 0) {
            AppHeader(
                onAvatar: { tab = .profile },
                onSearch: { showSearch = true }
            )

            if shorts.isEmpty {
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { geo in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 0) {
                            ForEach(shorts) { clip in
                                ShortReelPage(
                                    clip: clip,
                                    isActive: activeId == clip.id
                                )
                                .frame(width: geo.size.width, height: geo.size.height)
                                .id(clip.id)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollTargetBehavior(.paging)
                    .scrollPosition(id: $activeId)
                }
            }
        }
        .background(Color.black.ignoresSafeArea(edges: .bottom))
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
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "play.rectangle.on.rectangle")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Theme.muted)
            Text("No shorts yet")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
            Text("New match clips will appear here")
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }
}

struct ShortReelPage: View {
    let clip: ShortClip
    var isActive: Bool
    @StateObject private var playback: StreamPlayback
    @State private var showShare = false

    init(clip: ShortClip, isActive: Bool) {
        self.clip = clip
        self.isActive = isActive
        _playback = StateObject(wrappedValue: StreamPlayback(url: clip.videoURL, autoplay: false, looping: true))
    }

    private var cloudflareLiveEmbed: (videoId: String, subdomain: String)? {
        guard let url = clip.videoURL, CloudflareStreamURL.shouldUseIframeEmbed(url) else { return nil }
        guard let videoId = CloudflareStreamURL.videoId(from: url) else { return nil }
        let subdomain = CloudflareStreamURL.customerSubdomain(from: url) ?? "febottgr27fxjy24"
        return (videoId, subdomain)
    }

    private var matchTitle: String {
        var tag = clip.matchTag
        let lower = tag.lowercased()
        if lower.hasPrefix("from:") {
            tag = String(tag.dropFirst(5))
        } else if lower.hasPrefix("from ") {
            tag = String(tag.dropFirst(5))
        }
        return tag.split(separator: "•").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? tag.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.black

            if clip.videoURL == nil {
                CoverImage(name: clip.imageName, showLoading: false)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .allowsHitTesting(false)
            } else if let embed = cloudflareLiveEmbed {
                CloudflareStreamEmbedView(
                    videoId: embed.videoId,
                    customerSubdomain: embed.subdomain,
                    fillCrop: true
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            } else {
                StreamVideoLayer(player: playback.player, videoGravity: .resizeAspectFill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()

                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { playback.toggle() }
            }

            LinearGradient(
                colors: [.clear, Color.black.opacity(0.45)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 88)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .allowsHitTesting(false)

            HStack(alignment: .bottom, spacing: 12) {
                Text(matchTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .shadow(color: .black.opacity(0.6), radius: 6, y: 1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    showShare = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color.black.opacity(0.35)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Share")
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .clipped()
        .onChange(of: isActive) { _, active in
            guard cloudflareLiveEmbed == nil else { return }
            if active { playback.play() } else { playback.pause() }
        }
        .onAppear {
            guard cloudflareLiveEmbed == nil else { return }
            if isActive { playback.play() }
        }
        .onDisappear { playback.pause() }
        .sheet(isPresented: $showShare) {
            ShareSheet(items: {
                var items: [Any] = [clip.caption]
                if let url = clip.videoURL { items.append(url) }
                return items
            }())
        }
    }
}
