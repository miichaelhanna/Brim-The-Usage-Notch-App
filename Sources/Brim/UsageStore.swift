import AppKit
import SwiftUI
import BrimCore

@MainActor
final class UsageStore: ObservableObject {
    @Published var snapshots: [Provider: UsageSnapshot] = [:]
    @Published var errors: [Provider: String] = [:]
    /// The tool whose detail the dashboard is showing, by `TrackedTool.id`.
    @Published var selected: String = Provider.claude.rawValue
    @Published private(set) var signedInProviders: Set<Provider> = [] {
        didSet {
            guard signedInProviders != oldValue else { return }
            if !tools.contains(where: { $0.id == selected }), let first = tools.first { selected = first.id }
            onLayoutChange?()
        }
    }
    /// Providers whose sign-in has actually been answered for since launch.
    ///
    /// An empty `signedInProviders` is two different things at once: signed out, and
    /// not asked yet. On the first run those look identical for the second or two a
    /// check takes, and reporting one as the other is how a screen ends up lying.
    @Published private(set) var checkedProviders: Set<Provider> = []
    @Published var isRefreshing = false
    /// The tools whose ring should look busy, by `TrackedTool.id`. Separate from
    /// `isRefreshing`, which is the Codex connection's own state and turns over on
    /// every background poll: this is only ever what the user asked for.
    @Published private(set) var refreshingTools: Set<String> = []
    var controlsMenuOpen = false
    @Published var now = Date()
    /// Light, dark, or whatever the Mac is doing.
    @Published var appearance: AppAppearance { didSet { defaults.set(appearance.rawValue, forKey: "appearance"); onAppearanceChange?() } }
    @Published private(set) var claudeAccountUUID: String?
    /// Whether live Claude usage is working, so first run and Connections agree.
    @Published private(set) var liveClaude: LiveClaudeState = .off
    @Published var notice: String?
    @Published private(set) var placement: NotchAnchor?
    @Published private(set) var preferredPosition: NotchPosition?
    @Published var notchVisible = true { didSet { onVisibilityChange?() } }
    @Published var visibilityMode: NotchVisibilityMode { didSet { defaults.set(visibilityMode.rawValue, forKey: "visibilityMode"); onLayoutChange?() } }
    @Published var presence: AppPresence { didSet { defaults.set(presence.rawValue, forKey: "presence"); onPresenceChange?() } }
    @Published var collapseWhenIdle: Bool { didSet { defaults.set(collapseWhenIdle, forKey: "collapseWhenIdle"); onLayoutChange?() } }
    /// What appears on the notch, by `TrackedTool.id`. Provider ids are their raw
    /// values, so a preference saved before described tools existed still applies.
    @Published var visible: Set<String> { didSet { defaults.set(Array(visible), forKey: "visible"); onLayoutChange?() } }
    /// Tools the user added by describing them. See `DescribedToolStore`.
    @Published private(set) var describedTools: [DescribedToolStore.Loaded] = []
    @Published private(set) var rejectedTools: [DescribedToolStore.Rejected] = []
    @Published var autoRefresh: Bool { didSet { defaults.set(autoRefresh, forKey: "autoRefresh") } }
    /// The tools the user has pressed Connect for, by `KnownTool.rawValue`.
    ///
    /// Nothing is read until this says so. Finding Claude Code on disk is not
    /// permission to run `claude auth status`, and finding the ChatGPT app is not
    /// permission to start its engine. An app that reaches into AI accounts the moment
    /// it launches has helped itself to something, however well it behaves afterwards.
    @Published private(set) var connectedTools: Set<String> {
        didSet { defaults.set(Array(connectedTools), forKey: "connectedTools") }
    }
    @Published var customCodexPath: String { didSet { defaults.set(customCodexPath, forKey: "codexPath"); codex.stop(); isRefreshing = false } }
    var onLayoutChange: (() -> Void)?
    var onPositionChange: (() -> Void)?
    var onVisibilityChange: (() -> Void)?
    var onPresenceChange: (() -> Void)?
    var onAppearanceChange: (() -> Void)?
    var openConnections: (() -> Void)?
    var openUsage: ((Provider) -> Void)?
    private let defaults: UserDefaults
    private let codex = CodexConnection()
    private let claudeSignIn = ClaudeSignInConnection()
    private let claudeReader = ClaudeUsageReader()
    private let claudeLive = ClaudeLiveConnection()
    private var liveUnavailable: ClaudeLiveConnection.Unavailable?
    private var timer: Timer?
    private let refreshPolicy = RefreshPolicy()
    private var refreshStates: [Provider: ProviderRefreshState] = [:]
    private var refreshStarted: [String: Date] = [:]
    private var refreshEnders: [String: DispatchWorkItem] = [:]
    /// Long enough to read as a deliberate turn of the ring, short enough that a
    /// fast answer is not held back behind it.
    private static let minimumRefreshFeedback: TimeInterval = 0.45
    private static let refreshFeedbackTimeout: TimeInterval = 12
    /// Drives the idle cadence. Bumped whenever the user actually looks at something.
    private var lastActivity = Date()
    private let described = DescribedToolStore()
    var displayProviders: [Provider] { AccountSignIn.displayed(signedIn: signedInProviders) }

    /// Everything the interface can show a ring for: the providers this Mac is signed
    /// in to, then whatever the user described themselves.
    var tools: [TrackedTool] {
        displayProviders.map(TrackedTool.init) + describedTools.map(\.tool)
    }

    /// The subset the user hasn't hidden, which is what the notch actually draws.
    var activeTools: [TrackedTool] { tools.filter { visible.contains($0.id) } }
    var executable: String? { customCodexPath.isEmpty ? CodexConnection.findExecutable() : customCodexPath }
    var claudeSourceMessage: String {
        if let error = errors[.claudeCode] { return error }
        guard signedInProviders.contains(.claudeCode) else {
            return "Sign in with Claude Code to show your Claude allowance here."
        }
        // A live failure is worth explaining even while a cached reading is on screen,
        // because it explains why the number is not moving.
        if let liveUnavailable { return liveUnavailable.message }
        guard let snapshot = snapshot(.claudeCode) else {
            return "Waiting for the first reading."
        }
        if snapshot.windows.isEmpty { return "Claude reported no limits for this account." }
        if snapshot.source == .claudeLive {
            return "Read live from Anthropic, using the login Claude Code already keeps on this Mac. "
                + "The token is used read-only, is never modified, and goes nowhere but Anthropic."
        }
        return "Showing Claude Code’s cached reading, which it refreshes only occasionally. "
            + "The timestamp says when it was taken; running /usage in a session refreshes it."
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: "notchPosition") {
            let saved = try? JSONDecoder().decode(NotchPosition.self, from: data)
            if let saved, NotchAnchor.allowedEdges.contains(saved.anchor) {
                preferredPosition = saved
            } else {
                defaults.removeObject(forKey: "notchPosition")
            }
        }
        visibilityMode = NotchVisibilityMode(rawValue: defaults.string(forKey: "visibilityMode") ?? "overApps") ?? .overApps
        presence = AppPresence(saved: defaults.string(forKey: "presence"))
        appearance = AppAppearance(saved: defaults.string(forKey: "appearance"))
        collapseWhenIdle = defaults.bool(forKey: "collapseWhenIdle")
        visible = Set(defaults.stringArray(forKey: "visible") ?? Provider.allCases.map(\.rawValue))
        autoRefresh = defaults.object(forKey: "autoRefresh") as? Bool ?? true
        if let saved = defaults.stringArray(forKey: "connectedTools") {
            connectedTools = Set(saved)
        } else if defaults.bool(forKey: "hasLaunched") {
            // Upgrading from a build that connected on launch. These have been reading
            // for a while with this person's knowledge, so leave them reading rather
            // than going dark and making them reconnect something already working.
            connectedTools = Set(KnownTool.installed.map(\.rawValue))
        } else {
            connectedTools = []
        }
        customCodexPath = defaults.string(forKey: "codexPath") ?? ""
        // Last good readings first, so the app opens with something rather than blank.
        snapshots = ReadingStore.load()
        refreshStates = Self.loadRefreshStates(defaults)
        // Settled now rather than on the first change: otherwise a fresh install that
        // never connects anything would take the upgrade branch on its second launch.
        defaults.set(Array(connectedTools), forKey: "connectedTools")
        defaults.removeObject(forKey: "codexEnabled")
        codex.onSnapshot = { [weak self] snapshot in
            guard let self else { return }
            self.snapshots[.codex] = snapshot
            self.snapshots[.chatgpt] = snapshot.sharedChatGPTWork()
            self.errors[.codex] = nil; self.errors[.chatgpt] = nil
            self.recordOutcome(.codex, succeeded: true)
            self.endRefreshing(AccountSignIn.openAIProviders.map(\.rawValue))
            self.persistReadings()
        }
        codex.onError = { [weak self] error in
            guard let self else { return }
            self.errors[.codex] = error
            self.errors[.chatgpt] = error
            self.recordOutcome(.codex, succeeded: false)
            self.endRefreshing(AccountSignIn.openAIProviders.map(\.rawValue))
        }
        codex.onState = { [weak self] busy in
            self?.isRefreshing = busy
            // Covers a refresh that ends without producing either a reading or an
            // error, which would otherwise leave the ring turning until the timeout.
            if !busy { self?.endRefreshing(AccountSignIn.openAIProviders.map(\.rawValue)) }
        }
        codex.onSignIn = { [weak self] providers in self?.updateSignIn(providers, family: AccountSignIn.openAIProviders) }
        claudeSignIn.onSignIn = { [weak self] providers in self?.updateSignIn(providers, family: AccountSignIn.claudeProviders) }
        claudeReader.onReading = { [weak self] reading in
            self?.claudeAccountUUID = reading.accountUUID
            self?.applyClaude(reading.snapshot)
        }
        claudeLive.onSnapshot = { [weak self] snapshot in
            guard let self else { return }
            self.liveUnavailable = nil
            self.liveClaude = .on
            self.applyClaude(snapshot)
            self.recordOutcome(.claudeCode, succeeded: true)
        }
        claudeLive.onUnavailable = { [weak self] reason in
            guard let self else { return }
            // The cached reading stays on screen; only the explanation changes.
            self.liveUnavailable = reason
            // Not yet asked for is a starting point, not a fault worth colouring orange.
            self.liveClaude = reason == .noCredential ? .off : .problem(reason.message)
            self.recordOutcome(.claudeCode, succeeded: false)
            self.endRefreshing(AccountSignIn.claudeProviders.map(\.rawValue))
        }
        claudeReader.onAbsent = { [weak self] in self?.claudeAccountUUID = nil }
        claudeReader.onFailure = { [weak self] message in
            for provider in [Provider.claude, .claudeCode] { self?.errors[provider] = message }
            self?.endRefreshing(AccountSignIn.claudeProviders.map(\.rawValue))
        }
    }

    func start() {
        // Earlier versions wrapped the Claude Code status line to capture usage.
        // That is retired; undo it wherever it is still installed.
        LegacyBridgeCleanup.run()
        // Earlier versions also kept a `claude setup-token` token. That token can only
        // ever be refused by the usage endpoint, so it is deleted rather than left in
        // someone's Keychain looking like a credential.
        ClaudeTokenStore.removeLegacyToken()
        // A described tool added while the app was closed should be there on launch.
        try? AppPaths.prepareTools()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        now = Date()
        // Cheap: these only re-parse when a file's modification date changed.
        readClaudeUsage()
        readDescribedTools()
        pollAccounts(force: false)
    }

    /// The user did something, so refreshing should stay on the active cadence.
    func noteActivity() { lastActivity = Date() }

    /// Someone is looking at a number, so make sure it is current.
    ///
    /// Called whenever usage is actually put in front of someone: the notch opening,
    /// a ring's card, the dashboard. A background cadence alone means the first glance
    /// after a quiet spell shows whatever was last fetched, which for a usage meter is
    /// the one moment it must not. This goes through the refresh policy rather than
    /// around it, so a hover cannot become a request per hover, and a provider that is
    /// backing off stays backed off.
    func refreshForDisplay() {
        noteActivity()
        now = Date()
        readClaudeUsage()
        readDescribedTools()
        pollAccounts(force: false)
    }

    func stop() { timer?.invalidate(); codex.stop(); claudeSignIn.stop(); claudeLive.stop() }
    func snapshot(_ provider: Provider) -> UsageSnapshot? {
        guard provider != .chatgpt || snapshots[provider]?.source == .chatgptWork else { return nil }
        return snapshots[provider]
    }
    func primary(_ provider: Provider) -> UsageWindow? { snapshot(provider)?.primary(at: now) }

    /// The reading behind a ring, whichever kind of tool it belongs to.
    func reading(_ tool: TrackedTool) -> ToolReading? {
        if let provider = tool.builtin { return snapshot(provider).map(ToolReading.init) }
        return describedTools.first { $0.tool.id == tool.id }?.reading
    }

    func headline(_ tool: TrackedTool) -> UsageWindow? { reading(tool)?.headline(at: now) }

    func error(_ tool: TrackedTool) -> String? {
        if let provider = tool.builtin { return errors[provider] }
        return describedTools.first { $0.tool.id == tool.id }?.error
    }

    func status(_ tool: TrackedTool) -> String {
        if let provider = tool.builtin { return status(provider) }
        if error(tool) != nil { return "Unavailable" }
        guard let reading = reading(tool) else { return "Waiting for a reading" }
        if reading.primary(at: now) == nil { return "Awaiting update" }
        return reading.isStale(at: now) ? "Last known" : "Connected"
    }

    /// What to say when a tool has no reading to show.
    func emptyMessage(_ tool: TrackedTool) -> String {
        if let error = error(tool) { return error }
        guard let provider = tool.builtin else {
            return "Waiting for the first reading from the file this tool was described with."
        }
        switch provider {
        case .claude, .claudeCode: return claudeSourceMessage
        case .chatgpt, .codex: return "Connect the ChatGPT app’s sign-in to read the Work allowance that ChatGPT and Codex share, refreshed automatically."
        }
    }

    func isRefreshing(_ tool: TrackedTool) -> Bool { refreshingTools.contains(tool.id) }

    /// The rings one fetch answers for. Claude and Claude Code are a single reading,
    /// and Codex and ChatGPT share the Work allowance, so refreshing either of a pair
    /// has to light both, otherwise one ring sits still while its own number moves.
    private func feedbackIDs(for provider: Provider) -> [String] {
        let family = AccountSignIn.claudeProviders.contains(provider)
            ? AccountSignIn.claudeProviders : AccountSignIn.openAIProviders
        return family.map(\.rawValue)
    }

    /// Show a ring as busy from the moment it is clicked.
    private func beginRefreshing(_ ids: [String]) {
        let start = Date()
        for id in ids {
            refreshStarted[id] = start
            refreshingTools.insert(id)
            // Never spin for ever. A provider that simply never answers has to stop
            // looking like one that is about to.
            clearRefreshing(id, after: Self.refreshFeedbackTimeout)
        }
    }

    /// Stop when the answer lands, but not before the spin has been on screen long
    /// enough to see. A local re-read finishes in a millisecond, and a ring that
    /// flickered instead of turning read as a glitch rather than as a refresh.
    private func endRefreshing(_ ids: [String]) {
        let now = Date()
        for id in ids where refreshingTools.contains(id) {
            let shown = refreshStarted[id].map { now.timeIntervalSince($0) } ?? Self.minimumRefreshFeedback
            clearRefreshing(id, after: max(0, Self.minimumRefreshFeedback - shown))
        }
    }

    /// One pending clear per tool, so a reply that lands replaces the long timeout
    /// rather than racing it.
    private func clearRefreshing(_ id: String, after delay: TimeInterval) {
        refreshEnders[id]?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.refreshEnders[id] = nil
            self.refreshStarted[id] = nil
            self.refreshingTools.remove(id)
        }
        refreshEnders[id] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func refresh(_ tool: TrackedTool) {
        if let provider = tool.builtin { refresh(provider); return }
        noteActivity()
        now = Date()
        beginRefreshing([tool.id])
        readDescribedTools(force: true)
        endRefreshing([tool.id])
    }

    func toggle(_ tool: TrackedTool) {
        if visible.contains(tool.id) { visible.remove(tool.id) } else { visible.insert(tool.id) }
    }

    /// Re-reads the described tools and republishes them if anything changed.
    func readDescribedTools(force: Bool = false) {
        described.refresh(force: force)
        let hadTools = describedTools.map(\.tool)
        if describedTools.map(\.reading) != described.loaded.map(\.reading)
            || describedTools.map(\.tool) != described.loaded.map(\.tool)
            || describedTools.map(\.error) != described.loaded.map(\.error) {
            describedTools = described.loaded
        }
        if rejectedTools.map(\.id) != described.rejected.map(\.id)
            || rejectedTools.map(\.reason) != described.rejected.map(\.reason) {
            rejectedTools = described.rejected
        }
        // The notch is laid out from the tool list, so a new or departed tool has to
        // rebuild it. A changed number does not.
        if hadTools != describedTools.map(\.tool) { onLayoutChange?() }
    }
    /// The window the big number represents. Prefers whichever limit the provider
    /// says is actually biting, so the headline keeps a fixed meaning.
    func headline(_ provider: Provider) -> UsageWindow? { snapshot(provider)?.headline(at: now) }
    func status(_ provider: Provider) -> String {
        if errors[provider] != nil { return "Unavailable" }
        guard let snapshot = snapshot(provider) else {
            if signedInProviders.contains(provider) {
                return provider == .claude || provider == .claudeCode ? "Waiting for usage" : "Signed in"
            }
            return "Not connected"
        }
        if snapshot.primary(at: now) == nil { return "Awaiting update" }
        if snapshot.isStale(at: now) { return "Last known" }
        return "Connected"
    }
    /// An explicit refresh ignores both the cadence and any backoff.
    func refresh() {
        noteActivity()
        now = Date()
        described.reset()
        readDescribedTools(force: true)
        refreshClaudeUsage()
        pollAccounts(force: true)
    }

    /// Refresh one provider without disturbing the others.
    func refresh(_ provider: Provider) {
        noteActivity()
        now = Date()
        beginRefreshing(feedbackIDs(for: provider))
        switch provider {
        case .claude, .claudeCode: refreshClaudeUsage()
        case .codex, .chatgpt: pollCodex(force: true)
        }
    }

    private func pollAccounts(force: Bool) {
        // Sign-out has to surface even when usage polling is backed off or disabled.
        if isConnected(.claudeCode),
           force || refreshPolicy.shouldAttempt(refreshState(.claudeCode), lastActivity: lastActivity, now: now) {
            // Preserve the failure count: overwriting it here would defeat the backoff.
            var state = refreshState(.claudeCode)
            state.lastAttempt = now
            refreshStates[.claudeCode] = state
            persistRefreshStates()
            claudeSignIn.refresh()
            claudeLive.refresh()
        }
        pollCodex(force: force)
    }

    private func pollCodex(force: Bool) {
        guard isConnected(.codex), !isRefreshing else { return }
        guard force || refreshPolicy.shouldAttempt(refreshState(.codex), lastActivity: lastActivity, now: now) else { return }
        var state = refreshState(.codex)
        state.lastAttempt = now
        refreshStates[.codex] = state
        persistRefreshStates()
        codex.refresh(executable: executable, includeUsage: force || autoRefresh)
    }

    /// The newest reading wins, whatever produced it, so a cache read can never
    /// overwrite a fresher live one, and a slow live reply can never overwrite a
    /// newer cache read.
    private func applyClaude(_ snapshot: UsageSnapshot) {
        if let existing = snapshots[.claudeCode], existing.updatedAt > snapshot.updatedAt { return }
        var shared = snapshot
        shared.provider = .claudeCode
        snapshots[.claudeCode] = shared
        shared.provider = .claude
        snapshots[.claude] = shared
        errors[.claude] = nil; errors[.claudeCode] = nil
        endRefreshing(AccountSignIn.claudeProviders.map(\.rawValue))
        persistReadings()
    }

    private func refreshState(_ provider: Provider) -> ProviderRefreshState {
        refreshStates[provider] ?? ProviderRefreshState()
    }

    private func recordOutcome(_ provider: Provider, succeeded: Bool) {
        refreshStates[provider] = refreshPolicy.state(after: refreshState(provider), succeeded: succeeded, now: Date())
        persistRefreshStates()
    }

    /// Backoff deadlines outlive the process, so restarting cannot be used to skip a
    /// wait the provider asked for.
    private static func loadRefreshStates(_ defaults: UserDefaults) -> [Provider: ProviderRefreshState] {
        guard let data = defaults.data(forKey: "refreshState"),
              let saved = try? JSONDecoder().decode([String: ProviderRefreshState].self, from: data) else { return [:] }
        return Dictionary(uniqueKeysWithValues: saved.compactMap { key, value in
            Provider(rawValue: key).map { ($0, value) }
        })
    }

    private func persistRefreshStates() {
        let encodable = Dictionary(uniqueKeysWithValues: refreshStates.map { ($0.key.rawValue, $0.value) })
        guard let data = try? JSONEncoder().encode(encodable) else { return }
        defaults.set(data, forKey: "refreshState")
    }

    private func persistReadings() {
        do { try ReadingStore.save(snapshots) }
        catch { /* A failed cache write must never interrupt live readings. */ }
    }

    private func updateSignIn(_ providers: Set<Provider>, family: Set<Provider>) {
        let confirmed = providers.intersection(family)
        checkedProviders.formUnion(family)
        for provider in family.subtracting(confirmed) where snapshots[provider]?.source != .manual {
            snapshots[provider] = nil
        }
        signedInProviders = signedInProviders.subtracting(family).union(confirmed)
        if family == AccountSignIn.claudeProviders { confirmed.isEmpty ? claudeReader.reset() : readClaudeUsage() }
    }
    func isConnected(_ tool: KnownTool) -> Bool { connectedTools.contains(tool.rawValue) }

    /// Pressing Connect, which is the only thing that starts any of this.
    ///
    /// The consent is recorded first, then the tool's own sign-in is asked to do the
    /// work: Codex opens OpenAI's page in a browser, and Claude Code's saved login is
    /// read after macOS asks about it. Brim never sees a password either way.
    func connect(_ tool: KnownTool) {
        noteActivity()
        connectedTools.insert(tool.rawValue)
        switch tool {
        case .codex: codex.login(executable: executable)
        case .claudeCode: claudeSignIn.refresh(); enableLiveClaude()
        }
    }

    /// Withdrawing it. Everything read under that consent goes with it, and the tool
    /// is not touched again until someone asks a second time.
    func disconnect(_ tool: KnownTool) {
        connectedTools.remove(tool.rawValue)
        switch tool {
        case .codex:
            codex.stop()
            isRefreshing = false
        case .claudeCode:
            claudeSignIn.stop(); claudeLive.stop()
            liveClaude = .off; liveUnavailable = nil
        }
        updateSignIn([], family: Set(tool.providers))
        // Not "checked and signed out": not asked at all, which is what the row says.
        checkedProviders.subtract(tool.providers)
        for provider in tool.providers {
            errors[provider] = nil
            // Including the backoff. Reconnecting later is a fresh start, not the
            // resumption of a punishment served before the tool was switched off.
            refreshStates[provider] = nil
        }
        endRefreshing(tool.providers.map(\.rawValue))
        persistRefreshStates()
        // Off means off on disk too: readings.json is rewritten without them, so a
        // disconnected tool leaves nothing behind for the next launch to show.
        persistReadings()
    }
    /// Forces a re-read even when the file has not changed, for an explicit refresh.
    func refreshClaudeUsage() {
        claudeReader.reset()
        readClaudeUsage()
    }
    func readClaudeUsage() {
        guard signedInProviders.contains(.claudeCode) else { claudeReader.reset(); return }
        claudeReader.refresh()
    }

    /// Asks for live Claude usage now.
    ///
    /// The first call makes macOS ask whether Brim may read the login Claude Code
    /// saved; later ones just re-read. There is nothing to mint and nothing to paste,
    /// so this is the whole of "connecting".
    func enableLiveClaude() {
        noteActivity()
        liveClaude = .checking
        claudeLive.refresh()
    }

    /// Opens the folder the descriptions live in, creating and seeding it first.
    func revealToolsFolder() {
        do {
            try AppPaths.prepareTools()
            NSWorkspace.shared.activateFileViewerSelecting([AppPaths.tools])
        } catch {
            notice = "Couldn’t open the tools folder: \(error.localizedDescription)"
        }
    }
    func savePosition(_ position: NotchPosition?) {
        guard position.map({ NotchAnchor.allowedEdges.contains($0.anchor) }) ?? true else { return }
        preferredPosition = position
        if let position, let data = try? JSONEncoder().encode(position) { defaults.set(data, forKey: "notchPosition") }
        else { defaults.removeObject(forKey: "notchPosition") }
        onPositionChange?()
    }
    func setAutomaticPlacement(_ placement: NotchAnchor?) {
        if self.placement != placement { self.placement = placement }
    }
}

/// Whether Anthropic is answering with live usage.
enum LiveClaudeState: Equatable {
    /// Not asked for yet, or there is no Claude Code login to read.
    case off
    case checking
    case on
    /// Asked for, and something is in the way: a declined permission, a lapsed login.
    case problem(String)
}
