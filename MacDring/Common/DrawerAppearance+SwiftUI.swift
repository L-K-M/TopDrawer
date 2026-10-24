import AppKit
import SwiftUI

extension DrawerAppearance.FontWeight {
    var swiftUIWeight: Font.Weight {
        switch self {
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        }
    }

    var appKitWeight: NSFont.Weight {
        switch self {
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        }
    }
}

extension DrawerAppearance {
    func translucency(following global: DrawerTranslucency) -> DrawerTranslucency {
        switch preset {
        case .system: return global
        case .glass: return .translucent
        case .flat, .highContrast: return .solid
        }
    }

    func cornerRadius(following global: Double) -> CGFloat {
        switch preset {
        case .system: return CGFloat(global)
        case .glass: return 14
        case .flat: return 0
        case .highContrast: return 4
        }
    }

    func tabStyle(following global: TabStyle) -> TabStyle {
        preset == .system ? global : .modern
    }
}
