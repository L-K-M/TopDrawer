#if os(macOS)
import SwiftUI

/// Selects the native editor on macOS 14+, retaining the web editor on Ventura.
struct NotesEditorPane: View {

    @ObservedObject var model: DrawerModel
    @ObservedObject var preferences: Preferences
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if #available(macOS 14, *), let documentID = model.documentID {
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
        } else {
            webEditor
        }
    }

    private var webEditor: some View {
        NotesEditorWebView(
            documentID: model.documentID,
            markdown: model.notes,
            theme: NotesEditorTheme(isDark: colorScheme == .dark),
            formattingBar: NotesEditorFormattingBar(isVisible: preferences.notesFormattingBarVisible),
            // One call, because mirroring and persisting have to stay together:
            // `model.notes` is this view's own input on the next update pass, so an
            // edit that is only persisted comes straight back at the editor as a
            // replacement (see `DrawerModel.handleNotesEdit`).
            onChanged: { text, documentID in model.handleNotesEdit(text, forDocument: documentID) },
            onOpenLink: { model.onOpenNoteLink?($0) },
            registerFlush: { handler in model.requestNotesFlush = handler }
        )
    }
}
#endif
