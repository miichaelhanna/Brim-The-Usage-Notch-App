import Foundation

/// The app's version, in one place.
///
/// It was previously typed out in three: the dashboard footer, `Info.plist`, and the
/// client identity sent to the Codex app-server. They drift.
///
/// The packaged app reads its bundle. `swift run` has no bundle, so it falls back to
/// the constant, which `Scripts/build.sh` checks against the `VERSION` file and
/// refuses to package if they disagree.
enum AppVersion {
    static let fallback = "1.1.0"
    static var current: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? fallback
    }
}

/// Where the app points people. One place, so a moved repo is one edit.
enum Links {
    static let addATool = URL(string: "https://github.com/miichaelhanna/Brim-The-Usage-Notch-App/blob/main/Docs/add-a-tool.md")!
    static let providers = URL(string: "https://github.com/miichaelhanna/Brim-The-Usage-Notch-App/blob/main/Docs/providers.md")!
    static let requestProvider = URL(string: "https://github.com/miichaelhanna/Brim-The-Usage-Notch-App/issues/new?template=provider_request.md")!
}
