import SwiftUI

/// Clipboard entries copy text through the controller; they never launch URLs.
struct ClipboardHistoryView: View {
    @ObservedObject var model: DrawerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let error = model.clipboardError {
                Text(error).font(.callout).foregroundStyle(.red)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    if model.clipboardEntries.isEmpty {
                        Text("Copy text in any app to add it here.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity).padding(.vertical, 22)
                    } else if model.clipboardSearchResults.isEmpty {
                        Text("No matching clipboard entries.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity).padding(.vertical, 22)
                    } else {
                        LazyVStack(spacing: 4) {
                            ForEach(model.clipboardSearchResults) { entry in
                                row(entry).id(entry.id)
                            }
                        }
                    }
                }
                .onChange(of: model.selectedItemID) { id in
                    if let id { proxy.scrollTo(id, anchor: .center) }
                }
            }
            Text("Click to copy, then paste with ⌘V. History stays in memory.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func row(_ entry: ClipboardEntry) -> some View {
        Button { model.onCopyClipboardEntry?(entry.id) } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "doc.on.clipboard").foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: entry.preview)
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
                .fill(model.selectedItemID == entry.id ? Color.accentColor.opacity(0.30) : Color.primary.opacity(0.06)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Copy \(entry.preview)")
        .help("Copy to clipboard")
        .contextMenu {
            Button("Copy") { model.onCopyClipboardEntry?(entry.id) }
            Button("Remove", role: .destructive) { model.onRemoveClipboardEntry?(entry.id) }
        }
    }
}
