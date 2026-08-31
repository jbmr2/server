import AVFoundation
import SwiftUI
import UIKit

enum HeroVideoFrameLoader {
    static func frame(from url: URL, at seconds: Double = 1.2) async -> UIImage? {
        await Task.detached(priority: .utility) {
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 960, height: 1280)

            for seek in [seconds, 0.4, 0] {
                let time = CMTime(seconds: seek, preferredTimescale: 600)
                if let cg = try? generator.copyCGImage(at: time, actualTime: nil) {
                    return UIImage(cgImage: cg)
                }
            }
            return nil
        }.value
    }
}

@MainActor
final class HeroFrameCache {
    static let shared = HeroFrameCache()

    private var images: [String: UIImage] = [:]

    private init() {}

    func image(for url: URL?) -> UIImage? {
        guard let url else { return nil }
        return images[url.absoluteString]
    }

    func preload(matches: [FeaturedMatch]) async {
        await withTaskGroup(of: (String, UIImage?).self) { group in
            for match in matches where match.isMatchHighlightSlide {
                guard let url = match.videoURL else { continue }
                let key = url.absoluteString
                if images[key] != nil { continue }
                group.addTask {
                    let frame = await HeroVideoFrameLoader.frame(from: url)
                    return (key, frame)
                }
            }
            for await (key, frame) in group {
                if let frame {
                    images[key] = frame
                }
            }
        }
    }
}

struct HeroVideoFrameBackground<Fallback: View>: View {
    let url: URL?
    @ViewBuilder var fallback: () -> Fallback

    @State private var frame: UIImage?

    var body: some View {
        ZStack {
            if let frame {
                Image(uiImage: frame)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .transition(.opacity)
            } else {
                fallback()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            }
        }
        .clipped()
        .task(id: url) {
            guard let url else {
                frame = nil
                return
            }
            if let cached = HeroFrameCache.shared.image(for: url) {
                frame = cached
                return
            }
            let loaded = await HeroVideoFrameLoader.frame(from: url)
            frame = loaded
        }
    }
}
