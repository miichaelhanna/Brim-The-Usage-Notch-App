import Foundation
import Security

/// Checks that a binary is signed with an Apple-issued identity before the app runs it.
///
/// Brim launches the `codex` executable to ask it for usage. That is a
/// deliberate design choice, since it means this app never handles an OpenAI credential,
/// but it does mean executing code the app did not build, found by searching the
/// filesystem.
///
/// Some of the places searched (`/usr/local/bin`, `~/.local/bin`) are writable without
/// administrator rights on a normal Mac. An attacker who can drop a file there could
/// otherwise have this app run it. Requiring an Apple anchor means an unsigned or
/// ad-hoc-signed binary planted in one of those directories is refused: real builds
/// from OpenAI are Developer ID signed and pass, while something dropped by malware
/// almost never is.
///
/// This is not a guarantee, and a signed-but-malicious binary would pass, but it raises
/// the bar from "any file with the right name" to "a file someone signed with an
/// identity Apple issued and has not revoked".
enum CodeSignature {
    /// What the answer was checked against: enough of the file's identity that a
    /// different binary at the same path cannot inherit a verdict given to this one.
    private struct Identity: Equatable {
        let size: Int
        let modified: Date
        let fileNumber: Int
    }

    private static let lock = NSLock()
    private static var verdicts: [String: (Identity, Bool)] = [:]

    /// True when the binary carries a valid signature chaining to an Apple root, which
    /// covers both Developer ID and App Store distribution.
    ///
    /// Verifying a signature hashes the whole binary, which costs hundreds of
    /// milliseconds on something the size of `codex`. That is fine once, but this is
    /// asked on every refresh, on the main thread, where the user feels it as the
    /// window going dead for a moment after clicking a ring. The verdict is therefore
    /// kept against the file's identity, meaning size, modification date and inode, so a
    /// binary that is replaced, edited or swapped for a different file is verified
    /// again rather than trusted on a stale answer.
    static func isAppleAnchored(_ path: String) -> Bool {
        guard let identity = identity(of: path) else { return false }
        lock.lock()
        let remembered = verdicts[path]
        lock.unlock()
        if let remembered, remembered.0 == identity { return remembered.1 }

        let verdict = verify(path)
        lock.lock()
        verdicts[path] = (identity, verdict)
        lock.unlock()
        return verdict
    }

    private static func identity(of path: String) -> Identity? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attributes[.size] as? Int,
              let modified = attributes[.modificationDate] as? Date,
              let fileNumber = attributes[.systemFileNumber] as? Int else { return nil }
        return Identity(size: size, modified: modified, fileNumber: fileNumber)
    }

    private static func verify(_ path: String) -> Bool {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode else { return false }

        var requirement: SecRequirement?
        guard SecRequirementCreateWithString("anchor apple generic" as CFString, [], &requirement) == errSecSuccess,
              let requirement else { return false }

        return SecStaticCodeCheckValidity(staticCode, [], requirement) == errSecSuccess
    }
}
