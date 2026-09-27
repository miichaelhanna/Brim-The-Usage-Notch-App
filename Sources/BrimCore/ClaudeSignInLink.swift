import Foundation

/// The sign-in link in what `claude auth login` prints.
///
/// It prints "If the browser didn't open, visit: <link>" as a fallback, and Brim offers
/// that link as a button. Only a link to Anthropic's own sign-in is ever offered: this
/// text comes from another program, and a button that opens whatever URL it happened to
/// print would be a way to put any page in front of someone as "the sign-in page".
public enum ClaudeSignInLink {
    public static func find(in text: String) -> URL? {
        for word in text.split(whereSeparator: \.isWhitespace) {
            guard word.hasPrefix("https://"), let url = URL(string: String(word)),
                  let host = url.host?.lowercased(), isAnthropic(host) else { continue }
            return url
        }
        return nil
    }

    static func isAnthropic(_ host: String) -> Bool {
        ["claude.ai", "claude.com", "anthropic.com"].contains { host == $0 || host.hasSuffix("." + $0) }
    }
}
