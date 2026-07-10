import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Manage all tabs: a selectable list on the left, a per-tab editor on the
/// right (name, color, glyph, edge, display, position, behavior, hotkey, items).
struct TabsView: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var store: TabStore
    let registry: DisplayRegistry
    @ObservedObject var router: SettingsRouter

    @State private var selection: UUID?

    var body: some View {
        HSplitView {
            tabList
                .frame(minWidth: 180, maxWidth: 240)

            Group {
                if let id = selection, let tab = store.tab(id: id) {
                    TabEditor(tab: tab, preferences: preferences, store: store, registry: registry)
                        .id(id)
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: 32)).foregroundStyle(.secondary)
                        Text("Select a tab, or add one with +")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            // Consume the routed selection so re-entering the pane later (after
            // the user picked a different tab) doesn't snap back to it.
            if let requested = router.tabToSelect {
                selection = requested
                router.tabToSelect = nil
            } else if selection == nil {
                selection = store.tabs.first?.id
            }
        }
        .onChange(of: router.tabToSelect) { requested in
            if let requested {
                selection = requested
                router.tabToSelect = nil
            }
        }
    }

    private var tabList: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach(store.tabs) { tab in
                    HStack(spacing: 8) {
                        Circle().fill(Color(hexString: tab.colorHex)).frame(width: 11, height: 11)
                        Text(tab.title.isEmpty ? "Untitled" : tab.title).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(tab.anchor.edge.displayName)
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .tag(tab.id)
                }
                .onMove(perform: moveTabs)
            }

            Divider()
            HStack(spacing: 2) {
                Button(action: addTab) { Image(systemName: "plus") }
                Button(action: removeSelected) { Image(systemName: "minus") }
                    .disabled(selection == nil)
                Spacer()
                Button(action: exportLayout) { Image(systemName: "square.and.arrow.up") }
                    .help("Export layout…")
                    .disabled(store.tabs.isEmpty)
                Button(action: importLayout) { Image(systemName: "square.and.arrow.down") }
                    .help("Import layout…")
            }
            .buttonStyle(.borderless)
            .padding(6)
        }
    }

    // MARK: Import / export

    private func exportLayout() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "MacDring Layout.json"
        panel.message = "Export your tabs and items as a JSON layout file"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try store.export(to: url)
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = "Couldn't export layout"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    private func importLayout() {
        let open = NSOpenPanel()
        open.allowedContentTypes = [.json]
        open.canChooseFiles = true
        open.allowsMultipleSelection = false
        open.message = "Choose a MacDring layout to import"
        guard open.runModal() == .OK, let url = open.url, let data = try? Data(contentsOf: url) else { return }

        let confirm = NSAlert()
        confirm.messageText = "Replace all tabs?"
        confirm.informativeText = "Importing a layout replaces your current tabs and items. This can't be undone."
        confirm.addButton(withTitle: "Replace")
        confirm.addButton(withTitle: "Cancel")
        guard confirm.runModal() == .alertFirstButtonReturn else { return }

        if store.importData(data) {
            selection = store.tabs.first?.id
        } else {
            let error = NSAlert()
            error.messageText = "Couldn't import that file"
            error.informativeText = "It doesn't look like a valid MacDring layout."
            error.runModal()
        }
    }

    private func addTab() {
        guard let uuid = registry.mainScreenUUID() else { return }
        // Stack the new tab on top of the ones already on this edge (highest `order`)
        // so the de-overlap pass snaps the newcomer into a legal gap and leaves the
        // existing tabs put.
        let rightTabs = store.tabs.filter { $0.anchor.edge == .right && $0.anchor.displayUUID == uuid }
        let order = PersistedLayoutBounds.nextOrder(after: rightTabs.map(\.anchor.order).max())
        let tab = Tab(
            title: "New Tab",
            colorHex: preferences.defaultTabColorHex,
            glyph: .symbol("folder.fill"),
            anchor: ScreenAnchor(displayUUID: uuid, edge: .right, position: 0.5, order: order),
            behavior: preferences.newTabBehavior
        )
        store.addTab(tab)
        selection = tab.id
    }

    private func removeSelected() {
        guard let id = selection else { return }
        store.removeTab(id: id)
        selection = store.tabs.first?.id
    }

    /// Reorders the tab list, renumbering each tab's stack `order` to its new
    /// position so tabs sharing an edge restack to match the list.
    private func moveTabs(from offsets: IndexSet, to destination: Int) {
        var tabs = store.tabs
        tabs.move(fromOffsets: offsets, toOffset: destination)
        for index in tabs.indices {
            tabs[index].anchor.order = PersistedLayoutBounds.clampedOrder(index)
        }
        store.replaceTabs(tabs)
    }
}

/// A per-tab override choice for a behavior that has a global default: follow the
/// global setting, or pin it On / Off for this tab. "Use global" is also the revert.
private enum BehaviorMode { case useGlobal, on, off }

/// Edits one tab through field-wise store bindings so unrelated live changes are
/// never replaced by a stale editor snapshot.
private struct TabEditor: View {
    let tab: Tab
    @ObservedObject var preferences: Preferences
    @ObservedObject var store: TabStore
    let registry: DisplayRegistry

    @State private var showingLinkSheet = false
    @State private var linkText = ""

    var body: some View {
        Form {
            Section("Tab") {
                // A tab's type is fixed at creation (it determines what the drawer
                // holds), so it's shown read-only here — change it by making a new tab.
                LabeledContent("Type", value: currentTab.kind.displayName)
                TextField("Name", text: tabBinding(\.title))
                ColorPicker("Color", selection: colorBinding, supportsOpacity: false)
                Picker("Glyph", selection: glyphIsSymbolBinding) {
                    Text("SF Symbol").tag(true)
                    Text("Letters / Emoji").tag(false)
                }
                .pickerStyle(.segmented)
                if glyphIsSymbolBinding.wrappedValue {
                    LabeledContent("Symbol") { SymbolPickerView(symbolName: symbolBinding) }
                } else {
                    HStack {
                        TextField("Letters or emoji", text: monogramBinding)
                        Button {
                            NSApp.orderFrontCharacterPalette(nil)
                        } label: {
                            Image(systemName: "face.smiling")
                        }
                        .help("Emoji & Symbols")
                    }
                }
            }

            Section("Placement") {
                Picker("Edge", selection: tabBinding(\.anchor.edge)) {
                    ForEach(Edge.allCases) { Text($0.displayName).tag($0) }
                }
                Picker("Display", selection: tabBinding(\.anchor.displayUUID)) {
                    ForEach(displayChoices, id: \.uuid) { Text($0.name).tag($0.uuid) }
                }
                VStack(alignment: .leading) {
                    Text("Position along edge")
                    Slider(value: tabBinding(\.anchor.position), in: 0...1)
                }
                Toggle("Locked (can't be moved)", isOn: tabBinding(\.locked))
            }

            Section("Drawer") {
                if currentTab.kind != .notes {
                    Picker("Layout", selection: tabBinding(\.layout)) {
                        ForEach(DrawerLayout.allCases) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                // Ranges match the General pane's new-tab defaults (and Preferences'
                // clamps): a tab created at 12×16 must be editable back up here.
                Stepper("Columns: \(currentTab.gridColumns)", value: tabBinding(\.gridColumns), in: 1...12)
                Stepper("Rows: \(currentTab.gridRows)", value: tabBinding(\.gridRows), in: 1...16)
                Text("Layout and size for the drawer. Items can be placed anywhere in the grid, with gaps; for a notes tab the columns/rows size the text area. The list layout shows entries top-to-bottom and adds a date column for the Fresh, Recents, and folder tabs.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Behavior") {
                // "Open on hover" and "Close on click-outside" follow the global
                // default (General → Drawers) unless this tab overrides them. Picking
                // "Use global default" reverts the override — the clear way to undo a
                // local change. See ANALYSIS.md I3.
                Picker("Open on hover", selection: openOnHoverModeBinding) {
                    Text("Use global default (\(globalText(preferences.newTabOpenOnHover)))").tag(BehaviorMode.useGlobal)
                    Text("On").tag(BehaviorMode.on)
                    Text("Off").tag(BehaviorMode.off)
                }
                Picker("Close drawer when clicking elsewhere", selection: autoHideModeBinding) {
                    Text("Use global default (\(globalText(preferences.newTabAutoHide)))").tag(BehaviorMode.useGlobal)
                    Text("On").tag(BehaviorMode.on)
                    Text("Off").tag(BehaviorMode.off)
                }
                Toggle("Keep open after launching an item", isOn: tabBinding(\.behavior.keepOpenAfterLaunch))
                Picker("When idle", selection: tabBinding(\.behavior.concealment)) {
                    ForEach(TabConcealment.allCases) { Text($0.displayName).tag($0) }
                }
                Text("Hover and close-on-click follow the global default unless set here. Auto-hide slides the tab off its edge (leaving a sliver); auto-fade dims it — either reveals when you move the pointer to that screen edge.")
                    .font(.caption).foregroundStyle(.secondary)
                LabeledContent("Hotkey") { HotkeyRecorderView(hotkey: tabBinding(\.hotkey)) }
            }

            if currentTab.kind == .items {
                Section("Items") {
                    if currentTab.items.isEmpty {
                        Text("No items yet. Add some below, or drag files onto the tab.")
                            .foregroundStyle(.secondary).font(.callout)
                    } else {
                        ForEach(currentTab.items) { item in
                            HStack(spacing: 8) {
                                Image(nsImage: ItemView.resolveIcon(item))
                                    .resizable().frame(width: 18, height: 18)
                                Text(item.displayName).lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .contextMenu {
                                Button("Remove", role: .destructive) {
                                    store.removeItem(id: item.id, fromTab: tab.id)
                                }
                            }
                        }
                    }
                    HStack {
                        Button("Add Files…", action: addFiles)
                        Button("Add Link…") { linkText = ""; showingLinkSheet = true }
                        Button("Add Trash", action: addTrash)
                            .disabled(currentTab.items.contains { $0.kind == .trash })
                    }
                }
            }

            if currentTab.kind == .folder {
                Section("Folder") {
                    LabeledContent("Directory") {
                        Text(folderDisplayPath)
                            .foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    Button("Choose Folder…", action: chooseFolder)
                    Picker("Sort by", selection: tabBinding(\.folderSort)) {
                        ForEach(FolderSort.allCases) { Text($0.displayName).tag($0) }
                    }
                    Toggle("Show hidden files", isOn: tabBinding(\.folderShowsHidden))
                    Text("The drawer shows this folder's contents live (read-only); it refreshes automatically when the folder changes. Folders sort before files.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            if currentTab.kind == .notes {
                Section("Notes") {
                    Text("Open the tab's drawer to write notes.")
                        .foregroundStyle(.secondary).font(.callout)
                }
            }

            if currentTab.kind == .disks {
                Section("Disks") {
                    Text("The drawer lists the mounted ejectable volumes live — external, removable, network, and disk-image volumes. Click one to open it in Finder, or use its menu to eject.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            if currentTab.kind == .network {
                Section("Network") {
                    Text("The drawer lists your mounted network shares live — SMB / AFP / NFS / WebDAV mounts. Click one to open it in Finder, or use its menu to eject (disconnect).")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            if currentTab.kind == .cloud {
                Section("Cloud") {
                    Text("The drawer lists your cloud drives live — iCloud Drive and the providers under ~/Library/CloudStorage (Dropbox, Google Drive, OneDrive, Box, …). Click one to open it in Finder.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            if currentTab.kind == .recents {
                Section("Recents") {
                    Picker("Source", selection: tabBinding(\.recentsSource)) {
                        ForEach(RecentsSource.allCases) { Text($0.displayName).tag($0) }
                    }
                    Text(recentsSourceHelp)
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            if currentTab.kind == .fresh {
                Section("Fresh") {
                    Text("The drawer lists files that recently arrived on this Mac — downloaded, copied, or saved into your Downloads, Desktop, or Documents — newest first, via Spotlight. Read-only; click one to open it. No special permission needed.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .sheet(isPresented: $showingLinkSheet) { linkSheet }
    }

    // MARK: Bindings

    private func globalText(_ value: Bool) -> String { value ? "On" : "Off" }

    private var currentTab: Tab {
        store.tab(id: tab.id) ?? tab
    }

    private func tabBinding<Value>(_ keyPath: WritableKeyPath<Tab, Value>) -> Binding<Value> {
        Binding(
            get: { store.tab(id: tab.id)?[keyPath: keyPath] ?? tab[keyPath: keyPath] },
            set: { value in
                store.updateTab(id: tab.id) { $0[keyPath: keyPath] = value }
            }
        )
    }

    /// Maps the tab's `overridesOpenOnHover` + `openOnHover` to a 3-way choice:
    /// follow the global default, or pin On / Off for this tab.
    private var openOnHoverModeBinding: Binding<BehaviorMode> {
        Binding(
            get: {
                let behavior = currentTab.behavior
                return behavior.overridesOpenOnHover ? (behavior.openOnHover ? .on : .off) : .useGlobal
            },
            set: { mode in
                store.updateTab(id: tab.id) { tab in
                    switch mode {
                    case .useGlobal: tab.behavior.overridesOpenOnHover = false
                    case .on:  tab.behavior.overridesOpenOnHover = true; tab.behavior.openOnHover = true
                    case .off: tab.behavior.overridesOpenOnHover = true; tab.behavior.openOnHover = false
                    }
                }
            }
        )
    }

    private var autoHideModeBinding: Binding<BehaviorMode> {
        Binding(
            get: {
                let behavior = currentTab.behavior
                return behavior.overridesAutoHide ? (behavior.autoHide ? .on : .off) : .useGlobal
            },
            set: { mode in
                store.updateTab(id: tab.id) { tab in
                    switch mode {
                    case .useGlobal: tab.behavior.overridesAutoHide = false
                    case .on:  tab.behavior.overridesAutoHide = true; tab.behavior.autoHide = true
                    case .off: tab.behavior.overridesAutoHide = true; tab.behavior.autoHide = false
                    }
                }
            }
        )
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: { Color(hexString: currentTab.colorHex) },
            set: { color in store.updateTab(id: tab.id) { $0.colorHex = color.hexString } }
        )
    }

    private var glyphIsSymbolBinding: Binding<Bool> {
        Binding(
            get: { if case .symbol = currentTab.glyph { return true } else { return false } },
            set: { isSymbol in
                store.updateTab(id: tab.id) { tab in
                    if isSymbol {
                        if case .symbol = tab.glyph {} else { tab.glyph = .symbol("folder.fill") }
                    } else {
                        if case .monogram = tab.glyph {} else { tab.glyph = .monogram("A") }
                    }
                }
            }
        )
    }

    private var symbolBinding: Binding<String> {
        Binding(
            get: { if case .symbol(let s) = currentTab.glyph { return s } else { return "" } },
            set: { symbol in store.updateTab(id: tab.id) { $0.glyph = .symbol(symbol) } }
        )
    }

    /// Accepts letters or emoji, capped to the two characters the pill actually
    /// renders (`TabStripView.glyphView` draws `prefix(2)`) — a third character
    /// used to be stored but silently never shown.
    private var monogramBinding: Binding<String> {
        Binding(
            get: { if case .monogram(let m) = currentTab.glyph { return m } else { return "" } },
            set: { monogram in
                store.updateTab(id: tab.id) { $0.glyph = .monogram(String(monogram.prefix(2))) }
            }
        )
    }

    private var displayChoices: [(uuid: String, name: String)] {
        var choices: [(uuid: String, name: String)] = []
        for screen in NSScreen.screens {
            if let uuid = registry.uuid(for: screen) {
                choices.append((uuid: uuid, name: screen.localizedName))
            }
        }
        if !choices.contains(where: { $0.uuid == currentTab.anchor.displayUUID }) {
            choices.append((uuid: currentTab.anchor.displayUUID, name: "Disconnected display"))
        }
        return choices
    }

    // MARK: Recents tab

    private var recentsSourceHelp: String {
        switch currentTab.recentsSource {
        case .macDring:
            return "Lists what you've opened from MacDring, most recent first. Clear them from the drawer's header."
        case .system:
            return "Lists documents you've recently opened anywhere — Finder or any app — read live from Spotlight. No special permission needed."
        case .both:
            return "Merges what you've opened from MacDring with documents opened anywhere (Spotlight), most recent first."
        }
    }

    // MARK: Folder tab

    private var folderDisplayPath: String {
        FolderLister.resolveFolder(currentTab)?.path ?? "None"
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder to mirror"
        if panel.runModal() == .OK, let url = panel.url {
            let bookmark = BookmarkResolver.makeBookmark(for: url)
            store.updateTab(id: tab.id) {
                $0.folderURL = url
                $0.folderBookmark = bookmark
            }
        }
    }

    // MARK: Adding items

    private func addFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = "Choose apps, files, or folders to add"
        if panel.runModal() == .OK {
            for url in panel.urls {
                store.addItem(DrawerItem.fromFileURL(url), toTab: tab.id)
            }
        }
    }

    /// Adds a Trash item (once): opens the Trash, and accepts drops to delete.
    private func addTrash() {
        guard let current = store.tab(id: tab.id),
              !current.items.contains(where: { $0.kind == .trash }) else { return }
        store.addItem(DrawerItem.trash(), toTab: tab.id)
    }

    @ViewBuilder private var linkSheet: some View {
        let linkItem = DrawerItem.fromLink(linkText)
        let enteredText = linkText.trimmingCharacters(in: .whitespacesAndNewlines)

        VStack(alignment: .leading, spacing: 12) {
            Text("Add a Link").font(.headline)
            TextField("https://example.com", text: $linkText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 320)
            if let destination = linkItem?.url?.absoluteString {
                Text("Destination: \(destination)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 320, alignment: .leading)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text(enteredText.isEmpty ? "Enter a link." : "Enter a valid link.")
                    .font(.caption)
                    .foregroundStyle(enteredText.isEmpty ? Color.secondary : Color.red)
                    .frame(width: 320, alignment: .leading)
            }

            HStack {
                Spacer()
                Button("Cancel") { showingLinkSheet = false }
                Button("Add") {
                    guard let linkItem else { return }
                    store.addItem(linkItem, toTab: tab.id)
                    showingLinkSheet = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(linkItem == nil)
            }
        }
        .padding(20)
    }
}
