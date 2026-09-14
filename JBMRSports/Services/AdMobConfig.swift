import Foundation

enum AdMobConfig {
    /// Production App ID — App Store release se pehle URLScheme.plist mein bhi yahi lagao
    static let appID = "ca-app-pub-4073629083284169~236964443"

    /// Player ke andar banner (legacy fallback)
    static let playerAd = "ca-app-pub-3940256099942544/2934735716"

    /// IMA VAST video ad tags — pehla fail ho to doosra try hota hai.
    static var playerVideoAdTagURLs: [String] {
        let correlator = Int(Date().timeIntervalSince1970 * 1000)
        return [
            playerVideoAdTagURL(sample: "skippablelinear", correlator: correlator),
            playerVideoAdTagURL(sample: "linear", correlator: correlator + 1),
            "https://pubads.g.doubleclick.net/gampad/ads?sz=640x480&iu=/124319096/external/single_ad_samples&ciu_szs=300x250&impl=s&gdfp_req=1&env=vp&output=vast&unviewed_position_start=1&cust_params=deployment%3Ddevsite%26sample_ct%3Dskippablelinear&correlator=\(correlator + 2)",
        ]
    }

    static func playerVideoAdTagURL(
        sample: String = "skippablelinear",
        correlator: Int = Int(Date().timeIntervalSince1970 * 1000)
    ) -> String {
        "https://pubads.g.doubleclick.net/gampad/ads?"
            + "iu=/21775744923/external/single_ad_samples"
            + "&sz=640x480"
            + "&cust_params=sample_ct%3D\(sample)"
            + "&ciu_szs=300x250%2C728x90"
            + "&gdfp_req=1&output=vast&unviewed_position_start=1&env=vp&impl=s&correlator="
            + "\(correlator)"
    }
}
