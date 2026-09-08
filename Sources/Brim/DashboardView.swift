import AppKit
import SwiftUI
import ServiceManagement
import BrimCore

/// The window is built the way System Settings is: a source list on the left, and
/// grouped forms on the right. That is not decoration. It is what tells someone this
/// belongs to their Mac rather than to a browser tab. So the layout is
/// `NavigationSplitView`, the content is `Form(.grouped)`, the controls are the system's
/// own, and every colour comes from the appearance rather than from a fixed palette.
enum DashboardPage: String, CaseIterable, Identifiable {
    case overview = "Usage"
    case connections = "Connections", appearance = "Notch", roadmap = "Roadmap"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .overview: "chart.bar.fill"
        case .connections: "link"
        case .appearance: "macbook"
        case .roadmap: "signpost.right.fill"
        }
    }

    /// System Settings gives every pane a coloured tile, and the colour is how people
    /// find a row without reading it.
    var tint: Color {
        switch self {
        case .overview: .blue
        case .connections: .green
        case .appearance: .indigo
        case .roadmap: .orange
        }
    }
}

@MainActor
final class NavigationState: ObservableObject {
    @Published var page = DashboardPage.overview
    /// Shown on first launch, and reopenable from the menu.
    @Published var showWelcome = false
}

/// A System Settings sidebar tile: a small tinted rounded square with a symbol in it.
struct SettingsIcon: View {
    let symbol: String
    var tint: Color = .blue
    var size: CGFloat = 20
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(tint.gradient)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.55, weight: .medium))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }
}

/// A status word, in the weight the system uses for secondary information.
struct StatusChip: View {
    let text: String
    var tint: Color = .secondary
    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(tint.opacity(0.12), in: Capsule())
            .accessibilityLabel(text.lowercased())
    }
}

struct DashboardView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var navigation: NavigationState

    var body: some View {
        if navigation.showWelcome {
            OnboardingView(store: store) { navigation.showWelcome = false }
        } else {
            split
        }
    }

    private var split: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .alert("Brim", isPresented: Binding(get: { store.notice != nil },
                                            set: { if !$0 { store.notice = nil } })) {
            Button("OK") { store.notice = nil }
        } message: { Text(store.notice ?? "") }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: Binding(get: { navigation.page }, set: { navigation.page = $0 ?? .overview })) {
            ForEach(DashboardPage.allCases) { page in
                Label {
                    Text(page.rawValue)
                } icon: {
                    SettingsIcon(symbol: page.symbol, tint: page.tint)
                }
                .tag(page)
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 190, ideal: 200, max: 240)
        .safeAreaInset(edge: .bottom) {
            // Appearance sits at the foot of the source list, the way System Settings
            // keeps its own appearance control out of the panes it affects.
            VStack(spacing: 0) {
                Divider()
                Picker("Appearance", selection: $store.appearance) {
                    ForEach(AppAppearance.allCases) { mode in
                        Label(mode.title, systemImage: mode.symbol).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .padding(.horizontal, 12).padding(.vertical, 9)
                .help("Light, dark, or match the Mac")
            }
        }
    }

    // MARK: - Detail

    @ViewBuilder private var detail: some View {
        Group {
            switch navigation.page {
            case .overview: overview
            case .connections: ConnectionsView(store: store)
            case .appearance: AppearanceView(store: store)
            case .roadmap: RoadmapView()
            }
        }
        .navigationTitle(navigation.page.rawValue)
        .navigationSplitViewColumnWidth(min: 520, ideal: 580)
        // The window's title bar is transparent so the sidebar runs the full height.
        // Without a toolbar background the form then scrolls *through* the title rather
        // than under it, and the two sets of words overlap.
        .toolbarBackground(.visible, for: .windowToolbar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    store.refresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Refresh usage now")
                .disabled(store.isRefreshing)
            }
        }
    }

    // MARK: - Usage

    private var overview: some View {
        Form {
            if store.tools.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("No accounts detected", systemImage: "person.crop.circle.badge.questionmark")
                    } description: {
                        Text("Connect Claude Code or the ChatGPT app in Connections and your usage appears here.")
                    } actions: {
                        Button("Open Connections") { navigation.page = .connections }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(.vertical, 8)
                }
            }
            ForEach(store.tools) { tool in usageSection(tool) }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder private func usageSection(_ tool: TrackedTool) -> some View {
        let reading = store.reading(tool)
        let error = store.error(tool)
        let headline = reading?.headline(at: store.now)
        Section {
            if let reading, !reading.windows.isEmpty {
                ForEach(reading.windows) { window in
                    UsageRow(window: window, now: store.now, emphasised: window.id == headline?.id)
                }
            } else {
                Text(store.emptyMessage(tool))
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 2)
                Button(tool.isDescribed ? "Open its description" : "Set up \(tool.name)") {
                    tool.isDescribed ? store.revealToolsFolder() : (navigation.page = .connections)
                }
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let reading, reading.isStale(at: store.now) {
                Label("Showing the last known reading. Refresh for a current one.",
                      systemImage: "clock.arrow.circlepath")
                    .font(.callout).foregroundStyle(.orange)
            }
        } header: {
            HStack(spacing: 8) {
                ToolMark(tool: tool, size: 17, tint: .primary)
                Text(tool.name).font(.headline)
                if let provider = tool.builtin {
                    Button {
                        store.openUsage?(provider)
                    } label: {
                        Image(systemName: "arrow.up.forward.square")
                    }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .help(tool.linkHint)
                }
                Spacer()
                StatusChip(text: store.status(tool),
                           tint: store.status(tool) == "Connected" ? .green : .secondary)
            }
            .padding(.bottom, 2)
        } footer: {
            VStack(alignment: .leading, spacing: 3) {
                if let scope = tool.scopeNote {
                    Text(scope).fixedSize(horizontal: false, vertical: true)
                }
                if let reading {
                    // When the reading was taken, not the clock time it was shown.
                    Text(reading.sourceLabel + " · taken "
                         + reading.updatedAt.formatted(.relative(presentation: .named)))
                }
            }
            .font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// One limit, as a row in a grouped form.
///
/// Separate from `UsageBar`, which draws the same reading inside the notch's black
/// card. The two surfaces want opposite things: the notch wants a dense custom bar, and
/// the window wants the system's own progress control, because that is what makes it
/// look like it came with the Mac.
struct UsageRow: View {
    let window: UsageWindow
    let now: Date
    var emphasised = false

    var body: some View {
        let expired = window.hasExpired(at: now)
        let tint = Palette.usage(window.usedPercent, severity: window.severity)
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Text(window.title).font(emphasised ? .body.weight(.medium) : .body)
                if window.isActive { StatusChip(text: "Limiting", tint: tint) }
                if window.isEstimated { StatusChip(text: "Estimated") }
                Spacer(minLength: 8)
                Text("\(Int(window.usedPercent.rounded()))%")
                    .font(.body.weight(.medium)).monospacedDigit()
                    .foregroundStyle(expired ? .secondary : tint)
            }
            ProgressView(value: window.fraction)
                .progressViewStyle(.linear)
                .tint(tint)
            HStack {
                Text(window.resetDescription(at: now))
                Spacer()
                if !expired {
                    Text("\(Int(max(0, 100 - window.usedPercent).rounded()))% left")
                }
            }
            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
        }
        .padding(.vertical, 3)
        .opacity(expired ? 0.55 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(window.title), \(Int(window.usedPercent.rounded())) percent used"
                            + (window.isActive ? ", currently limiting" : "")
                            + (window.isEstimated ? ", estimated" : ""))
    }
}

// MARK: - Connections

struct ConnectionsView: View {
    @ObservedObject var store: UsageStore
    /// Which tool's setup is open. One at a time. The point of this screen is that
    /// there is nothing to read unless you asked for it.
    @State private var expanded: KnownTool?
    @State private var copiedPrompt = false

    var body: some View {
        Form {
            connectable
            addATool
            openSource
        }
        .formStyle(.grouped)
    }

    // MARK: Tools that can be connected

    @ViewBuilder private var connectable: some View {
        Section {
            if KnownTool.installed.isEmpty {
                Text("No connectable tools found. Install Claude Code or the ChatGPT app and they appear here.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(KnownTool.installed) { tool in
                row(tool)
                if expanded == tool { setup(tool) }
            }
        } header: {
            Text("Ready to connect")
        } footer: {
            Text("Each switch is off until you turn it on, and turning one off stops every read and "
                 + "clears what was read. Brim never asks for an account password: connecting hands "
                 + "you to each tool’s own "
                 + "sign-in, which is the only place a password belongs. Subscription limits and API "
                 + "billing are separate, and Brim never substitutes one for the other.")
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func row(_ tool: KnownTool) -> some View {
        let state = tool.connection(in: store)
        return HStack(spacing: 11) {
            Group {
                if let provider = tool.providers.first {
                    ProviderMark(provider: provider, size: 19, tint: .primary)
                } else {
                    SettingsIcon(symbol: "puzzlepiece.extension.fill", tint: .gray, size: 19)
                }
            }.frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(tool.displayName)
                Text(state.detail)
                    .font(.caption)
                    .foregroundStyle(state.isProblem ? Color.orange : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 10)
            switch state.status {
            case .checking: ProgressView().controlSize(.small)
            case .needsSignIn: Button("Sign In") { store.connect(tool) }
            case .problem: Button("Try Again") { store.connect(tool) }
            case .connected: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .off: EmptyView()
            }
            Toggle("Connected", isOn: connection(tool))
                .toggleStyle(.switch).controlSize(.small).labelsHidden()
            Button(expanded == tool ? "Done" : "Manage") {
                expanded = expanded == tool ? nil : tool
            }
            .disabled(!state.isOn)
        }
        .padding(.vertical, 3)
    }

    /// The switch is the consent itself, so flipping it is the whole of connecting and
    /// the whole of disconnecting. Off stops every read and clears what was read.
    private func connection(_ tool: KnownTool) -> Binding<Bool> {
        Binding(get: { store.isConnected(tool) },
                set: { on in
                    if on { expanded = tool; store.connect(tool) }
                    else { expanded = nil; store.disconnect(tool) }
                })
    }

    /// What a tool needs beyond the button, shown only once it is asked for.
    @ViewBuilder private func setup(_ tool: KnownTool) -> some View {
        switch tool {
        case .claudeCode:
            ClaudeLiveSetupCard(store: store)
        case .codex:
            VStack(alignment: .leading, spacing: 10) {
                Text(Provider.chatgpt.usageScopeNote ?? "")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                DisclosureGroup("Executable") {
                    HStack {
                        Text(store.executable ?? "Codex wasn’t found")
                            .font(.caption.monospaced()).foregroundStyle(.secondary)
                            .lineLimit(2).textSelection(.enabled)
                        Spacer()
                        Button("Choose…") {
                            let panel = NSOpenPanel()
                            panel.canChooseDirectories = false
                            panel.allowsMultipleSelection = false
                            if panel.runModal() == .OK, let path = panel.url?.path {
                                store.customCodexPath = path
                                store.refresh()
                            }
                        }
                        if !store.customCodexPath.isEmpty {
                            Button("Auto-detect") { store.customCodexPath = ""; store.refresh() }
                        }
                    }.padding(.top, 6)
                }
                .font(.callout)
            }
            .padding(.leading, 39)
            .padding(.vertical, 2)
        }
    }

    // MARK: Anything the app doesn't know about

    /// There is no form here on purpose. Typing a percentage in makes a number that is
    /// wrong by the time you close the window; describing where the tool already keeps
    /// its own figure makes one that stays right.
    @ViewBuilder private var addATool: some View {
        Section {
            ForEach(Array(store.describedTools.enumerated()), id: \.element.id) { _, added in
                HStack(spacing: 11) {
                    ToolMark(tool: added.tool, size: 19, tint: .primary).frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(added.descriptor.name)
                        Text(added.error ?? added.descriptor.file)
                            .font(.caption)
                            .foregroundStyle(added.error == nil ? Color.secondary : Color.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 10)
                    StatusChip(text: added.error == nil ? "Reading" : "Check it",
                               tint: added.error == nil ? .green : .orange)
                }
                .padding(.vertical, 3)
            }
            ForEach(store.rejectedTools) { rejected in
                Label("\(rejected.filename): \(rejected.reason)", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Finding where a tool hides its usage is tedious, and writing the file is
            // easy once you know the format. That is exactly the split an assistant is
            // good at, so the app hands over the whole specification rather than
            // explaining it here and hoping. It goes first because it is the way that
            // works without reading anything.
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("The fast way: let your AI do it")
                    Text("Copies a prompt carrying the whole format and the rules that keep a reading "
                         + "honest. Paste it into Claude Code, Codex, or whatever you use, name the "
                         + "tool, and it finds the file and writes the description for you.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 14)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(ToolSamples.aiPrompt, forType: .string)
                    copiedPrompt = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copiedPrompt = false }
                } label: {
                    Label(copiedPrompt ? "Copied" : "Copy Prompt",
                          systemImage: copiedPrompt ? "checkmark" : "doc.on.doc")
                }
                // The prominent one, because handing the prompt to an assistant is what
                // almost everyone will do. Writing the JSON by hand is the fallback, and
                // it had the blue button purely because it was written first.
                .buttonStyle(.borderedProminent)
                .help("Copy a ready-made prompt that writes the description for you")
            }
            .padding(.vertical, 2)
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("The manual way: write it yourself")
                    Text("Drop a JSON file into the tools folder. The guide gives the format and a "
                         + "worked example to copy.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 14)
                VStack(alignment: .trailing, spacing: 7) {
                    Button("Open Tools Folder") { store.revealToolsFolder() }
                    Link("How it works", destination: Links.addATool).font(.callout)
                }
            }
            .padding(.vertical, 2)
        } header: {
            Text("Add a tool")
        } footer: {
            Text("A description reads one local file. It never runs a command, makes a request, or "
                 + "touches a credential.")
        }
    }

    /// The way in for everything else: the project itself.
    private var openSource: some View {
        Section {
            HStack {
                Text("Brim is open source. Want another tool read, or something it doesn't do yet? "
                     + "Ask, or send a pull request.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 14)
                VStack(alignment: .trailing, spacing: 7) {
                    Link("Contribute an Adapter", destination: Links.providers)
                    Link("Ask for a Tool", destination: Links.requestProvider)
                }
                .font(.callout)
            }
            .padding(.vertical, 2)
        } header: {
            HStack {
                Text("Want something else?")
                Spacer()
                Text("Open source · MIT").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Notch

struct AppearanceView: View {
    @ObservedObject var store: UsageStore
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    /// The one edge that cannot be chosen. Read each time the view draws, so moving the
    /// Dock while this is open updates which edge is unavailable.
    private var dockEdge: NotchAnchor? { NotchAnchor(rawValue: DockPositionReader.current().rawValue) }

    private var positionAlignment: Alignment {
        switch store.placement {
        case .left: .leading
        case .right: .trailing
        case .bottom: .bottom
        case .top: .top
        case nil: .center
        }
    }

    var body: some View {
        Form {
            position
            size
            presence
            visibility
            contents
            general
        }
        .formStyle(.grouped)
    }

    private var position: some View {
        Section {
            HStack(alignment: .center, spacing: 18) {
                screenPreview
                VStack(alignment: .leading, spacing: 6) {
                    Picker("Edge", selection: Binding(
                        get: { store.preferredPosition?.anchor },
                        set: { store.savePosition($0.map { NotchPosition(anchor: $0, fraction: 0.5) }) })) {
                        Text("Automatic").tag(NotchAnchor?.none)
                        Divider()
                        ForEach(NotchAnchor.allowedEdges) { edge in
                            Text(edge == dockEdge ? "\(edge.title) (Dock is here)" : edge.title)
                                .tag(NotchAnchor?.some(edge))
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 260)
                    Text(store.preferredPosition == nil
                         ? "Brim picks the first edge with room: right, then left, bottom, top."
                         : "Currently on the \(store.placement?.title.lowercased() ?? "chosen edge").")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 2)
        } header: {
            Text("Position")
        } footer: {
            Text("Every edge is available except the one your Dock is on, which the notch always "
                 + "leaves alone. You can also drag the grip inside the notch along an edge or onto "
                 + "another one. The top edge hangs from the very top of the screen, and on a Mac with "
                 + "a notch it tucks into the hardware.")
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// One control for the whole drawing, rather than one per dimension. The notch's
    /// proportions are the design; what changes between a 13-inch laptop and a 32-inch
    /// display is how big the whole thing should be on it.
    private var size: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    Slider(value: Binding(get: { Double(store.notchSize.scale) },
                                          set: { store.notchSize = NotchSize(scale: CGFloat($0)) }),
                           in: Double(NotchSize.range.lowerBound)...Double(NotchSize.range.upperBound),
                           step: Double(NotchSize.stepPercent) / 100) {
                        Text("Size")
                    } minimumValueLabel: {
                        Image(systemName: "circle").font(.system(size: 8)).foregroundStyle(.secondary)
                    } maximumValueLabel: {
                        Image(systemName: "circle").font(.system(size: 14)).foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Notch size")
                    .accessibilityValue(store.notchSize.label)
                    // A fixed slot: the percentage must not shove the slider sideways
                    // as it crosses from 95% to 100%.
                    Text(store.notchSize.label)
                        .font(.callout).monospacedDigit().foregroundStyle(.secondary)
                        .frame(width: 42, alignment: .trailing)
                }
                Button("Reset to default") { store.notchSize = .standard }
                    .buttonStyle(.link).font(.caption)
                    .disabled(store.notchSize.isStandard)
            }
            .padding(.vertical, 2)
        } header: {
            Text("Size")
        } footer: {
            Text("Everything on the notch scales together: the rings, the number under each "
                 + "one, the grip, and the thin edge it collapses to. The notch is rebuilt at "
                 + "the new size as you drag, so an edge that no longer has room for it will "
                 + "hand it to another one.")
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var screenPreview: some View {
        ZStack(alignment: positionAlignment) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.16, green: 0.28, blue: 0.27),
                                              Color(red: 0.08, green: 0.13, blue: 0.16)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            if let placement = store.placement {
                // Scaled by the same factor the notch is, so the slider can be seen
                // doing something without hunting for the notch on the screen edge.
                let scale = store.notchSize.scale
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(.black)
                    .frame(width: (placement.isHorizontal ? 62 : 15) * scale,
                           height: (placement.isHorizontal ? 15 : 56) * scale)
                    .padding(3)
            }
        }
        .frame(width: 132, height: 84)
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Palette.line))
        .accessibilityHidden(true)
    }

    private var presence: some View {
        Section {
            Toggle("Show in the Dock", isOn: Binding(get: { store.presence.showsDockIcon },
                                                     set: { store.presence = $0 ? .both : .menuBar }))
        } header: {
            Text("Where the app appears")
        } footer: {
            Text("Brim always lives in the menu bar, which is where usage and every control are, so "
                 + "the app can never go missing. The Dock icon is optional.")
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var visibility: some View {
        Section {
            Picker("Show the notch", selection: $store.visibilityMode) {
                ForEach(NotchVisibilityMode.allCases) { mode in Text(mode.title).tag(mode) }
            }
            .pickerStyle(.inline)
            Toggle("Collapse to an edge until hovered", isOn: $store.collapseWhenIdle)
        } header: {
            Text("Visibility")
        } footer: {
            Text(store.visibilityMode == .overApps
                 ? "The notch stays visible over app windows. Collapsed, it shows a small edge until "
                   + "you hover it, and stays open while you use its controls."
                 : "The notch stays on your desktop, behind app windows. Collapsed, it shows a small "
                   + "edge until you hover it.")
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var contents: some View {
        Section {
            if store.tools.isEmpty {
                Text("Connect a tool in Connections and it appears here.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            ForEach(store.tools) { tool in
                Toggle(isOn: Binding(get: { store.visible.contains(tool.id) },
                                     set: { _ in store.toggle(tool) })) {
                    HStack(spacing: 9) {
                        ToolMark(tool: tool, size: 17, tint: .primary).frame(width: 24)
                        Text(tool.name)
                    }
                }
            }
        } header: {
            Text("On your notch")
        } footer: {
            // These switches look identical to the ones in Connections and mean
            // something entirely different. Whichever screen someone is on, the
            // difference has to be on it too, not left to be inferred.
            Text("Which rings the notch draws. Hiding one is display only: its usage is still "
                 + "read, and it stays in Usage. To stop reading a tool altogether, turn it off "
                 + "in Connections.")
        }
    }

    private var general: some View {
        Section {
            Toggle("Refresh Codex every minute", isOn: $store.autoRefresh)
            Toggle("Open at login", isOn: Binding(get: { launchAtLogin }, set: { value in
                do {
                    if value { try SMAppService.mainApp.register() }
                    else { try SMAppService.mainApp.unregister() }
                    launchAtLogin = SMAppService.mainApp.status == .enabled
                } catch {
                    store.notice = "Couldn’t change login startup. Move Brim to Applications and try again."
                }
            }))
        } header: {
            Text("General")
        } footer: {
            Text("Brim \(AppVersion.current)")
        }
    }
}

// MARK: - Roadmap

/// What Brim aims to read next.
///
/// Deliberately undated, and deliberately bare. Earlier versions of this page explained
/// what each provider was waiting on, which read as excuses for work that had not been
/// done. The name and "Coming soon" say the same thing without the apology.
struct RoadmapView: View {
    /// A provider that is not read yet.
    private struct Planned: Identifiable {
        let id: String
        let name: String
        /// Its own mark. Shown in the row so the list reads as the products people
        /// recognise rather than as three grey placeholders.
        @ViewBuilder var mark: () -> AnyView
    }

    private let planned: [Planned] = [
        Planned(id: "cursor", name: "Cursor",
                mark: { AnyView(BrandGlyph(data: BrandMarks.cursor)
                    .fill(.primary, style: FillStyle(eoFill: true)).frame(width: 19, height: 19)) }),
        Planned(id: "figma-make", name: "Figma Make",
                mark: { AnyView(FigmaMark(size: 19)) }),
        Planned(id: "perplexity", name: "Perplexity",
                mark: { AnyView(BrandGlyph(data: BrandMarks.perplexity)
                    .fill(.primary).frame(width: 19, height: 19)) })
    ]


    var body: some View {
        Form {
            Section {
                ForEach(planned) { item in
                    HStack(spacing: 11) {
                        item.mark()
                            .frame(width: 28, alignment: .leading)
                        Text(item.name)
                        Spacer(minLength: 10)
                        StatusChip(text: "Coming soon", tint: .orange)
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("Planned")
            }

            Section {
                supported("Claude · Claude Code", detail: "One subscription allowance, read live from Anthropic.",
                          provider: .claude)
                supported("ChatGPT · Codex", detail: "One Work allowance, read live from the ChatGPT app’s own engine.",
                          provider: .chatgpt)
            } header: {
                Text("Supported today")
            } footer: {
                Text("Each pair shares one allowance, so each is one ring rather than two showing the "
                     + "same number.")
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                HStack {
                    Text("Brim is open source. The fastest way onto this list is a pull request from "
                         + "someone who has the tool installed, because an adapter can only be checked "
                         + "against real numbers.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 14)
                    VStack(alignment: .trailing, spacing: 7) {
                        Link("Contribute an Adapter", destination: Links.providers)
                        Link("Ask for a Tool", destination: Links.requestProvider)
                    }
                    .font(.callout)
                }
                .padding(.vertical, 2)
            } header: {
                Text("Want one sooner?")
            }
        }
        .formStyle(.grouped)
    }

    private func supported(_ name: String, detail: String, provider: Provider) -> some View {
        HStack(alignment: .top, spacing: 11) {
            ProviderMark(provider: provider, size: 19, tint: .primary)
                .frame(width: 28, alignment: .leading)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                Text(detail).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 10)
            StatusChip(text: "Live", tint: .green)
        }
        .padding(.vertical, 4)
    }
}
