import Foundation

/// The curated colors offered as one-click swatches wherever a tab or icon color
/// is chosen. They are the macOS system accent hues as they render in dark mode,
/// so tabs picked from here sit well together and beside the system UI; the color
/// well next to the swatches still allows any other color.
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

    /// The swatch `hex` names, if any. Case and a missing `#` are ignored, since
    /// hand-edited and older layouts store colors in either form.
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
