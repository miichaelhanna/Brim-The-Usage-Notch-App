import AppKit
import SwiftUI
import BrimCore

@main
enum BrimApp {
    static func main() {
        if CommandLine.arguments.contains("--diagnose-screen") {
            ScreenDiagnostic.run()
            return
        }
        if CommandLine.arguments.contains("--diagnose-claude") {
            ClaudeUsageDiagnostic.run()
            return
        }
        if CommandLine.arguments.contains("--diagnose-tools") {
            MainActor.assumeIsolated { DescribedToolDiagnostic.run() }
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let store = UsageStore()
    let navigation = NavigationState()
    private var window: NSWindow?
    private var notch: NotchController?
    private var statusItem: NSStatusItem?
    private let controlsMenu = NSMenu(title: "Brim")
    private var diagnostic: CodexConnection?
    private lazy var usageLinks = UsageLinkRouter(opener: DesktopUsageOpener()) { [weak self] provider in
        self?.showUsage(provider)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--diagnose-codex") {
            let connection = CodexConnection(); diagnostic = connection
            connection.onRawUsage = { data in
                if let root = try? JSONSerialization.jsonObject(with: data) {
                    print("What the Codex app-server returned:")
                    print(ClaudeUsageDiagnostic.outline(root).joined(separator: "\n"))
                }
            }
            connection.onSnapshot = { snapshot in
                print("Parsed \(snapshot.windows.count) window(s), source=\(snapshot.source.rawValue)")
                for window in snapshot.windows {
                    print("   \(window.title): \(Int(window.usedPercent.rounded()))% "
                          + "(\(window.durationMinutes.map { "\($0) min" } ?? "no duration"))")
                }
                connection.stop(); NSApp.terminate(nil)
            }
            connection.onError = { message in fputs("Codex: \(message)\n", stderr); connection.stop(); exit(1) }
            connection.refresh(executable: CodexConnection.findExecutable())
            return
        }
        setupMenu()
        store.onPresenceChange = { [weak self] in self?.applyPresence() }
        store.onAppearanceChange = { [weak self] in self?.applyAppearance() }
        applyAppearance()
        // Forces the first-run screen, for development and for capturing screenshots.
        if CommandLine.arguments.contains("--welcome") { navigation.showWelcome = true }
        // --page <name>, for development and screenshots.
        if let index = CommandLine.arguments.firstIndex(of: "--page"),
           CommandLine.arguments.count > index + 1,
           let page = DashboardPage(rawValue: CommandLine.arguments[index + 1].capitalized) {
            navigation.page = page
        }
        if let index = CommandLine.arguments.firstIndex(of: "--render-notch"),
           CommandLine.arguments.count > index + 1 {
            store.start()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self else { return }
                NotchRenderer.run(into: CommandLine.arguments[index + 1], store: self.store)
                NSApp.terminate(nil)
            }
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--render-welcome"),
           CommandLine.arguments.count > index + 1 {
            renderWelcome(into: CommandLine.arguments[index + 1])
            return
        }
        if CommandLine.arguments.contains("--render-preview") {
            store.start()
            showDashboard()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.renderPreview() }
            return
        }
        notch = NotchController(store: store, openDashboard: { [weak self] in self?.showDashboard() }, openConnections: { [weak self] in self?.showConnections() })
        store.openConnections = { [weak self] in self?.showConnections() }
        store.openUsage = { [weak self] provider in
            Task { @MainActor [weak self] in await self?.usageLinks.open(provider) }
        }
        store.start()
        applyPresence()
        // A usage meter that is not running is not a meter: the point of it is being
        // there before you think to look. Asserted on every launch rather than the
        // first, so a registration that failed once, or that points at a copy of Brim
        // which has since moved, is repaired by the next launch instead of leaving the
        // menu bar empty after every restart. Turning it off in Settings is remembered.
        LoginItem.assertRegistered()
        if !UserDefaults.standard.bool(forKey: "hasLaunched") {
            // First run leads with what was found, not with an empty dashboard.
            navigation.showWelcome = true
            showDashboard()
            UserDefaults.standard.set(true, forKey: "hasLaunched")
        } else if CommandLine.arguments.contains("--show") {
            showDashboard()
        }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(wake), name: NSWorkspace.didWakeNotification, object: nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showDashboard(); return true }
    func applicationWillTerminate(_ notification: Notification) { store.stop(); diagnostic?.stop(); notch?.stop() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func setupMenu() {
        installStatusItem()
        let menu = NSMenu()
        for (title, selector, key) in [("Usage & controls", #selector(showControlsMenu), "u"), ("Open Brim", #selector(showDashboard), "o"), ("Appearance", #selector(showAppearance), ""), ("Connections", #selector(showConnections), ","), ("Refresh usage", #selector(refresh), "r"), ("Show / hide notch", #selector(toggleNotch), "")] {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: key); item.target = self; menu.addItem(item)
        }
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Brim", action: #selector(quit), keyEquivalent: "q"); quit.target = self; menu.addItem(quit)
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem); appItem.submenu = menu.copy() as? NSMenu
        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit; NSApp.mainMenu = main
    }

    /// The Dock icon is a runtime activation policy, not a bundle setting, so it can
    /// be turned on and off without relaunching. The menu bar item is not a choice:
    /// it is installed once at launch and stays, so the app can never go missing.
    /// Light, dark, or the Mac's own setting. Applied to the whole app rather than one
    /// window, so the menu bar item's menu matches too.
    private func applyAppearance() {
        switch store.appearance {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    private func applyPresence() {
        NSApp.setActivationPolicy(store.presence.showsDockIcon ? .regular : .accessory)
    }

    private func menuItem(_ title: String, action: Selector? = nil, value: Any? = nil, checked: Bool = false) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self; item.representedObject = value; item.state = checked ? .on : .off
        item.isEnabled = action != nil
        return item
    }

    func menuWillOpen(_ menu: NSMenu) {
        guard menu === controlsMenu else { return }
        store.controlsMenuOpen = true
        // The menu bar item lists every allowance, so opening it is a reading too.
        store.refreshForDisplay()
    }

    func menuDidClose(_ menu: NSMenu) {
        guard menu === controlsMenu else { return }
        store.controlsMenuOpen = false
    }

    /// Ordered by what someone opened the menu for: the numbers first, then the actions
    /// on those numbers, then how the notch looks, then the rest of the app, then Quit.
    /// Refreshing used to sit at the head of the notch controls, away from the readings
    /// it acts on.
    ///
    /// No trailing ellipses. Apple's convention marks a command that opens a dialog, and
    /// none of these do: they open a window that is already part of the app.
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === controlsMenu else { return }
        menu.removeAllItems()
        menu.addItem(menuItem("Brim"))
        if store.tools.isEmpty { menu.addItem(menuItem("No signed-in accounts")) }
        for tool in store.tools {
            let reading = store.reading(tool)
            let usage = reading?.primary(at: store.now).map { "\(Int($0.usedPercent.rounded()))% used" } ?? store.status(tool)
            let row = NSMenuItem(title: "\(tool.name): \(usage)", action: nil, keyEquivalent: "")
            let details = NSMenu()
            if let provider = tool.builtin {
                details.addItem(menuItem("Open usage page", action: #selector(openProviderUsage(_:)), value: provider.rawValue))
                details.addItem(.separator())
            }
            details.addItem(menuItem(store.status(tool)))
            if let scope = tool.scopeNote { details.addItem(menuItem(scope)) }
            if let reading, !reading.windows.isEmpty {
                for window in reading.windows {
                    details.addItem(menuItem("\(window.title): \(Int(window.usedPercent.rounded()))% used"))
                    details.addItem(menuItem(window.resetDescription(at: store.now)))
                }
            } else { details.addItem(menuItem("Set up usage tracking", action: #selector(showConnections))) }
            row.submenu = details; menu.addItem(row)
        }
        // Only while there is something to set up. Once Anthropic is answering live, an
        // invitation to set up what is already working reads as a fault. The ChatGPT
        // side is the per-tool "Set up usage tracking" above, which appears on the same
        // terms: only while that tool has no reading.
        if store.liveClaude != .on {
            menu.addItem(menuItem("Set up live Claude", action: #selector(showWelcome)))
        }
        menu.addItem(menuItem("Refresh usage", action: #selector(refresh)))

        menu.addItem(.separator())
        menu.addItem(menuItem("Show notch", action: #selector(toggleNotch), checked: store.notchVisible))
        menu.addItem(menuItem("Collapse until hovered", action: #selector(toggleCollapse), checked: store.collapseWhenIdle))
        let visibility = NSMenuItem(title: "Visibility", action: nil, keyEquivalent: "")
        let modes = NSMenu()
        for mode in NotchVisibilityMode.allCases {
            modes.addItem(menuItem(mode.title, action: #selector(setVisibility(_:)), value: mode.rawValue, checked: store.visibilityMode == mode))
        }
        visibility.submenu = modes; menu.addItem(visibility)
        let position = NSMenuItem(title: "Position", action: nil, keyEquivalent: "")
        let edges = NSMenu()
        edges.autoenablesItems = false
        edges.addItem(menuItem("Automatic", action: #selector(resetPosition), checked: store.preferredPosition == nil))
        for edge in NotchAnchor.allowedEdges {
            let dockBlocked = edge.rawValue == DockPositionReader.current().rawValue
            let detail = dockBlocked ? " (Dock)" : ""
            let item = menuItem(edge.title + detail, action: #selector(setEdge(_:)), value: edge.rawValue, checked: store.preferredPosition?.anchor == edge)
            item.isEnabled = !dockBlocked; edges.addItem(item)
        }
        position.submenu = edges; menu.addItem(position)

        menu.addItem(.separator())
        menu.addItem(menuItem("Open Brim", action: #selector(showDashboard)))
        menu.addItem(menuItem("Connections", action: #selector(showConnections)))
        menu.addItem(menuItem("Settings", action: #selector(showAppearance)))

        menu.addItem(.separator())
        menu.addItem(menuItem("Quit Brim", action: #selector(quit)))
    }

    /// The app's mark as a menu bar glyph: the notch alone, 22×9, drawn as a template so
    /// macOS tints it for the menu bar's appearance and for the highlighted state. The
    /// tile the icon draws it on is dropped, since a filled black square in the menu bar reads
    /// as a bug, and the shape is the mark.
    private static func menuBarImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 22, height: 9), flipped: false) { rect in
            // Square shoulders at the top, rounded where the notch ends, as in the icon.
            let radius: CGFloat = 3
            let path = NSBezierPath()
            path.move(to: NSPoint(x: rect.minX, y: rect.maxY))
            path.line(to: NSPoint(x: rect.maxX, y: rect.maxY))
            path.appendArc(from: NSPoint(x: rect.maxX, y: rect.minY),
                           to: NSPoint(x: rect.minX, y: rect.minY), radius: radius)
            path.appendArc(from: NSPoint(x: rect.minX, y: rect.minY),
                           to: NSPoint(x: rect.minX, y: rect.maxY), radius: radius)
            path.close()
            path.fill()
            return true
        }
        image.isTemplate = true
        return image
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = Self.menuBarImage()
            button.image?.accessibilityDescription = "Brim"
            button.toolTip = "Brim, usage and controls"
            button.setAccessibilityLabel("Brim menu bar")
        }
        controlsMenu.delegate = self
        item.menu = controlsMenu
        statusItem = item
    }

    @objc func showControlsMenu() {
        DispatchQueue.main.async { [weak self] in self?.statusItem?.button?.performClick(nil) }
    }
    @objc func openProviderUsage(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String, let provider = Provider(rawValue: value) else { return }
        store.openUsage?(provider)
    }
    @objc func toggleCollapse() { store.collapseWhenIdle.toggle() }
    @objc func setVisibility(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String, let mode = NotchVisibilityMode(rawValue: value) else { return }
        store.visibilityMode = mode
    }
    @objc func setEdge(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String, let edge = NotchAnchor(rawValue: value),
              NotchAnchor.allowedEdges.contains(edge) else { return }
        store.savePosition(NotchPosition(anchor: edge, fraction: 0.5))
    }
    @objc func resetPosition() { store.savePosition(nil) }

    @objc func showDashboard() {
        if window == nil {
            // Hosted as a content *view controller*, not a content view: that is what
            // lets SwiftUI install the window's toolbar and give the sidebar its
            // material, which is most of what makes this look like a Mac app.
            let controller = NSHostingController(rootView: DashboardView(store: store, navigation: navigation))
            let window = NSWindow(contentViewController: controller)
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.title = "Brim"
            window.titlebarAppearsTransparent = true
            window.toolbarStyle = .unified
            window.isReleasedWhenClosed = false
            // No appearance override and no background colour: the window belongs to
            // whatever mode the Mac is in. Pinning it to Aqua is what made earlier
            // builds look like a web page in a frame.
            window.setContentSize(NSSize(width: 880, height: 640))
            window.minSize = NSSize(width: 720, height: 520)
            window.center(); self.window = window
        }
        // Opening the window is someone looking at their limits; the numbers should be
        // current by the time they have read the heading.
        store.refreshForDisplay()
        NSApp.activate(ignoringOtherApps: true); window?.makeKeyAndOrderFront(nil)
    }
    @objc func showAppearance() { navigation.showWelcome = false; navigation.page = .appearance; showDashboard() }
    @objc func showWelcome() { navigation.showWelcome = true; showDashboard() }
    @objc func showConnections() { navigation.showWelcome = false; navigation.page = .connections; showDashboard() }
    private func showUsage(_ provider: Provider) {
        store.selected = provider.displayProvider.rawValue
        navigation.page = .overview
        showDashboard()
    }
    @objc func refresh() { store.refresh() }
    @objc func wake() { store.refresh(); notch?.rebuild() }
    @objc func toggleNotch() { store.notchVisible.toggle() }
    @objc func quit() { NSApp.terminate(nil) }

    /// Renders the first-run screen straight from SwiftUI, for documentation and for
    /// looking at the keychain illustration without connecting anything.
    ///
    /// Hosted in an offscreen window and cached, not run through `ImageRenderer`.
    /// `ImageRenderer` cannot draw AppKit-backed controls and leaves a yellow
    /// placeholder where every switch should be, which makes the render useless for
    /// judging the screen. A real view in a real window draws real controls.
    private func renderWelcome(into path: String) {
        let view = NSHostingView(rootView: OnboardingView(store: store) {}.flattened)
        // Sized explicitly. A hosting view's `fittingSize` is no use here: measured off
        // the frame it answers at its own ideal width and clips, and measured off a
        // width constraint it runs away to tens of thousands of points. The screen is
        // a fixed-size illustration either way, so the size is simply stated.
        let size = NSSize(width: 880, height: 1000)
        view.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        // One turn of the run loop, so the hosting view has actually drawn before it
        // is asked for its bitmap.
        DispatchQueue.main.async {
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(1) }
            view.cacheDisplay(in: view.bounds, to: rep)
            guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
            do { try data.write(to: URL(fileURLWithPath: path)); NSApp.terminate(nil) }
            catch { exit(1) }
        }
    }

    private func renderPreview() {
        guard let index = CommandLine.arguments.firstIndex(of: "--render-preview"), CommandLine.arguments.count > index + 1,
              let view = window?.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(1) }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
        do { try data.write(to: URL(fileURLWithPath: CommandLine.arguments[index + 1])); NSApp.terminate(nil) }
        catch { exit(1) }
    }
}
