import Foundation
import BrimCore

/// Uses Claude's own status command. Never reads or copies its credential store.
@MainActor
final class ClaudeSignInConnection {
    var onSignIn: ((Set<Provider>) -> Void)?
    private var process: Process?
    private var timeout: Task<Void, Never>?
    private var generation = UUID()

    func refresh() {
        guard process == nil else { return }
        let home = FileManager.default.homeDirectoryForCurrentUser
        // Held to the same rule as the `codex` binary, see ClaudeSetup.findExecutable.
        guard let executable = ClaudeSetup.findExecutable() else {
            onSignIn?([]); return
        }
        let process = Process(), output = Pipe()
        let current = UUID(); generation = current
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["auth", "status"]
        process.currentDirectoryURL = home
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run(); self.process = process
            // Drain off the main thread so a slow status command cannot block the notch.
            Task.detached(priority: .utility) { [weak self] in
                var data = Data()
                while true {
                    let chunk = output.fileHandleForReading.availableData
                    if chunk.isEmpty { break }
                    data.append(chunk)
                    if data.count > 65_536 { process.terminate(); data.removeAll(); break }
                }
                process.waitUntilExit()
                let providers = process.terminationStatus == 0 ? (try? AccountSignIn.claude(data)) ?? [] : []
                await self?.complete(providers, generation: current)
            }
            timeout = Task { [weak self] in
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled else { return }
                self?.stop(); self?.onSignIn?([])
            }
        } catch { onSignIn?([]) }
    }

    private func complete(_ providers: Set<Provider>, generation current: UUID) {
        guard generation == current else { return }
        timeout?.cancel(); process = nil
        onSignIn?(providers)
    }

    func stop() {
        timeout?.cancel(); generation = UUID()
        process?.terminate(); process = nil
    }
}
