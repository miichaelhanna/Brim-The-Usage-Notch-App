import Foundation
import BrimCore

/// Time spent per day, per tool, and the switch that turns the reading on.
///
/// Off until it is asked for, like everything else in this app. Connecting Claude Code
/// was permission to read a usage figure, not permission to walk its transcripts, so
/// this asks separately and reads nothing at all until it is on. Turning it off
/// deletes what the scan built, so "off" means gone rather than merely hidden.
@MainActor
final class ActivityStore: ObservableObject {
    /// What one scan found. A value, so the work can happen off the main actor and
    /// arrive in one piece.
    struct Findings: Sendable {
        var days: [Provider: [ActivityDay]] = [:]
        var transcripts = 0
        var scannedAt = Date()
    }

    @Published private(set) var days: [Provider: [ActivityDay]] = [:]
    @Published private(set) var isScanning = false
    @Published private(set) var scannedAt: Date?
    @Published private(set) var transcripts = 0
    @Published var enabled: Bool {
        didSet {
            guard enabled != oldValue else { return }
            defaults.set(enabled, forKey: "trackTime")
            if enabled {
                refresh()
            } else {
                scan?.cancel(); scan = nil
                days = [:]; scannedAt = nil; transcripts = 0; isScanning = false
                TranscriptCache.erase()
            }
        }
    }

    /// The tools that keep a transcript on this Mac. A provider with no folder is not
    /// shown as a row of zeroes; it is simply not something this can measure.
    private(set) var measurable: [Provider] = []

    private let defaults: UserDefaults
    private var scan: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        enabled = defaults.bool(forKey: "trackTime")
        measurable = TranscriptReader.sources
            .filter { FileManager.default.fileExists(atPath: $0.folder.path) }
            .map(\.provider)
        if enabled { refresh() }
    }

    func refresh() {
        guard enabled, scan == nil else { return }
        isScanning = true
        let calendar = Calendar.current
        scan = Task { [weak self] in
            let findings = await Self.walk(calendar: calendar, keepingCache: true)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.enabled else { return }
                self.days = findings.days
                self.transcripts = findings.transcripts
                self.scannedAt = findings.scannedAt
                self.isScanning = false
                self.scan = nil
            }
        }
    }

    func stop() { scan?.cancel(); scan = nil }

    /// The scan itself, off the main actor: it walks gigabytes on a working Mac, and
    /// the first run reads all of it.
    /// `keepingCache` is false for a one-off report while tracking is off: reading
    /// on request is one thing, leaving a record of it behind is another.
    private static func walk(calendar: Calendar, keepingCache: Bool) async -> Findings {
        await Task.detached(priority: .utility) {
            let cache = TranscriptCache.load()
            var fresh = TranscriptCache()
            var findings = Findings()
            for source in TranscriptReader.sources {
                var runs: [ActivityRun] = []
                for file in TranscriptReader.transcripts(in: source) {
                    if Task.isCancelled { return findings }
                    let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                    let modified = values?.contentModificationDate ?? .distantPast
                    let size = values?.fileSize ?? 0
                    let key = file.path
                    let entry: TranscriptCache.Entry
                    if let known = cache.files[key], known.modified == modified, known.size == size {
                        entry = known
                    } else {
                        entry = TranscriptCache.Entry(modified: modified, size: size,
                                                      runs: TranscriptReader.runs(in: file, modified: modified))
                    }
                    fresh.files[key] = entry
                    runs += entry.runs
                    findings.transcripts += 1
                }
                guard !runs.isEmpty else { continue }
                findings.days[source.provider] = ActivityTimeline.days(runs, calendar: calendar)
            }
            if keepingCache { fresh.save() }
            return findings
        }.value
    }

    /// A plain-text account of the last `days` days, for `--activity-time`.
    static func report(days: Int, calendar: Calendar = .current) async -> String {
        let findings = await walk(calendar: calendar,
                                  keepingCache: UserDefaults.standard.bool(forKey: "trackTime"))
        var lines = ["Read \(findings.transcripts) transcripts."]
        let today = calendar.startOfDay(for: Date())
        for offset in stride(from: days - 1, through: 0, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let parts = findings.days.keys.sorted { $0.rawValue < $1.rawValue }.compactMap { provider -> String? in
                guard let found = findings.days[provider]?.first(where: { $0.start == day }),
                      found.seconds > 0 || found.sessions > 0 else { return nil }
                return "\(provider.name) \(ActivityTimeline.label(found.seconds)) "
                    + "(\(found.sessions) session\(found.sessions == 1 ? "" : "s"))"
            }
            lines.append("\(day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))  "
                         + (parts.isEmpty ? "—" : parts.joined(separator: "   ")))
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Reading the findings

    func days(for provider: Provider) -> [ActivityDay] { days[provider] ?? [] }

    func day(_ provider: Provider, on date: Date, calendar: Calendar = .current) -> ActivityDay? {
        let start = calendar.startOfDay(for: date)
        return days(for: provider).first { $0.start == start }
    }

    /// Every tool's time on one day, added up. Merged only within a tool: two tools
    /// used in the same hour are two hours of tool time, and saying otherwise would
    /// need a single timeline across tools that the transcripts cannot support.
    func total(on date: Date, calendar: Calendar = .current) -> TimeInterval {
        measurable.reduce(0) { $0 + (day($1, on: date, calendar: calendar)?.seconds ?? 0) }
    }

    func total(in month: DateInterval, calendar: Calendar = .current) -> TimeInterval {
        measurable.reduce(0) { running, provider in
            running + days(for: provider).filter { month.contains($0.start) }.reduce(0) { $0 + $1.seconds }
        }
    }

    /// The busiest day on record, which is what a heat map has to be scaled against.
    func busiestDay(calendar: Calendar = .current) -> TimeInterval {
        let everyDay = measurable.flatMap { days(for: $0) }
        return Dictionary(grouping: everyDay, by: \.start)
            .values.map { $0.reduce(0) { $0 + $1.seconds } }.max() ?? 0
    }

    var earliestDay: Date? { measurable.compactMap { days(for: $0).first?.start }.min() }
}
