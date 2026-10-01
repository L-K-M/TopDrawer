import AppKit

/// AppKit handles sit above the web view; the rest of the overlay passes clicks through.
final class NotesDrawerResizeView: NSView {
    enum Event {
        case began(NotesDrawerResize.Handle, CGPoint)
        case dragged(CGPoint)
        case ended(CGPoint)
    }

    var onEvent: ((Event) -> Void)?
    var edge: Edge = .right {
        didSet { needsLayout = true }
    }

    private static let cornerExtent: CGFloat = 16
    private var handles: [HandleView] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        for handle in NotesDrawerResize.Handle.allCases {
            let view = HandleView(handle: handle)
            view.onEvent = { [weak self] event in self?.onEvent?(event) }
            handles.append(view)
            addSubview(view)
        }
    }

    required init?(coder: NSCoder) { return nil }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }

    override func layout() {
        super.layout()
        let available = NotesDrawerResize.handles(for: edge)
        let inset = DrawerMetrics.notesResizeInset
        let corner = Self.cornerExtent
        let width = bounds.width
        let height = bounds.height

        for view in handles {
            view.isHidden = !available.contains(view.handle)
            switch view.handle {
            case .left: view.frame = CGRect(x: 0, y: corner, width: inset, height: max(0, height - 2 * corner))
            case .right: view.frame = CGRect(x: width - inset, y: corner, width: inset, height: max(0, height - 2 * corner))
            case .top: view.frame = CGRect(x: corner, y: height - inset, width: max(0, width - 2 * corner), height: inset)
            case .bottom: view.frame = CGRect(x: corner, y: 0, width: max(0, width - 2 * corner), height: inset)
            case .topLeft: view.frame = CGRect(x: 0, y: height - corner, width: corner, height: corner)
            case .topRight: view.frame = CGRect(x: width - corner, y: height - corner, width: corner, height: corner)
            case .bottomLeft: view.frame = CGRect(x: 0, y: 0, width: corner, height: corner)
            case .bottomRight: view.frame = CGRect(x: width - corner, y: 0, width: corner, height: corner)
            }
        }
        window?.invalidateCursorRects(for: self)
    }

    private final class HandleView: NSView {
        let handle: NotesDrawerResize.Handle
        var onEvent: ((Event) -> Void)?
        private var hoverTracking: NSTrackingArea?
        private var isHovered = false

        init(handle: NotesDrawerResize.Handle) {
            self.handle = handle
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { return nil }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override var needsPanelToBecomeKey: Bool { false }

        override func mouseDown(with event: NSEvent) {
            onEvent?(.began(handle, NSEvent.mouseLocation))
        }

        override func mouseDragged(with event: NSEvent) {
            onEvent?(.dragged(NSEvent.mouseLocation))
        }

        override func mouseUp(with event: NSEvent) {
            onEvent?(.ended(NSEvent.mouseLocation))
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let hoverTracking { removeTrackingArea(hoverTracking) }
            let tracking = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                           owner: self, userInfo: nil)
            addTrackingArea(tracking)
            hoverTracking = tracking
        }

        override func mouseEntered(with event: NSEvent) {
            isHovered = true
            needsDisplay = true
        }

        override func mouseExited(with event: NSEvent) {
            isHovered = false
            needsDisplay = true
        }

        override func resetCursorRects() {
            let cursor: NSCursor
            switch handle {
            case .left, .right: cursor = .resizeLeftRight
            case .top, .bottom: cursor = .resizeUpDown
            case .topRight, .bottomLeft: cursor = Self.ascendingCursor
            case .topLeft, .bottomRight: cursor = Self.descendingCursor
            }
            addCursorRect(bounds, cursor: cursor)
        }

        override func draw(_ dirtyRect: NSRect) {
            NSColor.secondaryLabelColor.withAlphaComponent(isHovered ? 0.9 : 0.45).setStroke()
            let path = NSBezierPath()
            path.lineWidth = 1.5
            path.lineCapStyle = .round

            switch handle {
            case .left, .right:
                path.move(to: CGPoint(x: bounds.midX, y: bounds.midY - 14))
                path.line(to: CGPoint(x: bounds.midX, y: bounds.midY + 14))
            case .top, .bottom:
                path.move(to: CGPoint(x: bounds.midX - 14, y: bounds.midY))
                path.line(to: CGPoint(x: bounds.midX + 14, y: bounds.midY))
            case .topLeft, .bottomRight:
                path.move(to: CGPoint(x: bounds.midX - 3, y: bounds.midY - 3))
                path.line(to: CGPoint(x: bounds.midX + 3, y: bounds.midY + 3))
            case .topRight, .bottomLeft:
                path.move(to: CGPoint(x: bounds.midX - 3, y: bounds.midY + 3))
                path.line(to: CGPoint(x: bounds.midX + 3, y: bounds.midY - 3))
            }
            path.stroke()
        }

        private enum Diagonal { case ascending, descending }
        private static let ascendingCursor = diagonalCursor(.ascending)
        private static let descendingCursor = diagonalCursor(.descending)

        /// AppKit has no diagonal resize cursor on the minimum supported macOS.
        private static func diagonalCursor(_ diagonal: Diagonal) -> NSCursor {
            let size: CGFloat = 18
            let image = NSImage(size: CGSize(width: size, height: size), flipped: false) { _ in
                func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                    CGPoint(x: x, y: diagonal == .ascending ? y : size - y)
                }
                let path = NSBezierPath()
                path.move(to: point(4, 9))
                path.line(to: point(4, 4))
                path.line(to: point(9, 4))
                path.move(to: point(4, 4))
                path.line(to: point(14, 14))
                path.move(to: point(9, 14))
                path.line(to: point(14, 14))
                path.line(to: point(14, 9))
                NSColor.white.setStroke()
                path.lineWidth = 3
                path.stroke()
                NSColor.black.setStroke()
                path.lineWidth = 1.5
                path.stroke()
                return true
            }
            return NSCursor(image: image, hotSpot: CGPoint(x: size / 2, y: size / 2))
        }
    }
}
