import Foundation

/// Sign-in evidence is independent of usage readings, saved entries, and app installation.
public enum AccountSignIn {
    public static let openAIProviders: Set<Provider> = [.chatgpt, .codex]
    public static let claudeProviders: Set<Provider> = [.claude, .claudeCode]

    public static func openAI(_ data: Data) throws -> Set<Provider> {
        let response = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        return response.result.account?.type == "chatgpt" ? openAIProviders : []
    }

    public static func claude(_ data: Data) throws -> Set<Provider> {
        let response = try JSONDecoder().decode(ClaudeStatus.self, from: data)
        // API/Console credentials do not establish a Claude subscription sign-in.
        return response.loggedIn && response.authMethod == "claude.ai" && response.apiProvider == "firstParty"
            ? claudeProviders : []
    }

    /// The rings to show: one per signed-in account family, in a fixed order.
    public static func displayed(signedIn: Set<Provider>, enabled: Set<Provider> = Set(Provider.allCases)) -> [Provider] {
        Provider.allCases.filter { $0.isDisplayed && signedIn.contains($0) && enabled.contains($0) }
    }

    private struct OpenAIResponse: Decodable { let result: AccountResult }
    private struct AccountResult: Decodable { let account: Account? }
    private struct Account: Decodable { let type: String }
    private struct ClaudeStatus: Decodable {
        let loggedIn: Bool
        let authMethod: String?
        let apiProvider: String?
    }
}
