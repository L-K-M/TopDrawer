import AppKit
import SwiftUI

struct FolderBrowserView: View {
    let folder: DrawerItem
    @ObservedObject var model: FolderBrowserModel
    let onLaunch: (DrawerItem) -> Void
    let onReveal: (DrawerItem) -> Void
    let onPreview: (DrawerItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(folder.displayName).font(.headline).lineLimit(1)
                Spacer()
                Button("Open in Finder") { onLaunch(folder) }
            }
            Divider()
            if model.isLoading {
                ProgressView().frame(maxWidth: .infinity)
            } else if let error = model.error {
                Text(error).foregroundStyle(.secondary)
                Button("Try Again") { model.load(folder) }
            } else if model.items.isEmpty {
                Text("This folder is empty.").foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(model.items) { item in
                            ItemView(item: item, iconSize: 24, layout: .list, listColumns: 1,
                                     launchOnSingleClick: true,
                                     onLaunch: { onLaunch(item) }, onReveal: { onReveal(item) },
                                     onPreview: item.kind == .file || item.kind == .folder ? { onPreview(item) } : nil)
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
