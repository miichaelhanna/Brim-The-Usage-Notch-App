import SwiftUI
import BrimCore

/// A month of days, and how long each tool was actually used on each of them.
///
/// The rings answer "how much of my allowance is left". This answers a different
/// question — "where did the week go" — and it answers it from a different place: the
/// transcripts the coding tools keep on this Mac, not the providers. That is why the
/// two disagree about who exists. Claude and ChatGPT in a browser have an allowance
/// but leave nothing on this Mac to time, so they are absent here rather than shown
/// as zero, and the page says so instead of letting it be inferred.
struct TimeView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var activity: ActivityStore
    /// Any day in the month on show.
    @State private var month = Date()
    @State private var selected = Date()

    private var calendar: Calendar { .current }
    private var monthInterval: DateInterval {
        calendar.dateInterval(of: .month, for: month) ?? DateInterval(start: month, duration: 0)
    }

    var body: some View {
        Form {
            if activity.enabled {
                monthSection
                daySection
                sourceSection
            } else {
                invitation
            }
        }
        .formStyle(.grouped)
        .onAppear { if activity.enabled { activity.refresh() } }
    }

    // MARK: - Off

    private var invitation: some View {
        Section {
            VStack(alignment: .leading, spacing: 14) {
                Label("Time is read from your own transcripts", systemImage: "calendar")
                    .font(.headline)
                Text("Claude Code and Codex each keep a session transcript on this Mac. Brim can "
                     + "read the timestamps in them and add up how long you were actually working, "
                     + "day by day. It reads nothing else: not your prompts, not the answers, not "
                     + "the files you were in. Nothing is sent anywhere.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("No provider reports time, so this cannot cover Claude or ChatGPT in a "
                     + "browser. Those leave nothing on this Mac to measure.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Turn on time tracking") { activity.enabled = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(activity.measurable.isEmpty)
                if activity.measurable.isEmpty {
                    Text("Neither Claude Code nor Codex has written a transcript on this Mac.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - The month

    private var monthSection: some View {
        Section {
            VStack(spacing: 10) {
                header
                weekdays
                grid
            }
            .padding(.vertical, 4)
        } footer: {
            HStack(spacing: 6) {
                if activity.isScanning {
                    ProgressView().controlSize(.small)
                    Text("Reading transcripts…")
                } else if let scannedAt = activity.scannedAt {
                    Text("\(activity.transcripts) transcripts, read \(scannedAt.formatted(.relative(presentation: .named)))")
                }
                Spacer()
            }
            .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var header: some View {
        HStack {
            Button { step(-1) } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.borderless)
                .disabled(!canStep(-1))
                .accessibilityLabel("Previous month")
            Text(month.formatted(.dateTime.month(.wide).year()))
                .font(.title3.weight(.semibold))
                .frame(minWidth: 160)
                .contentTransition(.numericText())
            Button { step(1) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.borderless)
                .disabled(!canStep(1))
                .accessibilityLabel("Next month")
            Spacer()
            // The month's own total, beside its name: the first thing anyone wants
            // from a calendar of hours is the month's total, not a day's.
            Text(ActivityTimeline.label(activity.total(in: monthInterval, calendar: calendar)))
                .font(.title3.weight(.semibold)).monospacedDigit()
        }
    }

    private var weekdays: some View {
        HStack(spacing: 4) {
            ForEach(orderedWeekdaySymbols, id: \.self) { symbol in
                Text(symbol).font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var grid: some View {
        VStack(spacing: 4) {
            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 4) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                        if let day { cell(day) } else { Color.clear.frame(height: 46) .frame(maxWidth: .infinity) }
                    }
                }
            }
        }
    }

    private func cell(_ day: Date) -> some View {
        let seconds = activity.total(on: day, calendar: calendar)
        let busiest = activity.busiestDay(calendar: calendar)
        // Scaled against the busiest day on record rather than against the month, so
        // a quiet month reads as a quiet month instead of being stretched to look busy.
        let intensity = busiest > 0 ? min(1, seconds / busiest) : 0
        let isSelected = calendar.isDate(day, inSameDayAs: selected)
        let isToday = calendar.isDateInToday(day)
        let inFuture = day > Date()
        return Button {
            selected = day
        } label: {
            VStack(spacing: 2) {
                Text(day.formatted(.dateTime.day()))
                    .font(.caption.weight(isToday ? .bold : .regular))
                    .monospacedDigit()
                Text(ActivityTimeline.compactLabel(seconds))
                    .font(.caption2.weight(.medium)).monospacedDigit()
                    .foregroundStyle(intensity > 0.55 ? Color.white : Palette.text)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(seconds > 0 ? Palette.accent.opacity(0.18 + 0.72 * intensity)
                                      : Color(nsColor: .quaternaryLabelColor).opacity(0.35))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(isSelected ? Palette.accent : .clear, lineWidth: 2)
            }
            .opacity(inFuture ? 0.4 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(day.formatted(.dateTime.weekday(.wide).day().month(.wide))), "
                            + ActivityTimeline.label(seconds))
    }

    // MARK: - One day

    private var daySection: some View {
        Section {
            ForEach(activity.measurable, id: \.self) { provider in
                let day = activity.day(provider, on: selected, calendar: calendar)
                HStack(spacing: 10) {
                    ToolMark(tool: TrackedTool(provider), size: 17, tint: .primary).frame(width: 24)
                    Text(provider.name)
                    Spacer()
                    if let day, day.seconds > 0 || day.sessions > 0 {
                        Text("\(day.sessions) session\(day.sessions == 1 ? "" : "s")")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(day.label).monospacedDigit()
                    } else {
                        Text("none").foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            HStack {
                Text(selected.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                Spacer()
                Text(ActivityTimeline.label(activity.total(on: selected, calendar: calendar)))
                    .monospacedDigit()
            }
        } footer: {
            Text("A gap of more than five minutes between one entry and the next is counted as "
                 + "time away, not time working. Two sessions running at once are one hour of "
                 + "that tool's day, not two.")
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Where it comes from

    private var sourceSection: some View {
        Section {
            Button("Read the transcripts again") { activity.refresh() }
                .disabled(activity.isScanning)
            Toggle("Track time on this Mac", isOn: $activity.enabled)
        } header: {
            Text("Source")
        } footer: {
            Text("Timestamps only, from Claude Code's and Codex's own session files in your home "
                 + "folder. Nothing is sent anywhere, and turning this off deletes what was read. "
                 + "Claude and ChatGPT used in a browser cannot appear here: no provider reports "
                 + "time, and those leave nothing on this Mac.")
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Calendar arithmetic

    private var orderedWeekdaySymbols: [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    /// The month as rows of seven, with the leading and trailing blanks a calendar
    /// needs. Built from the calendar rather than assumed, so a week starting on
    /// Monday lays out correctly.
    private var weeks: [[Date?]] {
        let interval = monthInterval
        let days = calendar.range(of: .day, in: .month, for: month)?.count ?? 0
        let leading = (calendar.component(.weekday, from: interval.start) - calendar.firstWeekday + 7) % 7
        var cells: [Date?] = Array(repeating: nil, count: leading)
        for offset in 0..<days {
            cells.append(calendar.date(byAdding: .day, value: offset, to: interval.start))
        }
        while cells.count % 7 != 0 { cells.append(nil) }
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
    }

    private func step(_ months: Int) {
        guard let moved = calendar.date(byAdding: .month, value: months, to: month) else { return }
        month = moved
        // Selecting the same day number in the new month would silently move the
        // selection to a day nobody asked about; the first is a neutral landing.
        selected = calendar.dateInterval(of: .month, for: moved)?.start ?? moved
    }

    private func canStep(_ months: Int) -> Bool {
        guard let moved = calendar.date(byAdding: .month, value: months, to: month),
              let interval = calendar.dateInterval(of: .month, for: moved) else { return false }
        if months > 0 { return interval.start <= Date() }
        guard let earliest = activity.earliestDay else { return false }
        return interval.end > earliest
    }
}
