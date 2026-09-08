import Foundation
import BrimCore

/// Reads what Perplexity's Mac app has left, from the preferences it already writes.
///
/// Polls the modification date, the same way `ClaudeUsageReader` does and for the same
/// reason: preferences are replaced atomically, so a vnode source would need re-arming
/// on every write, and the file changes far more often than the usage block inside it.
///
/// One caveat worth knowing when the number looks behind: macOS buffers preference
/// writes in `cfprefsd`, so the file on disk can trail what the running app believes by
/// up to a flush. The snapshot therefore carries the file's own modification date, not
/// the time it was read, so a reading that is a few minutes old says so rather than
/// presenting itself as current.
///
/// Nothing here is a credential and nothing is sent anywhere. This is one plist in the
/// user's own library, read only after Connect.
@MainActor
final class PerplexityReader {
    var onSnapshot: ((UsageSnapshot) -> Void)?
    /// The app is installed but its preferences hold no usage block yet, which is what
    /// a Perplexity that has never been signed in to looks like.
    var onAbsent: (() -> Void)?
    var onFailure: ((String) -> Void)?

    private var lastModified: Date?
    private var lastCounts: [UsageCount]?

    static var path: URL {
        URL(fileURLWithPath: (PerplexityUsage.preferencesPath as NSString).expandingTildeInPath)
    }

    /// Forget what was seen, so the next refresh republishes.
    func reset() {
        lastModified = nil
        lastCounts = nil
    }

    func refresh() {
        let path = Self.path
        guard let modified = try? path.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate else {
            reset()
            onAbsent?()
            return
        }
        guard modified != lastModified else { return }
        lastModified = modified
        guard let data = try? Data(contentsOf: path) else {
            onFailure?("Couldn’t read Perplexity’s preferences. This usually clears on the next refresh.")
            return
        }
        do {
            let counts = try PerplexityUsage.counts(data)
            guard counts != lastCounts else { return }
            lastCounts = counts
            onSnapshot?(UsageSnapshot(provider: .perplexity, windows: [], counts: counts,
                                      source: .perplexityApp, updatedAt: modified,
                                      plan: PerplexityUsage.plan(data)))
        } catch UsageParseError.missingLimits {
            // Installed, opened, and never signed in: the preferences exist but hold
            // nothing metered. Not a fault, and not something to colour orange.
            lastCounts = nil
            onAbsent?()
        } catch {
            // Preferences are rewritten often, so a read can land mid-write. Retry on
            // the next tick rather than calling one bad parse a broken source.
            onFailure?("Couldn’t read Perplexity’s usage. This usually clears on the next refresh.")
        }
    }
}
