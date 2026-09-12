#if os(macOS)
import SwiftUI

/// The notes tab's body: the bundled web editor wired to the drawer's model.
///
/// It exists to keep `DrawerView` out of the bridge's details — the model's notes,
/// callbacks and flush hook are plumbed here, and the colour scheme comes from the
/// SwiftUI environment rather than AppKit appearance plumbing.
struct NotesEditorPane: View {

    @ObservedObject var model: DrawerModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NotesEditorWebView(
            documentID: model.documentID,
            markdown: model.notes,
            theme: NotesEditorTheme(isDark: colorScheme == .dark),
            onChanged: { text, documentID in
                // Mirror first, persist second: `model.notes` is this view's own input
                // on the next update pass, so an un-mirrored edit comes straight back
                // at the editor as a replacement (see `DrawerModel.recordNotesEdit`).
                model.recordNotesEdit(text, forDocument: documentID)
                model.onNotesChanged?(text, documentID)
            },
            onOpenLink: { model.onOpenNoteLink?($0) },
            registerFlush: { handler in model.requestNotesFlush = handler }
        )
    }
}
#endif
