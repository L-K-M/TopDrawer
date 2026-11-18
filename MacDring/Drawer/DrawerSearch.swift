import Foundation

/// Pure helpers for the drawer's **type-to-find**: filtering items by a query and
/// moving the keyboard selection. Kept free of AppKit/state so it's unit-testable;
/// `DrawerModel` holds the query (bound to the drawer's filter field) and
/// `TabController`'s key monitor drives result navigation (Up/Down/Return/Esc).
enum DrawerSearch {

    /// Show the search bar (and capture type-to-find keystrokes) only once a drawer
    /// has at least this many items — below it, search is just clutter.
    static let minItemsToShow = 5

    /// Items whose name matches `query` (case- and diacritic-insensitive substring),
    /// ranked **prefix matches first**, then by grid slot. An empty/whitespace query
    /// returns all items in slot order.
    static func filter(_ items: [DrawerItem], query: String) -> [DrawerItem] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return items.sorted { $0.slot < $1.slot } }
        let needle = fold(trimmed)
        let matches: [(item: DrawerItem, isPrefix: Bool)] = items.compactMap { item in
            let name = fold(item.displayName)
            guard let range = name.range(of: needle) else { return nil }
            return (item, range.lowerBound == name.startIndex)
        }
        return matches.sorted { lhs, rhs in
            if lhs.isPrefix != rhs.isPrefix { return lhs.isPrefix }   // prefix matches first
            return lhs.item.slot < rhs.item.slot
        }.map(\.item)
    }

    /// The next selected index for an arrow press, clamped to `[0, count)` (no wrap).
    /// `nil` when there are no results. A `nil` current selection starts at the top
    /// (Down) or bottom (Up).
    static func nextIndex(count: Int, current: Int?, down: Bool) -> Int? {
        guard count > 0 else { return nil }
        guard let current, current >= 0 else { return down ? 0 : count - 1 }
        return min(max(current + (down ? 1 : -1), 0), count - 1)
    }

    /// Whether a keystroke's text should extend the query — printable characters
    /// (letters, digits, punctuation, space), not control keys (Tab, arrows, …).
    static func isFilterText(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        return text.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
    }

    /// The text a keystroke that reached the drawer *outside* the filter field adds to
    /// type-to-find, or `nil` when the key should keep its usual meaning. Shortcuts
    /// (⌘/⌃/⌥), control keys, and AppKit's function-key characters (arrows, Home,
    /// F-keys — private-use scalars, not control characters) never type, and a
    /// leading space never starts a query because Space is Quick Look.
    static func typeToFindText(_ characters: String?, hasShortcutModifier: Bool,
                               isSearching: Bool) -> String? {
        guard !hasShortcutModifier, let characters, isFilterText(characters),
              !characters.unicodeScalars.contains(where: { functionKeyCharacters.contains($0.value) })
        else { return nil }
        if !isSearching, characters.first?.isWhitespace == true { return nil }
        return characters
    }

    /// `NSUpArrowFunctionKey` through the end of AppKit's function-key range.
    private static let functionKeyCharacters: ClosedRange<UInt32> = 0xF700...0xF8FF

    private static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}
