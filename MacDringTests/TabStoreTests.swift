import Combine
import XCTest
@testable import MacDring

final class TabStoreTests: XCTestCase {

    private var storeURL: URL!

    override func setUp() {
        super.setUp()
        storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("macdring-store-\(UUID().uuidString)")
            .appendingPathComponent("launcher.json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: storeURL.deletingLastPathComponent())
        storeURL = nil
        super.tearDown()
    }

    private func makeTab(_ title: String = "T") -> Tab {
        Tab(title: title,
            colorHex: "#0A84FF",
            anchor: ScreenAnchor(displayUUID: "D1", edge: .right, position: 0.5))
    }

    func testFreshStoreIsEmpty() {
        let store = TabStore(storeURL: storeURL)
        XCTAssertFalse(store.loadedFromDisk)
        XCTAssertTrue(store.tabs.isEmpty)
    }

    func testAddSaveAndReload() {
        let store = TabStore(storeURL: storeURL)
        let tab = makeTab("Work")
        store.addTab(tab)
        store.saveNow()

        let reloaded = TabStore(storeURL: storeURL)
        XCTAssertTrue(reloaded.loadedFromDisk)
        XCTAssertEqual(reloaded.tabs.count, 1)
        XCTAssertEqual(reloaded.tabs.first?.title, "Work")
        XCTAssertEqual(reloaded.tabs.first?.id, tab.id)
    }

    func testUpdateTabAssignsSlotsToNewlyAppendedItems() {
        // The Settings editor appends items with an unassigned slot (-1) and commits
        // via updateTab; they must get a real slot so they render without a restart.
        let store = TabStore(storeURL: storeURL)
        var tab = makeTab()
        store.addTab(tab)

        tab = try! XCTUnwrap(store.tab(id: tab.id))
        tab.items.append(DrawerItem.trash())               // slot defaults to -1
        tab.items.append(DrawerItem(kind: .url, displayName: "Site", url: URL(string: "https://example.com")))
        store.updateTab(tab)

        let saved = store.tab(id: tab.id)!
        XCTAssertTrue(saved.items.allSatisfy { $0.slot >= 0 }, "every item should get a real slot")
        XCTAssertEqual(Set(saved.items.map(\.slot)).count, saved.items.count, "slots should be distinct")
    }

    func testReplaceTabsNormalizesItemSlots() {
        let store = TabStore(storeURL: storeURL)
        var tab = makeTab()
        tab.items = [
            DrawerItem(kind: .file, displayName: "A", slot: -1),
            DrawerItem(kind: .file, displayName: "B", slot: 0),
            DrawerItem(kind: .file, displayName: "C", slot: 0),
        ]

        store.replaceTabs([tab])

        let saved = store.tab(id: tab.id)!
        XCTAssertTrue(saved.items.allSatisfy { $0.slot >= 0 })
        XCTAssertEqual(Set(saved.items.map(\.slot)).count, saved.items.count)
    }

    func testUpdateAllBehaviorsAppliesToEveryTab() {
        let store = TabStore(storeURL: storeURL)
        var a = makeTab("A"); a.behavior = TabBehavior(openOnHover: false, autoHide: true)
        var b = makeTab("B"); b.behavior = TabBehavior(openOnHover: true, autoHide: true)
        store.addTab(a)
        store.addTab(b)

        store.updateAllBehaviors { $0.autoHide = false }

        XCTAssertTrue(store.tabs.allSatisfy { !$0.behavior.autoHide })
        // Only the targeted field changes; others are untouched.
        XCTAssertFalse(store.tab(id: a.id)?.behavior.openOnHover ?? true)
        XCTAssertTrue(store.tab(id: b.id)?.behavior.openOnHover ?? false)
    }

    func testItemMutations() {
        let store = TabStore(storeURL: storeURL)
        let tab = makeTab()
        store.addTab(tab)

        let item = DrawerItem(kind: .url, displayName: "Site", url: URL(string: "https://example.com"))
        store.addItem(item, toTab: tab.id)
        XCTAssertEqual(store.tab(id: tab.id)?.items.count, 1)

        store.removeItem(id: item.id, fromTab: tab.id)
        XCTAssertEqual(store.tab(id: tab.id)?.items.count, 0)
    }

    func testSetAnchor() {
        let store = TabStore(storeURL: storeURL)
        let tab = makeTab()
        store.addTab(tab)

        let newAnchor = ScreenAnchor(displayUUID: "D2", edge: .bottom, position: 0.2, order: 1)
        store.setAnchor(newAnchor, forTab: tab.id)
        XCTAssertEqual(store.tab(id: tab.id)?.anchor, newAnchor)
    }

    func testSetAnchorDefaultFiresOnChange() {
        let store = TabStore(storeURL: storeURL)
        let tab = makeTab()
        store.addTab(tab)

        var changes = 0
        store.onChange = { changes += 1 }
        store.setAnchor(ScreenAnchor(displayUUID: "D2", edge: .bottom, position: 0.2, order: 1), forTab: tab.id)
        XCTAssertEqual(changes, 1)   // a normal reposition reconciles
    }

    func testSetAnchorWithoutNotifyMutatesButDoesNotFireOnChange() {
        // The de-overlap pass persists settled positions mid-reconcile with notify:false.
        // It must still write the anchor, but must NOT fire onChange — that would
        // re-enter reconcile (which has no re-entrancy guard) from inside itself.
        let store = TabStore(storeURL: storeURL)
        let tab = makeTab()
        store.addTab(tab)

        var changes = 0
        store.onChange = { changes += 1 }
        let newAnchor = ScreenAnchor(displayUUID: "D2", edge: .bottom, position: 0.2, order: 1)
        store.setAnchor(newAnchor, forTab: tab.id, notify: false)
        XCTAssertEqual(store.tab(id: tab.id)?.anchor, newAnchor)   // persisted
        XCTAssertEqual(changes, 0)                                 // but no reconcile-triggering notify
    }

    func testAddItemAssignsSequentialSlots() {
        let store = TabStore(storeURL: storeURL)
        let tab = makeTab()
        store.addTab(tab)
        store.addItem(DrawerItem(kind: .file, displayName: "A"), toTab: tab.id)
        store.addItem(DrawerItem(kind: .file, displayName: "B"), toTab: tab.id)
        XCTAssertEqual(store.tab(id: tab.id)?.items.map(\.slot).sorted(), [0, 1])
    }

    func testAddItemSkipsDuplicateTarget() {
        let store = TabStore(storeURL: storeURL)
        let tab = makeTab()
        store.addTab(tab)
        let url = URL(fileURLWithPath: "/Applications/Safari.app")
        store.addItem(DrawerItem(kind: .application, displayName: "Safari", url: url), toTab: tab.id)
        // Same target, different display name / id — should not be added again.
        store.addItem(DrawerItem(kind: .application, displayName: "Safari again", url: url), toTab: tab.id)
        XCTAssertEqual(store.tab(id: tab.id)?.items.count, 1)
    }

    func testAddItemAllowsDistinctTargets() {
        let store = TabStore(storeURL: storeURL)
        let tab = makeTab()
        store.addTab(tab)
        store.addItem(DrawerItem(kind: .url, displayName: "A", url: URL(string: "https://a.example")), toTab: tab.id)
        store.addItem(DrawerItem(kind: .url, displayName: "B", url: URL(string: "https://b.example")), toTab: tab.id)
        XCTAssertEqual(store.tab(id: tab.id)?.items.count, 2)
    }

    func testPlaceItemMovesToEmptySlotLeavingGap() {
        let store = TabStore(storeURL: storeURL)
        let tab = makeTab()
        store.addTab(tab)
        let a = DrawerItem(kind: .file, displayName: "A")
        store.addItem(a, toTab: tab.id)        // slot 0

        store.placeItem(a.id, atSlot: 5, inTab: tab.id)
        XCTAssertEqual(store.tab(id: tab.id)?.items.first { $0.id == a.id }?.slot, 5)
        XCTAssertNil(store.tab(id: tab.id)?.items.first { $0.slot == 0 })   // gap left behind
    }

    func testPlaceItemSwapsWhenSlotOccupied() {
        let store = TabStore(storeURL: storeURL)
        let tab = makeTab()
        store.addTab(tab)
        let a = DrawerItem(kind: .file, displayName: "A")
        let b = DrawerItem(kind: .file, displayName: "B")
        store.addItem(a, toTab: tab.id)        // slot 0
        store.addItem(b, toTab: tab.id)        // slot 1

        store.placeItem(a.id, atSlot: 1, inTab: tab.id)
        let items = store.tab(id: tab.id)!.items
        XCTAssertEqual(items.first { $0.id == a.id }?.slot, 1)
        XCTAssertEqual(items.first { $0.id == b.id }?.slot, 0)
    }

    // MARK: Slot-drop edge cases (I4)

    func testAddItemReturnsNewItemID() {
        let store = TabStore(storeURL: storeURL)
        let tab = makeTab(); store.addTab(tab)
        let item = DrawerItem(kind: .url, displayName: "A", url: URL(string: "https://a.example"))
        XCTAssertEqual(store.addItem(item, toTab: tab.id), item.id)
    }

    func testAddItemReturnsExistingIDOnDuplicate() {
        let store = TabStore(storeURL: storeURL)
        let tab = makeTab(); store.addTab(tab)
        let url = URL(fileURLWithPath: "/Applications/Safari.app")
        let first = DrawerItem(kind: .application, displayName: "Safari", url: url)
        XCTAssertEqual(store.addItem(first, toTab: tab.id), first.id)
        // A second add of the same target returns the *existing* id, not the new one.
        let dup = DrawerItem(kind: .application, displayName: "Safari again", url: url)
        XCTAssertEqual(store.addItem(dup, toTab: tab.id), first.id)
        XCTAssertEqual(store.tab(id: tab.id)?.items.count, 1)
    }

    func testPlaceItemsLandConsecutivelyFromTarget() {
        let store = TabStore(storeURL: storeURL)
        let tab = makeTab(); store.addTab(tab)
        let a = DrawerItem(kind: .url, displayName: "A", url: URL(string: "https://a.example"))
        let b = DrawerItem(kind: .url, displayName: "B", url: URL(string: "https://b.example"))
        let c = DrawerItem(kind: .url, displayName: "C", url: URL(string: "https://c.example"))
        [a, b, c].forEach { store.addItem($0, toTab: tab.id) }

        store.placeItems([a.id, b.id, c.id], startingAt: 5, inTab: tab.id)
        let items = store.tab(id: tab.id)!.items
        XCTAssertEqual(items.first { $0.id == a.id }?.slot, 5)
        XCTAssertEqual(items.first { $0.id == b.id }?.slot, 6)
        XCTAssertEqual(items.first { $0.id == c.id }?.slot, 7)
    }

    func testPlaceItemsSkipSlotsHeldByOtherItems() {
        let store = TabStore(storeURL: storeURL)
        let tab = makeTab(); store.addTab(tab)
        let keep = DrawerItem(kind: .url, displayName: "K", url: URL(string: "https://k.example"))
        let a = DrawerItem(kind: .url, displayName: "A", url: URL(string: "https://a.example"))
        let b = DrawerItem(kind: .url, displayName: "B", url: URL(string: "https://b.example"))
        [keep, a, b].forEach { store.addItem($0, toTab: tab.id) }
        store.placeItem(keep.id, atSlot: 3, inTab: tab.id)   // keep now occupies slot 3

        store.placeItems([a.id, b.id], startingAt: 3, inTab: tab.id)
        let items = store.tab(id: tab.id)!.items
        XCTAssertEqual(items.first { $0.id == keep.id }?.slot, 3)   // untouched
        XCTAssertEqual(items.first { $0.id == a.id }?.slot, 4)      // skipped the blocked 3
        XCTAssertEqual(items.first { $0.id == b.id }?.slot, 5)
    }

    func testDuplicateDropMovesExistingItemToTarget() {
        // The drop flow: addItem returns the existing id on a dup, placeItems moves it.
        let store = TabStore(storeURL: storeURL)
        let tab = makeTab(); store.addTab(tab)
        let url = URL(fileURLWithPath: "/Applications/Safari.app")
        store.addItem(DrawerItem(kind: .application, displayName: "Safari", url: url), toTab: tab.id)  // slot 0
        let resolved = store.addItem(DrawerItem(kind: .application, displayName: "Safari", url: url), toTab: tab.id)
        store.placeItems([resolved].compactMap { $0 }, startingAt: 4, inTab: tab.id)
        XCTAssertEqual(store.tab(id: tab.id)?.items.count, 1)        // still one item (deduped)
        XCTAssertEqual(store.tab(id: tab.id)?.items.first?.slot, 4)  // existing item moved to the target
    }

    // MARK: Ordered bulk drops

    func testAddItemsPublishesAndNotifiesOnce() {
        let store = TabStore(storeURL: storeURL)
        let tab = makeTab(); store.addTab(tab)
        let items = [
            DrawerItem(kind: .url, displayName: "A", url: URL(string: "https://a.example")),
            DrawerItem(kind: .url, displayName: "B", url: URL(string: "https://b.example")),
            DrawerItem(kind: .url, displayName: "C", url: URL(string: "https://c.example")),
        ]
        var publications = 0
        var changes = 0
        let cancellable = store.objectWillChange.sink { publications += 1 }
        store.onChange = { changes += 1 }

        withExtendedLifetime(cancellable) {
            _ = store.addItems(items, toTab: tab.id, startingAt: 5)
        }

        XCTAssertEqual(publications, 1)
        XCTAssertEqual(changes, 1)
    }

    func testAddItemsPreservesFirstSeenOrder() {
        let store = TabStore(storeURL: storeURL)
        let tab = makeTab(); store.addTab(tab)
        let c = DrawerItem(kind: .url, displayName: "C", url: URL(string: "https://c.example"))
        let a = DrawerItem(kind: .url, displayName: "A", url: URL(string: "https://a.example"))
        let b = DrawerItem(kind: .url, displayName: "B", url: URL(string: "https://b.example"))

        let ids = store.addItems([c, a, b], toTab: tab.id)

        XCTAssertEqual(ids, [c.id, a.id, b.id])
        XCTAssertEqual(store.tab(id: tab.id)?.items.map(\.id), [c.id, a.id, b.id])
    }

    func testAddItemsReusesExistingAndEarlierBatchDuplicates() {
        let store = TabStore(storeURL: storeURL)
        let tab = makeTab(); store.addTab(tab)
        let existing = DrawerItem(kind: .url, displayName: "Existing", url: URL(string: "https://existing.example"))
        store.addItem(existing, toTab: tab.id)
        let existingDuplicate = DrawerItem(kind: .url, displayName: "Existing again", url: existing.url)
        let new = DrawerItem(kind: .url, displayName: "New", url: URL(string: "https://new.example"))
        let newDuplicate = DrawerItem(kind: .url, displayName: "New again", url: new.url)

        let ids = store.addItems([existingDuplicate, new, newDuplicate], toTab: tab.id)

        XCTAssertEqual(ids, [existing.id, new.id])
        XCTAssertEqual(store.tab(id: tab.id)?.items.map(\.id), [existing.id, new.id])
    }

    func testAddItemsReusesDuplicateInsideGroup() {
        let store = TabStore(storeURL: storeURL)
        let tab = makeTab(); store.addTab(tab)
        let a = DrawerItem(kind: .url, displayName: "A", url: URL(string: "https://a.example"))
        let b = DrawerItem(kind: .url, displayName: "B", url: URL(string: "https://b.example"))
        store.addItem(a, toTab: tab.id)
        store.addItem(b, toTab: tab.id)
        store.groupItems(draggedID: a.id, ontoTargetID: b.id, inTab: tab.id)

        let duplicate = DrawerItem(kind: .url, displayName: "A again", url: a.url)
        let new = DrawerItem(kind: .url, displayName: "New", url: URL(string: "https://new.example"))
        let ids = store.addItems([duplicate, new], toTab: tab.id, startingAt: 1)
        let saved = store.tab(id: tab.id)!.items

        XCTAssertEqual(ids, [a.id, new.id])
        XCTAssertEqual(saved.count, 2)
        XCTAssertEqual(saved.first { $0.kind == .group }?.children.count, 2)
        XCTAssertEqual(saved.first { $0.id == new.id }?.slot, 2)
    }

    func testAddItemsPlacesExistingAndNewItemsFromTarget() {
        let store = TabStore(storeURL: storeURL)
        let tab = makeTab(); store.addTab(tab)
        let existing = DrawerItem(kind: .url, displayName: "Existing", url: URL(string: "https://existing.example"))
        store.addItem(existing, toTab: tab.id)
        let duplicate = DrawerItem(kind: .url, displayName: "Existing again", url: existing.url)
        let a = DrawerItem(kind: .url, displayName: "A", url: URL(string: "https://a.example"))
        let b = DrawerItem(kind: .url, displayName: "B", url: URL(string: "https://b.example"))

        let ids = store.addItems([duplicate, a, b], toTab: tab.id, startingAt: 4)
        let saved = store.tab(id: tab.id)!.items

        XCTAssertEqual(ids, [existing.id, a.id, b.id])
        XCTAssertEqual(saved.first { $0.id == existing.id }?.slot, 4)
        XCTAssertEqual(saved.first { $0.id == a.id }?.slot, 5)
        XCTAssertEqual(saved.first { $0.id == b.id }?.slot, 6)
    }

    func testAddItemsPlacementSkipsBlockers() {
        let store = TabStore(storeURL: storeURL)
        var tab = makeTab()
        let firstBlocker = DrawerItem(kind: .url, displayName: "K1", url: URL(string: "https://k1.example"), slot: 3)
        let secondBlocker = DrawerItem(kind: .url, displayName: "K2", url: URL(string: "https://k2.example"), slot: 5)
        tab.items = [firstBlocker, secondBlocker]
        store.addTab(tab)
        let a = DrawerItem(kind: .url, displayName: "A", url: URL(string: "https://a.example"))
        let b = DrawerItem(kind: .url, displayName: "B", url: URL(string: "https://b.example"))

        store.addItems([a, b], toTab: tab.id, startingAt: 3)
        let saved = store.tab(id: tab.id)!.items

        XCTAssertEqual(saved.first { $0.id == firstBlocker.id }?.slot, 3)
        XCTAssertEqual(saved.first { $0.id == secondBlocker.id }?.slot, 5)
        XCTAssertEqual(saved.first { $0.id == a.id }?.slot, 4)
        XCTAssertEqual(saved.first { $0.id == b.id }?.slot, 6)
    }

    func testAddItemsCompleteDuplicateWithoutPlacementDoesNotMutate() {
        let store = TabStore(storeURL: storeURL)
        let tab = makeTab(); store.addTab(tab)
        let existing = DrawerItem(kind: .url, displayName: "Existing", url: URL(string: "https://existing.example"))
        store.addItem(existing, toTab: tab.id)
        let before = store.document
        var publications = 0
        var changes = 0
        let cancellable = store.objectWillChange.sink { publications += 1 }
        store.onChange = { changes += 1 }

        let duplicate = DrawerItem(kind: .url, displayName: "Existing again", url: existing.url)
        let ids = withExtendedLifetime(cancellable) {
            store.addItems([duplicate], toTab: tab.id)
        }

        XCTAssertEqual(ids, [existing.id])
        XCTAssertEqual(store.document, before)
        XCTAssertEqual(publications, 0)
        XCTAssertEqual(changes, 0)
    }

    func testAssigningMissingSlotsFillsGapsAndKeepsValidSlots() {
        let items = [
            DrawerItem(kind: .file, displayName: "A", slot: -1),
            DrawerItem(kind: .file, displayName: "B", slot: 2),    // keep; leaves a gap at 1
            DrawerItem(kind: .file, displayName: "C", slot: -1),
        ].assigningMissingSlots()
        let bySlot = Dictionary(uniqueKeysWithValues: items.map { ($0.displayName, $0.slot) })
        XCTAssertEqual(bySlot["B"], 2)
        XCTAssertEqual(Set([bySlot["A"], bySlot["C"]]), Set([0, 1]))
    }

    func testAssigningMissingSlotsResolvesDuplicates() {
        let items = [
            DrawerItem(kind: .file, displayName: "A", slot: 0),
            DrawerItem(kind: .file, displayName: "B", slot: 0),
        ].assigningMissingSlots()
        XCTAssertEqual(Set(items.map(\.slot)), Set([0, 1]))
    }

    func testRemoveTab() {
        let store = TabStore(storeURL: storeURL)
        let tab = makeTab()
        store.addTab(tab)
        store.removeTab(id: tab.id)
        XCTAssertTrue(store.tabs.isEmpty)
    }

    func testOnChangeFires() {
        let store = TabStore(storeURL: storeURL)
        var changes = 0
        store.onChange = { changes += 1 }
        store.addTab(makeTab())
        store.addItem(DrawerItem(kind: .file, displayName: "x"), toTab: store.tabs[0].id)
        XCTAssertEqual(changes, 2)
    }

    func testRecoversFromBackupWhenPrimaryCorrupt() throws {
        // Write a good document, then corrupt the primary file; the .bak should load.
        let store = TabStore(storeURL: storeURL)
        store.addTab(makeTab("Backed"))
        store.saveNow()                                   // creates launcher.json
        store.addTab(makeTab("Second"))
        store.saveNow()                                   // copies prior -> .bak, writes new

        try "{ not valid json".data(using: .utf8)!.write(to: storeURL)
        let reloaded = TabStore(storeURL: storeURL)
        XCTAssertTrue(reloaded.loadedFromDisk)            // recovered from .bak
        XCTAssertFalse(reloaded.tabs.isEmpty)
    }

    private var bakURL: URL {
        storeURL.deletingPathExtension().appendingPathExtension("bak.json")
    }

    private func quarantineFiles() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: storeURL.deletingLastPathComponent(),
                                                    includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("launcher.corrupt-") }
    }

    func testBackupHoldsPreviousVersionAfterSave() throws {
        let store = TabStore(storeURL: storeURL)
        store.addTab(makeTab("First"))
        store.saveNow()
        store.addTab(makeTab("Second"))
        store.saveNow()

        let backup = try JSONDecoder().decode(LauncherDocument.self, from: Data(contentsOf: bakURL))
        XCTAssertEqual(backup.tabs.map(\.title), ["First"])
    }

    func testFirstSaveAfterBackupRecoveryPreservesTheGoodBackup() throws {
        // Build a good .bak (one tab) and a newer primary (two tabs)…
        let store = TabStore(storeURL: storeURL)
        store.addTab(makeTab("Backed"))
        store.saveNow()
        store.addTab(makeTab("Second"))
        store.saveNow()

        // …then corrupt the primary and recover from the backup.
        try "{ not valid json".data(using: .utf8)!.write(to: storeURL)
        let recovered = TabStore(storeURL: storeURL)
        XCTAssertEqual(recovered.tabs.map(\.title), ["Backed"])

        // The first save after recovery must not rotate the (corrupt) primary
        // over the good backup — the old failure mode that could leave *both*
        // copies unreadable.
        recovered.saveNow()
        let backup = try JSONDecoder().decode(LauncherDocument.self, from: Data(contentsOf: bakURL))
        XCTAssertEqual(backup.tabs.map(\.title), ["Backed"])
        // And the corrupt original is preserved for inspection, not destroyed.
        XCTAssertEqual(try quarantineFiles().count, 1)
    }

    func testCorruptDocumentIsQuarantinedNotOverwritten() throws {
        let garbage = "{ definitely not json"
        try FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data(garbage.utf8).write(to: storeURL)

        let store = TabStore(storeURL: storeURL)   // no .bak to recover from
        XCTAssertFalse(store.loadedFromDisk)
        XCTAssertTrue(store.tabs.isEmpty)

        // Simulate the first-run seeding that would previously overwrite the file.
        store.addTab(makeTab("Starter"))
        store.saveNow()

        let preserved = try XCTUnwrap(quarantineFiles().first)
        XCTAssertEqual(try String(contentsOf: preserved, encoding: .utf8), garbage)
    }

    func testRefusesToSaveDocumentFromANewerVersion() throws {
        let futureJSON = """
        { "version": 99,
          "tabs": [ { "title": "Future",
                      "anchor": { "displayUUID": "D1", "edge": "right", "position": 0.5 } } ] }
        """
        try FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data(futureJSON.utf8).write(to: storeURL)

        let store = TabStore(storeURL: storeURL)
        XCTAssertTrue(store.loadedFromDisk)               // best-effort load still works
        store.addTab(makeTab("Local Change"))
        store.saveNow()                                   // must refuse

        let onDisk = try String(contentsOf: storeURL, encoding: .utf8)
        XCTAssertEqual(onDisk, futureJSON, "a newer-versioned document must never be rewritten by an older build")
    }

    func testImportRejectsDocumentFromANewerVersion() throws {
        let store = TabStore(storeURL: storeURL)
        store.addTab(makeTab("Existing"))

        let futureJSON = """
        { "version": 99,
          "tabs": [ { "title": "Future",
                      "anchor": { "displayUUID": "D1", "edge": "right", "position": 0.5 } } ] }
        """

        XCTAssertFalse(store.importData(Data(futureJSON.utf8)))
        XCTAssertEqual(store.tabs.map(\.title), ["Existing"])
    }

    func testImportAdoptsTheImportedVersionSoTheLayoutCanPersistAgain() throws {
        // Load a document written by a "newer" build — saves are (rightly) disabled…
        let futureJSON = """
        { "version": 99,
          "tabs": [ { "title": "Future",
                      "anchor": { "displayUUID": "D1", "edge": "right", "position": 0.5 } } ] }
        """
        try FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data(futureJSON.utf8).write(to: storeURL)
        let store = TabStore(storeURL: storeURL)

        // …then importing a current-version layout must adopt its version too,
        // so the imported tabs aren't silently unpersistable.
        let importedJSON = """
        { "version": 1,
          "tabs": [ { "title": "Imported",
                      "anchor": { "displayUUID": "D1", "edge": "right", "position": 0.5 } } ] }
        """
        XCTAssertTrue(store.importData(Data(importedJSON.utf8)))
        store.saveNow()

        let onDisk = try JSONDecoder().decode(LauncherDocument.self, from: Data(contentsOf: storeURL))
        XCTAssertEqual(onDisk.version, 1)
        XCTAssertEqual(onDisk.tabs.map(\.title), ["Imported"])
    }

    // MARK: Groups (iOS-folder-like)

    /// Adds a tab holding two loose file items (A at slot 0, B at slot 1) and returns
    /// their ids for the group tests.
    private func tabWithTwoItems() -> (tab: Tab, a: UUID, b: UUID) {
        let store = TabStore(storeURL: storeURL)
        let tab = makeTab(); store.addTab(tab)
        let a = DrawerItem(kind: .file, displayName: "A")
        let b = DrawerItem(kind: .file, displayName: "B")
        store.addItem(a, toTab: tab.id)   // slot 0
        store.addItem(b, toTab: tab.id)   // slot 1
        self.groupStore = store
        return (tab, a.id, b.id)
    }
    /// Retains the store built by `tabWithTwoItems` for the duration of a test.
    private var groupStore: TabStore!

    func testGroupItemsFormsAGroupAtTheTargetSlot() {
        let (tab, a, b) = tabWithTwoItems()
        let store = groupStore!
        store.groupItems(draggedID: a, ontoTargetID: b, inTab: tab.id)

        let items = store.tab(id: tab.id)!.items
        XCTAssertEqual(items.count, 1)                       // A + B collapsed into one group
        let group = items.first!
        XCTAssertEqual(group.kind, .group)
        XCTAssertEqual(group.slot, 1)                        // takes the target's slot
        XCTAssertEqual(Set(group.children.map(\.id)), [a, b])
        XCTAssertEqual(Set(group.children.map(\.slot)), [0, 1])
    }

    func testGroupItemsIntoExistingGroupAppendsChild() {
        let (tab, a, b) = tabWithTwoItems()
        let store = groupStore!
        let c = DrawerItem(kind: .file, displayName: "C")
        store.addItem(c, toTab: tab.id)                      // slot 2
        store.groupItems(draggedID: a, ontoTargetID: b, inTab: tab.id)   // group A+B
        let groupID = store.tab(id: tab.id)!.items.first { $0.kind == .group }!.id

        store.groupItems(draggedID: c, ontoTargetID: groupID, inTab: tab.id)   // drop C into it
        let group = store.tab(id: tab.id)!.items.first { $0.kind == .group }!
        XCTAssertEqual(Set(group.children.map(\.id)), [a, b, c])
        XCTAssertEqual(store.tab(id: tab.id)!.items.count, 1)   // only the group remains
    }

    func testRenameGroup() {
        let (tab, a, b) = tabWithTwoItems()
        let store = groupStore!
        store.groupItems(draggedID: a, ontoTargetID: b, inTab: tab.id)
        let groupID = store.tab(id: tab.id)!.items.first { $0.kind == .group }!.id

        store.renameGroup(groupID: groupID, to: "Work", inTab: tab.id)
        XCTAssertEqual(store.tab(id: tab.id)!.items.first!.displayName, "Work")
    }

    func testRemoveFromGroupDissolvesWhenBelowTwo() {
        let (tab, a, b) = tabWithTwoItems()
        let store = groupStore!
        store.groupItems(draggedID: a, ontoTargetID: b, inTab: tab.id)
        let groupID = store.tab(id: tab.id)!.items.first { $0.kind == .group }!.id

        // Popping one child leaves a single item, so the group dissolves back to loose
        // items — both A and B at the top level, none a group.
        store.removeFromGroup(childID: a, groupID: groupID, inTab: tab.id)
        let items = store.tab(id: tab.id)!.items
        XCTAssertEqual(Set(items.map(\.id)), [a, b])
        XCTAssertTrue(items.allSatisfy { $0.kind != .group })
    }

    func testRemoveFromGroupKeepsGroupWhenTwoRemain() {
        let (tab, a, b) = tabWithTwoItems()
        let store = groupStore!
        let c = DrawerItem(kind: .file, displayName: "C")
        store.addItem(c, toTab: tab.id)
        store.groupItems(draggedID: a, ontoTargetID: b, inTab: tab.id)
        let groupID = store.tab(id: tab.id)!.items.first { $0.kind == .group }!.id
        store.groupItems(draggedID: c, ontoTargetID: groupID, inTab: tab.id)   // group of 3

        store.removeFromGroup(childID: c, groupID: groupID, inTab: tab.id)     // → group of 2
        let items = store.tab(id: tab.id)!.items
        let group = items.first { $0.kind == .group }
        XCTAssertNotNil(group)
        XCTAssertEqual(Set(group!.children.map(\.id)), [a, b])
        XCTAssertTrue(items.contains { $0.id == c && $0.kind != .group })      // C back at top level
    }

    func testPlaceItemInGroupSwapsChildSlots() {
        let (tab, a, b) = tabWithTwoItems()
        let store = groupStore!
        store.groupItems(draggedID: a, ontoTargetID: b, inTab: tab.id)
        let group = store.tab(id: tab.id)!.items.first { $0.kind == .group }!
        // B is slot 0 (the target came first), A is slot 1.
        let bSlot0 = group.children.first { $0.slot == 0 }!.id

        store.placeItemInGroup(bSlot0, atSlot: 1, groupID: group.id, inTab: tab.id)
        let after = store.tab(id: tab.id)!.items.first { $0.kind == .group }!
        XCTAssertEqual(after.children.first { $0.id == bSlot0 }?.slot, 1)      // moved
        XCTAssertEqual(after.children.first { $0.id != bSlot0 }?.slot, 0)      // the other swapped in
    }

    func testGroupingAGroupIsRejected() {
        let (tab, a, b) = tabWithTwoItems()
        let store = groupStore!
        let c = DrawerItem(kind: .file, displayName: "C")
        store.addItem(c, toTab: tab.id)
        store.groupItems(draggedID: a, ontoTargetID: b, inTab: tab.id)
        let groupID = store.tab(id: tab.id)!.items.first { $0.kind == .group }!.id

        // Dragging a group onto another item must not nest — a no-op.
        store.groupItems(draggedID: groupID, ontoTargetID: c, inTab: tab.id)
        XCTAssertEqual(store.tab(id: tab.id)!.items.count, 2)   // group + C, unchanged
        XCTAssertTrue(store.tab(id: tab.id)!.items.contains { $0.id == c && $0.kind != .group })
    }
}
