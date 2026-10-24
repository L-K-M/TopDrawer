import XCTest
@testable import MacDring

/// Persistence-layer enforcement of per-item editing locks (`DrawerItem.isLocked`,
/// `Tab.lockNewItems`, `TabStore.ItemLockState`). Pure store tests against an
/// isolated temp launcher file — no real user data.
final class ItemLockTests: XCTestCase {

    private var storeURL: URL!

    override func setUp() {
        super.setUp()
        storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("macdring-locks-\(UUID().uuidString)")
            .appendingPathComponent("launcher.json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: storeURL.deletingLastPathComponent())
        storeURL = nil
        super.tearDown()
    }

    private func makeTab(_ title: String = "T", lockNewItems: Bool = false) -> Tab {
        Tab(title: title,
            colorHex: "#0A84FF",
            anchor: ScreenAnchor(displayUUID: "D1", edge: .right, position: 0.5),
            lockNewItems: lockNewItems)
    }

    private func fileItem(_ name: String) -> DrawerItem {
        DrawerItem(kind: .file, displayName: name)
    }

    private func link(_ name: String, _ url: String) -> DrawerItem {
        DrawerItem(kind: .url, displayName: name, url: URL(string: url))
    }

    private func item(_ id: UUID, in store: TabStore, tab tabID: UUID) -> DrawerItem? {
        store.tab(id: tabID)?.items.first { $0.id == id }
            ?? store.tab(id: tabID)?.items.lazy
                .first { $0.kind == .group }?.children.first { $0.id == id }
    }

    // MARK: Defaults & persistence

    func testItemsAndTabsDefaultToUnlocked() {
        let store = TabStore(storeURL: storeURL)
        let tab = makeTab()
        store.addTab(tab)
        let a = fileItem("A")
        store.addItem(a, toTab: tab.id)

        XCTAssertFalse(item(a.id, in: store, tab: tab.id)?.isLocked ?? true)
        XCTAssertFalse(item(a.id, in: store, tab: tab.id)?.containsLockedItems ?? true)
        XCTAssertFalse(store.tab(id: tab.id)?.lockNewItems ?? true)
        XCTAssertFalse(store.isItemEditingLocked(a.id, inTab: tab.id))
        XCTAssertFalse(store.isItemEditingLocked(UUID(), inTab: tab.id))   // unknown id
        XCTAssertFalse(store.isItemEditingLocked(a.id, inTab: UUID()))     // unknown tab
    }

    func testLockStateRoundTripsThroughSaveAndReload() throws {
        let store = TabStore(storeURL: storeURL)
        var tab = makeTab()
        tab.lockNewItems = true
        let lockedChild = DrawerItem(kind: .file, displayName: "Child", isLocked: true)
        tab.items = [
            DrawerItem(kind: .file, displayName: "Top", isLocked: true),
            DrawerItem(kind: .group, displayName: "G",
                       children: [lockedChild, fileItem("Sibling")]),
        ]
        store.addTab(tab)
        store.saveNow()

        let reloaded = TabStore(storeURL: storeURL)
        let saved = try XCTUnwrap(reloaded.tab(id: tab.id))
        XCTAssertTrue(saved.lockNewItems)
        XCTAssertEqual(saved.items.map(\.isLocked), [true, false])
        let group = try XCTUnwrap(saved.items.first { $0.kind == .group })
        XCTAssertEqual(group.children.map(\.isLocked), [true, false])

        // …and a reloaded store still enforces the persisted locks.
        reloaded.removeItem(id: saved.items[0].id, fromTab: tab.id)
        reloaded.removeItem(id: lockedChild.id, fromTab: tab.id)
        XCTAssertEqual(reloaded.tab(id: tab.id)?.items.count, 2)
        XCTAssertEqual(reloaded.tab(id: tab.id)?.items.first { $0.kind == .group }?.children.count, 2)
    }

    func testLockFieldsDecodeLeniently() throws {
        let json = """
        { "version": 1,
          "tabs": [ {
            "title": "T",
            "anchor": { "displayUUID": "D1", "edge": "right", "position": 0.5 },
            "lockNewItems": true,
            "items": [
              { "kind": "file", "displayName": "Plain", "slot": 0 },
              { "kind": "file", "displayName": "Bolted", "slot": 1, "isLocked": true },
              { "kind": "group", "displayName": "G", "slot": 2,
                "children": [
                  { "kind": "file", "displayName": "C1", "slot": 0, "isLocked": true },
                  { "kind": "file", "displayName": "C2", "slot": 1 }
                ] }
            ]
          } ] }
        """
        try FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data(json.utf8).write(to: storeURL)

        let store = TabStore(storeURL: storeURL)
        let tab = try XCTUnwrap(store.tabs.first)
        XCTAssertTrue(tab.lockNewItems)
        XCTAssertEqual(tab.items.map(\.isLocked), [false, true, false])
        XCTAssertEqual(tab.items[2].children.map(\.isLocked), [true, false])
        // A locked child protects its container from editing checks.
        XCTAssertTrue(store.isItemEditingLocked(tab.items[2].id, inTab: tab.id))
    }

    // MARK: Explicit lock APIs

    func testSetItemLockTogglesAnItem() {
        let store = TabStore(storeURL: storeURL)
        let tab = makeTab(); store.addTab(tab)
        let a = fileItem("A")
        store.addItem(a, toTab: tab.id)

        store.setItemLock(.locked, forItem: a.id, inTab: tab.id)
        XCTAssertTrue(store.isItemEditingLocked(a.id, inTab: tab.id))
        XCTAssertTrue(item(a.id, in: store, tab: tab.id)?.isLocked ?? false)

        store.setItemLock(.unlocked, forItem: a.id, inTab: tab.id)
        XCTAssertFalse(store.isItemEditingLocked(a.id, inTab: tab.id))
    }

    func testSetAllItemLocksCoversGroupsAndChildren() {
        let store = TabStore(storeURL: storeURL)
        let tab = makeTab(); store.addTab(tab)
        let a = fileItem("A"), b = fileItem("B"), c = fileItem("C")
        [a, b, c].forEach { store.addItem($0, toTab: tab.id) }
        store.groupItems(draggedID: a.id, ontoTargetID: b.id, inTab: tab.id)
        let groupID = store.tab(id: tab.id)!.items.first { $0.kind == .group }!.id

        store.setAllItemLocks(.locked, inTab: tab.id)
        var items = store.tab(id: tab.id)!.items
        XCTAssertTrue(items.allSatisfy { $0.isLocked })
        XCTAssertTrue(items.first { $0.kind == .group }!.children.allSatisfy { $0.isLocked })

        // Spot-check enforcement under the bulk lock.
        store.removeItem(id: c.id, fromTab: tab.id)
        store.removeFromGroup(childID: a.id, groupID: groupID, inTab: tab.id)
        store.removeItem(id: a.id, fromTab: tab.id)
        XCTAssertEqual(store.tab(id: tab.id)?.items.count, 2)
        XCTAssertEqual(store.tab(id: tab.id)?.items.first { $0.kind == .group }?.children.count, 2)

        // The explicit bulk unlock clears a locked group and its children at once.
        store.setAllItemLocks(.unlocked, inTab: tab.id)
        items = store.tab(id: tab.id)!.items
        XCTAssertFalse(items.contains { $0.containsLockedItems })
        XCTAssertFalse(store.isItemEditingLocked(a.id, inTab: tab.id))
        store.removeItem(id: c.id, fromTab: tab.id)
        XCTAssertEqual(store.tab(id: tab.id)?.items.count, 1)
    }

    // MARK: Locked item (source-side denials)

    func testLockedItemDeniesRemovalMoveGroupAndEdits() throws {
        let store = TabStore(storeURL: storeURL)
        let tab = makeTab(); store.addTab(tab)
        let a = fileItem("A"), b = fileItem("B")
        store.addItem(a, toTab: tab.id)   // slot 0
        store.addItem(b, toTab: tab.id)   // slot 1
        store.setItemLock(.locked, forItem: a.id, inTab: tab.id)

        var renamed = item(a.id, in: store, tab: tab.id)!
        renamed.displayName = "Renamed"
        store.updateItem(renamed, inTab: tab.id)
        store.removeItem(id: a.id, fromTab: tab.id)
        store.placeItem(a.id, atSlot: 5, inTab: tab.id)
        store.groupItems(draggedID: a.id, ontoTargetID: b.id, inTab: tab.id)
        store.setCustomIconBookmark(Data([1]), forItem: a.id, inTab: tab.id)
        store.setIconStyle(IconStyle(base: .tile, colorHex: "#445566", symbol: nil),
                           forItem: a.id, inTab: tab.id)

        let saved = try XCTUnwrap(store.tab(id: tab.id))
        XCTAssertEqual(saved.items.count, 2)
        XCTAssertFalse(saved.items.contains { $0.kind == .group })
        let savedA = try XCTUnwrap(saved.items.first { $0.id == a.id })
        XCTAssertTrue(savedA.isLocked)
        XCTAssertEqual(savedA.displayName, "A")
        XCTAssertEqual(savedA.slot, 0)
        XCTAssertNil(savedA.customIconBookmark)
        XCTAssertNil(savedA.iconStyle)
    }

    // MARK: Occupied locked destination

    func testSwapOntoALockedOccupantIsDenied() throws {
        let store = TabStore(storeURL: storeURL)
        let tab = makeTab(); store.addTab(tab)
        let a = fileItem("A"), b = fileItem("B")
        store.addItem(a, toTab: tab.id)   // slot 0
        store.addItem(b, toTab: tab.id)   // slot 1
        store.setItemLock(.locked, forItem: a.id, inTab: tab.id)

        // Dropping B onto A's slot would swap A out — denied.
        store.placeItem(b.id, atSlot: 0, inTab: tab.id)

        XCTAssertEqual(item(a.id, in: store, tab: tab.id)?.slot, 0)
        XCTAssertEqual(item(b.id, in: store, tab: tab.id)?.slot, 1)
    }

    func testPlaceItemsKeepsLockedMembersAndSkipsTheirSlots() throws {
        let store = TabStore(storeURL: storeURL)
        let tab = makeTab(); store.addTab(tab)
        let locked = fileItem("K"), a = fileItem("A"), b = fileItem("B")
        [locked, a, b].forEach { store.addItem($0, toTab: tab.id) }
        store.placeItem(locked.id, atSlot: 3, inTab: tab.id)   // still unlocked: moves
        store.setItemLock(.locked, forItem: locked.id, inTab: tab.id)

        // The locked entry is named in the run but never moves; its slot stays a
        // blocked occupant the others land around.
        store.placeItems([locked.id, a.id, b.id], startingAt: 3, inTab: tab.id)

        let items = store.tab(id: tab.id)!.items
        XCTAssertEqual(items.first { $0.id == locked.id }?.slot, 3)
        XCTAssertEqual(items.first { $0.id == a.id }?.slot, 4)
        XCTAssertEqual(items.first { $0.id == b.id }?.slot, 5)
    }

    // MARK: updateItem can't smuggle lock changes

    func testUpdateItemCannotChangeLockStateEitherWay() {
        let store = TabStore(storeURL: storeURL)
        let tab = makeTab(); store.addTab(tab)
        let a = fileItem("A")
        store.addItem(a, toTab: tab.id)

        // An update arriving with the lock bit set can't turn the lock on.
        var smuggled = item(a.id, in: store, tab: tab.id)!
        smuggled.isLocked = true
        smuggled.displayName = "Edited"
        store.updateItem(smuggled, inTab: tab.id)
        var saved = item(a.id, in: store, tab: tab.id)!
        XCTAssertFalse(saved.isLocked)
        XCTAssertEqual(saved.displayName, "Edited")

        // And a locked item ignores an update carrying isLocked = false — the
        // edit itself is denied, so nothing slips through with it.
        store.setItemLock(.locked, forItem: a.id, inTab: tab.id)
        var unlock = saved
        unlock.isLocked = false
        unlock.displayName = "Bypassed"
        store.updateItem(unlock, inTab: tab.id)
        saved = item(a.id, in: store, tab: tab.id)!
        XCTAssertTrue(saved.isLocked)
        XCTAssertEqual(saved.displayName, "Edited")

        store.setItemLock(.unlocked, forItem: a.id, inTab: tab.id)
        XCTAssertFalse(item(a.id, in: store, tab: tab.id)!.isLocked)
    }

    // MARK: Groups

    /// Groups [a, b] inside `tab` on `store` and returns the group's id.
    @discardableResult
    private func group(_ a: DrawerItem, _ b: DrawerItem,
                       in store: TabStore, tab tabID: UUID) -> UUID {
        store.groupItems(draggedID: a.id, ontoTargetID: b.id, inTab: tabID)
        return store.tab(id: tabID)!.items.first { $0.kind == .group }!.id
    }

    func testLockedGroupProtectsChildEditsAndContainer() throws {
        let store = TabStore(storeURL: storeURL)
        let tab = makeTab(); store.addTab(tab)
        let a = fileItem("A"), b = fileItem("B"), c = fileItem("C")
        [a, b, c].forEach { store.addItem($0, toTab: tab.id) }
        let groupID = group(a, b, in: store, tab: tab.id)
        store.setItemLock(.locked, forItem: groupID, inTab: tab.id)

        // Every mutation aimed inside the locked group is denied…
        var renamed = item(a.id, in: store, tab: tab.id)!
        renamed.displayName = "Renamed"
        store.updateItem(renamed, inTab: tab.id)
        store.removeItem(id: a.id, fromTab: tab.id)
        store.removeFromGroup(childID: a.id, groupID: groupID, inTab: tab.id)
        store.placeItemInGroup(a.id, atSlot: 0, groupID: groupID, inTab: tab.id)
        store.setCustomIconBookmark(Data([9]), forItem: a.id, inTab: tab.id)
        // …as are edits to the container itself…
        store.renameGroup(groupID: groupID, to: "New", inTab: tab.id)
        store.placeItem(groupID, atSlot: 7, inTab: tab.id)
        store.removeItem(id: groupID, fromTab: tab.id)
        store.groupItems(draggedID: c.id, ontoTargetID: groupID, inTab: tab.id)

        let saved = try XCTUnwrap(store.tab(id: tab.id))
        let group = try XCTUnwrap(saved.items.first { $0.kind == .group })
        XCTAssertEqual(group.displayName, "Group")
        XCTAssertEqual(group.slot, 1)
        XCTAssertEqual(group.children.count, 2)
        XCTAssertEqual(group.children.first { $0.id == a.id }?.displayName, "A")
        XCTAssertNil(group.children.first { $0.id == a.id }?.customIconBookmark)
        XCTAssertEqual(group.children.map(\.slot).sorted(), [0, 1])
        XCTAssertEqual(item(c.id, in: store, tab: tab.id)?.kind, .file)
        XCTAssertTrue(store.isItemEditingLocked(a.id, inTab: tab.id))

        // Unlocking the group frees child editing again.
        store.setItemLock(.unlocked, forItem: groupID, inTab: tab.id)
        XCTAssertFalse(store.isItemEditingLocked(a.id, inTab: tab.id))
        store.removeFromGroup(childID: a.id, groupID: groupID, inTab: tab.id)
        XCTAssertNil(store.tab(id: tab.id)?.items.first { $0.kind == .group })
    }

    func testUnlockingAChildInsideALockedGroupIsDenied() throws {
        let store = TabStore(storeURL: storeURL)
        let tab = makeTab(); store.addTab(tab)
        let a = fileItem("A"), b = fileItem("B")
        store.addItem(a, toTab: tab.id)
        store.addItem(b, toTab: tab.id)
        let groupID = group(a, b, in: store, tab: tab.id)
        store.setItemLock(.locked, forItem: a.id, inTab: tab.id)   // while group is open — fine
        store.setItemLock(.locked, forItem: groupID, inTab: tab.id)

        store.setItemLock(.unlocked, forItem: a.id, inTab: tab.id)   // denied: inside a locked group
        XCTAssertTrue(item(a.id, in: store, tab: tab.id)?.isLocked ?? false)

        // Unlock the parent first, then the child's own lock clears explicitly.
        store.setItemLock(.unlocked, forItem: groupID, inTab: tab.id)
        XCTAssertTrue(store.isItemEditingLocked(a.id, inTab: tab.id))   // own lock survives
        store.setItemLock(.unlocked, forItem: a.id, inTab: tab.id)
        XCTAssertFalse(store.isItemEditingLocked(a.id, inTab: tab.id))
    }

    func testLockedChildProtectsContainerFromMoveAndDissolve() throws {
        let store = TabStore(storeURL: storeURL)
        let tab = makeTab(); store.addTab(tab)
        let a = fileItem("A"), b = fileItem("B"), c = fileItem("C")
        [a, b, c].forEach { store.addItem($0, toTab: tab.id) }
        let groupID = group(a, b, in: store, tab: tab.id)
        store.setItemLock(.locked, forItem: a.id, inTab: tab.id)   // child locked, group open

        // The container is editing-locked because moving/dissolving it would move
        // or destroy the locked child.
        XCTAssertTrue(store.isItemEditingLocked(groupID, inTab: tab.id))
        store.placeItem(groupID, atSlot: 6, inTab: tab.id)
        store.removeItem(id: groupID, fromTab: tab.id)
        var group = try XCTUnwrap(store.tab(id: tab.id)?.items.first { $0.id == groupID })
        XCTAssertEqual(group.kind, .group)
        XCTAssertEqual(group.slot, 1)

        // The locked child can't be renamed, popped, moved, or swapped onto.
        var renamed = group.children.first { $0.id == a.id }!
        renamed.displayName = "Renamed"
        store.updateItem(renamed, inTab: tab.id)
        store.removeFromGroup(childID: a.id, groupID: groupID, inTab: tab.id)
        store.placeItemInGroup(a.id, atSlot: 0, groupID: groupID, inTab: tab.id)
        let aSlot = group.children.first { $0.id == a.id }!.slot
        store.placeItemInGroup(b.id, atSlot: aSlot, groupID: groupID, inTab: tab.id)

        // Removing the unlocked sibling would dissolve the pair and eject the
        // locked child to the top level — denied as an indirect move.
        store.removeItem(id: b.id, fromTab: tab.id)
        store.removeFromGroup(childID: b.id, groupID: groupID, inTab: tab.id)

        group = try XCTUnwrap(store.tab(id: tab.id)?.items.first { $0.id == groupID })
        XCTAssertEqual(group.children.count, 2)
        XCTAssertEqual(group.children.first { $0.id == a.id }?.displayName, "A")
        XCTAssertEqual(group.children.first { $0.id == b.id }?.slot, 0)

        // A larger group tolerates losing an unlocked sibling: no dissolve means
        // no locked item moves.
        store.groupItems(draggedID: c.id, ontoTargetID: groupID, inTab: tab.id)
        store.removeItem(id: b.id, fromTab: tab.id)
        group = try XCTUnwrap(store.tab(id: tab.id)?.items.first { $0.id == groupID })
        XCTAssertEqual(group.children.map(\.id).sorted { $0.uuidString < $1.uuidString },
                       [a.id, c.id].sorted { $0.uuidString < $1.uuidString })
        XCTAssertTrue(group.children.first { $0.id == a.id }?.isLocked ?? false)
    }

    // MARK: lockNewItems & batch placement

    func testLockNewItemsLocksOnlyNewEntries() {
        let store = TabStore(storeURL: storeURL)
        let tab = makeTab(); store.addTab(tab)
        let existing = link("Existing", "https://existing.example")
        store.addItem(existing, toTab: tab.id)

        store.updateTab(id: tab.id) { $0.lockNewItems = true }   // the settings seam

        // A deduplicated re-add of the unlocked existing item is reused untouched.
        XCTAssertEqual(store.addItem(link("Again", "https://existing.example"), toTab: tab.id),
                       existing.id)
        XCTAssertFalse(item(existing.id, in: store, tab: tab.id)?.isLocked ?? true)

        // New entries arrive locked.
        let added = link("New", "https://new.example")
        XCTAssertEqual(store.addItem(added, toTab: tab.id), added.id)
        XCTAssertTrue(item(added.id, in: store, tab: tab.id)?.isLocked ?? false)
        XCTAssertTrue(store.isItemEditingLocked(added.id, inTab: tab.id))
    }

    func testAddItemsPlacesNewLockedEntriesButKeepsLockedDedupInPlace() throws {
        let store = TabStore(storeURL: storeURL)
        let tab = makeTab(); store.addTab(tab)

        // A locked existing entry sits at slot 0.
        let existing = link("Existing", "https://existing.example")
        store.addItem(existing, toTab: tab.id)
        store.setItemLock(.locked, forItem: existing.id, inTab: tab.id)
        store.updateTab(id: tab.id) { $0.lockNewItems = true }

        let a = link("A", "https://a.example")
        let b = link("B", "https://b.example")
        let ids = store.addItems([link("Again", "https://existing.example"), a, b],
                               toTab: tab.id, startingAt: 0)

        let saved = try XCTUnwrap(store.tab(id: tab.id))
        // The locked dedup target is reused but never repositioned; the run skips
        // its occupied slot and places the new (already locked) entries after it.
        XCTAssertEqual(ids, [existing.id, a.id, b.id])
        XCTAssertEqual(saved.items.first { $0.id == existing.id }?.slot, 0)
        XCTAssertEqual(saved.items.first { $0.id == a.id }?.slot, 1)
        XCTAssertEqual(saved.items.first { $0.id == b.id }?.slot, 2)
        XCTAssertTrue(saved.items.first { $0.id == a.id }!.isLocked)
        XCTAssertTrue(saved.items.first { $0.id == b.id }!.isLocked)
        XCTAssertTrue(saved.items.first { $0.id == existing.id }!.isLocked)
    }

    func testNewLockedEntryMayTakeItsRequestedSlot() {
        let store = TabStore(storeURL: storeURL)
        let tab = makeTab(lockNewItems: true)
        store.addTab(tab)

        let ids = store.addItems([link("A", "https://a.example")], toTab: tab.id, startingAt: 5)
        let saved = store.tab(id: tab.id)!.items.first!
        XCTAssertEqual(ids, [saved.id])
        XCTAssertTrue(saved.isLocked)
        XCTAssertEqual(saved.slot, 5)
    }

    // MARK: Indirect destruction & maintenance

    func testRemoveTabDeniedWhileItHoldsLockedItems() {
        let store = TabStore(storeURL: storeURL)
        let tab = makeTab(); store.addTab(tab)
        let a = fileItem("A")
        store.addItem(a, toTab: tab.id)
        store.setItemLock(.locked, forItem: a.id, inTab: tab.id)

        store.removeTab(id: tab.id)   // would destroy the locked item inside
        XCTAssertEqual(store.tabs.count, 1)

        store.setAllItemLocks(.unlocked, inTab: tab.id)
        store.removeTab(id: tab.id)
        XCTAssertTrue(store.tabs.isEmpty)
    }

    func testBookmarkRepairStillAppliesToLockedItems() throws {
        // Bookmark re-minting is maintenance, not launcher editing — it stays
        // allowed on locked items.
        let original = Data([2]), replacement = Data([12])
        let locked = DrawerItem(kind: .file, displayName: "A",
                                bookmark: original, isLocked: true)
        var document = LauncherDocument(tabs: [makeTab()])
        document.tabs[0].items = [locked]

        let repairs = TabStore.makeBookmarkRepairs(in: document.tabs) { _ in replacement }
        TabStore.applyBookmarkRepairs(repairs, to: &document)

        let item = try XCTUnwrap(document.tabs[0].items.first)
        XCTAssertEqual(item.bookmark, replacement)
        XCTAssertTrue(item.isLocked)
    }

    // MARK: Unlocked behavior

    func testUnlockedItemsRemainFullyEditable() throws {
        let store = TabStore(storeURL: storeURL)
        let tab = makeTab(); store.addTab(tab)
        let a = fileItem("A"), b = fileItem("B")
        store.addItem(a, toTab: tab.id)
        store.addItem(b, toTab: tab.id)

        var renamed = item(a.id, in: store, tab: tab.id)!
        renamed.displayName = "Renamed"
        store.updateItem(renamed, inTab: tab.id)
        store.setCustomIconBookmark(Data([1]), forItem: a.id, inTab: tab.id)
        store.placeItem(a.id, atSlot: 1, inTab: tab.id)   // swaps with B

        let savedA = try XCTUnwrap(item(a.id, in: store, tab: tab.id))
        XCTAssertEqual(savedA.displayName, "Renamed")
        XCTAssertEqual(savedA.customIconBookmark, Data([1]))
        XCTAssertEqual(savedA.slot, 1)
        XCTAssertEqual(item(b.id, in: store, tab: tab.id)?.slot, 0)

        // Grouping and popping work, ending with A removed by the ordinary path.
        let groupID = group(a, b, in: store, tab: tab.id)
        store.removeFromGroup(childID: a.id, groupID: groupID, inTab: tab.id)
        store.removeItem(id: a.id, fromTab: tab.id)

        let items = store.tab(id: tab.id)!.items
        XCTAssertEqual(items.map(\.id), [b.id])
        XCTAssertNil(item(a.id, in: store, tab: tab.id))
    }
}
