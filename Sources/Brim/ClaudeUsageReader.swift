import Foundation
import BrimCore

/// Reads Claude's usage from the cache Claude Code keeps in `~/.claude.json`.
///
/// Polls the modification date rather than watching with a `DispatchSource`: Claude
/// Code replaces this file atomically, which invalidates a vnode source's descriptor
/// and would mean re-arming it on every write. The surrounding file changes every few
/// minutes while the usage block inside it changes rarely, so a reading is published
/// only when it actually differs.
///
/// The reading carries its own `fetchedAt` as the snapshot timestamp, which is
/// frequently hours or days old. That staleness is the honest state of this source
/// and must be shown, not smoothed over.
@MainActor
final class ClaudeUsageReader {
    var onReading: ((ClaudeAccountUsage) -> Void)?
    var onAbsent: (() -> Void)?
    var onFailure: ((String) -> Void)?

    private(set) var lastReading: ClaudeAccountUsage?
    private var lastModified: Date?

    static var path: URL { AppPaths.claudeConfig }

    /// Forget what was seen, so the next refresh republishes. Used when the signed-in
    /// account changes and a previous account's numbers must not linger.
    func reset() {
        lastModified = nil
        lastReading = nil
    }

    func refresh() {
        let path = Self.path
        guard let modified = try? path.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate else {
            lastModified = nil
            onAbsent?()
            return
        }
        guard modified != lastModified else { return }
        lastModified = modified
        do {
            guard let reading = try ClaudeUsageCache.read(Data(contentsOf: path)) else {
                onAbsent?()
                return
            }
            guard reading != lastReading else { return }
            lastReading = reading
            onReading?(reading)
        } catch {
            // The file is rewritten frequently, so a read can land mid-write. Retry on
            // the next tick rather than treating one bad parse as a broken source.
            onFailure?("Couldn’t read Claude’s usage file. This usually clears on the next refresh.")
        }
    }
}
