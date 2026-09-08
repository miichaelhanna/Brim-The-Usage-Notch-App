import Foundation
import BrimCore

/// How long a tool was actually used, taken from the session transcripts that tool
/// already writes on this Mac.
///
/// **Only the timestamps.** The scan looks for `"timestamp":"` and reads the nineteen
/// bytes after it. The prompts, the code, the answers and the file paths in those
/// transcripts are never parsed, never held, and never leave the Mac; there is nowhere
/// in this type a message body could go even by accident. That is the whole reason it
/// scans bytes rather than decoding JSON.
///
/// Only tools that keep a local transcript can be measured this way, which is Claude
/// Code and Codex. Claude and ChatGPT in a browser leave nothing on this Mac to read,
/// and the view has to say so rather than showing them as zero.
enum TranscriptReader {
    struct Source: Sendable {
        let provider: Provider
        let folder: URL
        /// Codex keeps more than transcripts under its sessions folder.
        let prefix: String?
    }

    static var sources: [Source] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            Source(provider: .claudeCode,
                   folder: home.appendingPathComponent(".claude/projects", isDirectory: true),
                   prefix: nil),
            Source(provider: .codex,
                   folder: home.appendingPathComponent(".codex/sessions", isDirectory: true),
                   prefix: "rollout-")
        ]
    }

    static func transcripts(in source: Source) -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
        guard let walk = FileManager.default.enumerator(at: source.folder, includingPropertiesForKeys: keys,
                                                        options: [.skipsHiddenFiles]) else { return [] }
        return walk.compactMap { $0 as? URL }.filter { file in
            file.pathExtension == "jsonl"
                && source.prefix.map { file.lastPathComponent.hasPrefix($0) } ?? true
        }
    }

    /// The runs of work in one transcript.
    ///
    /// Stamps far outside the file's own lifetime are dropped. A transcript can quote
    /// a log or a JSON blob that carries a timestamp of its own, and one stray date
    /// from years ago would otherwise open a run on a day nobody worked.
    static func runs(in file: URL, modified: Date) -> [ActivityRun] {
        let stamps = timestamps(in: file).filter {
            $0 <= modified.addingTimeInterval(86_400) && $0 >= modified.addingTimeInterval(-400 * 86_400)
        }
        return ActivityTimeline.runs(from: stamps, sourceID: file.lastPathComponent)
    }

    static func timestamps(in file: URL) -> [Date] {
        // Mapped rather than read: one of these transcripts can be a hundred megabytes
        // of inlined attachments wrapped around a few thousand timestamps, and none of
        // that has any business being resident.
        guard let data = try? Data(contentsOf: file, options: .mappedIfSafe) else { return [] }
        let needle = Data(#""timestamp":""#.utf8)
        var stamps: [Date] = []
        var searchFrom = data.startIndex
        while searchFrom < data.endIndex,
              let found = data.range(of: needle, options: [], in: searchFrom..<data.endIndex) {
            let start = found.upperBound
            let end = data.index(start, offsetBy: 19, limitedBy: data.endIndex) ?? data.endIndex
            if let date = UTCTimestamp.parse(data[start..<end]) { stamps.append(date) }
            searchFrom = end
        }
        return stamps
    }
}

/// What the last scan found, per file, so the next one only reads what changed.
///
/// Without this every visit to the view would re-read every transcript on the Mac.
/// Runs are kept rather than daily totals: two sessions running at once overlap, and
/// only the runs themselves can be merged without counting that hour twice.
struct TranscriptCache: Codable {
    struct Entry: Codable {
        let modified: Date
        let size: Int
        let runs: [ActivityRun]
    }
    var files: [String: Entry] = [:]

    static var path: URL { AppPaths.support.appendingPathComponent("activity.json") }

    static func load() -> TranscriptCache {
        guard let data = try? Data(contentsOf: path),
              let cache = try? JSONDecoder().decode(TranscriptCache.self, from: data) else { return .init() }
        return cache
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? AppPaths.prepare()
        try? data.write(to: Self.path, options: .atomic)
    }

    /// Forget everything read from the transcripts. Turning the view off has to leave
    /// nothing behind, or "off" means only that the app stopped showing it.
    static func erase() { try? FileManager.default.removeItem(at: path) }
}
