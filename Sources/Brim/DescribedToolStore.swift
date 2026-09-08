import Foundation
import BrimCore

/// Tools the user added by describing them, rather than by anyone writing an adapter.
///
/// Each `.json` file in `~/Library/Application Support/Brim/tools/` names a file
/// some tool already writes and the paths to the numbers inside it. This loads those
/// descriptions, reads what they point at, and reports what went wrong in terms of the
/// file the person has open. A description with a typo should say so once, by name,
/// rather than becoming a tool that silently never has a number.
///
/// Polls modification dates on the app's existing tick, in the same way as the Claude
/// reader: the described files belong to other programs, which replace them atomically.
@MainActor
final class DescribedToolStore {
    struct Loaded: Identifiable {
        let descriptor: ToolDescriptor
        /// The file this description came from, for error messages.
        let filename: String
        var reading: ToolReading?
        var error: String?
        var id: String { descriptor.id }
        var tool: TrackedTool { TrackedTool(descriptor) }
    }

    /// A file in the folder that isn't a usable description.
    struct Rejected: Identifiable {
        let filename: String
        let reason: String
        var id: String { filename }
    }

    private(set) var loaded: [Loaded] = []
    private(set) var rejected: [Rejected] = []

    private var directoryModified: Date?
    private var fileModified: [String: Date] = [:]

    var isEmpty: Bool { loaded.isEmpty && rejected.isEmpty }

    /// Re-reads what changed. `force` ignores the modification dates, for an explicit
    /// refresh and for the moment the user comes back from editing a file.
    func refresh(force: Bool = false) {
        if force || directoryChanged() { reloadDescriptors() }
        for index in loaded.indices { readIfChanged(index, force: force) }
    }

    /// Forget every timestamp, so the next refresh reads everything again.
    func reset() {
        directoryModified = nil
        fileModified = [:]
    }

    private func directoryChanged() -> Bool {
        let modified = try? AppPaths.tools.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate
        guard modified != directoryModified else { return false }
        directoryModified = modified
        return true
    }

    private func reloadDescriptors() {
        let manager = FileManager.default
        let files = ((try? manager.contentsOfDirectory(at: AppPaths.tools,
                                                       includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var loaded: [Loaded] = []
        var rejected: [Rejected] = []
        var seen: Set<String> = []

        for file in files {
            let name = file.lastPathComponent
            guard let data = try? Data(contentsOf: file) else {
                rejected.append(Rejected(filename: name, reason: "Couldn’t be read."))
                continue
            }
            guard let descriptor = try? JSONDecoder().decode(ToolDescriptor.self, from: data) else {
                rejected.append(Rejected(filename: name,
                                         reason: "Not a tool description. Check it is valid JSON with id, name, file and windows."))
                continue
            }
            let problems = descriptor.problems()
            guard problems.isEmpty else {
                rejected.append(Rejected(filename: name, reason: problems.joined(separator: " ")))
                continue
            }
            guard seen.insert(descriptor.id).inserted else {
                rejected.append(Rejected(filename: name,
                                         reason: "Another file already describes “\(descriptor.id)”."))
                continue
            }
            // A description for something that isn't installed is not an error. It is
            // a tool that isn't here. Saying so beats a ring that never fills.
            guard descriptor.isInstalled() else {
                rejected.append(Rejected(filename: name, reason: "\(descriptor.name) isn’t installed on this Mac."))
                continue
            }
            // Keep any reading already taken, so a folder rescan doesn't blank the
            // rings while the described files themselves haven't changed.
            let existing = self.loaded.first { $0.descriptor == descriptor }
            loaded.append(Loaded(descriptor: descriptor, filename: name,
                                 reading: existing?.reading, error: existing?.error))
        }
        self.loaded = loaded
        self.rejected = rejected
        fileModified = fileModified.filter { key, _ in seen.contains(key) }
    }

    private func readIfChanged(_ index: Int, force: Bool) {
        let descriptor = loaded[index].descriptor
        let url = descriptor.resolvedFile
        let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate
        guard force || modified != fileModified[descriptor.id] else { return }
        fileModified[descriptor.id] = modified
        do {
            let windows = try DescribedTool.read(contentsOf: url, using: descriptor)
            // The file's own modification date, not now: this is when the tool last
            // wrote the numbers, which is the only honest timestamp available.
            loaded[index].reading = ToolReading(windows: windows, sourceLabel: "Read from a file",
                                                updatedAt: modified ?? Date(), freshFor: 3600)
            loaded[index].error = nil
        } catch {
            loaded[index].reading = nil
            loaded[index].error = error.localizedDescription
        }
    }
}
