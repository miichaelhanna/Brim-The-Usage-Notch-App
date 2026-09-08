import Foundation

/// A tool described in data rather than in code.
///
/// Every automatic provider in this app does the same thing: the tool writes its usage
/// somewhere on disk, and a reader opens that file and pulls out a few fields. Claude's
/// reader is about forty lines of exactly that. Once you notice the shape repeats, it
/// can be described instead of written, which is what lets someone add a tool without
/// writing Swift, and lets adapters be shared as files rather than pull requests.
///
/// Deliberately limited to reading a local file. No commands are run and no requests
/// are made, because a descriptor is a thing strangers will share with each other and
/// it must not be able to do anything a text file shouldn't.
public struct ToolDescriptor: Codable, Equatable, Sendable {
    /// Stable identifier, used as the storage key. Lowercase, no spaces.
    public let id: String
    public let name: String
    /// Paths that prove the tool is installed. Missing means "always show".
    public var detect: [String]?
    /// The file holding the usage, `~` allowed.
    public let file: String
    /// Where in that file the reading lives.
    public let windows: [WindowDescriptor]
    /// Optional note shown in the UI, e.g. what this figure does not include.
    public var note: String?

    public init(id: String, name: String, detect: [String]? = nil, file: String,
                windows: [WindowDescriptor], note: String? = nil) {
        self.id = id; self.name = name; self.detect = detect
        self.file = file; self.windows = windows; self.note = note
    }
}

/// One limit inside the file.
///
/// Either give `usedPercent`, or give `used` and `limit` and let the percentage be
/// worked out. Anything absent stays unknown rather than becoming zero.
public struct WindowDescriptor: Codable, Equatable, Sendable {
    public let title: String
    public var usedPercent: String?
    public var used: String?
    public var limit: String?
    public var resetsAt: String?
    /// True when the file reports what is *left* rather than what is used.
    public var isRemaining: Bool?

    public init(title: String, usedPercent: String? = nil, used: String? = nil,
                limit: String? = nil, resetsAt: String? = nil, isRemaining: Bool? = nil) {
        self.title = title; self.usedPercent = usedPercent; self.used = used
        self.limit = limit; self.resetsAt = resetsAt; self.isRemaining = isRemaining
    }
}

public enum ToolDescriptorError: LocalizedError, Equatable {
    case unreadableFile, noUsableWindows, missingFile(String)
    public var errorDescription: String? {
        switch self {
        case .unreadableFile: "That file could not be read as JSON."
        case .noUsableWindows: "None of the described fields were found in that file."
        case .missingFile(let path): "\(path) doesn’t exist yet."
        }
    }
}

public extension ToolDescriptor {
    /// The file to read, with `~` expanded.
    var resolvedFile: URL {
        URL(fileURLWithPath: (file as NSString).expandingTildeInPath)
    }

    /// Whether the tool looks installed. No `detect` paths means "always show it":
    /// the person who wrote the descriptor is the one running it.
    func isInstalled(_ fileManager: FileManager = .default) -> Bool {
        guard let detect, !detect.isEmpty else { return true }
        return detect.contains { fileManager.fileExists(atPath: ($0 as NSString).expandingTildeInPath) }
    }

    /// What is wrong with this descriptor, in the words of whoever has to fix it.
    ///
    /// Checked on load rather than on read, so a typo is reported once with the
    /// filename attached instead of surfacing later as a tool that never has a number.
    func problems() -> [String] {
        var problems: [String] = []
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-_")
        if id.isEmpty || id.rangeOfCharacter(from: allowed.inverted) != nil {
            problems.append("“id” must be lowercase letters, digits, - or _.")
        }
        if id.count > 40 { problems.append("“id” is too long.") }
        if name.trimmingCharacters(in: .whitespaces).isEmpty { problems.append("“name” is empty.") }
        if file.trimmingCharacters(in: .whitespaces).isEmpty { problems.append("“file” is empty.") }
        if windows.isEmpty { problems.append("No “windows” were described.") }
        if windows.count > 6 { problems.append("A tool can describe at most 6 windows.") }
        for window in windows where window.usedPercent == nil && (window.used == nil || window.limit == nil) {
            problems.append("“\(window.title)” needs either “usedPercent”, or both “used” and “limit”.")
        }
        return problems
    }
}

public enum DescribedTool {
    /// Resolves a dotted key path, with array indexing: `usage.limits[0].percent`.
    ///
    /// Kept to that: no wildcards, no filters, no expressions. A descriptor is shared
    /// between strangers, and a query language is a place for surprises to hide.
    public static func value(at path: String, in root: Any) -> Any? {
        var current: Any? = root
        for rawKey in path.split(separator: ".") {
            guard var remainder = current else { return nil }
            var key = String(rawKey)

            // Split "limits[0][2]" into a key and its indices.
            var indices: [Int] = []
            while let open = key.lastIndex(of: "["), key.hasSuffix("]") {
                let inside = key[key.index(after: open)..<key.index(before: key.endIndex)]
                guard let index = Int(inside) else { return nil }
                indices.insert(index, at: 0)
                key = String(key[key.startIndex..<open])
            }

            if !key.isEmpty {
                guard let dictionary = remainder as? [String: Any],
                      let next = dictionary[key] else { return nil }
                remainder = next
            }
            for index in indices {
                guard let array = remainder as? [Any], array.indices.contains(index) else { return nil }
                remainder = array[index]
            }
            current = remainder
        }
        return current
    }

    /// Builds a snapshot from a described file's contents.
    ///
    /// A window whose fields are missing is dropped, not defaulted. The whole point of
    /// this app is that an unknown number stays unknown.
    public static func read(_ data: Data, using descriptor: ToolDescriptor,
                            now: Date = Date()) throws -> [UsageWindow] {
        guard let root = try? JSONSerialization.jsonObject(with: data) else {
            throw ToolDescriptorError.unreadableFile
        }

        let windows = descriptor.windows.enumerated().compactMap { index, described -> UsageWindow? in
            guard let percent = percent(for: described, in: root) else { return nil }
            return UsageWindow(id: "\(descriptor.id):\(index)",
                               title: described.title,
                               usedPercent: percent,
                               resetsAt: described.resetsAt.flatMap {
                                   ClaudeUsageCache.date(value(at: $0, in: root))
                               })
        }
        guard !windows.isEmpty else { throw ToolDescriptorError.noUsableWindows }
        return windows
    }

    /// Reads the described file from disk.
    public static func read(contentsOf url: URL, using descriptor: ToolDescriptor,
                            now: Date = Date()) throws -> [UsageWindow] {
        guard let data = try? Data(contentsOf: url) else {
            throw ToolDescriptorError.missingFile(descriptor.file)
        }
        return try read(data, using: descriptor, now: now)
    }

    private static func percent(for described: WindowDescriptor, in root: Any) -> Double? {
        if let path = described.usedPercent, let raw = number(at: path, in: root) {
            let percent = described.isRemaining == true ? 100 - raw : raw
            return clamp(percent)
        }
        guard let usedPath = described.used, let limitPath = described.limit,
              let used = number(at: usedPath, in: root),
              let limit = number(at: limitPath, in: root), limit > 0 else { return nil }
        let consumed = described.isRemaining == true ? limit - used : used
        return clamp(consumed / limit * 100)
    }

    private static func number(at path: String, in root: Any) -> Double? {
        UsageParser.number(value(at: path, in: root))
    }

    private static func clamp(_ value: Double) -> Double? {
        guard value.isFinite else { return nil }
        return max(0, min(100, value))
    }
}
