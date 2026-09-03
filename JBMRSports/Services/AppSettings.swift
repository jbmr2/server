import Foundation
import Network
import Combine

enum AppSettings {
    static let autoPlayKey = "jbmr_auto_play"
    static let liveAlertsKey = "jbmr_live_alerts"
    static let wifiOnlyKey = "jbmr_wifi_only"

    static var autoPlay: Bool {
        UserDefaults.standard.object(forKey: autoPlayKey) as? Bool ?? true
    }

    static var wifiOnlyStreaming: Bool {
        UserDefaults.standard.object(forKey: wifiOnlyKey) as? Bool ?? false
    }
}

@MainActor
final class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()

    @Published private(set) var isOnWifi = true

    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isOnWifi = path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet)
            }
        }
        monitor.start(queue: DispatchQueue(label: "jbmr.network.monitor"))
    }
}
