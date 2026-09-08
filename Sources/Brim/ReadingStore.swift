import Foundation
import BrimCore

/// Keeps the last good reading for each provider on disk.
///
/// Without this only Claude survived a relaunch, and only as a side effect of the old
/// bridge writing a file. Codex readings lived in memory and vanished on quit, so the
/// app opened blank and stayed blank until a fresh request happened to succeed.
///
/// Saved readings keep their original `updatedAt`, so a restored reading is correctly
/// reported as old rather than looking freshly fetched.
enum ReadingStore {
    static var path: URL { AppPaths.support.appendingPathComponent("readings.json") }

    /// Manual entries have their own file and are loaded separately.
    private static func isPersistable(_ snapshot: UsageSnapshot) -> Bool {
        snapshot.source != .manual
            && snapshot.windows.allSatisfy { $0.usedPercent.isFinite && $0.usedPercent >= 0 }
    }

    static func load() -> [Provider: UsageSnapshot] {
        guard let data = try? Data(contentsOf: path),
              let saved = try? JSONDecoder().decode([UsageSnapshot].self, from: data) else { return [:] }
        return Dictionary(saved.filter(isPersistable).map { ($0.provider, $0) },
                          uniquingKeysWith: { first, _ in first })
    }

    static func save(_ snapshots: [Provider: UsageSnapshot]) throws {
        let entries = snapshots.values.filter(isPersistable).sorted { $0.provider.rawValue < $1.provider.rawValue }
        guard !entries.isEmpty else {
            try? FileManager.default.removeItem(at: path)
            return
        }
        try AppPaths.prepare()
        try JSONEncoder().encode(entries).write(to: path, options: .atomic)
    }
}
