import SwiftUI

/// Clipboard entries copy text through the controller; they never launch URLs.
struct ClipboardHistoryView: View {
    @ObservedObject var model: DrawerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let error = model.clipboardError {
                Text(error).font(.callout).foregroundStyle(.red)
            }
            if let error = model.clipboardPersistenceError {
                Text(error).font(.callout).foregroundStyle(.red)
            }
            // One search per render: the empty check and the rows share it.
            let results = model.clipboardSearchResults
            ScrollViewReader { proxy in
                ScrollView {
                    if model.clipboardEntries.isEmpty {
                        Text("Copy text in any app to add it here.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity).padding(.vertical, 22)
                    } else if results.isEmpty {
                        Text("No matching clipboard entries.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity).padding(.vertical, 22)
                    } else {
                        LazyVStack(spacing: 4) {
                            ForEach(results) { result in
                                row(result).id(result.id)
                            }
                        }
                    }
                }
                .onChange(of: model.selectedItemID) { id in
                    if let id { proxy.scrollTo(id, anchor: .center) }
                }
            }
            Text("Click to copy, then paste with ⌘V.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func row(_ result: ClipboardEntry.SearchResult) -> some View {
        let entry = result.entry
        let excerpt = result.excerpt
        let selected = model.selectedItemID == entry.id
        return Button { model.onCopyClipboardEntry?(entry.id) } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "doc.on.clipboard").foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    (Text(verbatim: excerpt.leading)
                     + Text(verbatim: excerpt.matched).bold()
                         .foregroundStyle(selected ? Color.primary : Color.accentColor)
                     + Text(verbatim: excerpt.trailing))
                        .font(.callout).lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(entry.date, style: .relative)
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: 8)
                .fill(selected ? Color.accentColor.opacity(0.30) : Color.primary.opacity(0.06)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Copy \(excerpt.text)")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .help("Copy to clipboard")
        .contextMenu {
            Button("Copy") { model.onCopyClipboardEntry?(entry.id) }
            Button("Remove", role: .destructive) { model.onRemoveClipboardEntry?(entry.id) }
        }
    }
}
