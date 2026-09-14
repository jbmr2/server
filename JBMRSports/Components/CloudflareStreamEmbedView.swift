import SwiftUI
import WebKit

enum CloudflareStreamURL {
    static func videoId(from url: URL) -> String? {
        let parts = url.path.split(separator: "/").map(String.init)
        return parts.first(where: { $0.count == 32 && isHexId($0) })
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
        return host.contains("cloudflarestream.com") || host == "videodelivery.net"
    }

    private static func isHexId(_ value: String) -> Bool {
        value.count == 32 && value.unicodeScalars.allSatisfy {
            CharacterSet(charactersIn: "0123456789abcdef").contains($0)
        }
    }
}

struct CloudflareStreamEmbedView: UIViewRepresentable {
    let videoId: String
    let customerSubdomain: String

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        if #available(iOS 10.0, *) {
            configuration.mediaTypesRequiringUserActionForPlayback = []
        }
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedVideoId != videoId else { return }
        context.coordinator.loadedVideoId = videoId

        let base = "https://customer-\(customerSubdomain).cloudflarestream.com"
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="utf-8" />
          <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1" />
          <style>
            html, body { margin: 0; height: 100%; background: #000; overflow: hidden; }
            stream { width: 100%; height: 100%; display: block; }
          </style>
        </head>
        <body>
          <stream
            src="\(videoId)"
            controls
            autoplay
            muted
            playsinline
            customer-domain-prefix="customer-\(customerSubdomain)"
          ></stream>
          <script
            defer
            src="\(base)/embed/sdk-iframe-integration.fla9.latest.js?video=\(videoId)"
          ></script>
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: URL(string: base))
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var loadedVideoId: String?
    }
}
