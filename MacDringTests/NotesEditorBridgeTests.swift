import XCTest
@testable import MacDring

/// The bridge is the part of the notes-editor integration that can be verified
/// without a web view, so it carries the protocol's guarantees: the message
/// shapes, and that a note's text cannot escape its JavaScript string literal.
final class NotesEditorBridgeTests: XCTestCase {

    // MARK: Host -> editor

    func testInitializeCarriesTheDocumentThemeAndRevision() {
        let message = NotesEditorHostMessage.initialize(markdown: "# Hi", theme: "dark", revision: 3, documentID: "note-1")
        let object = message.jsonObject

        XCTAssertEqual(object["type"] as? String, "initialize")
        XCTAssertEqual(object["markdown"] as? String, "# Hi")
        XCTAssertEqual(object["theme"] as? String, "dark")
        XCTAssertEqual(object["revision"] as? Int, 3)
        XCTAssertEqual(object["platform"] as? String, "macos")
        XCTAssertEqual(object["documentID"] as? String, "note-1")
    }

    func testEveryMessageTypeEncodesItsDiscriminator() {
        XCTAssertEqual(NotesEditorHostMessage.replaceDocument(markdown: "x", revision: 1).jsonObject["type"] as? String, "replaceDocument")
        XCTAssertEqual(NotesEditorHostMessage.setTheme(theme: "light").jsonObject["type"] as? String, "setTheme")
        XCTAssertEqual(NotesEditorHostMessage.focus.jsonObject["type"] as? String, "focus")
        XCTAssertEqual(NotesEditorHostMessage.flush.jsonObject["type"] as? String, "flush")
        XCTAssertEqual(NotesEditorHostMessage.command(name: "toggleMode").jsonObject["type"] as? String, "command")
    }

    // MARK: The JavaScript invocation

    func testInvocationCallsTheEditorGlobalWithThePayloadAsAStringLiteral() throws {
        let invocation = try NotesEditorHostMessage.flush.javaScriptInvocation()

        XCTAssertTrue(invocation.hasPrefix("window.topdrawerEditor.handleMessage("))
        XCTAssertTrue(invocation.hasSuffix(")"))
        // The argument must be a *string literal* holding JSON, which is what the
        // page's JSON.parse expects.
        let decoded = try decodeSoleArgument(of: invocation)
        let payload = try XCTUnwrap(decoded.data(using: .utf8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: payload) as? [String: Any])
        XCTAssertEqual(object["type"] as? String, "flush")
    }

    /// A note is untrusted text as far as this encoding is concerned. Quotes,
    /// backslashes, newlines and the U+2028/U+2029 line separators must all
    /// survive inside the literal without ending it.
    func testNoteTextCannotEscapeTheStringLiteral() throws {
        let hostile = """
        "); window.topdrawerEditor = null; (" \\
        line two
        \u{2028}separator\u{2029}more
        🍼 emoji
        """
        let message = NotesEditorHostMessage.initialize(markdown: hostile, theme: "light", revision: 1, documentID: "note-1")
        let invocation = try message.javaScriptInvocation()

        // The literal decodes back to exactly the payload we meant to send …
        let decoded = try decodeSoleArgument(of: invocation)
        let payload = try XCTUnwrap(decoded.data(using: .utf8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: payload) as? [String: Any])
        XCTAssertEqual(object["markdown"] as? String, hostile)

        // … and the invocation is one line: a raw separator would let a JavaScript
        // parser read the rest as new statements.
        XCTAssertFalse(invocation.contains("\n"))
        XCTAssertFalse(invocation.contains("\u{2028}"))
        XCTAssertFalse(invocation.contains("\u{2029}"))
        XCTAssertEqual(invocation.components(separatedBy: "handleMessage(").count - 1, 1)
    }

    // MARK: Editor -> host

    func testReadyDecodesTheProtocolVersion() {
        let event = NotesEditorEvent(scriptMessageBody: ["type": "ready", "protocolVersion": 1])
        XCTAssertEqual(event, .ready(protocolVersion: 1))
    }

    func testChangedDecodesTextAndRevision() {
        let event = NotesEditorEvent(scriptMessageBody: ["type": "changed", "markdown": "# a", "editorRevision": 7, "documentID": "note-1"])
        XCTAssertEqual(event, .changed(markdown: "# a", editorRevision: 7, documentID: "note-1"))
    }

    func testOpenLinkAndFocusAndDiagnosticDecode() {
        XCTAssertEqual(NotesEditorEvent(scriptMessageBody: ["type": "openLink", "url": "https://example.com"]),
                       .openLink(url: "https://example.com"))
        XCTAssertEqual(NotesEditorEvent(scriptMessageBody: ["type": "focusChanged", "isFocused": false]),
                       .focusChanged(isFocused: false))
        XCTAssertEqual(NotesEditorEvent(scriptMessageBody: ["type": "diagnostic", "code": "bad-message"]),
                       .diagnostic(code: "bad-message", detail: nil))
    }

    /// Rejected rather than ignored: page and host ship in the same bundle, so an
    /// unknown or malformed message means they disagree and must be seen.
    func testMalformedOrUnknownMessagesAreRejected() {
        XCTAssertNil(NotesEditorEvent(scriptMessageBody: "not a dictionary"))
        XCTAssertNil(NotesEditorEvent(scriptMessageBody: [String: Any]()))
        XCTAssertNil(NotesEditorEvent(scriptMessageBody: ["type": "futureThing"]))
        XCTAssertNil(NotesEditorEvent(scriptMessageBody: ["type": "changed"]), "missing markdown")
        XCTAssertNil(
            NotesEditorEvent(scriptMessageBody: ["type": "changed", "markdown": "x", "documentID": ""]),
            "an edit with no document identity cannot be attributed"
        )
        XCTAssertNil(NotesEditorEvent(scriptMessageBody: ["type": "openLink"]), "missing url")
    }

    // MARK: Protocol constants and URLs

    func testPageURLMatchesTheSchemeHandlerContract() {
        let url = try? XCTUnwrap(NotesEditorProtocol.pageURL)
        XCTAssertEqual(url?.scheme, "topdrawer-editor")
        XCTAssertEqual(url?.host, "editor")
        XCTAssertEqual(url?.lastPathComponent, "editor.html")
        XCTAssertEqual(url?.absoluteString, "topdrawer-editor://editor/editor.html")
    }

    /// Only the web schemes may reach the user's browser; the editor refuses others
    /// itself, and the host refuses them again rather than trusting the page.
    func testOnlyWebSchemesCountAsOpenable() {
        XCTAssertTrue(NotesEditorProtocol.isWebURL(URL(string: "https://example.com")!))
        XCTAssertTrue(NotesEditorProtocol.isWebURL(URL(string: "http://example.com")!))
        XCTAssertFalse(NotesEditorProtocol.isWebURL(URL(string: "javascript:alert(1)")!))
        XCTAssertFalse(NotesEditorProtocol.isWebURL(URL(string: "file:///etc/passwd")!))
        XCTAssertFalse(NotesEditorProtocol.isWebURL(URL(string: "topdrawer-editor://editor/editor.html")!))
    }

    func testOnlyTheKnownAssetsAreServed() {
        func url(_ path: String) -> URL { URL(string: "topdrawer-editor://editor/\(path)")! }

        XCTAssertEqual(NotesEditorProtocol.assetName(for: url("editor.html")), "editor.html")
        XCTAssertEqual(NotesEditorProtocol.assetName(for: url("editor.js")), "editor.js")
        XCTAssertEqual(NotesEditorProtocol.assetName(for: url("editor.css")), "editor.css")
        // Traversal and anything not on the list is refused, however it is spelled.
        XCTAssertNil(NotesEditorProtocol.assetName(for: url("../Info.plist")))
        XCTAssertNil(NotesEditorProtocol.assetName(for: url("secret.txt")))
        XCTAssertNil(NotesEditorProtocol.assetName(for: URL(string: "https://example.com/editor.js")!))
        XCTAssertNil(NotesEditorProtocol.assetName(for: URL(string: "file:///etc/passwd")!))
    }

    // MARK: Helpers

    /// Extracts and decodes the single string literal inside `fn("…")`.
    private func decodeSoleArgument(of invocation: String) throws -> String {
        let prefix = "window.topdrawerEditor.handleMessage("
        let body = invocation.dropFirst(prefix.count).dropLast()
        let data = try XCTUnwrap(String(body).data(using: .utf8))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) as? String)
    }
}
