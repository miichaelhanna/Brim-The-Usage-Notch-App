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
    static let fallback = "1.4.0"
    static var current: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? fallback
    }

    /// When this particular build was made.
    ///
    /// The version number alone does not say which build is running. A day of local
    /// builds all call themselves 1.2.0, and the one on screen is regularly not the
    /// one just made. `Scripts/build.sh` stamps `CFBundleVersion` with the minute it
    /// ran, so that is the figure that tells them apart. Nil under `swift run`, which
    /// has no bundle to read, and nil for any stamp that is not one of ours.
    static var builtAt: Date? {
        guard let stamp = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String else { return nil }
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "yyyyMMddHHmm"
        return format.date(from: stamp)
    }
}

/// Where the app points people. One place, so a moved repo is one edit.
enum Links {
    static let addATool = URL(string: "https://github.com/miichaelhanna/Brim-The-Usage-Notch-App/blob/main/Docs/add-a-tool.md")!
    static let providers = URL(string: "https://github.com/miichaelhanna/Brim-The-Usage-Notch-App/blob/main/Docs/providers.md")!
    static let requestProvider = URL(string: "https://github.com/miichaelhanna/Brim-The-Usage-Notch-App/issues/new?template=provider_request.md")!
}
