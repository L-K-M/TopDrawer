#if os(macOS)
import AppKit
import SwiftUI
import XCTest
@testable import MacDring

@available(macOS 14, *)
@MainActor
final class NotesEditorNativeViewTests: XCTestCase {
    func testViewingAndFlushingPreservesMarkdownWithoutAnEdit() throws {
        let markdown = "# Note\n\n- [ ] task\n\n| A | B |\n| --- | --- |\n| 1 | 2 |\n\n"
            + "<b>literal HTML</b> ![image](https://example.com/image.png)\n"
            + "[[Name|opaque-id]]\n\nEmoji 👩🏽‍💻 and café\n"
        let record = Record(markdown: markdown)
        let (window, host) = makeEditor(record)
        defer { window.close() }
        _ = try XCTUnwrap(findTextView(in: host))

        XCTAssertTrue(record.edits.isEmpty, "Opening a note must not save a normalized copy")
        try XCTUnwrap(record.flush)()
        XCTAssertEqual(record.edits.map(\.0), [markdown])
        XCTAssertEqual(record.edits.map(\.1), [record.documentID])
    }

    func testImmediateFlushIncludesTheLastKeystrokeAndWikiLinkID() throws {
        let original = "[[Name|opaque-id]]\nHello"
        let record = Record(markdown: original)
        let (window, host) = makeEditor(record)
        defer { window.close() }
        let textView = try XCTUnwrap(findTextView(in: host))
        let end = (textView.string as NSString).length

        textView.insertText(" 👩🏽‍💻", replacementRange: NSRange(location: end, length: 0))
        // No run-loop turn: the engine's asynchronous Binding setter has not run.
        try XCTUnwrap(record.flush)()

        XCTAssertEqual(record.edits.last?.0, original + " 👩🏽‍💻")
        XCTAssertEqual(record.edits.last?.1, record.documentID)
    }

    func testRefreshAndFormattingBarKeepTheEditorAndSelection() throws {
        let record = Record(markdown: "A note with **bold** text")
        let (window, host) = makeEditor(record)
        defer { window.close() }
        let textView = try XCTUnwrap(findTextView(in: host))
        let selection = NSRange(location: 2, length: 4)
        textView.setSelectedRange(selection)

        host.rootView = content(record, formattingBar: .visible)
        host.layoutSubtreeIfNeeded()

        XCTAssertTrue(findTextView(in: host) === textView)
        XCTAssertEqual(textView.selectedRange(), selection)
        XCTAssertTrue(record.edits.isEmpty)
    }

    func testSwitchKeepsPendingEditsWithTheirOriginalDocument() throws {
        let record = Record(markdown: "First note")
        let firstID = record.documentID
        let (window, host) = makeEditor(record)
        defer { window.close() }
        let firstEditor = try XCTUnwrap(findTextView(in: host))
        firstEditor.insertText("!", replacementRange: NSRange(location: 10, length: 0))

        record.documentID = UUID()
        record.markdown = "Second note"
        host.rootView = content(record)
        host.layoutSubtreeIfNeeded()
        // A queue barrier drains the pending engine bindings without a timed sleep.
        let drained = expectation(description: "Pending editor bindings drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 2)
        host.layoutSubtreeIfNeeded()
        let secondEditor = try XCTUnwrap(findTextView(in: host))
        try XCTUnwrap(record.flush)()

        XCTAssertFalse(firstEditor === secondEditor)
        XCTAssertEqual(secondEditor.string, "Second note")
        XCTAssertEqual(record.markdown, "Second note")
        XCTAssertTrue(record.edits.contains { $0 == ("First note!", firstID) })
        XCTAssertFalse(record.edits.contains { $0.0 == "First note!" && $0.1 == record.documentID })
        XCTAssertFalse(try XCTUnwrap(secondEditor.undoManager).canUndo)
    }

    func testUndoStillReachesThePersistenceCallback() throws {
        let record = Record(markdown: "Hello")
        let (window, host) = makeEditor(record)
        defer { window.close() }
        let textView = try XCTUnwrap(findTextView(in: host))
        textView.insertText("!", replacementRange: NSRange(location: 5, length: 0))
        textView.breakUndoCoalescing()

        textView.undoManager?.undo()
        try XCTUnwrap(record.flush)()

        XCTAssertEqual(record.edits.last?.0, "Hello")
    }

    // MARK: Native host fixture

    private final class Record {
        var documentID = UUID()
        var markdown: String
        var edits: [(String, UUID)] = []
        var flush: (() -> Void)?

        init(markdown: String) { self.markdown = markdown }
    }

    private func content(_ record: Record,
                         formattingBar: NotesEditorFormattingBar = .hidden) -> AnyView {
        let documentID = record.documentID
        return AnyView(NotesEditorNativeView(
            documentID: documentID, markdown: record.markdown, formattingBar: formattingBar,
            onChanged: { text, id in
                record.edits.append((text, id))
                if id == record.documentID { record.markdown = text }
            },
            onOpenLink: { _ in XCTFail("Loading or editing a note must not open a URL") },
            registerFlush: { handler in
                guard record.documentID == documentID else { return }
                record.flush = handler
            }
        ).id(documentID))
    }

    private func makeEditor(_ record: Record) -> (NSPanel, NSHostingView<AnyView>) {
        let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 320),
                             styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: content(record))
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        return (window, host)
    }

    private func findTextView(in view: NSView) -> NSTextView? {
        if let textView = view as? NSTextView { return textView }
        return view.subviews.lazy.compactMap { self.findTextView(in: $0) }.first
    }
}
#endif
