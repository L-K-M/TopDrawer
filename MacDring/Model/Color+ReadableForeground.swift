import SwiftUI

extension Color {
    /// A legible foreground (near-black or near-white) for text drawn on top of
    /// this color, chosen from its perceived luminance. Used by classic tabs,
    /// whose fill is the tab's own color rather than a dark translucency.
    var readableForeground: Color {
        let c = NSColor(self).usingColorSpace(.sRGB) ?? .white
        let luma = 0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent
        return luma > 0.62 ? Color.black.opacity(0.82) : .white
    }
}
