import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The panel that expands from a tab. Its content depends on the tab's kind:
/// - **items**: a freely-arranged grid/list (slots + gaps, drag-to-reorder,
///   drop-to-add, remove).
/// - **folder**: a read-only live listing of a directory (launch + reveal; items
///   are draggable *out* to Finder/other apps).
/// - **notes**: a text editor.
///
/// File drops are routed by what they land on: an **app** opens the files with
/// it, a **folder** receives them, and an empty slot / the background adds them
/// (items tab) or files them into the mirrored directory (folder tab).
struct DrawerView: View {
    @ObservedObject var model: DrawerModel
    @ObservedObject var preferences: Preferences

    @State private var dragging: DrawerItem?
    @State private var dragOffset: CGSize = .zero
    @State private var slotFrames: [Int: CGRect] = [:]
    @State private var dropTargetSlot: Int?      // internal reorder target
    // The external file-drop target lives on the model so the AppKit-driven drop
    // delegate can update it during a drag without sharing internal reorder slots.

    /// The occupied slot a drag has *dwelled* over long enough to form a group on drop
    /// (iOS-folder-style). `nil` until the dwell timer fires; drives the target's
    /// "will group" highlight.
    @State private var groupTargetSlot: Int?
    @State private var dwellWork: DispatchWorkItem?   // pending dwell timer
    @State private var dwellSlot: Int?                // the slot that timer is arming for
    /// The inline group-rename buffer, committed on Return / Back (so keystrokes don't
    /// each hit the store and rebuild the drawer mid-edit).
    @State private var groupNameDraft = ""

    /// Keyboard focus target. The filter field is focused on open (type-to-find); the
    /// notes editor is focused when the user clicks into a note to edit it.
    @FocusState private var focus: Field?
    private enum Field { case search, notes, groupName }

    private let contentSpace = "topdrawer.drawer.content"
    private var columns: Int { PersistedLayoutBounds.clampedGridColumns(model.columns) }
    /// The items the grid/list currently shows: an open group's children, else the top
    /// level. Everything below (`maxSlot`, `rows`, slot lookup) works over this.
    private var contextItems: [DrawerItem] { model.visibleItems }
    private var maxSlot: Int { contextItems.map(\.slot).max() ?? -1 }
    private var rows: Int {
        DrawerMetrics.gridRowCount(configuredRows: model.rows, maxSlot: maxSlot,
                                   itemCount: contextItems.count, columns: columns)
    }
    private var renderedSlotCount: Int {
        DrawerMetrics.renderedGridSlotCount(rows: rows, columns: columns)
    }
    private var cellHeight: CGFloat { CGFloat(preferences.iconSize) + 26 }
    /// Only `.items` tabs support internal reorder / remove (and groups only ever live
    /// in an `.items` tab).
    private var editable: Bool { model.kind == .items }

    var body: some View {
        // The two corners touching the screen edge stay sharp; the inward corners
        // are rounded — so the drawer reads as sliding flush out of the edge. An
        // inner corner the tab sits against is squared so the tab joins flush.
        let shape = edgeRoundedRect(edge: model.edge, radius: CGFloat(preferences.cornerRadius),
                                    squareStart: model.squareInnerStart, squareEnd: model.squareInnerEnd)

        VStack(alignment: .leading, spacing: 10) {
            header
            if let undo = model.undoToast { undoBanner(undo) }
            if model.isSearchable { searchBar }
            bodyContent
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            ZStack {
                VisualEffectBlur(material: .popover, blendingMode: .behindWindow)
                // Paint an opaque backing over the blur to taste: nothing for
                // Translucent, half for Frosted, fully Solid.
                Color(nsColor: .windowBackgroundColor).opacity(preferences.drawerTranslucency.backingOpacity)
                Color(hexString: model.colorHex).opacity(0.10)
            }
        )
        .clipShape(shape)
        // Primary (not hardcoded white): the outline has to read over the light
        // appearance's Frosted/Solid backing too, where white-on-white vanishes.
        .overlay(
            shape.stroke(Color.primary.opacity(model.isDropTargeted ? 0.85 : 0.14),
                         lineWidth: model.isDropTargeted ? 2 : 1)
        )
        .onHover { inside in
            if inside { model.onMouseEntered?() } else { model.onMouseExited?() }
        }
        // Report frames in this outermost coordinate space, which fills the hosting
        // view. Internal reorder keeps integer slots; AppKit file drops use a separate
        // identity-aware target map. (SwiftUI `.onDrop` is unreliable in this panel.)
        .coordinateSpace(name: contentSpace)
        .overlay(alignment: .topLeading) { draggedOverlay }
        .onPreferenceChange(SlotFramesKey.self) { slotFrames = $0 }
        .onPreferenceChange(ExternalDropTargetFramesKey.self) { model.externalDropTargetFrames = $0 }
    }

    @ViewBuilder
    private var bodyContent: some View {
        switch model.kind {
        case .notes:
            // Bleed the editor/view to the drawer's left/right/bottom edges (negating
            // the outer content padding) — the field's own text inset is enough.
            Group {
                if model.notesPreview { notesPreview } else { notesEditor }
            }
            .padding(.horizontal, -14)
            .padding(.bottom, -14)
        case .items, .folder, .disks, .network, .cloud, .recents, .fresh:
            if model.isSearching { searchResultsList }
            else if model.items.isEmpty { emptyState }
            else { content }
        }
    }

    // MARK: Type-to-find

    /// The filter field — an editable, focusable text field bound to the live query.
    /// It's auto-focused when the drawer opens, so type-to-find works immediately; the
    /// ✕ clears it. Result navigation (Up/Down/Return/Esc) is driven by
    /// `TabController`'s key monitor, which swallows those keys before the field sees them.
    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.callout).foregroundStyle(.secondary)
            TextField("Type to filter…", text: $model.searchQuery)
                .textFieldStyle(.plain)
                .focused($focus, equals: .search)
            if !model.searchQuery.isEmpty {
                Button { model.clearSearch() } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .help("Clear filter")
            }
        }
        .font(.callout)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.08)))
        // Defer a tick so the field is in the responder chain before we focus it (the
        // panel has just become key as it slides open).
        .onAppear { DispatchQueue.main.async { focus = .search } }
    }

    /// The filtered results as a compact, keyboard-navigable list (Up/Down select,
    /// Return launches — handled by the key monitor). The selected row is tinted
    /// and kept scrolled into view as ↑/↓ move it past the fold.
    private var searchResultsList: some View {
        let results = model.searchResults
        return ScrollViewReader { proxy in
            ScrollView {
                if results.isEmpty {
                    Text("No matches for “\(model.searchQuery)”")
                        .foregroundStyle(.secondary).font(.callout)
                        .frame(maxWidth: .infinity).padding(.vertical, 20)
                } else {
                    VStack(spacing: 2) {
                        ForEach(results) { item in
                            let target = model.externalDropTarget(for: item, atLocalSlot: item.slot)
                            itemView(item, layout: .list)
                                .padding(.vertical, 3)
                                .padding(.horizontal, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.primary.opacity(model.fileDropTarget == target ? 0.12 : 0)))
                                .background(RoundedRectangle(cornerRadius: 8)
                                    .fill(item.id == model.selectedItemID ? Color.accentColor.opacity(0.30) : .clear))
                                .overlay {
                                    if model.fileDropTarget == target,
                                       item.kind == .folder || item.kind == .application {
                                        RoundedRectangle(cornerRadius: 8)
                                            .strokeBorder(Color(hexString: model.colorHex), lineWidth: 2)
                                    }
                                }
                                .background(externalDropTargetFrameReporter(target))
                                .id(item.id)
                        }
                    }
                }
            }
            .onChange(of: model.selectedItemID) { selected in
                guard let selected else { return }
                withAnimation(.easeInOut(duration: 0.12)) {
                    proxy.scrollTo(selected, anchor: .center)
                }
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(hexString: model.colorHex))
                .frame(width: 10, height: 10)
            Text(model.title.isEmpty ? "Drawer" : model.title)
                .font(.headline)
            Spacer(minLength: 12)
            if model.kind != .notes {
                // A trailing "+" when the listing was capped (e.g. a folder with
                // more than `FolderLister.limit` entries): "300+".
                Text("\(model.items.count)\(model.itemsTruncated ? "+" : "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help(model.itemsTruncated ? "Showing the first \(model.items.count) items" : "")
            }
            if model.kind == .folder {
                headerButton("folder", help: "Open folder in Finder") { model.onOpenFolder?() }
                    .disabled(model.folderURL == nil)
            }
            if model.kind == .disks {
                headerButton("eject", help: "Eject all volumes") { model.onEjectAll?() }
                    .disabled(model.items.isEmpty || !model.ejectingItemIDs.isEmpty)
            }
            if model.kind == .recents, model.canClearRecents {
                headerButton("trash", help: "Clear recent items") { model.onClearRecents?() }
            }
            headerButton(model.locked ? "lock.fill" : "lock.open",
                         help: model.locked ? "Unlock this tab's position" : "Lock this tab's position") {
                model.onToggleLocked?()
            }
            headerButton("gearshape", help: "Configure Tab…") { model.onOpenSettings?() }
        }
    }

    private func headerButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol) }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(help)
    }

    /// A transient "Moved N items — Undo" banner, shown after a drop moved files into
    /// a folder/app. The controller dismisses it after a few seconds; Undo reverses
    /// the move (and dismisses immediately).
    private func undoBanner(_ undo: DrawerUndo) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.uturn.backward.circle")
                .foregroundStyle(.secondary)
            Text(undo.message)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Button("Undo") { undo.action(); withAnimation { model.undoToast = nil } }
                .controlSize(.small)
            Button { withAnimation { model.undoToast = nil } } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .help("Dismiss")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.08)))
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: Notes

    private var notesEditor: some View {
        // Full-bleed and transparent over the drawer's blur — the TextEditor's own text
        // inset is the only spacing. A ✓ button (bottom-right) returns to view mode.
        TextEditor(text: notesBinding)
            .font(.body)
            .focused($focus, equals: .notes)
            .scrollContentBackground(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottomTrailing) { doneEditingButton }
            .onAppear { DispatchQueue.main.async { focus = .notes } }
    }

    /// Finishes editing and returns the note to its rendered view (shown only while
    /// editing). A filled, labelled button so it reads as an action, not a status badge.
    private var doneEditingButton: some View {
        Button { model.notesPreview = true } label: {
            Label("Done", systemImage: "checkmark")
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .help("Finish editing and show the rendered note")
        .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
        .padding(10)
    }

    /// Rendered-Markdown view of the note — the default when a notes drawer opens.
    /// Clicking anywhere switches to the editor.
    private var notesPreview: some View {
        ScrollView {
            if model.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Nothing here yet — click to edit.")
                    .foregroundStyle(.secondary).font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            } else {
                MarkdownText(text: model.notes, onToggle: toggleNoteCheckbox)
                    .padding(10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .onTapGesture { model.notesPreview = false }
    }

    private var notesBinding: Binding<String> {
        Binding(get: { model.notes }, set: { model.notes = $0; model.onNotesChanged?($0) })
    }

    /// Flips the `- [ ]` / `- [x]` checkbox on note line `index` (tapped in the
    /// preview) and persists it, without leaving the rendered view.
    private func toggleNoteCheckbox(_ index: Int) {
        let updated = MarkdownText.togglingCheckbox(in: model.notes, lineIndex: index)
        guard updated != model.notes else { return }
        model.notes = updated
        model.onNotesChanged?(updated)
    }

    // MARK: Items / folder grid

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.openGroup != nil { groupHeader }
            ScrollView { itemsLayout }
                // Recreate the grid when the open group changes so the crossfade fires;
                // `withAnimation` at the open/close call sites drives the transition.
                .id(model.openGroupID)
                .transition(.opacity)
        }
    }

    /// The open-group header: a Back chevron to the top level and an inline-editable
    /// name field (iOS-folder style). The name commits on Return or when leaving.
    private var groupHeader: some View {
        HStack(spacing: 8) {
            Button {
                commitGroupName()
                withAnimation(.easeInOut(duration: 0.2)) { model.openGroupID = nil }
            } label: {
                Image(systemName: "chevron.backward")
                Text("Back")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            TextField("Group", text: $groupNameDraft)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .font(.headline)
                .focused($focus, equals: .groupName)
                .onSubmit { commitGroupName() }
                .frame(maxWidth: 180)
        }
        .onAppear { groupNameDraft = model.openGroup?.displayName ?? "" }
        .onChange(of: model.openGroupID) { _ in groupNameDraft = model.openGroup?.displayName ?? "" }
    }

    /// Persists the edited group name (defaulting a blank back to "Group"), only when
    /// it actually changed — one store write, not one per keystroke.
    private func commitGroupName() {
        guard let group = model.openGroup else { return }
        let trimmed = groupNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? DrawerGrouping.defaultName : trimmed
        if name != group.displayName { model.onRenameGroup?(group.id, name) }
    }

    @ViewBuilder
    private var itemsLayout: some View {
        if model.layout == .grid {
            let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 10), count: columns)
            LazyVGrid(columns: gridColumns, spacing: 12) {
                ForEach(Array(0..<renderedSlotCount), id: \.self) { slot in
                    gridSlot(slot)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                let ordered = contextItems.sorted { $0.slot < $1.slot }
                if model.openGroup == nil, model.kind == .recents || model.kind == .fresh {
                    // The date-ranked lists (Recents by last-used, Fresh by Date Added)
                    // read better grouped into recency sections (Today / Yesterday /
                    // This Week / Older).
                    ForEach(TimeBucket.grouped(ordered, now: Date()) { $0.date }) { section in
                        Text(section.bucket.title)
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                        ForEach(section.items) { listRow($0) }
                    }
                } else {
                    ForEach(ordered) { listRow($0) }
                }
            }
        }
    }

    /// One row of the list layout: the item plus its file-drop highlight ring.
    private func listRow(_ item: DrawerItem) -> some View {
        let target = model.externalDropTarget(for: item, atLocalSlot: item.slot)
        let fileDropHere = model.fileDropTarget == target
        // Match the grid: a file dragged onto a folder/app is a
        // "file into / open with" target — give it a distinct ring.
        let intoTarget = fileDropHere && (item.kind == .folder || item.kind == .application)
        return inCellItem(item)
            .padding(.vertical, 3)
            .padding(.horizontal, 4)
            .background(RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(fileDropHere ? 0.12 : 0)))
            .overlay {
                if intoTarget {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color(hexString: model.colorHex), lineWidth: 2)
                }
            }
            .background(slotFrameReporter(item.slot))
            .background(externalDropTargetFrameReporter(target))
    }

    private func gridSlot(_ slot: Int) -> some View {
        let item = model.visibleItem(atSlot: slot)
        let externalTarget = model.externalDropTarget(for: item, atLocalSlot: slot)
        let reorderHere = dropTargetSlot == slot && dragging?.slot != slot
        let fileDropHere = model.fileDropTarget == externalTarget
        // A file dragged onto a folder/app is a "file into / open with" target, not a
        // plain slot drop — give it a distinct ring so the difference is obvious.
        let intoTarget = fileDropHere && (item?.kind == .folder || item?.kind == .application || item?.kind == .trash)
        // A drag has dwelled over this (occupied) slot: releasing here forms a group.
        let groupHere = groupTargetSlot == slot && dragging != nil && dragging?.slot != slot
        return ZStack {
            // Primary adapts to light/dark; hardcoded white washed out over the
            // light appearance's Frosted/Solid backing.
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity((reorderHere || fileDropHere || groupHere) ? 0.12 : 0))
            if let item {
                inCellItem(item)
                    .scaleEffect(groupHere ? 1.12 : 1)
                    .animation(.easeInOut(duration: 0.15), value: groupHere)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: cellHeight)
        .overlay {
            if intoTarget {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color(hexString: model.colorHex), lineWidth: 2)
            } else if groupHere {
                // The "will group" affordance: a soft ring around the item the drag is
                // hovering, echoing iOS's folder-forming halo. Primary so it reads over
                // the light appearance's backing too.
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.primary.opacity(0.6), lineWidth: 2)
            }
        }
        .background(slotFrameReporter(slot))
        .background(externalDropTargetFrameReporter(externalTarget))
    }

    /// An item in its home cell. `.items` tabs reorder by dragging; `.folder`
    /// items are draggable *out* (to Finder / other apps) as their file URL.
    @ViewBuilder
    private func inCellItem(_ item: DrawerItem) -> some View {
        let cell = itemView(item).opacity(dragging?.id == item.id ? 0.25 : 1)
        if editable {
            cell.gesture(reorderGesture(item))
        } else {
            cell.onDrag { dragProvider(item) }
        }
    }

    @ViewBuilder
    private var draggedOverlay: some View {
        if editable, let dragging, let home = slotFrames[dragging.slot] {
            itemView(dragging)
                .frame(width: home.width, height: home.height)
                .scaleEffect(1.06)
                .opacity(0.95)
                .offset(x: home.minX + dragOffset.width, y: home.minY + dragOffset.height)
                .allowsHitTesting(false)
        }
    }

    private func slotFrameReporter(_ slot: Int) -> some View {
        GeometryReader { proxy in
            Color.clear.preference(key: SlotFramesKey.self, value: [slot: proxy.frame(in: .named(contentSpace))])
        }
    }

    private func externalDropTargetFrameReporter(_ target: ExternalDropTarget) -> some View {
        GeometryReader { proxy in
            Color.clear.preference(key: ExternalDropTargetFramesKey.self,
                                   value: [target: proxy.frame(in: .named(contentSpace))])
        }
    }

    private func reorderGesture(_ item: DrawerItem) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .named(contentSpace))
            .onChanged { value in
                if dragging?.id != item.id { dragging = item }
                dragOffset = value.translation
                let target = targetSlot(at: value.location)
                dropTargetSlot = target
                updateDwell(target: target, dragged: item)
            }
            .onEnded { value in
                finishDrag(dragged: item, dropSlot: targetSlot(at: value.location))
                dragging = nil
                dragOffset = .zero
                dropTargetSlot = nil
                cancelDwell()
            }
    }

    /// Resolves a finished drag. Top level: a dwell over another item forms a group,
    /// otherwise it's a reorder. Inside an open group: a reorder within the sub-grid.
    private func finishDrag(dragged: DrawerItem, dropSlot: Int?) {
        let topLevel = model.openGroupID == nil
        if topLevel, let g = groupTargetSlot, g == dropSlot,
           let target = model.visibleItem(atSlot: g), target.id != dragged.id,
           DrawerGrouping.isGroupable(dragged),
           target.kind == .group || DrawerGrouping.isGroupable(target) {
            model.onGroupItems?(dragged.id, target.id)
            return
        }
        guard let slot = dropSlot else { return }
        withAnimation(.easeInOut(duration: 0.16)) {
            if topLevel {
                model.onPlaceItem?(dragged.id, slot)
            } else {
                model.onPlaceInGroup?(dragged.id, slot)
            }
        }
    }

    /// Arms (or re-arms) the dwell timer that turns hovering over another item into a
    /// group-on-drop target — only at the top level, only over a *different*, occupied
    /// slot, and never while dragging a group (groups don't nest). Moving to a new slot
    /// resets the countdown, so brushing past an item to reorder doesn't group.
    private func updateDwell(target: Int?, dragged: DrawerItem) {
        guard model.openGroupID == nil, DrawerGrouping.isGroupable(dragged),
              let target, let occupant = model.visibleItem(atSlot: target),
              occupant.id != dragged.id,
              occupant.kind == .group || DrawerGrouping.isGroupable(occupant) else {
            cancelDwell()
            return
        }
        if dwellSlot == target { return }   // already counting down over this slot
        dwellWork?.cancel()
        groupTargetSlot = nil
        dwellSlot = target
        let work = DispatchWorkItem { groupTargetSlot = target }
        dwellWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    private func cancelDwell() {
        dwellWork?.cancel()
        dwellWork = nil
        dwellSlot = nil
        groupTargetSlot = nil
    }

    private func targetSlot(at point: CGPoint) -> Int? {
        if let hit = slotFrames.first(where: { $0.value.contains(point) })?.key {
            return hit
        }
        return slotFrames.min { squaredDistance($0.value, point) < squaredDistance($1.value, point) }?.key
    }

    private func squaredDistance(_ rect: CGRect, _ point: CGPoint) -> CGFloat {
        let dx = point.x - rect.midX, dy = point.y - rect.midY
        return dx * dx + dy * dy
    }

    private func dragProvider(_ item: DrawerItem) -> NSItemProvider {
        if let url = BookmarkResolver.url(for: item) {
            return NSItemProvider(object: url as NSURL)
        }
        return NSItemProvider()
    }

    private func itemView(_ item: DrawerItem, layout: DrawerLayout? = nil) -> some View {
        ItemView(
            item: item,
            iconSize: CGFloat(preferences.iconSize),
            layout: layout ?? model.layout,
            listColumns: columns,
            launchOnSingleClick: preferences.launchOnSingleClick,
            onLaunch: {
                if item.isGroup {
                    withAnimation(.easeInOut(duration: 0.2)) { model.openGroupID = item.id }
                } else {
                    model.onLaunch?(item)
                }
            },
            onReveal: { model.onRevealItem?(item) },
            onRemove: editable ? { model.onRemoveItem?(item) } : nil,
            onRename: editable ? { model.onRenameItem?(item) } : nil,
            onChangeIcon: editable ? { model.onChangeItemIcon?(item) } : nil,
            onResetIcon: editable ? { model.onResetItemIcon?(item) } : nil,
            onEmptyTrash: item.kind == .trash ? { model.onEmptyTrash?() } : nil,
            iconNonce: model.iconNonce,
            onEject: item.kind == .disk ? { model.onEjectItem?(item) } : nil,
            onCustomizeIcon: { model.onCustomizeItemIcon?(item) },   // any item, any tab kind
            onUngroup: (editable && model.openGroupID != nil && !item.isGroup)
                ? {
                    if let gid = model.openGroupID {
                        withAnimation(.easeInOut(duration: 0.2)) { model.onRemoveFromGroup?(item.id, gid) }
                    }
                }
                : nil,
            runningBundleIDs: model.runningBundleIDs,
            isEjecting: model.ejectingItemIDs.contains(item.id),
            sparkle: model.sparklingItemIDs.contains(item.id)
        )
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: emptyIcon)
                .font(.system(size: 26))
                .foregroundStyle(.secondary)
            Text(emptyMessage)
                .foregroundStyle(.secondary)
                .font(.callout)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
    }

    private var emptyIcon: String {
        switch model.kind {
        case .folder: return "folder"
        case .disks: return "externaldrive"
        case .network: return "externaldrive.connected.to.line.below"
        case .cloud: return "icloud"
        case .recents: return "clock.arrow.circlepath"
        case .fresh: return "sparkles"
        default: return "tray.and.arrow.down"
        }
    }

    private var emptyMessage: String {
        switch model.kind {
        case .folder:
            return model.folderURL == nil
                ? "No folder chosen.\nPick one with the gear above."
                : "This folder is empty."
        case .disks:
            return "No ejectable disks mounted."
        case .network:
            return "No network shares mounted."
        case .cloud:
            return "No cloud drives found."
        case .recents:
            // Source-agnostic: a System/Both tab shows this too (including the
            // moment Spotlight is still gathering), so "from Top Drawer" would lie.
            return "Nothing recently opened yet."
        case .fresh:
            return "No files have arrived recently."
        default:
            return "Drag apps & files here"
        }
    }
}
