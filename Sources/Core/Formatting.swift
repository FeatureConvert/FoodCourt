import Foundation

/// Idle games run to absurd numbers, so everything the player sees goes through here.
/// Short scale up to trillions, then the classic `aa, ab, ac…` ladder used by the genre.
enum Format {

    private static let shortSuffixes = ["", "K", "M", "B", "T"]

    /// `1234` -> `1.23K`, `4.5e18` -> `4.50ac`
    static func currency(_ value: Double) -> String {
        guard value.isFinite else { return "∞" }
        let v = abs(value)
        let sign = value < 0 ? "-" : ""

        if v < 1000 {
            // Under a thousand we show whole coins - fractional coins read as noise.
            return sign + String(Int(v))
        }

        var tier = Int(floor(log10(v) / 3))
        var scaled = v / pow(1000, Double(tier))

        // Rounding near a tier boundary (e.g. 999.996B) can push the displayed mantissa to
        // 1000; bump to the next tier rather than ever showing a 4-digit mantissa.
        if scaled >= 999.995 {
            tier += 1
            scaled = v / pow(1000, Double(tier))
        }

        let suffix = suffixForTier(tier)

        // Keep the mantissa three significant digits wide so the HUD never jitters in width.
        let digits: Int
        if scaled >= 100 { digits = 0 }
        else if scaled >= 10 { digits = 1 }
        else { digits = 2 }

        return sign + String(format: "%.\(digits)f", scaled) + suffix
    }

    /// Tier 0 is units, 1 is thousands, and so on. Past "T" we switch to letter pairs.
    static func suffixForTier(_ tier: Int) -> String {
        if tier < shortSuffixes.count { return shortSuffixes[tier] }
        // aa, ab, ... az, ba, bb, ...
        let index = tier - shortSuffixes.count
        let first = Character(UnicodeScalar(97 + (index / 26) % 26)!)
        let second = Character(UnicodeScalar(97 + index % 26)!)
        return String([first, second])
    }

    /// Rate shown in the HUD, e.g. `12.4K/s`.
    static func rate(_ perSecond: Double) -> String {
        currency(perSecond) + "/s"
    }

    /// Whole numbers that stay small (gems, stars, levels).
    static func count(_ value: Int) -> String {
        if value < 10_000 {
            return NumberFormatter.grouped.string(from: NSNumber(value: value)) ?? "\(value)"
        }
        return currency(Double(value))
    }

    /// Agrees the noun with the count: "1 manager", "2 managers".
    static func plural(_ count: Int, _ singular: String, _ plural: String? = nil) -> String {
        "\(self.count(count)) " + (count == 1 ? singular : (plural ?? singular + "s"))
    }

    /// `9014` -> `2h 30m`. Used for boost timers and offline windows.
    static func duration(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded()))
        let h = s / 3600
        let m = (s % 3600) / 60
        let sec = s % 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m \(sec)s" }
        return "\(sec)s"
    }

    /// Compact `mm:ss` for countdowns that need a fixed width.
    static func clock(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded()))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    /// Cycle length on a station card: sub-second speeds matter once milestones stack up.
    static func cycle(_ seconds: TimeInterval) -> String {
        seconds < 1 ? String(format: "%.2fs", seconds) : String(format: "%.1fs", seconds)
    }
}

private extension NumberFormatter {
    static let grouped: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f
    }()
}
