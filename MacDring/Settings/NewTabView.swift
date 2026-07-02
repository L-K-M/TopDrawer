import SwiftUI
import AppKit

/// The settings collected by the New Tab dialog before a tab is created.
struct NewTabConfig {
    var name: String
    var colorHex: String
    var kind: TabKind
    var folderBookmark: Data?
    var folderURL: URL?
}

/// A small modal for creating a tab: set its name, color, type, and (for a folder
/// tab) the directory it mirrors.
struct NewTabView: View {
    let onCreate: (NewTabConfig) -> Void
    let onCancel: () -> Void

    @State private var name: String = ""
    @State private var colorHex: String
    @State private var kind: TabKind
    @State private var folderURL: URL?
    @State private var folderBookmark: Data?

    init(kind: TabKind,
         defaultColorHex: String,
         onCreate: @escaping (NewTabConfig) -> Void,
         onCancel: @escaping () -> Void) {
        self.onCreate = onCreate
        self.onCancel = onCancel
        _colorHex = State(initialValue: defaultColorHex)
        _kind = State(initialValue: kind)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Tab").font(.headline)

            Form {
                TextField("Name", text: $name, prompt: Text(defaultName))
                ColorPicker("Color", selection: colorBinding, supportsOpacity: false)
                Picker("Type", selection: $kind) {
                    ForEach(TabKind.allCases) { Text($0.displayName).tag($0) }
                }
                if kind == .folder {
                    LabeledContent("Directory") {
                        HStack(spacing: 8) {
                            Text(folderURL?.lastPathComponent ?? "None")
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Button("Choose…", action: chooseFolder)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Create", action: create)
                    .keyboardShortcut(.defaultAction)
                    .disabled(kind == .folder && folderURL == nil)
            }
        }
        .padding(16)
        .frame(width: 400, height: 340)
        .onChange(of: kind) { newKind in
            // Undo the folder-derived name auto-fill if the user switches the type
            // away before creating (the folder itself is dropped in `create()`).
            if newKind != .folder, name == folderURL?.lastPathComponent {
                name = ""
            }
        }
    }

    private var defaultName: String {
        switch kind {
        case .items: return "Tab"
        case .notes: return "Notes"
        case .folder: return folderURL?.lastPathComponent ?? "Folder"
        case .disks: return "Disks"
        case .network: return "Network"
        case .cloud: return "Cloud"
        case .recents: return "Recents"
        case .fresh: return "Fresh"
        }
    }

    private var colorBinding: Binding<Color> {
        Binding(get: { Color(hexString: colorHex) }, set: { colorHex = $0.hexString })
    }

    private func create() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        // A directory picked while the Type was "Folder" must not ride along when
        // the user switches to another kind before creating — a notes tab has no
        // business carrying a folder bookmark (or the folder's auto-filled name).
        let isFolder = kind == .folder
        onCreate(NewTabConfig(
            name: trimmed.isEmpty ? defaultName : trimmed,
            colorHex: colorHex,
            kind: kind,
            folderBookmark: isFolder ? folderBookmark : nil,
            folderURL: isFolder ? folderURL : nil
        ))
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder to mirror"
        if panel.runModal() == .OK, let url = panel.url {
            folderURL = url
            folderBookmark = BookmarkResolver.makeBookmark(for: url)
            if name.trimmingCharacters(in: .whitespaces).isEmpty {
                name = url.lastPathComponent
            }
        }
    }
}
