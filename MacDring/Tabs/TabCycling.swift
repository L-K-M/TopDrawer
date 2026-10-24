import Foundation

enum TabCycling {
    enum Direction { case previous, next }

    static func adjacentID(to currentID: UUID, direction: Direction,
                           in tabs: [Tab], availableIDs: Set<UUID>) -> UUID? {
        guard let current = tabs.first(where: { $0.id == currentID }) else { return nil }
        let peers = tabs.filter {
            $0.anchor.displayUUID == current.anchor.displayUUID
                && $0.anchor.edge == current.anchor.edge && availableIDs.contains($0.id)
        }.sorted {
            if $0.anchor.position != $1.anchor.position {
                return current.anchor.edge.isVertical
                    ? $0.anchor.position > $1.anchor.position : $0.anchor.position < $1.anchor.position
            }
            if $0.anchor.order != $1.anchor.order { return $0.anchor.order < $1.anchor.order }
            return $0.id.uuidString < $1.id.uuidString
        }
        guard peers.count > 1, let index = peers.firstIndex(where: { $0.id == currentID }) else { return nil }
        let step = direction == .next ? 1 : -1
        return peers[(index + step + peers.count) % peers.count].id
    }

    struct ScrollState {
        enum Source { case wheel, trackpad }
        enum Phase { case began, changed, ended, momentum }
        static let trackpadThreshold = 24.0
        static let wheelInterval: TimeInterval = 0.2

        private var accumulated = 0.0
        private var switchedInGesture = false
        private var lastWheelSwitch = -Double.infinity

        mutating func consume(delta: Double, source: Source, phase: Phase,
                              timestamp: TimeInterval) -> Direction? {
            guard delta.isFinite, timestamp.isFinite, phase != .momentum else { return nil }
            if phase == .began { accumulated = 0; switchedInGesture = false }
            if phase == .ended { accumulated = 0; switchedInGesture = false; return nil }
            if source == .wheel {
                guard delta != 0, timestamp - lastWheelSwitch >= Self.wheelInterval else { return nil }
                lastWheelSwitch = timestamp
                return delta > 0 ? .previous : .next
            }
            guard !switchedInGesture else { return nil }
            accumulated += delta
            guard abs(accumulated) >= Self.trackpadThreshold else { return nil }
            switchedInGesture = true
            return accumulated > 0 ? .previous : .next
        }
    }
}
