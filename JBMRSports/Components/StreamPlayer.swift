import AVFoundation
import AVKit
import Combine
import SwiftUI

enum StreamMedia {
    /// Used only when a real stream URL is unavailable; prefer API/CDN URLs.
    static let placeholder = URL(string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_fmp4/master.m3u8")!
}

final class StreamPlayback: ObservableObject {
    let player: AVPlayer
    @Published var isPlaying = false
    @Published var progress: Double = 0
    @Published var isReady = false
    @Published var durationLabel = "0:00"
    @Published var currentLabel = "0:00"
    @Published var playbackError: String?
    private(set) var hasMedia: Bool

    var onFinished: (() -> Void)?

    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var statusObserver: NSKeyValueObservation?
    private let looping: Bool
    private let isLiveStream: Bool

    init(url: URL?, autoplay: Bool = false, looping: Bool = false, muted: Bool = false, isLive: Bool = false) {
        self.looping = looping
        self.isLiveStream = isLive
        self.hasMedia = url != nil
        if let url {
            Self.activateAudioSession()
            let item = Self.makePlayerItem(url: url, isLive: isLive)
            player = AVPlayer(playerItem: item)
            player.isMuted = muted
            player.automaticallyWaitsToMinimizeStalling = !isLive
            player.actionAtItemEnd = looping ? .none : .pause

            statusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
                DispatchQueue.main.async {
                    guard let self else { return }
                    switch item.status {
                    case .readyToPlay:
                        self.isReady = true
                        self.playbackError = nil
                    case .failed:
                        self.isReady = false
                        self.playbackError = item.error?.localizedDescription ?? "Playback failed"
                    default:
                        break
                    }
                    let d = item.duration.seconds
                    if d.isFinite, d > 0 {
                        self.durationLabel = Self.format(d)
                    }
                }
            }

            timeObserver = player.addPeriodicTimeObserver(
                forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
                queue: .main
            ) { [weak self] time in
                guard let self else { return }
                let current = time.seconds
                let total = self.player.currentItem?.duration.seconds ?? 0
                if total.isFinite, total > 0 {
                    self.progress = min(max(current / total, 0), 1)
                    self.currentLabel = Self.format(current)
                    self.durationLabel = Self.format(total)
                }
                self.isPlaying = self.player.rate > 0
            }

            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                if self.looping {
                    self.player.seek(to: .zero)
                    self.player.play()
                    self.isPlaying = true
                } else {
                    self.isPlaying = false
                    self.progress = 1
                    self.onFinished?()
                }
            }

            if autoplay {
                player.play()
                isPlaying = true
            }
        } else {
            player = AVPlayer()
        }
    }

    func replace(url: URL?, autoplay: Bool = true, isLive: Bool? = nil) {
        player.pause()
        guard let url else { return }
        hasMedia = true
        playbackError = nil
        Self.activateAudioSession()
        let live = isLive ?? isLiveStream
        let item = Self.makePlayerItem(url: url, isLive: live)
        player.automaticallyWaitsToMinimizeStalling = !live
        player.replaceCurrentItem(with: item)
        statusObserver?.invalidate()
        statusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                switch item.status {
                case .readyToPlay:
                    self.isReady = true
                    self.playbackError = nil
                case .failed:
                    self.isReady = false
                    self.playbackError = item.error?.localizedDescription ?? "Playback failed"
                default:
                    break
                }
                let d = item.duration.seconds
                if d.isFinite, d > 0 {
                    self.durationLabel = Self.format(d)
                }
            }
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            if self.looping {
                self.player.seek(to: .zero)
                self.player.play()
                self.isPlaying = true
            } else {
                self.isPlaying = false
                self.progress = 1
                self.onFinished?()
            }
        }
        if autoplay {
            player.play()
            isPlaying = true
        }
        progress = 0
        isReady = false
    }

    func play() {
        player.play()
        isPlaying = true
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    func toggle() {
        if isPlaying { pause() } else { play() }
    }

    func seek(fraction: Double) {
        guard hasMedia else { return }
        guard let total = player.currentItem?.duration.seconds, total.isFinite, total > 0 else { return }
        let t = CMTime(seconds: total * fraction, preferredTimescale: 600)
        player.seek(to: t)
        progress = fraction
    }

    deinit {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        statusObserver?.invalidate()
        player.pause()
    }

    private static func format(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let s = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private static func activateAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
        try? session.setActive(true)
    }

    private static func makePlayerItem(url: URL, isLive: Bool) -> AVPlayerItem {
        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        if isLive {
            item.preferredForwardBufferDuration = 1
            if #available(iOS 15.0, *) {
                item.automaticallyPreservesTimeOffsetFromLive = true
                item.canUseNetworkResourcesForLiveStreamingWhilePaused = true
            }
        }
        return item
    }
}

struct StreamVideoLayer: UIViewRepresentable {
    let player: AVPlayer
    var videoGravity: AVLayerVideoGravity = .resizeAspectFill

    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        view.isUserInteractionEnabled = false
        view.playerLayer.player = player
        view.playerLayer.videoGravity = videoGravity
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        uiView.playerLayer.player = player
        uiView.playerLayer.videoGravity = videoGravity
    }

    final class PlayerUIView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}
