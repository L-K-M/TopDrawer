import Foundation

/// Where a tab lives: a *stable display identity*, an *edge*, and a *fractional
/// position* along that edge. Storing a fraction (not raw pixels) keyed by a
/// durable display UUID is what lets a tab return to the same spot after a
/// restart, a resolution change, or a monitor reconnection. See PLAN.md §6.
struct ScreenAnchor: Codable, Equatable {

    /// `CGDisplayCreateUUIDFromDisplayID` string — stable across reboots and
    /// reconnections for the same physical display.
    var displayUUID: String

    /// Which edge of the display the tab is flush against.
    var edge: Edge

    /// Position along the edge, in `0…1`. For left/right edges `0` is the top and
    /// `1` is the bottom; for top/bottom edges `0` is leading (left) and `1` is
    /// trailing (right). Measured against the screen's `visibleFrame`.
    var position: Double

    /// Tie-break / stack order for tabs that share the same edge on a display.
    var order: Int {
        didSet {
            let bounded = PersistedLayoutBounds.clampedOrder(order)
            if order != bounded { order = bounded }
        }
    }

    init(displayUUID: String, edge: Edge, position: Double, order: Int = 0) {
        self.displayUUID = displayUUID
        self.edge = edge
        self.position = ScreenAnchor.clampPosition(position)
        self.order = PersistedLayoutBounds.clampedOrder(order)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        displayUUID = try c.decode(String.self, forKey: .displayUUID)
        edge = try c.decode(Edge.self, forKey: .edge)
        position = ScreenAnchor.clampPosition(try c.decode(Double.self, forKey: .position))
        order = PersistedLayoutBounds.clampedOrder(try c.decodeIfPresent(Int.self, forKey: .order) ?? 0)
    }

    private enum CodingKeys: String, CodingKey { case displayUUID, edge, position, order }

    /// Clamps a fractional position into `0…1`, mapping non-finite values
    /// (from corrupted storage) to the mid-point.
    static func clampPosition(_ value: Double) -> Double {
        guard value.isFinite else { return 0.5 }
        return Swift.min(Swift.max(value, 0), 1)
    }
}
