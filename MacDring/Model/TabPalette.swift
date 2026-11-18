import Foundation

/// The curated colors offered as one-click swatches wherever a tab or icon color
/// is chosen. They are the dark-mode system hues of macOS 11 to 15, the palette
/// the default tab blue (`#0A84FF`) comes from, kept fixed rather than read from
/// `NSColor` so stored colors and the swatch ring stay stable across OS updates
/// (macOS 26 shifted most system hues slightly). The color well next to the
/// swatches still allows any other color.
enum TabPalette {
    struct Swatch: Equatable {
        let name: String
        /// `#RRGGBB`, uppercase, the form `Color.hexString` produces.
        let hex: String
    }

    static let swatches: [Swatch] = [
        Swatch(name: "Red", hex: "#FF453A"),
        Swatch(name: "Orange", hex: "#FF9F0A"),
        Swatch(name: "Yellow", hex: "#FFD60A"),
        Swatch(name: "Green", hex: "#30D158"),
        Swatch(name: "Teal", hex: "#40C8E0"),
        Swatch(name: "Blue", hex: "#0A84FF"),
        Swatch(name: "Indigo", hex: "#5E5CE6"),
        Swatch(name: "Purple", hex: "#BF5AF2"),
        Swatch(name: "Pink", hex: "#FF375F"),
    ]

    /// The swatch `hex` names, if any. Case, surrounding whitespace and a missing
    /// `#` are ignored, since hand-edited and older layouts store colors that way.
    static func swatch(matching hex: String) -> Swatch? {
        let normalized = normalize(hex)
        return swatches.first { $0.hex == normalized }
    }

    private static func normalize(_ hex: String) -> String {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if !value.hasPrefix("#") { value = "#" + value }
        return value
    }
}
