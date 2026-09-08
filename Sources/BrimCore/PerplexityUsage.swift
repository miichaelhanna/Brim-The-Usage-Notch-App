import Foundation

/// One allowance a tool reports as a count rather than as a proportion.
///
/// Most providers say how much of an allowance is gone, which is a ring. Perplexity
/// says only how many goes are left, and never how many there were, so there is no
/// denominator anywhere on the machine to divide by. Rather than invent one, the
/// reading keeps the shape the provider actually gave it.
public struct UsageCount: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    /// How many are left. Nil when the provider says the mode cannot be used right
    /// now, which it reports the same way whether the plan never included it or the
    /// allowance is spent. Nil rather than 0 because those are different facts and
    /// the file does not distinguish them.
    public var remaining: Int?

    public init(id: String, title: String, remaining: Int?) {
        self.id = id; self.title = title; self.remaining = remaining
    }

    /// What the number reads as, in the one place it is phrased.
    public var detail: String {
        guard let remaining else { return "Unavailable" }
        return "\(remaining) left"
    }
}

/// Perplexity's own record of what is left, as its Mac app writes it.
///
/// The app keeps this in its preferences, under `remainingUsage`, and stores it as a
/// *string* of JSON rather than as property-list values, so it is decoded twice: once
/// as a plist, once as JSON out of the string that plist holds.
///
/// It reports only what remains. There is no allowance and no reset time in the file,
/// nor anywhere else the app writes, so this produces counts rather than windows and
/// Brim shows "4 Pro searches left" instead of a ring. Picking a denominator would
/// mean inventing the one number Perplexity declines to give, and a ring drawn from a
/// guess is the thing this app exists not to do.
public enum PerplexityUsage {
    /// Where the Mac app keeps it. `~` is expanded by the caller.
    public static let preferencesPath = "~/Library/Preferences/ai.perplexity.macv3.plist"

    /// Perplexity's own names for the modes it meters, so the app does not invent a
    /// second vocabulary for something the user already sees named in Perplexity.
    /// An unrecognised id keeps its own name rather than being dropped: a new mode is
    /// still a real allowance, and a rename here should not silently hide one.
    private static let modeTitles = [
        "pro_search": "Pro searches",
        "research": "Deep research",
        "agentic_research": "Model council",
        "browser_agent": "Control browser",
        "asi": "Computer",
    ]

    /// The counts inside a copy of that preferences file.
    ///
    /// Throws only when the file cannot be understood at all. A file that parses but
    /// meters nothing is an empty result, not a failure: an account with no counted
    /// limits is a real state, and reporting it as a broken read would be a lie about
    /// a working machine.
    public static func counts(_ data: Data) throws -> [UsageCount] {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw UsageParseError.invalidData
        }
        guard let root = json(plist["remainingUsage"]) else { throw UsageParseError.missingLimits }
        guard let modes = root["modes"] as? [String: Any] else { return [] }

        return modes.keys.sorted { rank($0) < rank($1) }.compactMap { id in
            guard let mode = modes[id] as? [String: Any] else { return nil }
            // A mode Perplexity marks unavailable gets no number. It reports a plan
            // that never included the mode and an allowance spent to the last query
            // identically, both as zero, so neither claim is made here.
            guard mode["available"] as? Bool ?? true else {
                return UsageCount(id: id, title: title(id), remaining: nil)
            }
            // "exact" is the only kind carrying a number. The others say, in so many
            // words, that Perplexity is not telling, so the mode is left out rather
            // than shown as none left.
            let detail = mode["remaining_detail"] as? [String: Any]
            guard detail?["kind"] as? String == "exact",
                  let remaining = UsageParser.number(detail?["remaining"]) else { return nil }
            return UsageCount(id: id, title: title(id), remaining: Int(remaining))
        }
    }

    /// The account's plan, when the app has recorded one. Shown rather than used:
    /// nothing here is derived from it, because a tier name is not an allowance.
    public static func plan(_ data: Data) -> String? {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let user = json(plist["current_user__data"]),
              let subscription = user["subscription"] as? [String: Any],
              let tier = subscription["tier"] as? String, tier != "none" else { return nil }
        return tier.capitalized
    }

    /// Perplexity stores JSON as a string inside the plist, so a value is decoded
    /// twice. Accepts either the data or the string form; older builds wrote both.
    private static func json(_ value: Any?) -> [String: Any]? {
        let data: Data? = switch value {
        case let data as Data: data
        case let string as String: string.data(using: .utf8)
        default: nil
        }
        guard let data else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func title(_ id: String) -> String {
        modeTitles[id] ?? id.replacingOccurrences(of: "_", with: " ").capitalized
    }

    /// Keeps the listed modes in Perplexity's own order and sends anything new to the
    /// end, so a mode this build has never heard of cannot displace a known one.
    private static func rank(_ id: String) -> String {
        let order = ["pro_search", "research", "agentic_research", "browser_agent", "asi"]
        guard let index = order.firstIndex(of: id) else { return "z\(id)" }
        return "\(index)"
    }
}
