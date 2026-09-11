import Foundation

/// Host-side state for one notes editor: which document the editor is showing,
/// which revision was last sent, and what the host believes the text to be.
///
/// It is a reconciler, not a queue. The drawer's model is invalidated constantly
/// by unrelated events (a screen or preference change, another tab's mutation,
/// a running-app list update — see BACKLOG.md B7), so the view re-evaluates the
/// editor's inputs many times per second while the user types. Sending a
/// document on every one of those evaluations would reset the cursor and the
/// undo history, which is the failure this type exists to prevent: it emits a
/// message only when the editor is actually out of step with the host.
///
/// Pure Foundation, so both CI jobs test it.
final class NotesEditorHostSession {

    /// What the host wants the editor to show.
    private var desiredDocumentID: UUID?
    private var desiredMarkdown = ""
    private var desiredTheme = NotesEditorTheme.light.rawValue

    /// What the host has successfully asked the editor to show. An editor
    /// callback (`changed`) updates these too, because then the editor is the
    /// source of truth for the text.
    private(set) var deliveredDocumentID: UUID?
    private var deliveredMarkdown = ""
    private var deliveredTheme: String?

    private var revision = 0

    /// True once the page has announced itself. Nothing is sent before that:
    /// `window.topdrawerEditor` does not exist until the bundle has run, and a
    /// message sent too early is lost rather than queued by WebKit.
    private(set) var isReady = false

    /// The last markdown the host knows about, whether it came from the store or
    /// from the editor. The drawer's persistence callback mirrors this.
    private(set) var markdown = ""

    /// Whether the editor is showing the document the host last asked for.
    var isInSync: Bool {
        isReady && deliveredDocumentID == desiredDocumentID && deliveredMarkdown == desiredMarkdown
            && deliveredTheme == desiredTheme
    }

    // MARK: Host-side input

    /// Records what the drawer wants shown. Call it on every view update; it is
    /// cheap and idempotent.
    func setDesired(documentID: UUID?, markdown: String, theme: NotesEditorTheme) {
        desiredDocumentID = documentID
        desiredMarkdown = markdown
        desiredTheme = theme.rawValue
    }

    /// The page is up: the next `nextMessage()` may send the document.
    func markReady() {
        isReady = true
    }

    /// The editor reported an edit of the document it named.
    ///
    /// Returns the document the edit belongs to, or `nil` when it names one the
    /// host is no longer showing — an edit can land after the drawer moved to
    /// another tab, and applying it to whatever is open then would write one
    /// note's text into another. The caller reports the rejection.
    @discardableResult
    func recordEditorChange(_ markdown: String, documentID: String) -> UUID? {
        guard let deliveredDocumentID,
              documentID == deliveredDocumentID.uuidString else { return nil }
        acceptEditorChange(markdown)
        return deliveredDocumentID
    }

    /// The host changed the text itself (not via the editor), e.g. the store was
    /// reloaded from disk.
    func recordHostChange(_ markdown: String) {
        self.markdown = markdown
        desiredMarkdown = markdown
    }

    private func acceptEditorChange(_ markdown: String) {
        self.markdown = markdown
        desiredMarkdown = markdown
        deliveredMarkdown = markdown
    }

    // MARK: Output

    /// The one message needed to bring the editor in line with the host, or `nil`
    /// when they already agree. Everything queued is delivered in one pass by
    /// calling this until it returns `nil`.
    func nextMessage() -> NotesEditorHostMessage? {
        guard isReady else { return nil }

        if deliveredDocumentID != desiredDocumentID {
            revision += 1
            deliveredDocumentID = desiredDocumentID
            deliveredMarkdown = desiredMarkdown
            deliveredTheme = desiredTheme
            markdown = desiredMarkdown
            // A document switch always carries an identity: the editor echoes it on
            // every change, and an unidentified change is refused on the way back.
            guard let documentID = desiredDocumentID?.uuidString else { return nil }
            return .initialize(markdown: desiredMarkdown, theme: desiredTheme, revision: revision,
                               documentID: documentID)
        }

        if deliveredMarkdown != desiredMarkdown {
            revision += 1
            deliveredMarkdown = desiredMarkdown
            markdown = desiredMarkdown
            return .replaceDocument(markdown: desiredMarkdown, revision: revision)
        }

        if deliveredTheme != desiredTheme {
            deliveredTheme = desiredTheme
            return .setTheme(theme: desiredTheme)
        }

        return nil
    }

    /// Asks the editor to report any pending edit now, for the drawer-close and
    /// termination paths. Deliberately not tracked as delivered state: the reply
    /// arrives as a `changed` event like any other edit.
    func flushMessage() -> NotesEditorHostMessage? {
        isReady ? .flush : nil
    }
}

/// The editor's light/dark setting. The app's appearance maps onto this.
enum NotesEditorTheme: String {
    case light
    case dark

    /// Maps SwiftUI's colour scheme (or `NSAppearance`) onto the editor's theme.
    init(isDark: Bool) {
        self = isDark ? .dark : .light
    }
}
