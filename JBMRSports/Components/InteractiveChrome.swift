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
                    Spacer()
                    Button("Done") { dismiss() }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
                .padding()
                Spacer()
                Button { playback.toggle() } label: {
                    Image(systemName: playback.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(.white)
                }
                .padding(.bottom, 40)
            }
        }
        .onDisappear { playback.pause() }
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
