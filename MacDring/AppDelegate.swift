import AppKit

/// Boots the app: wires the store, display registry, and tab controller, builds
/// the menu-bar item, and seeds a starter tab on first run.
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private let preferences = Preferences.shared
    private let store = TabStore()
    private let registry = DisplayRegistry()
    private lazy var controller = TabController(store: store, preferences: preferences, registry: registry)
    private let updateChecker = UpdateChecker(
        configuration: .init(owner: "L-K-M", repo: "MacDring", appName: "MacDring")
    )
    private lazy var settingsWindow = SettingsWindowController(preferences: preferences, store: store, registry: registry, updateChecker: updateChecker)
    private lazy var newTabWindow = NewTabWindowController(preferences: preferences, store: store, registry: registry)

    private var statusItem: NSStatusItem?
    private var launchAtLoginItem: NSMenuItem?

    // MARK: NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.isRunningTests else { return }

        installMainMenu()
        if !store.loadedFromDisk && store.tabs.isEmpty {
            seedStarterTab()
        }
        controller.onOpenSettings = { [weak self] tabID in self?.settingsWindow.show(selectTab: tabID) }
        setUpStatusItem()
        controller.start()
        store.remintStaleBookmarks()   // heal bookmarks whose targets moved/renamed
        updateChecker.start()   // check GitHub for a newer release on launch + daily
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Same guard as didFinishLaunching: under XCTest this would instantiate
        // the lazy controller at test-host exit and save the (real) store —
        // rewriting the developer's live launcher.json and rotating its backup.
        guard !Self.isRunningTests else { return }
        controller.saveAndTeardown()
    }

    /// Opt into secure state restoration. We persist no NSWindow state ourselves,
    /// but macOS 14+ logs a warning unless the delegate answers this explicitly.
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    // MARK: Main menu

    /// Installs an App + Edit menu so the standard text-editing shortcuts
    /// (⌘C/⌘V/⌘X/⌘A, ⌘Z/⇧⌘Z) reach the first responder. Without it, an `LSUIElement`
    /// agent has no menu at all, so those keys do nothing in the notes editor, the
    /// rename field, or Settings fields. The Edit-menu items target the first
    /// responder (`nil` target), so their key equivalents route to whatever text view
    /// is focused. The menu bar stays hidden while the app is `.accessory` — only the
    /// key-equivalent routing matters here; it shows normally when Settings switches
    /// the app to `.regular`.
    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit MacDring", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: Selector(("cut:")), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: Selector(("copy:")), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: Selector(("paste:")), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: Selector(("selectAll:")), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        NSApp.mainMenu = mainMenu
    }

    // MARK: Status item

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = Self.statusBarImage()
        item.menu = buildMenu()
        statusItem = item
    }

    /// A template menu-bar glyph that echoes the app icon: a rounded "screen"
    /// outline with a single drawer pulled up from its bottom edge.
    private static func statusBarImage() -> NSImage {
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size, flipped: false) { _ in
            // The screen.
            let body = NSRect(x: 2, y: 2, width: 12, height: 12)
            let bodyPath = NSBezierPath(roundedRect: body, xRadius: 3, yRadius: 3)
            bodyPath.lineWidth = 1.4
            NSColor.black.setStroke()
            bodyPath.stroke()

            // A drawer riding the bottom edge, filled so it reads at small sizes.
            let drawer = NSRect(x: 4.75, y: 3, width: 6.5, height: 4)
            NSColor.black.setFill()
            NSBezierPath(roundedRect: drawer, xRadius: 1.6, yRadius: 1.6).fill()
            return true
        }
        image.isTemplate = true
        return image
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        let newItems = NSMenuItem(title: "New Items Tab…", action: #selector(newItemsTab), keyEquivalent: "n")
        newItems.target = self
        menu.addItem(newItems)

        let newNotes = NSMenuItem(title: "New Notes Tab…", action: #selector(newNotesTab), keyEquivalent: "")
        newNotes.target = self
        menu.addItem(newNotes)

        let newFolder = NSMenuItem(title: "New Folder Tab…", action: #selector(newFolderTab), keyEquivalent: "")
        newFolder.target = self
        menu.addItem(newFolder)

        let newDisks = NSMenuItem(title: "New Disks Tab…", action: #selector(newDisksTab), keyEquivalent: "")
        newDisks.target = self
        menu.addItem(newDisks)

        let newNetwork = NSMenuItem(title: "New Network Tab…", action: #selector(newNetworkTab), keyEquivalent: "")
        newNetwork.target = self
        menu.addItem(newNetwork)

        let newCloud = NSMenuItem(title: "New Cloud Tab…", action: #selector(newCloudTab), keyEquivalent: "")
        newCloud.target = self
        menu.addItem(newCloud)

        let newRecents = NSMenuItem(title: "New Recents Tab…", action: #selector(newRecentsTab), keyEquivalent: "")
        newRecents.target = self
        menu.addItem(newRecents)

        let newFresh = NSMenuItem(title: "New Fresh Tab…", action: #selector(newFreshTab), keyEquivalent: "")
        newFresh.target = self
        menu.addItem(newFresh)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "MacDring Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let updatesItem = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        updatesItem.target = self
        menu.addItem(updatesItem)

        menu.addItem(.separator())

        let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.target = self
        menu.addItem(loginItem)
        launchAtLoginItem = loginItem

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit MacDring", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        preferences.refreshLaunchAtLoginStatus()
        launchAtLoginItem?.state = preferences.launchAtLogin ? .on : .off
    }

    // MARK: Actions

    @objc private func newItemsTab() { newTabWindow.show(kind: .items) }
    @objc private func newNotesTab() { newTabWindow.show(kind: .notes) }
    @objc private func newFolderTab() { newTabWindow.show(kind: .folder) }
    @objc private func newDisksTab() { newTabWindow.show(kind: .disks) }
    @objc private func newNetworkTab() { newTabWindow.show(kind: .network) }
    @objc private func newCloudTab() { newTabWindow.show(kind: .cloud) }
    @objc private func newRecentsTab() { newTabWindow.show(kind: .recents) }
    @objc private func newFreshTab() { newTabWindow.show(kind: .fresh) }

    @objc private func openSettings() {
        settingsWindow.show(selectTab: nil)
    }

    @objc private func checkForUpdates() {
        updateChecker.checkNow()
    }

    @objc private func toggleLaunchAtLogin() {
        preferences.launchAtLogin.toggle()
        launchAtLoginItem?.state = preferences.launchAtLogin ? .on : .off
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: First-run starter tab

    private func seedStarterTab() {
        guard let uuid = registry.mainScreenUUID() else { return }

        var items: [DrawerItem] = []
        for bundleID in ["com.apple.finder", "com.apple.Safari", "com.apple.systempreferences"] {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                items.append(DrawerItem.fromFileURL(url))
            }
        }
        items.append(DrawerItem.fromFileURL(URL(fileURLWithPath: "/Applications", isDirectory: true)))

        let tab = Tab(
            title: "Apps",
            colorHex: preferences.defaultTabColorHex,
            glyph: .symbol("square.grid.2x2.fill"),
            anchor: ScreenAnchor(displayUUID: uuid, edge: .right, position: 0.5, order: 0),
            items: items,
            behavior: preferences.newTabBehavior,
            gridColumns: Int(preferences.gridColumns),
            gridRows: Int(preferences.gridRows)
        )
        store.addTab(tab)
        store.addTab(welcomeTab(displayUUID: uuid))
    }

    /// A first-run "Welcome" notes tab whose content is a checklist of things to
    /// try. The `- [ ]` lines render as real, tappable checkboxes in the note's
    /// preview — onboarding that demos the notes feature while it teaches the rest.
    /// Just a normal tab: rename it, restyle it, or delete it like any other.
    private func welcomeTab(displayUUID: String) -> Tab {
        let notes = """
        # Welcome to MacDring 👋

        Five things to try:

        - [ ] Drag a file from Finder onto the **Apps** tab
        - [ ] Open a drawer and just start typing to filter it
        - [ ] ⌘-click any item to reveal it in Finder
        - [ ] Right-click an item → **Customize Icon…**
        - [ ] Right-click a tab → *Configure Tab…* → set **When idle** to *Auto-hide*

        Ticking a box edits this note — it's a real scratchpad.
        Click anywhere to write; delete this tab whenever you're done.
        """
        return Tab(
            title: "Welcome",
            colorHex: "#E8A33D",
            glyph: .symbol("hand.wave.fill"),
            anchor: ScreenAnchor(displayUUID: displayUUID, edge: .right, position: 0.3, order: 1),
            behavior: preferences.newTabBehavior,
            gridColumns: 5,   // for a notes tab, columns/rows size the text area
            gridRows: 5,
            kind: .notes,
            notes: notes
        )
    }

    // MARK: Helpers

    static var isRunningTests: Bool {
        NSClassFromString("XCTestCase") != nil ||
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}
