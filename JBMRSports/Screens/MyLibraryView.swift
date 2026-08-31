import SwiftUI

struct MyLibraryView: View {
    @EnvironmentObject private var library: DownloadLibraryStore
    @State private var segment = 0
    @State private var playingURL: URL?
    @State private var playingTitle = ""

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $segment) {
                Text("Ball Clips (\(library.ballItems.count))").tag(0)
                Text("My Reels (\(library.reelItems.count))").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(16)

            if segment == 0 {
                ballList
            } else {
                reelList
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("My Reels")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: Binding(
            get: {
                playingURL.map { PlayableItem(url: $0, title: playingTitle) }
            },
            set: { _ in
                playingURL = nil
                playingTitle = ""
            }
        )) { item in
            LocalVideoPlayerSheet(url: item.url, title: item.title)
        }
        .overlay(alignment: .top) {
            if let toast = library.toastMessage {
                Text(toast)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Theme.sixGreen.opacity(0.9)))
                    .padding(.top, 8)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            library.clearToast()
                        }
                    }
            }
        }
    }

    private var ballList: some View {
        Group {
            if library.ballItems.isEmpty {
                emptyState(
                    icon: "arrow.down.circle",
                    title: "No ball clips yet",
                    subtitle: "Match → Ball by Ball → download icon"
                )
            } else {
                List {
                    ForEach(library.ballItems) { item in
                        libraryRow(
                            title: item.ballLabel,
                            subtitle: item.matchTitle,
                            meta: item.downloadedAt.formatted(date: .abbreviated, time: .shortened),
                            downloaded: true
                        ) {
                            if let url = library.localBallURL(id: item.id) {
                                playingURL = url
                                playingTitle = item.ballLabel
                            }
                        }
                        .listRowBackground(Theme.card)
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
    }

    private var reelList: some View {
        Group {
            if library.reelItems.isEmpty {
                emptyState(
                    icon: "film.stack",
                    title: "No reels yet",
                    subtitle: "Reel Studio se export karo — yahan save hoga"
                )
            } else {
                List {
                    ForEach(library.reelItems) { item in
                        libraryRow(
                            title: item.title,
                            subtitle: "\(item.clipCount) clips",
                            meta: ByteCountFormatter.string(fromByteCount: item.fileSizeBytes, countStyle: .file),
                            downloaded: true
                        ) {
                            if let url = library.localReelURL(id: item.id) {
                                playingURL = url
                                playingTitle = item.title
                            }
                        }
                        .listRowBackground(Theme.card)
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
    }

    private func libraryRow(
        title: String,
        subtitle: String,
        meta: String,
        downloaded: Bool,
        onPlay: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Button(action: onPlay) {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                Text(meta)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.mutedSoft)
            }

            Spacer()

            if downloaded {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.sixGreen)
            }
        }
        .padding(.vertical, 4)
    }

    private func emptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(Theme.muted)
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }
}

private struct PlayableItem: Identifiable {
    let id = UUID()
    let url: URL
    let title: String
}

private struct LocalVideoPlayerSheet: View {
    let url: URL
    let title: String
    @Environment(\.dismiss) private var dismiss
    @StateObject private var playback: StreamPlayback

    init(url: URL, title: String) {
        self.url = url
        self.title = title
        _playback = StateObject(wrappedValue: StreamPlayback(url: url, autoplay: true, looping: false))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                StreamVideoLayer(player: playback.player, videoGravity: .resizeAspect)
                    .ignoresSafeArea()
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onDisappear { playback.pause() }
    }
}
