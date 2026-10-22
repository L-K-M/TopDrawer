#if os(macOS)
import SwiftUI

/// Wires the native Markdown editor to the drawer's persistence callbacks.
struct NotesEditorPane: View {

    @ObservedObject var model: DrawerModel
    @ObservedObject var preferences: Preferences

    var body: some View {
        if let documentID = model.documentID {
            NotesEditorNativeView(
                documentID: documentID,
                markdown: model.notes,
                formattingBar: NotesEditorFormattingBar(isVisible: preferences.notesFormattingBarVisible),
                onChanged: { text, id in model.handleNotesEdit(text, forDocument: id) },
                onOpenLink: { model.onOpenNoteLink?($0) },
                registerFlush: { handler in
                    // An outgoing editor must not unregister the incoming note's hook.
                    guard model.documentID == documentID || model.kind != .notes else { return }
                    model.requestNotesFlush = handler
                }
            )
            .id(documentID)
        }
    }
}
#endif
