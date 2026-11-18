import Foundation
#if canImport(Combine)
import Combine
#endif

/// A pop-up's listing is transient; late disk replies cannot revive a closed browser.
final class FolderBrowserModel: ObservableObject {
    typealias Listing = (items: [DrawerItem], truncated: Bool)
    typealias Loader = (DrawerItem) throws -> Listing
    @Published private(set) var items: [DrawerItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    @Published private(set) var truncated = false
    /// The folders opened in this pop-up, outermost first. The last one is listed;
    /// opening a subfolder pushes it and Back pops it, so the pop-up browses the
    /// tree in place instead of handing every subfolder to Finder.
    @Published private(set) var path: [DrawerItem] = []
    private var generation = UUID()
    private let listing: Loader

    init(listing: Loader? = nil) {
        self.listing = listing ?? Self.readFolder
    }

    private static func readFolder(_ item: DrawerItem) throws -> Listing {
        guard item.kind == .folder, let url = BookmarkResolver.url(for: item), url.isFileURL else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        return try FolderLister.listing(at: url)
    }

    /// The folder currently listed.
    var current: DrawerItem? { path.last }
    var canGoBack: Bool { path.count > 1 }

    /// Starts browsing at `item`, forgetting any folders opened before.
    func load(_ item: DrawerItem) {
        path = [item]
        read(item)
    }

    /// Lists `folder` (an entry of the current listing) in place.
    func open(_ folder: DrawerItem) {
        guard folder.kind == .folder else { return }
        path.append(folder)
        read(folder)
    }

    /// Returns to the enclosing folder.
    func goBack() {
        guard canGoBack else { return }
        path.removeLast()
        if let current { read(current) }
    }

    /// Reads the current folder again (Try Again after an error).
    func reload() {
        if let current { read(current) }
    }

    private func read(_ item: DrawerItem) {
        let generation = UUID()
        self.generation = generation
        items = []
        error = nil
        truncated = false
        isLoading = true
        let listing = listing
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { try listing(item) }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == generation else { return }
                self.isLoading = false
                switch result {
                case .success(let listing):
                    self.items = listing.items
                    self.truncated = listing.truncated
                case .failure(let error):
                    self.error = "Couldn't read this folder: \(error.localizedDescription)"
                }
            }
        }
    }

    func cancel() {
        generation = UUID()
        isLoading = false
        items = []
    }
}
