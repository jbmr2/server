import AVFoundation
import AVKit
import Combine
import CoreMedia
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
    private var failObserver: NSObjectProtocol?
    private var errorLogObserver: NSObjectProtocol?
    private var statusObserver: NSKeyValueObservation?
    private let looping: Bool
    private var isLiveStream: Bool
    private var lastURL: URL?
    private var liveRetryCount = 0
    private var retryWorkItem: DispatchWorkItem?

    init(url: URL?, autoplay: Bool = false, looping: Bool = false, muted: Bool = false, isLive: Bool = false) {
        self.looping = looping
        self.isLiveStream = isLive
        self.hasMedia = url != nil
        self.lastURL = url
        if let url {
            Self.activateAudioSession()
            let item = Self.makePlayerItem(url: url, isLive: isLive)
            player = AVPlayer(playerItem: item)
            player.isMuted = muted
            player.automaticallyWaitsToMinimizeStalling = !isLive
            player.actionAtItemEnd = looping ? .none : .pause
            attachObservers(to: item)
            if autoplay {
                player.play()
                isPlaying = true
            }
        } else {
            player = AVPlayer()
            player.automaticallyWaitsToMinimizeStalling = !isLive
        }
    }

    func replace(url: URL?, autoplay: Bool = true, isLive: Bool? = nil, isRetry: Bool = false) {
        retryWorkItem?.cancel()
        player.pause()
        guard let url else { return }
        hasMedia = true
        playbackError = nil
        lastURL = url
        if !isRetry { liveRetryCount = 0 }
        Self.activateAudioSession()
        let live = isLive ?? isLiveStream
        isLiveStream = live
        let item = Self.makePlayerItem(url: url, isLive: live)
        player.automaticallyWaitsToMinimizeStalling = !live
        player.replaceCurrentItem(with: item)
        attachObservers(to: item)
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
        retryWorkItem?.cancel()
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        if let failObserver {
            NotificationCenter.default.removeObserver(failObserver)
        }
        if let errorLogObserver {
            NotificationCenter.default.removeObserver(errorLogObserver)
        }
        statusObserver?.invalidate()
        player.pause()
    }

    private func attachObservers(to item: AVPlayerItem) {
        statusObserver?.invalidate()
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        if let failObserver {
            NotificationCenter.default.removeObserver(failObserver)
        }
        if let errorLogObserver {
            NotificationCenter.default.removeObserver(errorLogObserver)
        }

        statusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                switch item.status {
                case .readyToPlay:
                    self.isReady = true
                    self.playbackError = nil
                    self.liveRetryCount = 0
                case .failed:
                    self.handleItemFailure(item.error)
                default:
                    break
                }
                let d = item.duration.seconds
                if d.isFinite, d > 0 {
                    self.durationLabel = Self.format(d)
                }
            }
        }

        if timeObserver == nil {
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

        failObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] note in
            let error = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            self?.handleItemFailure(error ?? item.error)
        }

        errorLogObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemNewErrorLogEntry,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self, let events = item.errorLog()?.events, let last = events.last else { return }
            let comment = (last.errorComment ?? "") + " \(last.errorStatusCode) \(last.errorDomain)"
            if Self.isTransientLiveFailure(status: last.errorStatusCode, domain: last.errorDomain, message: comment) {
                self.handleItemFailure(item.error, logHint: comment)
            }
        }
    }

    private func handleItemFailure(_ error: Error?, logHint: String? = nil) {
        isReady = false
        let message = Self.friendlyPlaybackMessage(
            error,
            extra: logHint,
            isLive: isLiveStream
        )
        playbackError = message
        guard isLiveStream, Self.isTransientLiveError(error, extra: logHint), liveRetryCount < 2, let lastURL else {
            return
        }
        liveRetryCount += 1
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.replace(url: lastURL, autoplay: true, isLive: true, isRetry: true)
        }
        retryWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: work)
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
        // Avoid ultra-aggressive live-edge chasing — Cloudflare LL-HLS blocking
        // playlists often return HTTP 204 and AVPlayer fails with CoreMedia -12667.
        if isLive {
            item.preferredForwardBufferDuration = 1
            item.configuredTimeOffsetFromLive = CMTime(seconds: 1.5, preferredTimescale: 600)
            if #available(iOS 15.0, *) {
                item.automaticallyPreservesTimeOffsetFromLive = true
                item.canUseNetworkResourcesForLiveStreamingWhilePaused = true
            }
        }
        return item
    }

    private static func friendlyPlaybackMessage(_ error: Error?, extra: String?, isLive: Bool) -> String {
        if isTransientLiveError(error, extra: extra) || (isLive && isGenericOperationFailed(error, extra: extra)) {
            return "Live stream abhi connect ho raha hai — thodi der baad retry karein"
        }
        return error?.localizedDescription ?? "Playback failed"
    }

    private static func isGenericOperationFailed(_ error: Error?, extra: String?) -> Bool {
        let text = ((error?.localizedDescription ?? "") + " " + (extra ?? "")).lowercased()
        return text.contains("operation could not be completed")
    }

    private static func isTransientLiveError(_ error: Error?, extra: String?) -> Bool {
        if let error {
            var cursor: Error? = error
            while let current = cursor {
                let ns = current as NSError
                if isTransientLiveFailure(status: ns.code, domain: ns.domain, message: ns.localizedDescription) {
                    return true
                }
                if let info = ns.userInfo as [String: Any]? {
                    for value in info.values {
                        if let nested = value as? Error {
                            let nestedNS = nested as NSError
                            if isTransientLiveFailure(status: nestedNS.code, domain: nestedNS.domain, message: nestedNS.localizedDescription) {
                                return true
                            }
                        }
                        if let number = value as? NSNumber,
                           isTransientLiveFailure(status: number.intValue, domain: ns.domain, message: "") {
                            return true
                        }
                    }
                }
                cursor = ns.userInfo[NSUnderlyingErrorKey] as? Error
            }
        }
        return isTransientLiveFailure(status: 0, domain: "", message: extra ?? "")
    }

    private static func isTransientLiveFailure(status: Int, domain: String, message: String) -> Bool {
        let combined = "\(domain) \(message)".lowercased()
        if status == -12667 || status == 12667 { return true }
        if status == 204 || combined.contains(" 204") || combined.contains("http 204") || combined.contains("status code 204") {
            return true
        }
        if combined.contains("coremedia") && (combined.contains("12667") || combined.contains("204")) {
            return true
        }
        return false
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
