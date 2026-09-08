import AppKit
import BrimCore

@MainActor
final class CodexConnection {
    var onSnapshot: ((UsageSnapshot) -> Void)?
    /// The untouched rate-limits reply, for `--diagnose-codex`. A parser that reads
    /// fewer windows than the account has is invisible without it.
    var onRawUsage: ((Data) -> Void)?
    var onError: ((String) -> Void)?
    var onState: ((Bool) -> Void)?
    var onSignIn: ((Set<Provider>) -> Void)?
    private var process: Process?
    private var input: Pipe?
    private var buffer = Data()
    private var initialized = false
    private var wantsLogin = false
    private var timeout: Task<Void, Never>?
    private var generation = UUID()
    private var nextRequestID = 10
    private var accountRequestID: Int?
    private var usageRequestID: Int?
    private var signedIn = false
    private var includeUsage = true

    static func findExecutable() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = ["/Applications/Codex.app/Contents/Resources/codex", "/Applications/ChatGPT.app/Contents/Resources/codex",
                          "\(home)/Applications/Codex.app/Contents/Resources/codex", "\(home)/.local/bin/codex",
                          "/opt/homebrew/bin/codex", "/usr/local/bin/codex"]
        // Only a properly signed binary is auto-discovered. Several of these
        // directories are writable without admin rights, and this app should not run
        // whatever happens to be sitting there under the right name.
        return candidates.first {
            FileManager.default.isExecutableFile(atPath: $0) && CodeSignature.isAppleAnchored($0)
        }
    }

    func refresh(executable: String?, includeUsage: Bool = true) {
        self.includeUsage = includeUsage
        onState?(true)
        guard process != nil else { start(executable: executable); return }
        guard initialized else { return }
        // Read sign-in separately: a saved quota or a transient usage error is
        // not evidence that an account is currently signed in.
        accountRequestID = nextRequestID; nextRequestID += 1
        usageRequestID = nil
        send(["id": accountRequestID!, "method": "account/read", "params": ["refreshToken": false]])
        armTimeout()
    }

    func login(executable: String?) {
        wantsLogin = true
        if process == nil { start(executable: executable) }
        else if initialized { requestLogin() }
    }

    private func start(executable: String?) {
        guard let executable, FileManager.default.isExecutableFile(atPath: executable) else {
            fail("Install Codex or choose its executable in Connections."); return
        }
        // Re-checked here as well as during discovery, because an explicitly chosen
        // path skips discovery entirely, and because the file may have changed since.
        guard CodeSignature.isAppleAnchored(executable) else {
            fail("That Codex executable isn’t signed by a developer Apple recognises, so it wasn’t run. "
                 + "Reinstall the ChatGPT app, or pick the copy inside it in Connections.")
            return
        }
        generation = UUID()
        let current = generation
        let process = Process(), input = Pipe(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["app-server"]
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { @MainActor [weak self] in
                guard let self, self.generation == current else { return }
                self.receive(data)
            }
        }
        process.terminationHandler = { [weak self] _ in
            output.fileHandleForReading.readabilityHandler = nil
            Task { @MainActor [weak self] in
                guard let self, self.generation == current else { return }
                self.process = nil; self.initialized = false
                self.signedIn = false; self.onSignIn?([])
                self.fail("Codex disconnected. Refresh to reconnect.")
            }
        }
        do {
            try process.run()
            self.process = process; self.input = input
            send(["id": 1, "method": "initialize", "params": ["clientInfo": ["name": "brim", "title": "Brim", "version": AppVersion.current]]])
            armTimeout()
        } catch { fail("Couldn’t start Codex. Check the executable in Connections.") }
    }

    private func receive(_ data: Data) {
        buffer.append(data)
        if buffer.count > 2_000_000 { stop(); fail("Codex returned an oversized response."); return }
        while let end = buffer.firstIndex(of: 10) {
            let line = Data(buffer[..<end]); buffer.removeSubrange(...end)
            guard let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            let id = json["id"] as? Int
            if json["error"] != nil {
                guard let id else { continue }
                guard id == 1 || id == 3 || id == accountRequestID || id == usageRequestID else { continue }
                timeout?.cancel()
                if id == accountRequestID { signedIn = false; onSignIn?([]) }
                accountRequestID = nil; usageRequestID = nil
                fail(id == 3 ? "Sign-in couldn’t start. Sign in through Codex, then refresh." : "Usage unavailable. Check your Codex sign-in and network, then refresh.")
                continue
            }
            if id == 1 {
                initialized = true
                send(["method": "initialized", "params": [:]])
                if wantsLogin { requestLogin() } else { refresh(executable: nil, includeUsage: includeUsage) }
            } else if let id, id == accountRequestID {
                accountRequestID = nil
                do {
                    let providers = try AccountSignIn.openAI(line)
                    signedIn = providers.contains(.codex)
                    onSignIn?(providers)
                    if signedIn && includeUsage {
                        usageRequestID = nextRequestID; nextRequestID += 1
                        send(["id": usageRequestID!, "method": "account/rateLimits/read"])
                        armTimeout()
                    } else { timeout?.cancel(); onState?(false) }
                } catch { signedIn = false; onSignIn?([]); timeout?.cancel(); fail("Couldn’t check the OpenAI account sign-in.") }
            } else if let id, id == usageRequestID {
                usageRequestID = nil
                timeout?.cancel(); onState?(false)
                onRawUsage?(line)
                do { onSnapshot?(try UsageParser.codex(line)) }
                catch { fail(error.localizedDescription) }
            } else if id == 3 {
                timeout?.cancel(); onState?(false)
                if let result = json["result"] as? [String: Any], let address = result["authUrl"] as? String,
                   let url = URL(string: address), url.scheme == "https",
                   let host = url.host, host == "auth.openai.com" || host.hasSuffix(".openai.com") || host == "chatgpt.com" {
                    NSWorkspace.shared.open(url)
                }
            } else if json["method"] as? String == "account/login/completed" {
                refresh(executable: nil)
            } else if json["method"] as? String == "account/updated" {
                // Hide immediately, then verify the new account. Ignore late
                // responses and quota notifications belonging to the old one.
                signedIn = false; onSignIn?([])
                refresh(executable: nil, includeUsage: includeUsage)
            } else if json["method"] as? String == "account/rateLimits/updated",
                      signedIn, accountRequestID == nil,
                      let params = json["params"], let payload = try? JSONSerialization.data(withJSONObject: params),
                      let snapshot = try? UsageParser.codex(payload) { onSnapshot?(snapshot) }
        }
    }

    private func requestLogin() {
        wantsLogin = false
        send(["id": 3, "method": "account/login/start", "params": ["type": "chatgpt"]])
        armTimeout()
    }
    private func send(_ message: [String: Any]) {
        guard let input, let data = try? JSONSerialization.data(withJSONObject: message) else { return }
        do { try input.fileHandleForWriting.write(contentsOf: data + Data([10])) }
        catch { stop(); fail("Codex connection closed. Refresh to reconnect.") }
    }
    private func armTimeout() {
        timeout?.cancel()
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled else { return }
            self?.stop(); self?.fail("Codex took too long to respond. Check your connection and retry.")
        }
    }
    private func fail(_ message: String) { onState?(false); onError?(message) }
    func stop() {
        timeout?.cancel(); generation = UUID()
        try? input?.fileHandleForWriting.close()
        process?.terminate(); process = nil; input = nil; initialized = false; buffer.removeAll()
        accountRequestID = nil; usageRequestID = nil; signedIn = false; onSignIn?([])
    }
}
