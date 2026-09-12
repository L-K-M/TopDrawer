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
    private var desiredFormattingBar = NotesEditorFormattingBar.hidden.rawValue

    /// What the host has successfully asked the editor to show. An editor
    /// callback (`changed`) updates these too, because then the editor is the
    /// source of truth for the text.
    private(set) var deliveredDocumentID: UUID?
    private var deliveredMarkdown = ""
    private var deliveredTheme: String?
    /// Not optional, unlike the fields above: a fresh page holds no document and no
    /// theme, but it does start with the formatting bar hidden, so that is what the
    /// editor is known to be showing until told otherwise.
    private var deliveredFormattingBar = NotesEditorFormattingBar.hidden.rawValue

    /// Every document this session has sent to the editor. A `changed` naming one of
    /// these is genuine even if the drawer has since moved on — the editor reports
    /// the edit it had in flight when the switch happened, and dropping it would
    /// lose the last keystrokes of the note the user just left.
    private var deliveredDocuments: Set<UUID> = []

    /// Highest `editorRevision` accepted so far, within the current page. The
    /// editor's counter only rises for as long as a page lives, so anything at or
    /// below this is a reply that lost a race with a newer one and would otherwise
    /// revert newer text. Reset when a fresh page says `ready`, because its counter
    /// starts over — comparing across page loads would reject every later edit.
    private var lastEditorRevision = -1

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
            && deliveredTheme == desiredTheme && deliveredFormattingBar == desiredFormattingBar
    }

    // MARK: Host-side input

    /// Records what the drawer wants shown. Call it on every view update; it is
    /// cheap and idempotent.
    func setDesired(documentID: UUID?, markdown: String, theme: NotesEditorTheme,
                    formattingBar: NotesEditorFormattingBar) {
        desiredDocumentID = documentID
        desiredMarkdown = markdown
        desiredTheme = theme.rawValue
        desiredFormattingBar = formattingBar.rawValue
    }

    /// The page is up: the next `nextMessage()` may send the document.
    ///
    /// `ready` means a *fresh* page — the editor reports it once per load — so
    /// everything the session believed about the previous page is stale: it holds no
    /// document (the host must send one again, or a reload would leave the drawer
    /// blank), and its edit counter has restarted (so the monotonic gate must not
    /// compare against the old page's numbers, which would reject every edit).
    func markReady() {
        isReady = true
        deliveredDocumentID = nil
        deliveredMarkdown = ""
        deliveredTheme = nil
        deliveredFormattingBar = NotesEditorFormattingBar.hidden.rawValue
        deliveredDocuments.removeAll()
        lastEditorRevision = -1
    }

    /// The editor reported an edit, naming the document it belongs to.
    ///
    /// Returns the document the edit belongs to, or `nil` when it cannot be trusted:
    /// it names a document this session never sent, or its revision is not newer than
    /// the last one accepted. The caller reports the rejection.
    ///
    /// Only the *desired* document's text updates the host's idea of the current note;
    /// a late reply for the document being replaced is still accepted and returned, so
    /// the caller can persist it against the right note, but it must not overwrite the
    /// text the host is about to hand the editor for the new one.
    @discardableResult
    func recordEditorChange(_ markdown: String, documentID: String,
                            editorRevision: Int) -> UUID? {
        guard let document = UUID(uuidString: documentID),
              deliveredDocuments.contains(document) else { return nil }
        guard editorRevision > lastEditorRevision else { return nil }
        lastEditorRevision = editorRevision

        if document == deliveredDocumentID { deliveredMarkdown = markdown }
        if document == desiredDocumentID {
            desiredMarkdown = markdown
            self.markdown = markdown
        }
        return document
    }

    /// The host changed the text itself (not via the editor), e.g. the store was
    /// reloaded from disk.
    func recordHostChange(_ markdown: String) {
        self.markdown = markdown
        desiredMarkdown = markdown
    }

    // MARK: Output

    /// The one message needed to bring the editor in line with the host, or `nil`
    /// when they already agree. Everything queued is delivered in one pass by
    /// calling this until it returns `nil`.
    func nextMessage() -> NotesEditorHostMessage? {
        guard isReady else { return nil }

        if deliveredDocumentID != desiredDocumentID {
            // Nothing is committed until the message is certain to be sent: a nil
            // desired document (nothing to show) must leave the delivered state alone,
            // or the session would claim to be in sync while the editor still holds
            // the previous note.
            guard let document = desiredDocumentID else { return nil }
            revision += 1
            deliveredDocumentID = document
            deliveredDocuments.insert(document)
            deliveredMarkdown = desiredMarkdown
            deliveredTheme = desiredTheme
            markdown = desiredMarkdown
            return .initialize(markdown: desiredMarkdown, theme: desiredTheme, revision: revision,
                               documentID: document.uuidString)
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

        // Not folded into `initialize`: the editor's own default matches this
        // session's, so the common case sends nothing at all, and keeping the bar a
        // message of its own means a toggle costs no document round trip.
        if deliveredFormattingBar != desiredFormattingBar {
            deliveredFormattingBar = desiredFormattingBar
            return .setFormattingBar(formattingBar: desiredFormattingBar)
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

/// Whether the rich-mode formatting bar is shown. Hidden is the editor's own
/// default, so a host that never sends one gets an uncluttered drawer.
enum NotesEditorFormattingBar: String {
    case hidden
    case visible

    init(isVisible: Bool) {
        self = isVisible ? .visible : .hidden
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
