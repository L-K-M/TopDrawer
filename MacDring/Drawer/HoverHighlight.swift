import SwiftUI

/// A faint rounded plate behind a drawer cell or row while the pointer is over it,
/// matching the footprint of the selection and drop highlights, so pointing at an
/// item gives the same "this is live" feedback as Finder or the Dock.
///
/// The hover state lives here, per cell: moving the pointer across a large drawer
/// re-renders only the cells it leaves and enters, never the whole drawer.
struct HoverHighlight: ViewModifier {
    let cornerRadius: CGFloat
    var isEnabled = true
    var highContrast = false

    @State private var isHovered = false

    /// Strong enough to read over every backing, but quieter than the selection
    /// plate (accent at 30%) and the drop highlight (primary at 12%).
    private var opacity: Double {
        guard isHovered, isEnabled else { return 0 }
        return highContrast ? 0.18 : 0.07
    }

    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: cornerRadius).fill(Color.primary.opacity(opacity)))
            .onHover { isHovered = $0 }
    }
}

extension View {
    func hoverHighlight(cornerRadius: CGFloat, isEnabled: Bool = true, highContrast: Bool = false) -> some View {
        modifier(HoverHighlight(cornerRadius: cornerRadius, isEnabled: isEnabled, highContrast: highContrast))
    }
}
