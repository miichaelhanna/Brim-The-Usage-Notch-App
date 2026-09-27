import AppKit
import CryptoKit
import Foundation
import BrimCore

/// Gets Claude Code signed in for someone who has never opened a terminal.
///
/// The only credential on a Mac that can read the Claude allowance is Claude Code's own
/// sign-in, and the Claude desktop app keeps its sign-in to itself, so someone who only
/// uses the app has nothing Brim can read. This does the two steps they would otherwise
/// be sent to a terminal for, and nothing else:
///
/// 1. Installs Claude Code from Anthropic's download service, into their home folder,
///    if no signed copy is already there: checked against Anthropic's published
///    checksum and Anthropic's own signature before it is run. No admin rights, no
///    password, and no script: Brim does not run shell.
/// 2. Runs Claude Code's own `claude auth login`, which opens claude.ai in the browser.
///    The password is typed there and only there.
///
/// Brim still holds no credential of its own: the sign-in lands in Claude Code's
/// Keychain entry, which is read exactly as before. It does not sign in by itself,
/// which would mean presenting itself to Anthropic as Claude Code, and it never touches
/// the desktop app's private sign-in.
@MainActor
final class ClaudeSetup {
    enum Step: Equatable {
        case idle
        case installing
        /// Waiting on the browser. The link is Claude Code's own fallback, for when the
        /// browser did not open by itself.
        case signingIn(link: URL?)
        case failed(String)
    }

    var onStep: ((Step) -> Void)?
    /// Claude Code reported a completed sign-in.
    var onSignedIn: (() -> Void)?

    private(set) var step: Step = .idle { didSet { onStep?(step) } }
    private var process: Process?
    private var input: Pipe?
    private var generation = UUID()

    private static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    /// Claude Code, if a copy Anthropic signed is installed. The same rule every
    /// executable Brim runs is held to: these folders are writable without admin
    /// rights, so a file planted under the right name must not be run.
    static func findExecutable() -> String? {
        let candidates = [home.appendingPathComponent(".local/bin/claude").path,
                          "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
        return candidates.first {
            FileManager.default.isExecutableFile(atPath: $0) && CodeSignature.isAppleAnchored($0)
        }
    }

    var isBusy: Bool {
        switch step {
        case .installing, .signingIn: true
        case .idle, .failed: false
        }
    }

    func start() {
        guard !isBusy else { return }
        if let executable = Self.findExecutable() { signIn(with: executable) } else { install() }
    }

    func cancel() {
        generation = UUID()
        process?.terminate()
        process = nil; input = nil
        step = .idle
    }

    /// For the rare case where claude.ai shows a code rather than returning to Claude
    /// Code by itself. Claude Code is already asking for it on its input.
    func submit(code: String) {
        let code = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty, let input else { return }
        input.fileHandleForWriting.write(Data((code + "\n").utf8))
    }

    // MARK: Installing

    private func install() {
        step = .installing
        let current = UUID(); generation = current
        Task { [weak self] in
            do {
                let executable = try await Self.downloadAndInstall()
                guard let self, self.generation == current else { return }
                self.signIn(with: executable)
            } catch {
                guard let self, self.generation == current else { return }
                self.step = .failed((error as? SetupError)?.message
                                    ?? "Claude Code couldn’t be installed: \(error.localizedDescription)")
            }
        }
    }

    /// What Anthropic's installer script does, without running a script: find the
    /// latest build, download it, check it against Anthropic's published checksum and
    /// Anthropic's own signature, and only then run it, to install itself.
    private static func downloadAndInstall() async throws -> String {
        let (latest, _) = try await URLSession.shared.data(from: ClaudeCodeRelease.latest)
        guard let version = ClaudeCodeRelease.version(latest) else {
            throw SetupError("Anthropic’s download service didn’t answer. Check your connection and try again.")
        }
        let platform = ClaudeCodeRelease.platform(arm64: isArm64, translated: isTranslated)
        let (manifest, _) = try await URLSession.shared.data(from: ClaudeCodeRelease.manifest(version))
        guard let expected = ClaudeCodeRelease.checksum(manifest, platform: platform) else {
            throw SetupError("Anthropic hasn’t published Claude Code for this Mac.")
        }

        let (download, response) = try await URLSession.shared.download(from: ClaudeCodeRelease.binary(version, platform: platform))
        let binary = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-\(version)-\(UUID().uuidString)")
        try FileManager.default.moveItem(at: download, to: binary)
        defer { try? FileManager.default.removeItem(at: binary) }
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              try sha256(of: binary) == expected else {
            throw SetupError("The Claude Code download didn’t match what Anthropic published, so it wasn’t run. Try again.")
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
        guard CodeSignature.isSigned(byTeam: ClaudeCodeRelease.signingTeam, binary.path) else {
            throw SetupError("The Claude Code download isn’t signed by Anthropic, so it wasn’t run.")
        }

        let status = try await run(binary.path, ["install"])
        guard status == 0, let executable = findExecutable() else {
            throw SetupError("Claude Code didn’t finish installing. Try again, or install it from claude.com/code.")
        }
        return executable
    }

    private static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static var isArm64: Bool {
        #if arch(arm64)
        true
        #else
        false
        #endif
    }

    private static var isTranslated: Bool {
        var translated: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname("sysctl.proc_translated", &translated, &size, nil, 0) == 0 && translated == 1
    }

    private static func run(_ path: String, _ arguments: [String]) async throws -> Int32 {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            process.currentDirectoryURL = home
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
    }

    // MARK: Signing in

    private func signIn(with executable: String) {
        step = .signingIn(link: nil)
        let current = UUID(); generation = current
        let process = Process(), input = Pipe(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        // The Claude subscription sign-in, which is the one that carries usage. The
        // Console sign-in is API billing and has no allowance to show.
        process.arguments = ["auth", "login", "--claudeai"]
        process.currentDirectoryURL = Self.home
        process.standardInput = input
        process.standardOutput = output
        process.standardError = output
        process.terminationHandler = { [weak self] finished in
            let status = finished.terminationStatus
            Task { @MainActor [weak self] in self?.finished(status, generation: current) }
        }
        do {
            try process.run()
            self.process = process; self.input = input
        } catch {
            step = .failed("Claude Code couldn’t be started: \(error.localizedDescription)")
            return
        }
        // Claude Code opens the browser itself and prints the same link as a fallback.
        // It is kept, not opened a second time, so a working browser does not get two
        // sign-in tabs.
        Task.detached(priority: .utility) { [weak self] in
            var text = ""
            while true {
                let chunk = output.fileHandleForReading.availableData
                if chunk.isEmpty { break }
                text += String(decoding: chunk, as: UTF8.self)
                if text.count > 65_536 { text = String(text.suffix(8_192)) }
                if let link = ClaudeSignInLink.find(in: text) {
                    await self?.found(link, generation: current)
                }
            }
        }
    }

    private func found(_ link: URL, generation current: UUID) {
        guard generation == current, case .signingIn(nil) = step else { return }
        step = .signingIn(link: link)
    }

    private func finished(_ status: Int32, generation current: UUID) {
        guard generation == current else { return }
        process = nil; input = nil
        if status == 0 {
            step = .idle
            onSignedIn?()
        } else {
            step = .failed("The sign-in didn’t finish. Nothing was changed; try again when you’re ready.")
        }
    }

    func openLink() {
        if case .signingIn(let link?) = step { NSWorkspace.shared.open(link) }
    }
}

private struct SetupError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}
