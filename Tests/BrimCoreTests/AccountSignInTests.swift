import XCTest
@testable import BrimCore

final class AccountSignInTests: XCTestCase {
    private func data(_ string: String) -> Data { Data(string.utf8) }

    func testChatGPTAccountConfirmsOpenAIServicesWithoutQuotas() throws {
        let providers = try AccountSignIn.openAI(data(#"{"result":{"account":{"type":"chatgpt","planType":"plus"}}}"#))
        XCTAssertEqual(providers, [.chatgpt, .codex])
    }

    func testSignedOutAndAPIAccountsNeverAppearAsSubscriptionSignIns() throws {
        for account in ["null", #"{"type":"apiKey"}"#, #"{"type":"amazonBedrock"}"#, #"{"type":"unknown"}"#] {
            XCTAssertTrue(try AccountSignIn.openAI(data("{\"result\":{\"account\":\(account),\"requiresOpenaiAuth\":false}}")).isEmpty)
        }
    }

    func testClaudeSubscriptionConfirmsSharedAccountServices() throws {
        XCTAssertEqual(try AccountSignIn.claude(data(#"{"loggedIn":true,"authMethod":"claude.ai","apiProvider":"firstParty"}"#)), [.claude, .claudeCode])
    }

    func testClaudeLogoutConsoleAndIncompleteStatusStayHidden() throws {
        for status in [#"{"loggedIn":false}"#,
                       #"{"loggedIn":true,"authMethod":"api_key","apiProvider":"firstParty"}"#,
                       #"{"loggedIn":true,"authMethod":"claude.ai","apiProvider":"bedrock"}"#,
                       #"{"loggedIn":true}"#] {
            XCTAssertTrue(try AccountSignIn.claude(data(status)).isEmpty)
        }
    }

    func testErrorsUsageAndMalformedStatusCannotEstablishSignIn() {
        for payload in [#"{"error":{"message":"offline"}}"#, #"{"loggedIn":"true"}"#, #"{"windows":[{"usedPercent":50}],"source":"manual"}"#, "invalid"] {
            XCTAssertThrowsError(try AccountSignIn.openAI(data(payload)))
            XCTAssertThrowsError(try AccountSignIn.claude(data(payload)))
        }
    }

    /// Claude and Claude Code draw on one allowance, as do ChatGPT and Codex. Each
    /// pair used to be two rings showing the same number; now it is one.
    func testEachSharedAllowanceIsShownOnce() {
        XCTAssertEqual(AccountSignIn.displayed(signedIn: [.chatgpt, .codex, .claude, .claudeCode]), [.claude, .chatgpt])
        XCTAssertEqual(AccountSignIn.displayed(signedIn: AccountSignIn.openAIProviders), [.chatgpt])
        XCTAssertEqual(AccountSignIn.displayed(signedIn: AccountSignIn.claudeProviders), [.claude])
        XCTAssertTrue(AccountSignIn.displayed(signedIn: []).isEmpty)
        XCTAssertTrue(AccountSignIn.displayed(signedIn: [.codex], enabled: []).isEmpty)
        for provider in Provider.allCases {
            XCTAssertTrue(provider.displayProvider.isDisplayed, "\(provider) must be shown under a displayed provider")
        }
        XCTAssertEqual(Provider.claudeCode.displayProvider, .claude)
        XCTAssertEqual(Provider.codex.displayProvider, .chatgpt)
    }

    func testLogoutRemovesOnlyThatAccountFamily() throws {
        var signedIn = try AccountSignIn.openAI(data(#"{"result":{"account":{"type":"chatgpt"}}}"#))
        signedIn.formUnion(try AccountSignIn.claude(data(#"{"loggedIn":true,"authMethod":"claude.ai","apiProvider":"firstParty"}"#)))
        signedIn.subtract(AccountSignIn.openAIProviders)
        signedIn.formUnion(try AccountSignIn.openAI(data(#"{"result":{"account":null}}"#)))
        XCTAssertEqual(AccountSignIn.displayed(signedIn: signedIn), [.claude])
    }
}
