import AppKit
import SwiftUI

struct FolderBrowserView: View {
    let folder: DrawerItem
    @ObservedObject var model: FolderBrowserModel
    let onLaunch: (DrawerItem) -> Void
    let onReveal: (DrawerItem) -> Void
    let onPreview: (DrawerItem) -> Void

    /// The folder being listed: the one browsed into, else the drawer's folder item.
    private var shownFolder: DrawerItem { model.current ?? folder }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                if model.canGoBack {
                    Button { model.goBack() } label: { Image(systemName: "chevron.backward") }
                        .buttonStyle(.borderless)
                        .help("Back to \(model.path.dropLast().last?.displayName ?? "the enclosing folder")")
                        .accessibilityLabel("Back")
                }
                Text(shownFolder.displayName).font(.headline).lineLimit(1).truncationMode(.middle)
                Spacer()
                Button("Open in Finder") { onLaunch(shownFolder) }
            }
            Divider()
            if model.isLoading {
                ProgressView().frame(maxWidth: .infinity)
            } else if let error = model.error {
                Text(error).foregroundStyle(.secondary)
                Button("Try Again") { model.reload() }
            } else if model.items.isEmpty {
                Text("This folder is empty.").foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(model.items) { item in
                            // A subfolder opens in place; its context menu still offers Finder.
                            ItemView(item: item, iconSize: 24, layout: .list, listColumns: 1,
                                     launchOnSingleClick: true,
                                     onLaunch: { item.kind == .folder ? model.open(item) : onLaunch(item) },
                                     onReveal: { onReveal(item) },
                                     onPreview: item.kind == .file || item.kind == .folder ? { onPreview(item) } : nil,
                                     onLaunchExternally: item.kind == .folder ? { onLaunch(item) } : nil)
                                .padding(.vertical, 3)
                        }
                    }
                }
                if model.truncated {
                    Text("Showing the first \(FolderLister.limit) items. Open in Finder to see all.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(width: 400)
        .frame(minHeight: 90, maxHeight: 380)
        .onAppear { model.load(folder) }
        .onDisappear { model.cancel() }
    }
}
