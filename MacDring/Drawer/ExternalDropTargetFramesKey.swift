import SwiftUI

/// Collects the displayed targets' frames for the AppKit file-drop destination.
struct ExternalDropTargetFramesKey: PreferenceKey {
    static var defaultValue: [ExternalDropTarget: CGRect] = [:]

    static func reduce(value: inout [ExternalDropTarget: CGRect],
                       nextValue: () -> [ExternalDropTarget: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}
