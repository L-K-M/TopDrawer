import Foundation

/// Bounds for persisted values that directly drive drawer allocation or index math.
enum PersistedLayoutBounds {
    static let gridColumns = 1...12
    static let gridRows = 1...16

    /// Ten thousand slots supports very large sparse drawers, and ten thousand stack
    /// positions far exceeds what can fit on an edge, without allowing hostile values
    /// near `Int.max` into allocation or increment arithmetic.
    static let maximumSlotOrOrder = 10_000
    static let maximumSlotCount = maximumSlotOrOrder + 1

    static func clampedGridColumns(_ value: Int) -> Int {
        clamp(value, to: gridColumns)
    }

    static func clampedGridRows(_ value: Int) -> Int {
        clamp(value, to: gridRows)
    }

    static func normalizedSlot(_ value: Int) -> Int {
        (0...maximumSlotOrOrder).contains(value) ? value : -1
    }

    static func clampedOrder(_ value: Int) -> Int {
        clamp(value, to: 0...maximumSlotOrOrder)
    }

    /// Returns the next stack order without incrementing a value at or above the cap.
    static func nextOrder(after value: Int?) -> Int {
        guard let value, value >= 0 else { return 0 }
        return value >= maximumSlotOrOrder ? maximumSlotOrOrder : value + 1
    }

    private static func clamp(_ value: Int, to range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
