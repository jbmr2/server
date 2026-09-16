import SwiftUI
import WebKit

enum YouTubeURL {
    static func isYouTube(_ url: URL) -> Bool {
        videoId(from: url) != nil
    }

    static func isYouTube(_ raw: String?) -> Bool {
        guard let raw, let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return false
        }
        return isYouTube(url)
    }

    static func videoId(from url: URL) -> String? {
        let host = url.host?.lowercased() ?? ""
        guard host.contains("youtube.com") || host.contains("youtu.be") || host.contains("youtube-nocookie.com") else {
            return nil
        }
        if host.contains("youtu.be") {
            let id = url.path.split(separator: "/").first.map(String.init) ?? ""
            return sanitize(id)
        }
        if let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems {
            if let v = items.first(where: { $0.name == "v" })?.value, let id = sanitize(v) {
                return id
            }
        }
        let parts = url.path.split(separator: "/").map(String.init)
        if let idx = parts.firstIndex(where: { $0 == "embed" || $0 == "shorts" || $0 == "live" }),
           parts.indices.contains(idx + 1),
           let id = sanitize(parts[idx + 1]) {
            return id
        }
        return nil
    }

    private static func sanitize(_ value: String) -> String? {
        let id = value.split(separator: "?").first.map(String.init) ?? value
        let trimmed = id.trimmingCharacters(in: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-")).inverted)
        return trimmed.count >= 11 ? String(trimmed.prefix(11)) : nil
    }
}

/// YouTube: play/pause only — no seek bar. Ball clips stay on Cloudflare/native player.
struct YouTubePlayPauseView: View {
    let videoId: String
    var autoplay: Bool = false
    var muted: Bool = false
    var looping: Bool = false
    var showsPlayButton: Bool = true
    @Binding var isPlaying: Bool
    @State private var mediaPlaying = false

    var body: some View {
        ZStack {
            YouTubeWebPlayer(
                videoId: videoId,
                autoplay: autoplay,
                muted: muted,
                looping: looping,
                isPlaying: $isPlaying,
                mediaPlaying: $mediaPlaying
            )
            // Hide YouTube share / related / logo overlays until real playback (and while paused).
            if !mediaPlaying {
                Color.black.allowsHitTesting(false)
            }
        }
    }
}

private struct YouTubeWebPlayer: UIViewRepresentable {
    let videoId: String
    var autoplay: Bool
    var muted: Bool
    var looping: Bool
    @Binding var isPlaying: Bool
    @Binding var mediaPlaying: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(isPlaying: $isPlaying, mediaPlaying: $mediaPlaying, looping: looping)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.userContentController.add(context.coordinator, name: "yt")
        let web = WKWebView(frame: .zero, configuration: config)
        web.isOpaque = false
        web.backgroundColor = .black
        web.scrollView.isScrollEnabled = false
        web.scrollView.bounces = false
        web.isUserInteractionEnabled = false
        context.coordinator.webView = web
        return web
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.looping = looping
        context.coordinator.isPlaying = $isPlaying
        context.coordinator.mediaPlaying = $mediaPlaying
        if context.coordinator.loadedId != videoId {
            context.coordinator.loadedId = videoId
            context.coordinator.desiredPlay = isPlaying
            mediaPlaying = false
            webView.loadHTMLString(
                Self.html(videoId: videoId, autoplay: autoplay, muted: muted, looping: looping),
                baseURL: URL(string: "https://www.youtube-nocookie.com")
            )
        } else if context.coordinator.desiredPlay != isPlaying {
            context.coordinator.desiredPlay = isPlaying
            context.coordinator.applyPlayState(isPlaying)
        }
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "yt")
        uiView.stopLoading()
    }

    private static func html(videoId: String, autoplay: Bool, muted: Bool, looping: Bool) -> String {
        let auto = autoplay ? "true" : "false"
        let mute = muted ? "true" : "false"
        let loop = looping ? "true" : "false"
        return """
        <!DOCTYPE html><html><head>
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
        <style>
          html,body{margin:0;height:100%;background:#000;overflow:hidden}
          .clip{position:fixed;inset:0;overflow:hidden;background:#000}
          #player, iframe {
            position:absolute !important;
            top:-80px !important;
            left:-18% !important;
            width:136% !important;
            height:calc(100% + 160px) !important;
            pointer-events:none !important;
            border:0 !important;
          }
        </style>
        </head><body>
        <div class="clip"><div id="player"></div></div>
        <script>
        var looping = \(loop);
        var player;
        function onYouTubeIframeAPIReady() {
          player = new YT.Player('player', {
            videoId: '\(videoId)',
            host: 'https://www.youtube-nocookie.com',
            width: '100%', height: '100%',
            playerVars: {
              autoplay: \(autoplay ? 1 : 0),
              mute: \(muted ? 1 : 0),
              controls: 0, disablekb: 1, fs: 0, modestbranding: 1,
              rel: 0, playsinline: 1, iv_load_policy: 3, cc_load_policy: 0,
              autohide: 1, showinfo: 0,
              origin: 'https://www.youtube-nocookie.com'
            },
            events: {
              onReady: function(e) {
                if (\(mute)) e.target.mute();
                if (\(auto)) e.target.playVideo();
                window.webkit.messageHandlers.yt.postMessage('ready');
              },
              onStateChange: function(e) {
                if (e.data === 0 && looping) { e.target.seekTo(0); e.target.playVideo(); }
                window.webkit.messageHandlers.yt.postMessage('state:' + e.data);
              }
            }
          });
        }
        var tag = document.createElement('script');
        tag.src = 'https://www.youtube.com/iframe_api';
        document.head.appendChild(tag);
        </script></body></html>
        """
    }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        var webView: WKWebView?
        var loadedId: String?
        var looping: Bool
        var desiredPlay: Bool?
        var isPlaying: Binding<Bool>
        var mediaPlaying: Binding<Bool>
        private var applying = false

        init(isPlaying: Binding<Bool>, mediaPlaying: Binding<Bool>, looping: Bool) {
            self.isPlaying = isPlaying
            self.mediaPlaying = mediaPlaying
            self.looping = looping
        }

        func applyPlayState(_ play: Bool) {
            if !play {
                DispatchQueue.main.async { self.mediaPlaying.wrappedValue = false }
            }
            applying = true
            let js = play ? "player && player.playVideo && player.playVideo();" : "player && player.pauseVideo && player.pauseVideo();"
            webView?.evaluateJavaScript(js, completionHandler: { [weak self] _, _ in
                self?.applying = false
            })
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? String else { return }
            if body == "ready" {
                DispatchQueue.main.async {
                    self.applyPlayState(self.isPlaying.wrappedValue)
                }
                return
            }
            if body.hasPrefix("state:") {
                let code = body.replacingOccurrences(of: "state:", with: "")
                DispatchQueue.main.async {
                    if code == "1" {
                        self.mediaPlaying.wrappedValue = true
                        if !self.applying { self.isPlaying.wrappedValue = true }
                    } else if code == "2" || code == "0" || code == "5" || code == "-1" {
                        self.mediaPlaying.wrappedValue = false
                        if !self.applying, code == "2" || code == "0" {
                            self.isPlaying.wrappedValue = false
                        }
                    }
                }
            }
        }
    }
}
