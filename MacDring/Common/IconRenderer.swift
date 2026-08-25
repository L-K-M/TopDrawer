import AppKit

/// Renders an `IconStyle` (a base shape + color + optional SF Symbol) into an
/// `NSImage`. Shared by `ItemView.resolveIcon` (the drawer/Settings icon) and the
/// icon editor's live preview, so both look identical. Pure AppKit drawing — safe to
/// call synchronously from icon resolution.
enum IconRenderer {

    /// A square icon for `style`, drawn at `pointSize` (×1; AppKit scales it for the
    /// view's backing scale).
    static func image(for style: IconStyle, pointSize: CGFloat = 128) -> NSImage {
        let fill = NSColor(hex: style.colorHex) ?? .systemBlue
        let size = NSSize(width: pointSize, height: pointSize)
        return NSImage(size: size, flipped: false) { rect in
            switch style.base {
            case .folder: drawFolder(in: rect, fill: fill, symbol: style.symbol)
            case .tile:   drawTile(in: rect, fill: fill, symbol: style.symbol)
            }
            return true
        }
    }

    // MARK: Bases

    /// A tinted `folder.fill` with the glyph embossed (in white) on the folder body.
    private static func drawFolder(in rect: NSRect, fill: NSColor, symbol: String?) {
        let folderRect = rect.insetBy(dx: rect.width * 0.06, dy: rect.height * 0.10)
        drawSymbol("folder.fill", in: folderRect, color: fill, fit: .fit)
        guard let symbol, !symbol.isEmpty else { return }
        // The folder body is the lower ~55% of the shape; center the glyph there.
        var body = rect
        body.size.height = rect.height * 0.42
        body.origin.y = rect.minY + rect.height * 0.13
        body = body.insetBy(dx: rect.width * 0.30, dy: 0)
        drawSymbol(symbol, in: body, color: .white, fit: .fit)
    }

    /// A solid rounded-square tile in the fill color with the glyph centered.
    private static func drawTile(in rect: NSRect, fill: NSColor, symbol: String?) {
        let tile = rect.insetBy(dx: rect.width * 0.07, dy: rect.height * 0.07)
        let radius = tile.width * 0.22
        let path = NSBezierPath(roundedRect: tile, xRadius: radius, yRadius: radius)
        fill.setFill()
        path.fill()
        guard let symbol, !symbol.isEmpty else { return }
        drawSymbol(symbol, in: tile.insetBy(dx: tile.width * 0.26, dy: tile.height * 0.26),
                   color: contrastingColor(on: fill), fit: .fit)
    }

    // MARK: Drawing helpers

    private enum Fit { case fit, fill }

    /// Draws an SF Symbol, tinted `color`, scaled to `fit` inside `rect` and centered.
    private static func drawSymbol(_ name: String, in rect: NSRect, color: NSColor, fit: Fit) {
        let config = NSImage.SymbolConfiguration(pointSize: max(rect.width, rect.height), weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        // Rendering goes through the IconName seam (LP-13): the stored SF name on macOS,
        // the mapped Linux-set name on a Linux renderer. On macOS this returns `name`.
        let resolved = IconName(sfSymbol: name).resolved(for: .current)
        guard let symbol = NSImage(systemSymbolName: resolved, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return }
        let s = symbol.size
        guard s.width > 0, s.height > 0 else { return }
        let scale = fit == .fit
            ? min(rect.width / s.width, rect.height / s.height)
            : max(rect.width / s.width, rect.height / s.height)
        let drawn = NSSize(width: s.width * scale, height: s.height * scale)
        let origin = NSPoint(x: rect.midX - drawn.width / 2, y: rect.midY - drawn.height / 2)
        symbol.draw(in: NSRect(origin: origin, size: drawn))
    }

    /// Black on a light fill, white on a dark one (so a centered glyph stays legible).
    private static func contrastingColor(on color: NSColor) -> NSColor {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        let luma = 0.299 * rgb.redComponent + 0.587 * rgb.greenComponent + 0.114 * rgb.blueComponent
        return luma > 0.6 ? NSColor.black.withAlphaComponent(0.85) : .white
    }
}
