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
                    TabEditor(draft: tab, preferences: preferences, store: store, registry: registry)
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
        guard let data = store.exportData() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "MacDring Layout.json"
        panel.message = "Export your tabs and items as a JSON layout file"
        if panel.runModal() == .OK, let url = panel.url {
            try? data.write(to: url)
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
        let order = (rightTabs.map(\.anchor.order).max() ?? -1) + 1
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
        for index in tabs.indices { tabs[index].anchor.order = index }
        store.replaceTabs(tabs)
    }
}

/// A per-tab override choice for a behavior that has a global default: follow the
/// global setting, or pin it On / Off for this tab. "Use global" is also the revert.
private enum BehaviorMode { case useGlobal, on, off }

/// Edits one tab. Holds a local `draft` (re-seeded when the selection changes via
/// `.id`) and commits the whole tab to the store on any change.
private struct TabEditor: View {
    @State var draft: Tab
    @ObservedObject var preferences: Preferences
    let store: TabStore
    let registry: DisplayRegistry

    @State private var showingLinkSheet = false
    @State private var linkText = ""

    var body: some View {
        Form {
            Section("Tab") {
                // A tab's type is fixed at creation (it determines what the drawer
                // holds), so it's shown read-only here — change it by making a new tab.
                LabeledContent("Type", value: draft.kind.displayName)
                TextField("Name", text: $draft.title)
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
                Picker("Edge", selection: $draft.anchor.edge) {
                    ForEach(Edge.allCases) { Text($0.displayName).tag($0) }
                }
                Picker("Display", selection: $draft.anchor.displayUUID) {
                    ForEach(displayChoices, id: \.uuid) { Text($0.name).tag($0.uuid) }
                }
                VStack(alignment: .leading) {
                    Text("Position along edge")
                    Slider(value: $draft.anchor.position, in: 0...1)
                }
                Toggle("Locked (can't be moved)", isOn: $draft.locked)
            }

            Section("Drawer") {
                if draft.kind != .notes {
                    Picker("Layout", selection: $draft.layout) {
                        ForEach(DrawerLayout.allCases) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                // Ranges match the General pane's new-tab defaults (and Preferences'
                // clamps): a tab created at 12×16 must be editable back up here.
                Stepper("Columns: \(draft.gridColumns)", value: $draft.gridColumns, in: 1...12)
                Stepper("Rows: \(draft.gridRows)", value: $draft.gridRows, in: 1...16)
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
                Toggle("Keep open after launching an item", isOn: $draft.behavior.keepOpenAfterLaunch)
                Picker("When idle", selection: $draft.behavior.concealment) {
                    ForEach(TabConcealment.allCases) { Text($0.displayName).tag($0) }
                }
                Text("Hover and close-on-click follow the global default unless set here. Auto-hide slides the tab off its edge (leaving a sliver); auto-fade dims it — either reveals when you move the pointer to that screen edge.")
                    .font(.caption).foregroundStyle(.secondary)
                LabeledContent("Hotkey") { HotkeyRecorderView(hotkey: $draft.hotkey) }
            }

            if draft.kind == .items {
                Section("Items") {
                    if draft.items.isEmpty {
                        Text("No items yet. Add some below, or drag files onto the tab.")
                            .foregroundStyle(.secondary).font(.callout)
                    } else {
                        ForEach(draft.items) { item in
                            HStack(spacing: 8) {
                                Image(nsImage: ItemView.resolveIcon(item))
                                    .resizable().frame(width: 18, height: 18)
                                Text(item.displayName).lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .contextMenu {
                                Button("Remove", role: .destructive) {
                                    draft.items.removeAll { $0.id == item.id }
                                }
                            }
                        }
                    }
                    HStack {
                        Button("Add Files…", action: addFiles)
                        Button("Add Link…") { linkText = ""; showingLinkSheet = true }
                        Button("Add Trash", action: addTrash)
                            .disabled(draft.items.contains { $0.kind == .trash })
                    }
                }
            }

            if draft.kind == .folder {
                Section("Folder") {
                    LabeledContent("Directory") {
                        Text(folderDisplayPath)
                            .foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    Button("Choose Folder…", action: chooseFolder)
                    Picker("Sort by", selection: $draft.folderSort) {
                        ForEach(FolderSort.allCases) { Text($0.displayName).tag($0) }
                    }
                    Toggle("Show hidden files", isOn: $draft.folderShowsHidden)
                    Text("The drawer shows this folder's contents live (read-only); it refreshes automatically when the folder changes. Folders sort before files.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            if draft.kind == .notes {
                Section("Notes") {
                    Text("Open the tab's drawer to write notes.")
                        .foregroundStyle(.secondary).font(.callout)
                }
            }

            if draft.kind == .disks {
                Section("Disks") {
                    Text("The drawer lists the mounted ejectable volumes live — external, removable, network, and disk-image volumes. Click one to open it in Finder, or use its menu to eject.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            if draft.kind == .network {
                Section("Network") {
                    Text("The drawer lists your mounted network shares live — SMB / AFP / NFS / WebDAV mounts. Click one to open it in Finder, or use its menu to eject (disconnect).")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            if draft.kind == .cloud {
                Section("Cloud") {
                    Text("The drawer lists your cloud drives live — iCloud Drive and the providers under ~/Library/CloudStorage (Dropbox, Google Drive, OneDrive, Box, …). Click one to open it in Finder.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            if draft.kind == .recents {
                Section("Recents") {
                    Picker("Source", selection: $draft.recentsSource) {
                        ForEach(RecentsSource.allCases) { Text($0.displayName).tag($0) }
                    }
                    Text(recentsSourceHelp)
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            if draft.kind == .fresh {
                Section("Fresh") {
                    Text("The drawer lists files that recently arrived on this Mac — downloaded, copied, or saved into your Downloads, Desktop, or Documents — newest first, via Spotlight. Read-only; click one to open it. No special permission needed.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .onChange(of: draft) { _ in store.updateTab(draft) }
        .sheet(isPresented: $showingLinkSheet) { linkSheet }
    }

    // MARK: Bindings

    private func globalText(_ value: Bool) -> String { value ? "On" : "Off" }

    /// Maps the tab's `overridesOpenOnHover` + `openOnHover` to a 3-way choice:
    /// follow the global default, or pin On / Off for this tab.
    private var openOnHoverModeBinding: Binding<BehaviorMode> {
        Binding(
            get: { draft.behavior.overridesOpenOnHover ? (draft.behavior.openOnHover ? .on : .off) : .useGlobal },
            set: { mode in
                switch mode {
                case .useGlobal: draft.behavior.overridesOpenOnHover = false
                case .on:  draft.behavior.overridesOpenOnHover = true; draft.behavior.openOnHover = true
                case .off: draft.behavior.overridesOpenOnHover = true; draft.behavior.openOnHover = false
                }
            }
        )
    }

    private var autoHideModeBinding: Binding<BehaviorMode> {
        Binding(
            get: { draft.behavior.overridesAutoHide ? (draft.behavior.autoHide ? .on : .off) : .useGlobal },
            set: { mode in
                switch mode {
                case .useGlobal: draft.behavior.overridesAutoHide = false
                case .on:  draft.behavior.overridesAutoHide = true; draft.behavior.autoHide = true
                case .off: draft.behavior.overridesAutoHide = true; draft.behavior.autoHide = false
                }
            }
        )
    }

    private var colorBinding: Binding<Color> {
        Binding(get: { Color(hexString: draft.colorHex) },
                set: { draft.colorHex = $0.hexString })
    }

    private var glyphIsSymbolBinding: Binding<Bool> {
        Binding(
            get: { if case .symbol = draft.glyph { return true } else { return false } },
            set: { isSymbol in
                if isSymbol {
                    if case .symbol = draft.glyph {} else { draft.glyph = .symbol("folder.fill") }
                } else {
                    if case .monogram = draft.glyph {} else { draft.glyph = .monogram("A") }
                }
            }
        )
    }

    private var symbolBinding: Binding<String> {
        Binding(
            get: { if case .symbol(let s) = draft.glyph { return s } else { return "" } },
            set: { draft.glyph = .symbol($0) }
        )
    }

    /// Accepts letters or emoji, capped to the two characters the pill actually
    /// renders (`TabStripView.glyphView` draws `prefix(2)`) — a third character
    /// used to be stored but silently never shown.
    private var monogramBinding: Binding<String> {
        Binding(
            get: { if case .monogram(let m) = draft.glyph { return m } else { return "" } },
            set: { draft.glyph = .monogram(String($0.prefix(2))) }
        )
    }

    private var displayChoices: [(uuid: String, name: String)] {
        var choices: [(uuid: String, name: String)] = []
        for screen in NSScreen.screens {
            if let uuid = registry.uuid(for: screen) {
                choices.append((uuid: uuid, name: screen.localizedName))
            }
        }
        if !choices.contains(where: { $0.uuid == draft.anchor.displayUUID }) {
            choices.append((uuid: draft.anchor.displayUUID, name: "Disconnected display"))
        }
        return choices
    }

    // MARK: Recents tab

    private var recentsSourceHelp: String {
        switch draft.recentsSource {
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
        FolderLister.resolveFolder(draft)?.path ?? "None"
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder to mirror"
        if panel.runModal() == .OK, let url = panel.url {
            draft.folderURL = url
            draft.folderBookmark = BookmarkResolver.makeBookmark(for: url)
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
                draft.items.appendDeduplicatingTarget(DrawerItem.fromFileURL(url))
            }
        }
    }

    /// Adds a Trash item (once): opens the Trash, and accepts drops to delete.
    private func addTrash() {
        guard !draft.items.contains(where: { $0.kind == .trash }) else { return }
        draft.items.append(DrawerItem.trash())
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
                    draft.items.appendDeduplicatingTarget(linkItem)
                    showingLinkSheet = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(linkItem == nil)
            }
        }
        .padding(20)
    }
}
