import SwiftUI
import UIKit

#if canImport(GoogleMobileAds)
import GoogleMobileAds

struct BannerAdView: UIViewRepresentable {
    @ObservedObject private var adMob = AdMobService.shared
    let adUnitID: String
    let adSize: GADAdSize

    init(adUnitID: String, adSize: GADAdSize = GADAdSizeBanner) {
        self.adUnitID = adUnitID
        self.adSize = adSize
    }

    func makeUIView(context: Context) -> GADBannerView {
        let banner = GADBannerView(adSize: adSize)
        banner.adUnitID = adUnitID
        banner.rootViewController = AdMobService.topViewController()
        banner.delegate = context.coordinator
        context.coordinator.banner = banner
        return banner
    }

    func updateUIView(_ uiView: GADBannerView, context: Context) {
        guard adMob.isStarted, !context.coordinator.didLoad else { return }
        context.coordinator.didLoad = true
        uiView.rootViewController = AdMobService.topViewController()
        uiView.load(GADRequest())
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, GADBannerViewDelegate {
        weak var banner: GADBannerView?
        var didLoad = false
    }
}

#else

struct BannerAdView: UIViewRepresentable {
    let adUnitID: String

    init(adUnitID: String, adSize: Any? = nil) {
        self.adUnitID = adUnitID
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

#endif

/// IMA fail hone par player ke andar banner ad fallback.
struct PlayerBannerAdFallback: View {
    let adUnitID: String
    let onFinished: () -> Void

    @State private var secondsRemaining = 8

    var body: some View {
        ZStack {
            Color.black.opacity(0.95)

            VStack(spacing: 14) {
                Text("Advertisement")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.7))
                    .textCase(.uppercase)

                #if canImport(GoogleMobileAds)
                BannerAdView(adUnitID: adUnitID, adSize: GADAdSizeMediumRectangle)
                    .frame(width: 300, height: 250)
                #else
                BannerAdView(adUnitID: adUnitID)
                    .frame(width: 300, height: 250)
                #endif

                Text("Video in \(secondsRemaining)s")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(.horizontal, 16)
        }
        .task {
            for remaining in stride(from: 8, through: 1, by: -1) {
                secondsRemaining = remaining
                try? await Task.sleep(for: .seconds(1))
            }
            onFinished()
        }
    }
}
