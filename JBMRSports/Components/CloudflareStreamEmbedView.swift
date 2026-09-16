import Foundation
import SwiftUI
import WebKit

enum CloudflareStreamURL {
    static func videoId(from url: URL) -> String? {
        let parts = url.path.split(separator: "/").map(String.init)
        if let id = parts.first(where: { isHexId($0) }) {
            return id.lowercased()
        }
        let haystack = url.absoluteString
        guard let regex = try? NSRegularExpression(pattern: "[0-9a-fA-F]{32}") else { return nil }
        let ns = haystack as NSString
        if let match = regex.firstMatch(in: haystack, range: NSRange(location: 0, length: ns.length)) {
            let token = ns.substring(with: match.range)
            if isHexId(token) { return token.lowercased() }
        }
        return nil
    }

    static func customerSubdomain(from url: URL) -> String? {
        guard let host = url.host?.lowercased() else { return nil }
        let prefix = "customer-"
        let suffix = ".cloudflarestream.com"
        guard host.hasPrefix(prefix), host.hasSuffix(suffix) else { return nil }
        let start = host.index(host.startIndex, offsetBy: prefix.count)
        let end = host.index(host.endIndex, offsetBy: -suffix.count)
        let sub = String(host[start..<end])
        return sub.isEmpty ? nil : sub
    }

    static func isCloudflareStream(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host.contains("cloudflarestream.com") || host.contains("videodelivery.net")
    }

    static func looksLikeLiveManifest(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        return path.contains("/manifest/") || path.contains(".m3u8") || path.contains("webrtc")
    }

    /// HLS/manifest CF Stream URLs use the WebView player (AVPlayer LL-HLS 204).
    /// Ball clips and other `.mp4` stay on native playback.
    static func shouldUseIframeEmbed(_ url: URL) -> Bool {
        guard isCloudflareStream(url) else { return false }
        let path = url.path.lowercased()
        if path.contains("clip.mp4") || path.hasSuffix(".mp4") { return false }
        return videoId(from: url) != nil
    }

    private static func isHexId(_ value: String) -> Bool {
        value.count == 32 && value.unicodeScalars.allSatisfy {
            CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains($0)
        }
    }
}

struct CloudflareStreamEmbedView: UIViewRepresentable {
    let videoId: String
    let customerSubdomain: String
    var isLive: Bool = false
    var isPlaying: Binding<Bool> = .constant(true)
    var fillCrop: Bool = false

    func makeUIView(context: Context) -> StreamEmbedContainer {
        StreamEmbedContainer(coordinator: context.coordinator)
    }

    func updateUIView(_ container: StreamEmbedContainer, context: Context) {
        context.coordinator.playing = isPlaying
        let key = "\(videoId)|\(isLive)|\(fillCrop)"
        if context.coordinator.loadedKey != key {
            context.coordinator.loadedKey = key
            context.coordinator.lastCommandedPlaying = nil
            let html = Self.playerHTML(
                videoId: videoId,
                customerSubdomain: customerSubdomain,
                isLive: isLive,
                fillCrop: fillCrop
            )
            let base = "https://customer-\(customerSubdomain).cloudflarestream.com"
            container.webView.loadHTMLString(html, baseURL: URL(string: base))
            return
        }
        let want = isPlaying.wrappedValue
        if context.coordinator.lastCommandedPlaying != want {
            context.coordinator.lastCommandedPlaying = want
            let flag = want ? "true" : "false"
            container.webView.evaluateJavaScript("window.__jbmrSetPlaying && window.__jbmrSetPlaying(\(flag));")
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(playing: isPlaying)
    }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        var playing: Binding<Bool>
        var loadedKey: String?
        var lastCommandedPlaying: Bool?

        init(playing: Binding<Bool>) {
            self.playing = playing
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any] else { return }
            if let value = body["playing"] as? Bool {
                DispatchQueue.main.async {
                    self.lastCommandedPlaying = value
                    self.playing.wrappedValue = value
                }
            }
        }
    }

    final class StreamEmbedContainer: UIView {
        let webView: WKWebView

        init(coordinator: Coordinator) {
            let configuration = WKWebViewConfiguration()
            configuration.allowsInlineMediaPlayback = true
            configuration.allowsAirPlayForMediaPlayback = true
            configuration.allowsPictureInPictureMediaPlayback = true
            configuration.userContentController.add(coordinator, name: "jbmr")
            if #available(iOS 10.0, *) {
                configuration.mediaTypesRequiringUserActionForPlayback = []
            }
            let webView = WKWebView(frame: .zero, configuration: configuration)
            webView.isOpaque = false
            webView.backgroundColor = .black
            webView.scrollView.isOpaque = false
            webView.scrollView.backgroundColor = .black
            webView.scrollView.isScrollEnabled = false
            webView.scrollView.bounces = false
            webView.scrollView.contentInsetAdjustmentBehavior = .never
            self.webView = webView
            super.init(frame: .zero)
            backgroundColor = .black
            clipsToBounds = true
            isOpaque = true
            addSubview(webView)
        }

        required init?(coder: NSCoder) { nil }

        deinit {
            webView.configuration.userContentController.removeScriptMessageHandler(forName: "jbmr")
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            webView.frame = bounds
        }
    }

    /// LIVE: WHEP if 201; else LL-HLS when 200; iframe only after fatal HLS. No 1s seek snaps.
    static func playerHTML(videoId: String, customerSubdomain: String, isLive: Bool, fillCrop: Bool = false) -> String {
        let base = "https://customer-\(customerSubdomain).cloudflarestream.com"
        let iframeSrc = "\(base)/\(videoId)/iframe?autoplay=true&muted=true&preload=auto&letterboxColor=black&controls=false"
        let iframeFill = fillCrop
            ? "position:absolute;left:50%;top:50%;width:177.78%;height:100%;transform:translate(-50%,-50%);"
            : "width:100%;height:100%;"
        if !isLive {
            return """
            <!DOCTYPE html>
            <html>
            <head>
              <meta charset="utf-8" />
              <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1" />
              <style>
                html, body { margin: 0; height: 100%; background: #000; overflow: hidden; }
                body { position: relative; }
                iframe { border: 0; display: block; \(iframeFill) }
              </style>
            </head>
            <body>
              <iframe
                src="\(iframeSrc)"
                allow="accelerometer; gyroscope; autoplay; encrypted-media; picture-in-picture;"
                allowfullscreen
              ></iframe>
            </body>
            </html>
            """
        }
        let hlsLL = "\(base)/\(videoId)/manifest/video.m3u8?protocol=llhls"
        let hlsStd = "\(base)/\(videoId)/manifest/video.m3u8"
        let whep = "\(base)/\(videoId)/webRTC/play"
        return """
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="utf-8" />
          <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1" />
          <style>
            html, body { margin: 0; height: 100%; background: #07080c; overflow: hidden; position: relative; }
            #iframe {
              position: absolute; inset: 0; width: 100%; height: 100%; border: 0; display: none; z-index: 1;
            }
            #live {
              position: absolute; inset: 0; width: 100%; height: 100%; object-fit: \(fillCrop ? "cover" : "contain");
              background: #07080c; display: none; z-index: 2;
            }
            #status {
              position: absolute; left: 12px; right: 12px; bottom: 14px; z-index: 3;
              display: flex; align-items: center; justify-content: center;
              color: #e8eaed; font: 600 12px/1.35 -apple-system, BlinkMacSystemFont, sans-serif;
              text-align: center; padding: 8px 12px; border-radius: 8px;
              background: rgba(7,8,12,0.72); pointer-events: none; letter-spacing: 0.2px;
            }
          </style>
          <script src="https://cdn.jsdelivr.net/npm/hls.js@1.5.20/dist/hls.min.js"></script>
        </head>
        <body>
          <iframe id="iframe"
            allow="accelerometer; gyroscope; autoplay; encrypted-media; picture-in-picture; microphone;"
            allowfullscreen></iframe>
          <video id="live" autoplay playsinline webkit-playsinline muted></video>
          <div id="status"></div>
          <script>
            const HLS_LL = "\(hlsLL)";
            const HLS_STD = "\(hlsStd)";
            const WHEP = "\(whep)";
            const IFRAME_SRC = "\(iframeSrc)";
            const video = document.getElementById("live");
            const iframe = document.getElementById("iframe");
            const status = document.getElementById("status");
            var hls = null;
            var pc = null;
            var mode = "idle";
            var hlsSrc = HLS_LL;
            var fatalTries = 0;
            var miss = 0;
            var playWatch = 0;
            var lastIframeRetry = 0;
            var lastSnapAt = 0;
            var didInitialSnap = false;
            var stalledSince = 0;
            var whepUnavailable = false;
            var whepBusy = false;
            var lastWhepAt = 0;
            var userPaused = false;
            function notifyPlaying(on) {
              try {
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.jbmr) {
                  window.webkit.messageHandlers.jbmr.postMessage({ playing: !!on });
                }
                if (window.JBMR && window.JBMR.playing) window.JBMR.playing(!!on);
              } catch (e) {}
            }
            window.__jbmrSetPlaying = function (on) {
              userPaused = !on;
              if (!on) {
                try { video.pause(); } catch (e) {}
                notifyPlaying(false);
                return;
              }
              video.play().then(function () { notifyPlaying(true); }).catch(function () {});
            };
            function isLivePlaying() {
              return (mode === "live" || mode === "whep") && !video.paused && video.readyState >= 2;
            }
            function stopRtc() {
              if (pc) {
                try { pc.getSenders().forEach(function () {}); pc.close(); } catch (e) {}
                pc = null;
              }
            }
            function stopHls() {
              if (hls) { try { hls.destroy(); } catch (e) {} hls = null; }
              stopRtc();
              try {
                video.pause();
                video.removeAttribute("src");
                video.srcObject = null;
              } catch (e) {}
              video.style.display = "none";
            }
            function hideIframe() {
              iframe.style.display = "none";
              try { iframe.removeAttribute("src"); iframe.src = "about:blank"; } catch (e) {}
            }
            function showIframePlayer() {
              video.style.display = "none";
              iframe.style.display = "block";
              if (iframe.getAttribute("src") !== IFRAME_SRC) iframe.src = IFRAME_SRC;
            }
            function showWaiting() {
              if (isLivePlaying()) return;
              mode = "idle";
              stopHls();
              showIframePlayer();
              status.style.display = "none";
            }
            function fallbackIframe() {
              if (isLivePlaying()) return;
              mode = "iframe";
              stopHls();
              showIframePlayer();
              status.style.display = "none";
              lastIframeRetry = Date.now();
              notifyPlaying(true);
            }
            function onLivePlaying() {
              if (userPaused) return;
              if (video.readyState < 2 && !video.srcObject) return;
              fatalTries = 0;
              stalledSince = 0;
              playWatch = 0;
              status.style.display = "none";
              video.style.display = "block";
              hideIframe();
              notifyPlaying(true);
              if (mode === "live" && !didInitialSnap) {
                didInitialSnap = true;
                snapLive(true);
              }
            }
            function hlsConfig() {
              return {
                enableWorker: true,
                lowLatencyMode: true,
                liveSyncDurationCount: 2,
                liveMaxLatencyDurationCount: 8,
                liveDurationInfinity: true,
                maxBufferLength: 8,
                maxMaxBufferLength: 12,
                maxBufferHole: 0.5,
                backBufferLength: 8,
                maxLiveSyncPlaybackRate: 1.06,
                startPosition: -1
              };
            }
            function startHls(src) {
              if (mode === "whep" && isLivePlaying()) return;
              if (mode === "live" && hlsSrc === src && (hls || video.getAttribute("src"))) return;
              if (isLivePlaying() && mode === "live") return;
              mode = "live";
              hlsSrc = src;
              didInitialSnap = false;
              lastSnapAt = 0;
              hideIframe();
              status.style.display = "none";
              video.style.display = "block";
              stopRtc();
              if (window.Hls && window.Hls.isSupported()) {
                if (hls) { try { hls.destroy(); } catch (e) {} hls = null; }
                hls = new Hls(hlsConfig());
                hls.loadSource(src);
                hls.attachMedia(video);
                hls.on(Hls.Events.MANIFEST_PARSED, function () { if (!userPaused) video.play().catch(function () {}); });
                hls.on(Hls.Events.ERROR, function (_, data) {
                  if (!(data && data.fatal)) return;
                  onHlsFail(src);
                });
                playWatch = Date.now();
                return;
              }
              if (video.canPlayType("application/vnd.apple.mpegurl")) {
                if (video.getAttribute("src") !== src) video.src = src;
                if (!userPaused) video.play().catch(function () {});
                playWatch = Date.now();
                return;
              }
              fallbackIframe();
            }
            function onHlsFail(src) {
              if (isLivePlaying()) return;
              fatalTries += 1;
              try { if (hls) hls.destroy(); } catch (e) {}
              hls = null;
              mode = "retry";
              if (fatalTries < 3) { setTimeout(function () { startHls(src); }, 700); }
              else { fallbackIframe(); }
            }
            function startWhep(sdpAnswer, localPc) {
              mode = "whep";
              hideIframe();
              status.style.display = "none";
              if (hls) { try { hls.destroy(); } catch (e) {} hls = null; }
              video.removeAttribute("src");
              video.style.display = "block";
              localPc.setRemoteDescription({ type: "answer", sdp: sdpAnswer }).then(function () {
                pc = localPc;
                playWatch = Date.now();
                if (!userPaused) video.play().catch(function () {});
              }).catch(function () {
                try { localPc.close(); } catch (e) {}
                whepUnavailable = true;
              });
            }
            function tryWhep() {
              if (whepUnavailable || whepBusy || userPaused) return Promise.resolve(0);
              if (mode === "whep" && isLivePlaying()) return Promise.resolve(201);
              var now = Date.now();
              if (lastWhepAt && now - lastWhepAt < 8000) return Promise.resolve(0);
              lastWhepAt = now;
              whepBusy = true;
              var localPc = new RTCPeerConnection({
                iceServers: [{ urls: "stun:stun.cloudflare.com:3478" }]
              });
              localPc.addTransceiver("video", { direction: "recvonly" });
              localPc.addTransceiver("audio", { direction: "recvonly" });
              localPc.ontrack = function (ev) {
                if (ev.streams && ev.streams[0]) video.srcObject = ev.streams[0];
                else video.srcObject = new MediaStream([ev.track]);
                onLivePlaying();
              };
              return localPc.createOffer().then(function (offer) {
                return localPc.setLocalDescription(offer).then(function () {
                  return fetch(WHEP, {
                    method: "POST",
                    headers: { "Content-Type": "application/sdp" },
                    body: localPc.localDescription.sdp
                  });
                });
              }).then(function (res) {
                whepBusy = false;
                if (res.status === 201 || res.status === 200) {
                  return res.text().then(function (answer) {
                    startWhep(answer, localPc);
                    return 201;
                  });
                }
                try { localPc.close(); } catch (e) {}
                return res.text().then(function () { return res.status; }).catch(function () { return res.status; });
              }).catch(function () {
                whepBusy = false;
                try { localPc.close(); } catch (e) {}
                return 0;
              });
            }
            video.addEventListener("playing", onLivePlaying);
            video.addEventListener("loadeddata", onLivePlaying);
            video.addEventListener("pause", function () {
              if (userPaused) notifyPlaying(false);
            });
            video.addEventListener("waiting", function () {
              if ((mode === "live" || mode === "whep") && !stalledSince) stalledSince = Date.now();
            });
            video.addEventListener("error", function () {
              if (mode === "live" || mode === "retry") onHlsFail(hlsSrc);
              if (mode === "whep") {
                stopRtc();
                mode = "idle";
              }
            });
            function liveEdge() {
              var target = NaN;
              if (hls && isFinite(hls.liveSyncPosition)) target = hls.liveSyncPosition;
              if (!isFinite(target) && video.seekable && video.seekable.length) {
                target = video.seekable.end(video.seekable.length - 1);
              } else if (!isFinite(target) && video.buffered && video.buffered.length) {
                target = video.buffered.end(video.buffered.length - 1);
              }
              return target;
            }
            function snapLive(force) {
              if (mode !== "live") return;
              try {
                var now = Date.now();
                var stalled = stalledSince && (now - stalledSince > 2500);
                var target = liveEdge();
                var lag = NaN;
                if (hls && isFinite(hls.latency)) lag = hls.latency;
                if (!isFinite(lag) && isFinite(target)) lag = target - video.currentTime;
                if (!isFinite(target)) return;
                var farBehind = isFinite(lag) && lag > 12;
                if (!force && !stalled && !farBehind) return;
                if (!force && lastSnapAt && now - lastSnapAt < 15000) return;
                lastSnapAt = now;
                stalledSince = 0;
                video.currentTime = Math.max(0, target);
              } catch (e) {}
            }
            function handleHls(code, src) {
              if (code === 200) {
                miss = 0;
                if (mode === "whep" && isLivePlaying()) return;
                if (mode === "live") return;
                if (mode === "iframe") {
                  if (Date.now() - lastIframeRetry < 15000) return;
                  lastIframeRetry = Date.now();
                  fatalTries = 0;
                  startHls(src);
                  return;
                }
                startHls(src);
                return;
              }
              if (isLivePlaying()) { miss = 0; return; }
              miss += 1;
              if ((mode === "live" || mode === "retry" || mode === "whep") && miss < 2) return;
              showWaiting();
            }
            function probe() {
              if (userPaused) return;
              var hlsP = fetch(HLS_LL, { method: "GET", cache: "no-store" }).then(function (r) {
                if (r.status === 200 || r.status === 204) return { status: r.status, src: HLS_LL };
                return fetch(HLS_STD, { method: "GET", cache: "no-store" }).then(function (s) {
                  return { status: s.status, src: s.status === 200 ? HLS_STD : HLS_LL };
                });
              }).catch(function () {
                return fetch(HLS_STD, { method: "GET", cache: "no-store" }).then(function (g) {
                  return { status: g.status, src: g.status === 200 ? HLS_STD : HLS_LL };
                }).catch(function () { return { status: 0, src: HLS_LL }; });
              });
              var whepP = (whepUnavailable || isLivePlaying()) ? Promise.resolve(0) : tryWhep();
              Promise.all([hlsP, whepP]).then(function (pair) {
                var h = pair[0];
                var w = pair[1];
                if (w === 201) return;
                if (h.status === 200 && w === 409) {
                  whepUnavailable = true;
                }
                handleHls(h.status, h.src);
              });
              if ((mode === "live" || mode === "whep") && playWatch && Date.now() - playWatch > 8000 && video.readyState < 2 && !video.srcObject) {
                if (mode === "live") onHlsFail(hlsSrc);
              }
              snapLive(false);
            }
            probe();
            setInterval(probe, 2000);
          </script>
        </body>
        </html>
        """
    }
}
