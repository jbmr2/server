import SwiftUI

struct ExportShareView: View {
    let result: ReelExportResult

    @Environment(\.dismiss) private var dismiss
    @StateObject private var playback: StreamPlayback
    @State private var showShare = false

    init(result: ReelExportResult) {
        self.result = result
        _playback = StateObject(wrappedValue: StreamPlayback(url: result.fileURL, autoplay: false, looping: true))
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                header
                successBanner
                previewCard
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                shareSection
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                actions
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
            }
        }
        .background(Color(red: 0.03, green: 0.035, blue: 0.055).ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showShare) {
            ShareSheet(items: [
                MatchDeepLink.shareMessage(
                    title: "Watch live cricket on JBMR Sports",
                    url: MatchDeepLink.siteURL()
                ),
                MatchDeepLink.siteURL()
            ])
        }
        .onAppear { playback.play() }
        .onDisappear { playback.pause() }
    }

    private var header: some View {
        AppHeader(onLogo: { dismiss() }, showsAvatar: false)
            .padding(.vertical, 8)
            .background(Color(red: 0.07, green: 0.075, blue: 0.10))
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color(white: 0.13)).frame(height: 1)
            }
    }

    private var successBanner: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Theme.accent.opacity(0.1))
                    .overlay(Circle().stroke(Theme.accent, lineWidth: 3))
                    .frame(width: 88, height: 88)
                Image(systemName: "checkmark")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Theme.accent)
            }

            VStack(spacing: 4) {
                Text("Your Highlight Reel is Ready!")
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(.white)
                Text("\(result.clipCount) clips • \(result.durationLabel) • \(result.sizeLabel)")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
            }
        }
        .padding(24)
    }

    private var previewCard: some View {
        ZStack(alignment: .bottom) {
            StreamVideoLayer(player: playback.player, videoGravity: .resizeAspectFill)
                .frame(height: 220)
                .clipped()

            Color.black.opacity(0.15)

            VStack {
                HStack {
                    Text(result.durationLabel)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 6).fill(.black.opacity(0.8)))
                    Spacer()
                    Button { playback.toggle() } label: {
                        Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(Theme.accent))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.title)
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                        Text("Created via JBMR Reel Studio")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.muted)
                    }
                    Spacer()
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(red: 0.07, green: 0.075, blue: 0.10).opacity(0.88))
                )
            }
            .padding(12)
        }
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var shareSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Share Instantly")
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(.white)

            Button { showShare = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 18, weight: .semibold))
                    Text("Share JBMR Sports link")
                        .font(.system(size: 14, weight: .bold))
                    Spacer()
                }
                .foregroundStyle(.white)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(red: 0.07, green: 0.075, blue: 0.10))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(white: 0.13), lineWidth: 1))
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Text("Video streams in the app only. You can share a link to JBMR Sports, not a video file.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)

            Button { dismiss() } label: {
                Text("Done")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .padding(6)
            }
            .buttonStyle(.plain)
        }
    }
}
