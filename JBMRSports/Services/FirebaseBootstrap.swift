import FirebaseCore
import Foundation

enum FirebaseBootstrap {
    private static let legacyAdminAppID = "1:692709551364:ios:45bb82655a5626ab45f451"

    static func validateConfiguration() {
        if let issue = configurationIssue {
            NSLog("JBMR Firebase setup: %@", issue)
        }
    }

    static var configurationIssue: String? {
        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let dict = NSDictionary(contentsOfFile: path) as? [String: Any],
              let plistBundle = dict["BUNDLE_ID"] as? String,
              let appBundle = Bundle.main.bundleIdentifier else {
            return "GoogleService-Info.plist missing from app bundle"
        }

        if plistBundle != appBundle {
            return "Firebase bundle mismatch: plist=\(plistBundle), app=\(appBundle). Firebase Console se \(appBundle) ke liye naya iOS app add karo aur naya plist download karo."
        }

        if let appID = dict["GOOGLE_APP_ID"] as? String, appID == legacyAdminAppID {
            return "GoogleService-Info.plist abhi admin app (jbmrsportsott) ka hai. Firebase Console → Add iOS app → in.jbmrsports.ott → naya plist replace karo."
        }

        return nil
    }
}
