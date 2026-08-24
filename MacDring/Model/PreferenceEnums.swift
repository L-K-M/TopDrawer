#if canImport(AppKit)
import AppKit
#else
import Foundation   // CGFloat lives in Foundation on Linux
#endif

/// How translucent a drawer's background is — from the system blur showing the
/// desktop through, to a frosted look, to an opaque panel. Replaces the old "material"
/// picker, whose four blur styles were nearly indistinguishable behind a drawer.
enum DrawerTranslucency: String, Codable, CaseIterable, Identifiable {
    case translucent, frosted, solid

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .translucent: return "Translucent"
        case .frosted: return "Frosted"
        case .solid: return "Solid"
        }
    }

    /// How opaque the solid backing painted over the blur is: `0` = pure blur
    /// (translucent), `1` = an opaque panel (solid), with a frosted step between.
    var backingOpacity: Double {
        switch self {
        case .translucent: return 0
        case .frosted: return 0.5
        case .solid: return 1
        }
    }
}

/// How drawer items are arranged.
enum DrawerLayout: String, Codable, CaseIterable, Identifiable {
    case grid, list
    var id: String { rawValue }
    var displayName: String { self == .grid ? "Grid" : "List" }
}

/// The visual treatment of tab pills: a sleek translucent rounded pill, or the
/// skeuomorphic angled "folder tab" reminiscent of classic DragThing.
enum TabStyle: String, Codable, CaseIterable, Identifiable {
    case modern, classic
    var id: String { rawValue }
    var displayName: String { self == .modern ? "Modern" : "Classic" }

    /// Classic renders a bit thinner than modern, as a more compact alternative.
    /// Applied to the configured tab thickness by both the window and the view so
    /// they stay in lockstep. `CGFloat` via `import CoreGraphics`/AppKit.
    var thicknessScale: CGFloat { self == .classic ? 0.82 : 1.0 }
}

/// What happens to a tab when its display is disconnected (see PLAN.md §6).
enum DisconnectPolicy: String, Codable, CaseIterable, Identifiable {
    /// Hide the tab and keep its anchor; restore it exactly when the display returns.
    case park
    /// Move the tab to the main display so it stays visible.
    case moveToMain
    var id: String { rawValue }
    var displayName: String { self == .park ? "Keep them on that display" : "Move them to the main display" }
}

/// The window level tabs float at.
enum TabWindowLevel: String, Codable, CaseIterable, Identifiable {
    case floating, normal
    var id: String { rawValue }
    var displayName: String { self == .floating ? "Always on top" : "With other windows" }

    #if canImport(AppKit)
    var nsWindowLevel: NSWindow.Level {
        self == .floating ? .floating : .normal
    }

    var drawerWindowLevel: NSWindow.Level {
        switch self {
        case .floating:
            return .popUpMenu
        case .normal:
            return NSWindow.Level(rawValue: NSWindow.Level.normal.rawValue + 1)
        }
    }
    #endif
}
