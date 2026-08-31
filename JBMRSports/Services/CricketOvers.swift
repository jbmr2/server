import Foundation

enum CricketOvers {
    /// First over is 0.x. If CrickDB sends over 1 as the first over, shift down.
    static func oversBefore(overNumber: Int, minOverInInnings: Int) -> Int {
        if minOverInInnings <= 0 { return max(0, overNumber) }
        return max(0, overNumber - minOverInInnings)
    }

    /// 0.1…0.5 then 1.0 (never 0.6). Next over 1.1…1.5 then 2.0.
    static func ballLabel(overNumber: Int, ballNumber: Int, minOverInInnings: Int) -> String {
        let before = oversBefore(overNumber: overNumber, minOverInInnings: minOverInInnings)
        let ball = ballNumber <= 0 ? 1 : ballNumber
        if ball >= 6 {
            return "\(before + 1).0"
        }
        return "\(before).\(ball)"
    }

    static func overChipTitle(overNumber: Int, minOverInInnings: Int) -> String {
        "Over \(oversBefore(overNumber: overNumber, minOverInInnings: minOverInInnings) + 1)"
    }

    /// Scoreboard overs: 0.6 → 1.0, 1.6 → 2.0.
    static func format(_ value: Double) -> String {
        let parts = split(value)
        return "\(parts.overs).\(parts.balls)"
    }

    static func normalized(_ value: Double) -> Double {
        let parts = split(value)
        return Double(parts.overs) + Double(parts.balls) / 10.0
    }

    /// True decimal overs for run rate / economy (1.3 cricket = 1.5 decimal).
    static func decimal(_ value: Double) -> Double {
        let parts = split(value)
        return Double(parts.overs) + Double(parts.balls) / 6.0
    }

    private static func split(_ value: Double) -> (overs: Int, balls: Int) {
        guard value.isFinite else { return (0, 0) }
        let towardZero = value.rounded(.towardZero)
        guard towardZero.isFinite, towardZero >= Double(Int.min + 1), towardZero <= Double(Int.max - 1) else {
            return (0, 0)
        }
        var overs = Int(towardZero)
        var balls = Int(((value - Double(overs)) * 10).rounded())
        if balls < 0 { balls = 0 }
        while balls >= 6 {
            overs += 1
            balls -= 6
        }
        return (overs, balls)
    }
}
