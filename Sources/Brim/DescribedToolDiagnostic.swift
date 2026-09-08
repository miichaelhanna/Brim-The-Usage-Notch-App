import Foundation
import BrimCore

/// `--diagnose-tools`: says what the app makes of the tools you described.
///
/// The app shows the same conclusions, but a description is edited in a text editor,
/// and being able to check it from the same window you saved it in is worth the
/// thirty lines. Reads local files and prints numbers. Runs nothing, sends nothing.
@MainActor
enum DescribedToolDiagnostic {
    static func run() {
        try? AppPaths.prepareTools()
        print("Folder: \(AppPaths.tools.path)")
        let store = DescribedToolStore()
        store.refresh(force: true)

        if store.isEmpty {
            print("No descriptions found. Drop a .json file in that folder. See Docs/add-a-tool.md.")
            return
        }
        for added in store.loaded {
            print("\n\(added.descriptor.name)  [\(added.filename)]")
            print("  reads: \(added.descriptor.resolvedFile.path)")
            if let error = added.error {
                print("  PROBLEM: \(error)")
                continue
            }
            guard let reading = added.reading else {
                print("  No reading yet.")
                continue
            }
            print("  taken: \(reading.updatedAt.formatted(.iso8601))"
                  + (reading.isStale() ? "  (stale)" : ""))
            for window in reading.windows {
                let reset = window.resetsAt.map { "resets \($0.formatted(.iso8601))" } ?? "no reset time"
                print("    \(window.title): \(Int(window.usedPercent.rounded()))%  \(reset)")
            }
        }
        for rejected in store.rejected {
            print("\nSKIPPED \(rejected.filename)\n  \(rejected.reason)")
        }
    }
}
