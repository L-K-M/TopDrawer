#if canImport(CoreGraphics)
import CoreGraphics
#else
import Foundation
#endif

/// Resizes the exposed edges while retaining the screen attachment and tab join.
enum NotesDrawerResize {
    enum Handle: CaseIterable, Equatable {
        case left, right, top, bottom
        case topLeft, topRight, bottomLeft, bottomRight

        var movesLeft: Bool { self == .left || self == .topLeft || self == .bottomLeft }
        var movesRight: Bool { self == .right || self == .topRight || self == .bottomRight }
        var movesTop: Bool { self == .top || self == .topLeft || self == .topRight }
        var movesBottom: Bool { self == .bottom || self == .bottomLeft || self == .bottomRight }
    }

    static func handles(for edge: Edge) -> [Handle] {
        Handle.allCases.filter { handle in
            switch edge {
            case .left: return !handle.movesLeft
            case .right: return !handle.movesRight
            case .top: return !handle.movesTop
            case .bottom: return !handle.movesBottom
            }
        }
    }

    /// Reserve space for the tab riding on the drawer's inward face.
    static func maximumSize(edge: Edge, tabFrame: CGRect, in visibleFrame: CGRect) -> CGSize {
        CGSize(width: max(0, visibleFrame.width - (edge.isVertical ? tabFrame.width : 0)),
               height: max(0, visibleFrame.height - (edge.isVertical ? 0 : tabFrame.height)))
    }

    static func frame(handle: Handle, initialFrame: CGRect, translation: CGSize,
                      minimumSize: CGSize, tabFrame: CGRect, edge: Edge,
                      in visibleFrame: CGRect) -> CGRect {
        guard handles(for: edge).contains(handle),
              translation.width.isFinite, translation.height.isFinite else { return initialFrame }

        let maximum = maximumSize(edge: edge, tabFrame: tabFrame, in: visibleFrame)
        let minimumWidth = min(minimumSize.width, maximum.width)
        let minimumHeight = min(minimumSize.height, maximum.height)
        var left = initialFrame.minX
        var right = initialFrame.maxX
        var bottom = initialFrame.minY
        var top = initialFrame.maxY

        // Along the edge, the opposite side stays put and the whole tab must still fit.
        if handle.movesLeft {
            let upper = min(right - minimumWidth, edge.isVertical ? right : tabFrame.minX)
            left = clamp(left + translation.width, max(visibleFrame.minX, right - maximum.width), upper)
        }
        if handle.movesRight {
            let lower = max(left + minimumWidth, edge.isVertical ? left : tabFrame.maxX)
            right = clamp(right + translation.width, lower, min(visibleFrame.maxX, left + maximum.width))
        }
        if handle.movesBottom {
            let upper = min(top - minimumHeight, edge.isVertical ? tabFrame.minY : top)
            bottom = clamp(bottom + translation.height, max(visibleFrame.minY, top - maximum.height), upper)
        }
        if handle.movesTop {
            let lower = max(bottom + minimumHeight, edge.isVertical ? tabFrame.maxY : bottom)
            top = clamp(top + translation.height, lower, min(visibleFrame.maxY, bottom + maximum.height))
        }

        return CGRect(x: left, y: bottom, width: right - left, height: top - bottom)
    }

    /// Store relative placement, so resizing a single side survives a reopen.
    static func tabPosition(edge: Edge, tabFrame: CGRect, drawerFrame: CGRect) -> Double {
        let extent = edge.isVertical ? drawerFrame.height : drawerFrame.width
        guard extent > 0 else { return 0.5 }

        let offset = edge.isVertical
            ? drawerFrame.maxY - tabFrame.midY
            : tabFrame.midX - drawerFrame.minX
        return ScreenAnchor.clampPosition(Double(offset / extent))
    }

    private static func clamp(_ value: CGFloat, _ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
        min(max(value, lower), max(lower, upper))
    }
}
