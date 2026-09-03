import AVKit
import SwiftUI

struct AirPlayRoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = .white
        view.activeTintColor = UIColor(red: 0, green: 0.75, blue: 1, alpha: 1)
        view.prioritizesVideoDevices = true
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

struct FullscreenPlayerView: View {
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
        ZStack {
            Color.black.ignoresSafeArea()

            StreamVideoLayer(player: playback.player, videoGravity: .resizeAspect)
                .ignoresSafeArea()

            VStack {
                HStack {
                    Text(title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer()
                    Button("Done") { dismiss() }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                Spacer()

                Button { playback.toggle() } label: {
                    Image(systemName: playback.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.4), radius: 8)
                }
                .padding(.bottom, 36)
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear { OrientationManager.enableLandscape() }
        .onDisappear {
            playback.pause()
            OrientationManager.restorePortrait()
        }
    }
}

struct ReelPreviewSheet: View {
    let clips: [ReelClipItem]
    @Environment(\.dismiss) private var dismiss
    @State private var index = 0
    @StateObject private var playback: StreamPlayback

    init(clips: [ReelClipItem]) {
        self.clips = clips
        let url = clips.first(where: { $0.videoURL != nil })?.videoURL
        _playback = StateObject(wrappedValue: StreamPlayback(url: url, autoplay: true, looping: false))
    }

    private var current: ReelClipItem? {
        clips.indices.contains(index) ? clips[index] : clips.first
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                StreamVideoLayer(player: playback.player, videoGravity: .resizeAspect)
                    .ignoresSafeArea()
                VStack {
                    Spacer()
                    if let current {
                        Text("\(current.ballLabel) · \(current.match)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.bottom, 8)
                    }
                    Text("Clip \(min(index + 1, clips.count)) / \(clips.count)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.accent)
                        .padding(.bottom, 24)
                }
            }
            .navigationTitle("Preview Reel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear {
            playback.onFinished = { advance() }
        }
        .onDisappear { playback.pause() }
    }

    private func advance() {
        let urls = clips.compactMap(\.videoURL)
        guard !urls.isEmpty else { return }
        let next = index + 1
        if next < clips.count, let url = clips[next].videoURL {
            index = next
            playback.replace(url: url, autoplay: true)
            playback.onFinished = { advance() }
        } else {
            playback.pause()
        }
    }
}

struct LegalSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Terms of Use")
                        .font(.system(size: 18, weight: .bold))
                    Text("JBMR Sports OTT lets you watch live cricket, ball-by-ball clips, and create highlight reels for personal, non-commercial use. Do not copy or redistribute match footage outside this app without rights.")
                    Text("Privacy")
                        .font(.system(size: 18, weight: .bold))
                    Text("Downloads and exported reels stay on this device. Match data is loaded from JBMR’s OTT feed. We do not sell your personal information.")
                }
                .font(.system(size: 14))
                .foregroundStyle(.white)
                .padding(20)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Terms & Privacy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct ReelGuideSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Label("Match → Ball by Ball → + to add clips", systemImage: "plus.circle")
                Label("Download icon saves the ball offline", systemImage: "arrow.down.circle")
                Label("Bottom + opens Reel Studio", systemImage: "plus")
                Label("Preview, then Export Video Reel", systemImage: "square.and.arrow.up")
                Label("Saved reels: Profile → My Reels", systemImage: "person.crop.rectangle.stack")
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Reel Guide")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct PointsTablePanel: View {
    let rows: [PointsTableRow]

    var body: some View {
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

                if rows.isEmpty {
                    Text("Points table will appear after results")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .background(Color(white: 0.08))
                } else {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        HStack(spacing: 0) {
                            Text("\(index + 1)")
                                .frame(width: 28, alignment: .leading)
                                .foregroundStyle(Theme.mutedSoft)
                            Text(row.teamName)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .foregroundStyle(.white)
                            Text("\(row.played)").frame(width: 28)
                            Text("\(row.won)").frame(width: 28)
                            Text("\(row.lost)").frame(width: 28)
                            Text(row.nrr)
                                .frame(width: 48, alignment: .trailing)
                                .foregroundStyle(Theme.muted)
                            Text("\(row.points)")
                                .frame(width: 36, alignment: .trailing)
                                .foregroundStyle(Theme.accent)
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(index % 2 == 0 ? Color(white: 0.08) : Color(white: 0.06))

                        if index < rows.count - 1 {
                            Rectangle()
                                .fill(Color.white.opacity(0.06))
                                .frame(height: 1)
                                .padding(.leading, 12)
                        }
                    }
                }
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
