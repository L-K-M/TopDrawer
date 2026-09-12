import XCTest
@testable import MacDring

/// The host-side reconciler decides *when* the editor is told about a document.
/// Getting it wrong is the difference between an editor that survives the
/// drawer's constant unrelated invalidations and one that resets the cursor
/// mid-sentence, so these tests pin each of those cases.
final class NotesEditorHostSessionTests: XCTestCase {

    private let tabA = UUID()
    private let tabB = UUID()

    private func readySession() -> NotesEditorHostSession {
        let session = NotesEditorHostSession()
        session.markReady()
        return session
    }

    /// The first document is queued until the page announces itself: WebKit drops
    /// anything evaluated before the bundle has run.
    func testNothingIsSentBeforeReady() {
        let session = NotesEditorHostSession()
        session.setDesired(documentID: tabA, markdown: "# a", theme: .light, formattingBar: .hidden)

        XCTAssertNil(session.nextMessage())
        XCTAssertFalse(session.isInSync)

        session.markReady()
        XCTAssertEqual(session.nextMessage(), .initialize(markdown: "# a", theme: "light", revision: 1, documentID: tabA.uuidString))
    }

    /// The core invariant: re-evaluating the view with the same inputs — which the
    /// drawer does many times a second — must not re-send the document.
    func testRepeatedIdenticalUpdatesSendNothing() {
        let session = readySession()
        session.setDesired(documentID: tabA, markdown: "# a", theme: .light, formattingBar: .hidden)
        XCTAssertNotNil(session.nextMessage())

        for _ in 0..<5 {
            session.setDesired(documentID: tabA, markdown: "# a", theme: .light, formattingBar: .hidden)
            XCTAssertNil(session.nextMessage(), "an unrelated invalidation must not reset the editor")
        }
        XCTAssertTrue(session.isInSync)
    }

    /// The user's own edit must not be echoed back as a replacement.
    func testEditorChangeIsNotEchoedBack() {
        let session = readySession()
        session.setDesired(documentID: tabA, markdown: "# a", theme: .light, formattingBar: .hidden)
        XCTAssertNotNil(session.nextMessage())

        session.recordEditorChange("# a typed", documentID: tabA.uuidString, editorRevision: 1)
        session.setDesired(documentID: tabA, markdown: "# a typed", theme: .light, formattingBar: .hidden)

        XCTAssertNil(session.nextMessage(), "the editor already shows what the host was told")
        XCTAssertEqual(session.markdown, "# a typed")
    }

    /// The same invariant, but through the loop the drawer actually runs: the pane's
    /// inputs are `DrawerModel`'s, not the reconciler's, so the edit has to reach the
    /// model too. Without that mirror an unrelated invalidation — which the drawer
    /// serves many times a second — re-evaluates the pane with the text the drawer
    /// opened with, and the reconciler dutifully sends it as a replacement, reverting
    /// what the user just typed.
    func testARefreshAfterAnEditSendsNothingWhenTheDrawerMirrorsIt() throws {
        let model = DrawerModel()
        model.documentID = tabA
        model.notes = "# a"

        let session = readySession()
        session.setDesired(documentID: model.documentID, markdown: model.notes, theme: .light, formattingBar: .hidden)
        XCTAssertNotNil(session.nextMessage())

        // The editor reports an edit, and the drawer handles it the one way the pane
        // does: mirror into the model, then persist.
        let edited = session.recordEditorChange("# a typed", documentID: tabA.uuidString,
                                                editorRevision: 1)
        model.handleNotesEdit("# a typed",
                              forDocument: try XCTUnwrap(edited, "the edit is the shown note's"))

        // A screen change, another tab's mutation, a running-app update: the pane is
        // re-evaluated with the model's inputs and must produce no message.
        session.setDesired(documentID: model.documentID, markdown: model.notes, theme: .light, formattingBar: .hidden)
        XCTAssertNil(session.nextMessage(), "a refresh must not push the pre-edit text back")
    }

    /// A different tab is a different document, and gets a fresh revision.
    func testSwitchingDocumentInitializesWithANewRevision() {
        let session = readySession()
        session.setDesired(documentID: tabA, markdown: "# a", theme: .light, formattingBar: .hidden)
        XCTAssertEqual(session.nextMessage(), .initialize(markdown: "# a", theme: "light", revision: 1, documentID: tabA.uuidString))

        session.setDesired(documentID: tabB, markdown: "# b", theme: .light, formattingBar: .hidden)
        XCTAssertEqual(session.nextMessage(), .initialize(markdown: "# b", theme: "light", revision: 2, documentID: tabB.uuidString))
    }

    /// An edit naming a document this session never sent is refused outright: it is
    /// either a bug in the page or a message from somewhere else, and applying it
    /// would put text into a note the editor was never given.
    func testEditNamingANeverSentDocumentIsRejected() {
        let session = readySession()
        session.setDesired(documentID: tabA, markdown: "# a", theme: .light, formattingBar: .hidden)
        XCTAssertNotNil(session.nextMessage())

        XCTAssertNil(session.recordEditorChange("# text meant for another note",
                                                documentID: tabB.uuidString,
                                                editorRevision: 1))
        XCTAssertEqual(session.markdown, "# a", "the other document's text must not be adopted")
        XCTAssertEqual(session.deliveredDocumentID, tabA)
    }

    /// The same, after the host has switched documents: the late reply for the old
    /// note being replaced is still persisted against that note, but it must not
    /// become the current note's text.
    func testLateEditAfterSwitchIsPersistedToItsOwnNoteOnly() {
        let session = readySession()
        session.setDesired(documentID: tabA, markdown: "# a", theme: .light, formattingBar: .hidden)
        XCTAssertNotNil(session.nextMessage())

        session.setDesired(documentID: tabB, markdown: "# b", theme: .light, formattingBar: .hidden)
        XCTAssertNotNil(session.nextMessage())

        // The editor reports the edit it had in flight for the note just left; the
        // host saves it against tabA rather than dropping it or, worse, treating it
        // as tabB's text.
        XCTAssertEqual(
            session.recordEditorChange("# a, edited just before the switch",
                                       documentID: tabA.uuidString,
                                       editorRevision: 1),
            tabA
        )
        XCTAssertEqual(session.markdown, "# b", "the current note's text must not be overwritten")
    }

    /// A reply whose revision is not newer than one already accepted is a race that
    /// lost: applying it would revert the newer text.
    func testStaleEditorRevisionIsRejected() {
        let session = readySession()
        session.setDesired(documentID: tabA, markdown: "# a", theme: .light, formattingBar: .hidden)
        XCTAssertNotNil(session.nextMessage())

        XCTAssertEqual(session.recordEditorChange("# a v2", documentID: tabA.uuidString,
                                                  editorRevision: 2), tabA)
        XCTAssertNil(session.recordEditorChange("# a v1 (late)", documentID: tabA.uuidString,
                                                editorRevision: 1))
        XCTAssertEqual(session.markdown, "# a v2")
    }

    /// Nothing to show (no open tab) must not be reported as being in sync with an
    /// editor that is still holding the previous note.
    func testNoDesiredDocumentIsNotInSyncWithADeliveredOne() {
        let session = readySession()
        session.setDesired(documentID: tabA, markdown: "# a", theme: .light, formattingBar: .hidden)
        XCTAssertNotNil(session.nextMessage())
        XCTAssertTrue(session.isInSync)

        session.setDesired(documentID: nil, markdown: "", theme: .light, formattingBar: .hidden)
        XCTAssertNil(session.nextMessage())
        XCTAssertFalse(session.isInSync)
        XCTAssertEqual(session.deliveredDocumentID, tabA, "the editor still shows tabA")
    }

    /// And an edit for the document on screen is accepted, naming it back.
    func testEditForTheShownDocumentIsAccepted() {
        let session = readySession()
        session.setDesired(documentID: tabA, markdown: "# a", theme: .light, formattingBar: .hidden)
        XCTAssertNotNil(session.nextMessage())

        XCTAssertEqual(session.recordEditorChange("# a typed", documentID: tabA.uuidString, editorRevision: 1), tabA)
        XCTAssertEqual(session.markdown, "# a typed")
    }

    /// Text changed outside the editor (the store was reloaded, or the drawer
    /// re-read the tab) is a replacement, not an initialize: the document identity
    /// is unchanged, so the editor keeps its mode and scroll position.
    func testExternalTextChangeReplacesTheDocument() {
        let session = readySession()
        session.setDesired(documentID: tabA, markdown: "# a", theme: .light, formattingBar: .hidden)
        XCTAssertNotNil(session.nextMessage())

        session.setDesired(documentID: tabA, markdown: "# a edited elsewhere", theme: .light, formattingBar: .hidden)
        XCTAssertEqual(session.nextMessage(),
                       .replaceDocument(markdown: "# a edited elsewhere", revision: 2))
    }

    /// A theme flip is its own message: re-sending the whole document would throw
    /// away the cursor and the undo stack.
    func testThemeChangeSendsOnlyTheTheme() {
        let session = readySession()
        session.setDesired(documentID: tabA, markdown: "# a", theme: .light, formattingBar: .hidden)
        XCTAssertNotNil(session.nextMessage())

        session.setDesired(documentID: tabA, markdown: "# a", theme: .dark, formattingBar: .hidden)
        XCTAssertEqual(session.nextMessage(), .setTheme(theme: "dark"))
        XCTAssertNil(session.nextMessage())
        XCTAssertTrue(session.isInSync)
    }

    /// The formatting bar is chrome, so it travels on its own message too: toggling
    /// it must not cost the cursor or the undo stack.
    func testFormattingBarIsSentAfterTheDocumentAndOnlyWhenItChanges() {
        let session = readySession()
        session.setDesired(documentID: tabA, markdown: "# a", theme: .light, formattingBar: .visible)

        // The document first: `initialize` does not carry the bar, so the reconciler
        // follows it with one message and then agrees with the editor.
        XCTAssertEqual(session.nextMessage(),
                       .initialize(markdown: "# a", theme: "light", revision: 1,
                                   documentID: tabA.uuidString))
        XCTAssertEqual(session.nextMessage(), .setFormattingBar(formattingBar: "visible"))
        XCTAssertNil(session.nextMessage())
        XCTAssertTrue(session.isInSync)

        session.setDesired(documentID: tabA, markdown: "# a", theme: .light, formattingBar: .hidden)
        XCTAssertEqual(session.nextMessage(), .setFormattingBar(formattingBar: "hidden"))
        XCTAssertNil(session.nextMessage())
    }

    /// The editor starts with the bar hidden, so the host that also wants it hidden
    /// must say nothing at all: an extra message per document would be pure traffic.
    func testAHiddenFormattingBarIsNeverAnnounced() {
        let session = readySession()
        session.setDesired(documentID: tabA, markdown: "# a", theme: .light, formattingBar: .hidden)

        XCTAssertNotNil(session.nextMessage())
        XCTAssertNil(session.nextMessage())
        XCTAssertTrue(session.isInSync)
    }

    /// A reload starts a page whose bar is hidden again, so a host that wants it
    /// shown has to say so again even though its own wish never changed.
    func testFormattingBarIsResentAfterAReload() {
        let session = readySession()
        session.setDesired(documentID: tabA, markdown: "# a", theme: .light, formattingBar: .visible)
        while session.nextMessage() != nil {}

        session.markReady()
        var messages: [NotesEditorHostMessage] = []
        while let message = session.nextMessage() { messages.append(message) }

        XCTAssertTrue(messages.contains(.setFormattingBar(formattingBar: "visible")))
    }

    /// Revisions must strictly increase: the editor drops anything at or below the
    /// revision it has already applied, so a repeated value would be ignored.
    func testRevisionsAreStrictlyIncreasingAcrossMessages() {
        let session = readySession()
        session.setDesired(documentID: tabA, markdown: "# a", theme: .light, formattingBar: .hidden)
        var revisions: [Int] = []
        if case let .initialize(_, _, revision, _)? = session.nextMessage() { revisions.append(revision) }

        session.setDesired(documentID: tabA, markdown: "# b", theme: .light, formattingBar: .hidden)
        if case let .replaceDocument(_, revision)? = session.nextMessage() { revisions.append(revision) }

        session.setDesired(documentID: tabB, markdown: "# c", theme: .light, formattingBar: .hidden)
        if case let .initialize(_, _, revision, _)? = session.nextMessage() { revisions.append(revision) }

        XCTAssertEqual(revisions, revisions.sorted())
        XCTAssertEqual(Set(revisions).count, revisions.count, "a repeated revision is dropped by the editor")
    }

    /// A fresh page (a reload, or a crash recovery) holds no document and restarts
    /// the editor's edit counter, so the session must forget both: otherwise the
    /// host would leave the reloaded editor blank, and reject every edit it did make
    /// for numbering lower than the previous page's edits.
    func testReadyAfterAReloadResendsTheDocumentAndAcceptsNewEdits() {
        let session = readySession()
        session.setDesired(documentID: tabA, markdown: "# a", theme: .light, formattingBar: .hidden)
        XCTAssertNotNil(session.nextMessage())
        XCTAssertEqual(session.recordEditorChange("# a v5", documentID: tabA.uuidString,
                                                  editorRevision: 5), tabA)

        // The page reloads: the editor announces itself again, then the host updates
        // the view exactly as it did before.
        session.markReady()
        session.setDesired(documentID: tabA, markdown: "# a v5", theme: .light, formattingBar: .hidden)
        XCTAssertEqual(session.nextMessage(),
                       .initialize(markdown: "# a v5", theme: "light", revision: 2,
                                   documentID: tabA.uuidString),
                       "a reloaded page needs the document again")

        // Its counter starts over, so a low revision from the new page is valid.
        XCTAssertEqual(session.recordEditorChange("# a v1 after reload",
                                                  documentID: tabA.uuidString,
                                                  editorRevision: 1), tabA)
    }

    func testFlushIsOnlyOfferedOnceReady() {
        let session = NotesEditorHostSession()
        XCTAssertNil(session.flushMessage(), "nothing can be asked of a page that has not loaded")

        session.markReady()
        XCTAssertEqual(session.flushMessage(), .flush)
    }

    func testHostChangeRecordsTheTextAndSendsIt() {
        let session = readySession()
        session.setDesired(documentID: tabA, markdown: "# a", theme: .light, formattingBar: .hidden)
        XCTAssertNotNil(session.nextMessage())

        session.recordHostChange("# from disk")
        XCTAssertEqual(session.markdown, "# from disk")
        session.setDesired(documentID: tabA, markdown: "# from disk", theme: .light, formattingBar: .hidden)
        XCTAssertEqual(session.nextMessage(), .replaceDocument(markdown: "# from disk", revision: 2))
    }

    func testThemeMapsFromAppearance() {
        XCTAssertEqual(NotesEditorTheme(isDark: true), .dark)
        XCTAssertEqual(NotesEditorTheme(isDark: false), .light)
    }
}
