import Foundation

/// A stretch of one transcript with no gap in it longer than the idle cap: time at
/// the desk, rather than a file that happened to be open.
public struct ActivityRun: Codable, Equatable, Sendable {
    public let start: Date
    public let end: Date
    /// The transcript this came out of. Two sessions running at once overlap in wall
    /// clock time and must be counted once, but they are still two sessions, so the
    /// source travels with the run rather than being merged away.
    public let sourceID: String
    public init(start: Date, end: Date, sourceID: String) {
        self.start = start
        self.end = max(start, end)
        self.sourceID = sourceID
    }
    public var duration: TimeInterval { end.timeIntervalSince(start) }
}

/// One day of one tool.
public struct ActivityDay: Equatable, Identifiable, Sendable {
    /// Midnight, in the calendar the reader was given.
    public let start: Date
    public let seconds: TimeInterval
    public let sessions: Int
    public init(start: Date, seconds: TimeInterval, sessions: Int) {
        self.start = start; self.seconds = max(0, seconds); self.sessions = max(0, sessions)
    }
    public var id: Date { start }
    public var hours: Double { seconds / 3600 }
    public var label: String { ActivityTimeline.label(seconds) }
    public var compactLabel: String { ActivityTimeline.compactLabel(seconds) }
}

/// Turns the timestamps in a tool's own session transcripts into time per day.
///
/// This measures *attendance*, not tokens and not money: the question it answers is
/// "how long was I at this yesterday". It can only ever be as honest as its two
/// admissions — that a gap has to be capped to mean anything, and that only tools
/// which write a transcript to this Mac can be measured at all.
public enum ActivityTimeline {
    /// Longer than this between two entries and nobody was at the desk. Five minutes
    /// covers a pause for thought, a build, or a long answer; counting an hour of it
    /// as work would make every figure in the view a flattering lie.
    public static let idleCap: TimeInterval = 300

    /// One transcript's timestamps, reduced to the runs of work in it. Unsorted and
    /// duplicated stamps are fine: transcripts interleave a session with the
    /// subagents it spawned, and both write into the same file.
    public static func runs(from timestamps: [Date], sourceID: String,
                            idleCap: TimeInterval = idleCap) -> [ActivityRun] {
        let sorted = timestamps.sorted()
        guard let first = sorted.first else { return [] }
        var runs: [ActivityRun] = []
        var start = first, previous = first
        for stamp in sorted.dropFirst() {
            if stamp.timeIntervalSince(previous) > idleCap {
                runs.append(ActivityRun(start: start, end: previous, sourceID: sourceID))
                start = stamp
            }
            previous = stamp
        }
        runs.append(ActivityRun(start: start, end: previous, sourceID: sourceID))
        return runs
    }

    /// Overlapping runs, flattened. Two agents working at once is one hour of the
    /// day, not two, and a view that says otherwise cannot be checked against a clock.
    public static func union(_ runs: [ActivityRun]) -> [(start: Date, end: Date)] {
        var merged: [(start: Date, end: Date)] = []
        for run in runs.sorted(by: { $0.start < $1.start }) {
            if let last = merged.last, run.start <= last.end {
                merged[merged.count - 1].end = max(last.end, run.end)
            } else {
                merged.append((run.start, run.end))
            }
        }
        return merged
    }

    /// Per day, in the given calendar. A run crossing midnight is split at it, so a
    /// night shift lands on both days in the proportions actually worked.
    public static func days(_ runs: [ActivityRun], calendar: Calendar = .current) -> [ActivityDay] {
        var seconds: [Date: TimeInterval] = [:]
        for run in union(runs) {
            for piece in split(from: run.start, to: run.end, calendar: calendar) {
                seconds[piece.day, default: 0] += piece.seconds
            }
        }
        // Counted from the unmerged runs: the union has thrown away which session was
        // which, which is exactly what it is for.
        var sources: [Date: Set<String>] = [:]
        for run in runs {
            for piece in split(from: run.start, to: run.end, calendar: calendar) {
                sources[piece.day, default: []].insert(run.sourceID)
            }
        }
        return Set(sources.keys).union(seconds.keys).sorted().map { day in
            ActivityDay(start: day, seconds: seconds[day] ?? 0, sessions: sources[day]?.count ?? 0)
        }
    }

    private static func split(from start: Date, to end: Date,
                              calendar: Calendar) -> [(day: Date, seconds: TimeInterval)] {
        var pieces: [(day: Date, seconds: TimeInterval)] = []
        var cursor = start
        repeat {
            let day = calendar.startOfDay(for: cursor)
            // Days are added rather than 86400 seconds: the ones that change length
            // are the ones anybody would notice being wrong.
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day), nextDay > cursor else {
                pieces.append((day, max(0, end.timeIntervalSince(cursor))))
                break
            }
            let stop = min(end, nextDay)
            pieces.append((day, stop.timeIntervalSince(cursor)))
            cursor = stop
        } while cursor < end
        return pieces
    }

    /// "4h 12m". Never "0h 0m": a day with a single prompt in it is a real day, and
    /// rounding it to nothing would hide it.
    public static func label(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes <= 0 { return seconds > 0 ? "under a minute" : "none" }
        if minutes < 60 { return "\(minutes)m" }
        return minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h \(minutes % 60)m"
    }

    /// The same figure in a calendar cell, where there is room for four characters.
    public static func compactLabel(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes <= 0 { return seconds > 0 ? "·" : "" }
        if minutes < 60 { return "\(minutes)m" }
        let hours = Double(minutes) / 60
        return hours >= 10 ? "\(Int(hours.rounded()))h" : String(format: "%.1fh", hours)
    }
}
