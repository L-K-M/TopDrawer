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
        session.setDesired(documentID: tabA, markdown: "# a", theme: .light)

        XCTAssertNil(session.nextMessage())
        XCTAssertFalse(session.isInSync)

        session.markReady()
        XCTAssertEqual(session.nextMessage(), .initialize(markdown: "# a", theme: "light", revision: 1, documentID: tabA.uuidString))
    }

    /// The core invariant: re-evaluating the view with the same inputs — which the
    /// drawer does many times a second — must not re-send the document.
    func testRepeatedIdenticalUpdatesSendNothing() {
        let session = readySession()
        session.setDesired(documentID: tabA, markdown: "# a", theme: .light)
        XCTAssertNotNil(session.nextMessage())

        for _ in 0..<5 {
            session.setDesired(documentID: tabA, markdown: "# a", theme: .light)
            XCTAssertNil(session.nextMessage(), "an unrelated invalidation must not reset the editor")
        }
        XCTAssertTrue(session.isInSync)
    }

    /// The user's own edit must not be echoed back as a replacement.
    func testEditorChangeIsNotEchoedBack() {
        let session = readySession()
        session.setDesired(documentID: tabA, markdown: "# a", theme: .light)
        XCTAssertNotNil(session.nextMessage())

        session.recordEditorChange("# a typed", documentID: tabA.uuidString)
        session.setDesired(documentID: tabA, markdown: "# a typed", theme: .light)

        XCTAssertNil(session.nextMessage(), "the editor already shows what the host was told")
        XCTAssertEqual(session.markdown, "# a typed")
    }

    /// A different tab is a different document, and gets a fresh revision.
    func testSwitchingDocumentInitializesWithANewRevision() {
        let session = readySession()
        session.setDesired(documentID: tabA, markdown: "# a", theme: .light)
        XCTAssertEqual(session.nextMessage(), .initialize(markdown: "# a", theme: "light", revision: 1, documentID: tabA.uuidString))

        session.setDesired(documentID: tabB, markdown: "# b", theme: .light)
        XCTAssertEqual(session.nextMessage(), .initialize(markdown: "# b", theme: "light", revision: 2, documentID: tabB.uuidString))
    }

    /// An edit that names a document the host is no longer showing is refused, not
    /// applied to whatever is open now. This is the misattribution case: an edit can
    /// land after the drawer has moved to another tab, or after it closed (when the
    /// drawer no longer has an open tab at all).
    func testEditNamingAnotherDocumentIsRejected() {
        let session = readySession()
        session.setDesired(documentID: tabA, markdown: "# a", theme: .light)
        XCTAssertNotNil(session.nextMessage())

        XCTAssertNil(session.recordEditorChange("# text meant for another note",
                                                documentID: tabB.uuidString))
        XCTAssertEqual(session.markdown, "# a", "the other document's text must not be adopted")
        XCTAssertEqual(session.deliveredDocumentID, tabA)
    }

    /// The same, after the host has switched documents: the late reply for the old
    /// note must not be recorded as the new one's text.
    func testLateEditIsRejectedAfterSwitch() {
        let session = readySession()
        session.setDesired(documentID: tabA, markdown: "# a", theme: .light)
        XCTAssertNotNil(session.nextMessage())

        session.setDesired(documentID: tabB, markdown: "# b", theme: .light)
        XCTAssertNotNil(session.nextMessage())

        XCTAssertNil(session.recordEditorChange("# a, edited just before the switch",
                                                documentID: tabA.uuidString))
        XCTAssertEqual(session.markdown, "# b")
    }

    /// And an edit for the document on screen is accepted, naming it back.
    func testEditForTheShownDocumentIsAccepted() {
        let session = readySession()
        session.setDesired(documentID: tabA, markdown: "# a", theme: .light)
        XCTAssertNotNil(session.nextMessage())

        XCTAssertEqual(session.recordEditorChange("# a typed", documentID: tabA.uuidString), tabA)
        XCTAssertEqual(session.markdown, "# a typed")
    }

    /// Text changed outside the editor (the store was reloaded, or the drawer
    /// re-read the tab) is a replacement, not an initialize: the document identity
    /// is unchanged, so the editor keeps its mode and scroll position.
    func testExternalTextChangeReplacesTheDocument() {
        let session = readySession()
        session.setDesired(documentID: tabA, markdown: "# a", theme: .light)
        XCTAssertNotNil(session.nextMessage())

        session.setDesired(documentID: tabA, markdown: "# a edited elsewhere", theme: .light)
        XCTAssertEqual(session.nextMessage(),
                       .replaceDocument(markdown: "# a edited elsewhere", revision: 2))
    }

    /// A theme flip is its own message: re-sending the whole document would throw
    /// away the cursor and the undo stack.
    func testThemeChangeSendsOnlyTheTheme() {
        let session = readySession()
        session.setDesired(documentID: tabA, markdown: "# a", theme: .light)
        XCTAssertNotNil(session.nextMessage())

        session.setDesired(documentID: tabA, markdown: "# a", theme: .dark)
        XCTAssertEqual(session.nextMessage(), .setTheme(theme: "dark"))
        XCTAssertNil(session.nextMessage())
        XCTAssertTrue(session.isInSync)
    }

    /// Revisions must strictly increase: the editor drops anything at or below the
    /// revision it has already applied, so a repeated value would be ignored.
    func testRevisionsAreStrictlyIncreasingAcrossMessages() {
        let session = readySession()
        session.setDesired(documentID: tabA, markdown: "# a", theme: .light)
        var revisions: [Int] = []
        if case let .initialize(_, _, revision, _)? = session.nextMessage() { revisions.append(revision) }

        session.setDesired(documentID: tabA, markdown: "# b", theme: .light)
        if case let .replaceDocument(_, revision)? = session.nextMessage() { revisions.append(revision) }

        session.setDesired(documentID: tabB, markdown: "# c", theme: .light)
        if case let .initialize(_, _, revision, _)? = session.nextMessage() { revisions.append(revision) }

        XCTAssertEqual(revisions, revisions.sorted())
        XCTAssertEqual(Set(revisions).count, revisions.count, "a repeated revision is dropped by the editor")
    }

    func testFlushIsOnlyOfferedOnceReady() {
        let session = NotesEditorHostSession()
        XCTAssertNil(session.flushMessage(), "nothing can be asked of a page that has not loaded")

        session.markReady()
        XCTAssertEqual(session.flushMessage(), .flush)
    }

    func testHostChangeRecordsTheTextAndSendsIt() {
        let session = readySession()
        session.setDesired(documentID: tabA, markdown: "# a", theme: .light)
        XCTAssertNotNil(session.nextMessage())

        session.recordHostChange("# from disk")
        XCTAssertEqual(session.markdown, "# from disk")
        session.setDesired(documentID: tabA, markdown: "# from disk", theme: .light)
        XCTAssertEqual(session.nextMessage(), .replaceDocument(markdown: "# from disk", revision: 2))
    }

    func testThemeMapsFromAppearance() {
        XCTAssertEqual(NotesEditorTheme(isDark: true), .dark)
        XCTAssertEqual(NotesEditorTheme(isDark: false), .light)
    }
}
