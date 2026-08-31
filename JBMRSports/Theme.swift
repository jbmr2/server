import SwiftUI
import UIKit

enum Theme {
    /// Figma primary accent #00B4D8
    static let accent = Color(red: 0.00, green: 0.706, blue: 0.847)
    static let accentBright = Color(red: 0.00, green: 0.749, blue: 1.00) // #00BFFF
    static let accentDeep = Color(red: 0.18, green: 0.40, blue: 0.92)
    static let background = Color(red: 8 / 255, green: 8 / 255, blue: 12 / 255) // #08080C
    static let backgroundAlt = Color(red: 11 / 255, green: 11 / 255, blue: 18 / 255) // #0B0B12
    static let card = Color(red: 0.071, green: 0.082, blue: 0.106) // #12151B
    static let chip = Color(red: 0.071, green: 0.082, blue: 0.106)
    static let muted = Color(red: 0.557, green: 0.604, blue: 0.651) // #8E9AA6
    static let mutedSoft = Color(red: 0.557, green: 0.557, blue: 0.624) // #8E8E9F
    static let border = Color(red: 0.102, green: 0.114, blue: 0.145) // #1A1D25
    static let magenta = Color(red: 1.00, green: 0.118, blue: 0.482) // kept for splash/login
    static let sixGreen = Color(red: 0.12, green: 0.82, blue: 0.38)
    static let liveRed = Color(red: 0.90, green: 0.16, blue: 0.20)

    static func applyTabBarAppearance() {
        // Custom tab bar used in RootTabView — hide system tab bar chrome.
        UITabBar.appearance().isHidden = true
    }
}

extension Color {
    static func fromHex(_ raw: String?, fallback: Color) -> Color {
        guard var hex = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !hex.isEmpty else {
            return fallback
        }
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let value = UInt64(hex, radix: 16) else { return fallback }
        return Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

enum AppTab: Hashable {
    case home, schedule, create, shorts, profile
}
