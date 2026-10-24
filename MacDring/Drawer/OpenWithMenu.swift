import AppKit
import SwiftUI

/// Discover handlers only when the context menu appears, not for every grid cell.
struct OpenWithMenu: View {
    let item: DrawerItem
    let onSelect: (URL) -> Void
    @State private var applications: [ItemActionService.Application] = []
    @State private var isLoading = true

    var body: some View {
        Menu("Open With") {
            if isLoading {
                Text("Finding applications…")
            } else if applications.isEmpty {
                Text("No compatible applications found")
            } else {
                ForEach(applications) { application in
                    Button { onSelect(application.url) } label: {
                        Label {
                            Text(application.name)
                        } icon: {
                            Image(nsImage: application.icon).resizable().frame(width: 16, height: 16)
                        }
                    }
                }
            }
        }
        .task(id: item) {
            let item = item
            let result = await Task.detached(priority: .userInitiated) {
                ItemActionService.applications(for: item)
            }.value
            guard !Task.isCancelled else { return }
            applications = result
            isLoading = false
        }
    }
}
