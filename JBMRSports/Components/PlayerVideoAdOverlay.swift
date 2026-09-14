import AVFoundation
import SwiftUI
import UIKit

#if canImport(GoogleInteractiveMediaAds)
import GoogleInteractiveMediaAds

/// Player ke andar real video ad (IMA) — skippable ya non-skippable ad creative ke hisaab se.
struct PlayerVideoAdOverlay: UIViewRepresentable {
    let player: AVPlayer
    let adTagURLs: [String]
    let onFinished: () -> Void
    var onFailed: (() -> Void)? = nil

    init(
        player: AVPlayer,
        onFinished: @escaping () -> Void,
        onFailed: (() -> Void)? = nil
    ) {
        self.player = player
        self.adTagURLs = AdMobConfig.playerVideoAdTagURLs
        self.onFinished = onFinished
        self.onFailed = onFailed
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinished: onFinished, onFailed: onFailed)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        context.coordinator.attach(to: view, player: player, adTagURLs: adTagURLs)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.teardown()
    }

    @MainActor
    final class Coordinator: NSObject, IMAAdsLoaderDelegate, IMAAdsManagerDelegate {
        private let adContainer = UIView()
        private weak var hostView: UIView?

        private var adsLoader = IMAAdsLoader()
        private var adsManager: IMAAdsManager?
        private var contentPlayer: AVPlayer?
        private var contentPlayhead: IMAAVPlayerContentPlayhead?
        private var adTagURLs: [String] = []
        private var tagIndex = 0

        private let onFinished: () -> Void
        private let onFailed: (() -> Void)?

        private var didFinish = false
        private var didRequest = false
        private var statusObserver: NSKeyValueObservation?
        private var layoutAttempts = 0

        init(onFinished: @escaping () -> Void, onFailed: (() -> Void)?) {
            self.onFinished = onFinished
            self.onFailed = onFailed
        }

        func attach(to hostView: UIView, player: AVPlayer, adTagURLs: [String]) {
            self.hostView = hostView
            self.contentPlayer = player
            self.contentPlayhead = IMAAVPlayerContentPlayhead(avPlayer: player)
            self.adTagURLs = adTagURLs

            adContainer.backgroundColor = .black
            adContainer.translatesAutoresizingMaskIntoConstraints = false
            hostView.addSubview(adContainer)
            NSLayoutConstraint.activate([
                adContainer.topAnchor.constraint(equalTo: hostView.topAnchor),
                adContainer.bottomAnchor.constraint(equalTo: hostView.bottomAnchor),
                adContainer.leadingAnchor.constraint(equalTo: hostView.leadingAnchor),
                adContainer.trailingAnchor.constraint(equalTo: hostView.trailingAnchor),
            ])

            adsLoader.delegate = self
            contentPlayer?.pause()
            waitForPlayerThenRequest()
        }

        func teardown() {
            statusObserver?.invalidate()
            statusObserver = nil
            adsManager?.destroy()
            adsManager = nil
            adContainer.removeFromSuperview()
        }

        private func waitForPlayerThenRequest() {
            guard let item = contentPlayer?.currentItem else {
                scheduleLayoutCheck()
                return
            }

            if item.status == .readyToPlay {
                scheduleLayoutCheck()
                return
            }

            statusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
                guard item.status == .readyToPlay || item.status == .failed else { return }
                DispatchQueue.main.async {
                    self?.scheduleLayoutCheck()
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                self?.scheduleLayoutCheck()
            }
        }

        private func scheduleLayoutCheck() {
            guard !didFinish, !didRequest else { return }
            layoutAttempts += 1
            guard layoutAttempts < 40 else {
                retryOrFail()
                return
            }

            guard adContainer.bounds.width > 10, adContainer.bounds.height > 10 else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    self?.scheduleLayoutCheck()
                }
                return
            }

            requestAds()
        }

        private func requestAds() {
            guard !didFinish, !didRequest else { return }
            guard tagIndex < adTagURLs.count else {
                retryOrFail()
                return
            }
            guard let contentPlayhead else {
                retryOrFail()
                return
            }

            didRequest = true
            let hostVC = AdMobService.topViewController() ?? UIViewController()
            let displayContainer = IMAAdDisplayContainer(
                adContainer: adContainer,
                viewController: hostVC,
                companionSlots: nil
            )
            let request = IMAAdsRequest(
                adTagUrl: adTagURLs[tagIndex],
                adDisplayContainer: displayContainer,
                contentPlayhead: contentPlayhead,
                userContext: nil
            )
            NSLog("JBMR IMA requesting tag %d", tagIndex)
            adsLoader.requestAds(with: request)
        }

        private func retryOrFail() {
            tagIndex += 1
            didRequest = false
            layoutAttempts = 0
            adsManager?.destroy()
            adsManager = nil
            adsLoader = IMAAdsLoader()
            adsLoader.delegate = self

            if tagIndex < adTagURLs.count {
                NSLog("JBMR IMA trying fallback tag %d", tagIndex)
                scheduleLayoutCheck()
                return
            }

            NSLog("JBMR IMA all tags failed")
            if let onFailed {
                onFailed()
            } else {
                finish()
            }
        }

        private func finish() {
            guard !didFinish else { return }
            didFinish = true
            adsManager?.destroy()
            adsManager = nil
            onFinished()
        }

        // MARK: - IMAAdsLoaderDelegate

        func adsLoader(_ loader: IMAAdsLoader, adsLoadedWith adsLoadedData: IMAAdsLoadedData) {
            NSLog("JBMR IMA ads loaded")
            adsManager = adsLoadedData.adsManager
            adsManager?.delegate = self

            let settings = IMAAdsRenderingSettings()
            settings.linkOpenerPresentingController = AdMobService.topViewController()
            adsManager?.initialize(with: settings)
        }

        func adsLoader(_ loader: IMAAdsLoader, failedWith adErrorData: IMAAdLoadingErrorData) {
            NSLog("JBMR IMA load error: %@", adErrorData.adError.message ?? "unknown")
            retryOrFail()
        }

        // MARK: - IMAAdsManagerDelegate

        func adsManager(_ adsManager: IMAAdsManager, didReceive event: IMAAdEvent) {
            switch event.type {
            case .LOADED:
                NSLog("JBMR IMA ad loaded, starting")
                adsManager.start()
            case .STARTED:
                NSLog("JBMR IMA ad started")
            case .COMPLETE, .SKIPPED:
                NSLog("JBMR IMA ad ended: %@", event.type == .SKIPPED ? "skipped" : "complete")
            case .ALL_ADS_COMPLETED:
                NSLog("JBMR IMA all ads completed")
                finish()
            default:
                break
            }
        }

        func adsManager(_ adsManager: IMAAdsManager, didReceive error: IMAAdError) {
            NSLog("JBMR IMA manager error: %@", error.message ?? "unknown")
            retryOrFail()
        }

        func adsManagerDidRequestContentPause(_ adsManager: IMAAdsManager) {
            contentPlayer?.pause()
        }

        func adsManagerDidRequestContentResume(_ adsManager: IMAAdsManager) {}
    }
}

#else

struct PlayerVideoAdOverlay: View {
    let player: AVPlayer
    let onFinished: () -> Void
    var onFailed: (() -> Void)? = nil

    init(
        player: AVPlayer,
        onFinished: @escaping () -> Void,
        onFailed: (() -> Void)? = nil
    ) {
        self.player = player
        self.onFinished = onFinished
        self.onFailed = onFailed
    }

    var body: some View {
        Color.black
            .onAppear {
                if let onFailed { onFailed() } else { onFinished() }
            }
    }
}

#endif
