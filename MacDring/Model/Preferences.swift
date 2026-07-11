import Foundation
import SwiftUI
import ServiceManagement

/// App-wide appearance and behavior settings, backed by `UserDefaults`. Per-tab
/// values (color, items, anchor, behavior) live in the tab model instead; the
/// `newTab*` values here seed a tab's defaults when it's created.
///
/// An `ObservableObject` so SwiftUI settings views update live. A custom
/// `UserDefaults` can be injected for tests.
final class Preferences: ObservableObject {

    static let shared = Preferences()

    private let defaults: UserDefaults

    // MARK: Defaults

    enum Default {
        static let drawerTranslucency = DrawerTranslucency.translucent
        static let defaultTabColorHex = "#0A84FF"
        static let iconSize = 64.0
        static let tabStyle = TabStyle.modern
        static let gridColumns = 4.0
        static let gridRows = 2.0
        static let cornerRadius = 14.0
        static let tabThickness = 36.0
        static let fadedOpacity = 0.2
        static let showTabLabels = true
        static let newTabOpenOnHover = false
        static let newTabAutoHide = true
        static let newTabConcealment = TabConcealment.never
        static let revealAllConcealedTogether = false
        static let launchOnSingleClick = true
        static let animationMs = 140.0
        static let tabWindowLevel = TabWindowLevel.floating
        static let disconnectPolicy = DisconnectPolicy.park
    }

    private enum Key {
        static let drawerTranslucency = "drawerTranslucency"
        static let defaultTabColorHex = "defaultTabColorHex"
        static let iconSize = "iconSize"
        static let tabStyle = "tabStyle"
        static let gridColumns = "gridColumns"
        static let gridRows = "gridRows"
        static let cornerRadius = "cornerRadius"
        static let tabThickness = "tabThickness"
        static let fadedOpacity = "fadedOpacity"
        static let showTabLabels = "showTabLabels"
        static let newTabOpenOnHover = "newTabOpenOnHover"
        static let newTabAutoHide = "newTabAutoHide"
        static let newTabConcealment = "newTabConcealment"
        static let revealAllConcealedTogether = "revealAllConcealedTogether"
        static let launchOnSingleClick = "launchOnSingleClick"
        static let animationMs = "animationMs"
        static let tabWindowLevel = "tabWindowLevel"
        static let disconnectPolicy = "disconnectPolicy"
        static let launchAtLogin = "launchAtLogin"
    }

    // MARK: Stored settings

    /// How translucent the drawer background is (Translucent / Frosted / Solid).
    @Published var drawerTranslucency: DrawerTranslucency {
        didSet { defaults.set(drawerTranslucency.rawValue, forKey: Key.drawerTranslucency) }
    }

    /// Color applied to newly created tabs.
    @Published var defaultTabColorHex: String {
        didSet { defaults.set(defaultTabColorHex, forKey: Key.defaultTabColorHex) }
    }

    @Published var iconSize: Double {
        didSet { defaults.set(iconSize, forKey: Key.iconSize) }
    }

    /// The visual style of tab pills (modern pill vs. classic folder tab).
    @Published var tabStyle: TabStyle {
        didSet { defaults.set(tabStyle.rawValue, forKey: Key.tabStyle) }
    }

    /// Default grid columns for new tabs.
    @Published var gridColumns: Double {
        didSet { defaults.set(gridColumns, forKey: Key.gridColumns) }
    }

    /// Default grid rows for new tabs.
    @Published var gridRows: Double {
        didSet { defaults.set(gridRows, forKey: Key.gridRows) }
    }

    @Published var cornerRadius: Double {
        didSet { defaults.set(cornerRadius, forKey: Key.cornerRadius) }
    }

    /// Thickness (in points) of a tab pill measured perpendicular to its edge.
    @Published var tabThickness: Double {
        didSet { defaults.set(tabThickness, forKey: Key.tabThickness) }
    }

    /// Opacity an auto-faded tab dims to when idle (1 = no fade). Applied live to
    /// any tab whose concealment is `.fade` (and to auto-hide tabs that fall back
    /// to fading on a shared edge).
    @Published var fadedOpacity: Double {
        didSet { defaults.set(fadedOpacity, forKey: Key.fadedOpacity) }
    }

    /// Whether the tab pill shows its title text next to the glyph.
    @Published var showTabLabels: Bool {
        didSet { defaults.set(showTabLabels, forKey: Key.showTabLabels) }
    }

    @Published var newTabOpenOnHover: Bool {
        didSet { defaults.set(newTabOpenOnHover, forKey: Key.newTabOpenOnHover) }
    }

    @Published var newTabAutoHide: Bool {
        didSet { defaults.set(newTabAutoHide, forKey: Key.newTabAutoHide) }
    }

    /// Default idle concealment (auto-hide / auto-fade) for newly created tabs.
    @Published var newTabConcealment: TabConcealment {
        didSet { defaults.set(newTabConcealment.rawValue, forKey: Key.newTabConcealment) }
    }

    /// When the pointer reveals one idle (auto-hidden / auto-faded) tab, reveal every
    /// concealed tab at once — and re-hide them together when it leaves every reveal
    /// zone. Off by default, so each idle tab reveals on its own.
    @Published var revealAllConcealedTogether: Bool {
        didSet { defaults.set(revealAllConcealedTogether, forKey: Key.revealAllConcealedTogether) }
    }

    /// Launch an item on a single click (vs. requiring a double click).
    @Published var launchOnSingleClick: Bool {
        didSet { defaults.set(launchOnSingleClick, forKey: Key.launchOnSingleClick) }
    }

    /// Drawer open/close animation duration in milliseconds (0 = instant).
    @Published var animationMs: Double {
        didSet { defaults.set(animationMs, forKey: Key.animationMs) }
    }

    @Published var tabWindowLevel: TabWindowLevel {
        didSet { defaults.set(tabWindowLevel.rawValue, forKey: Key.tabWindowLevel) }
    }

    @Published var disconnectPolicy: DisconnectPolicy {
        didSet { defaults.set(disconnectPolicy.rawValue, forKey: Key.disconnectPolicy) }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            guard !isSyncingLaunchAtLogin else { return }
            applyLaunchAtLogin(launchAtLogin)
        }
    }

    /// New tabs inherit the current behavior defaults.
    var newTabBehavior: TabBehavior {
        TabBehavior(openOnHover: newTabOpenOnHover, autoHide: newTabAutoHide, concealment: newTabConcealment)
    }

    // MARK: Init

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        drawerTranslucency = DrawerTranslucency(rawValue: defaults.string(forKey: Key.drawerTranslucency) ?? "") ?? Default.drawerTranslucency
        defaultTabColorHex = Self.validColor(defaults.string(forKey: Key.defaultTabColorHex), default: Default.defaultTabColorHex)
        iconSize = Self.clamp(defaults.object(forKey: Key.iconSize) as? Double ?? Default.iconSize, 32, 128, Default.iconSize)
        tabStyle = TabStyle(rawValue: defaults.string(forKey: Key.tabStyle) ?? "") ?? Default.tabStyle
        gridColumns = Self.clamp(defaults.object(forKey: Key.gridColumns) as? Double ?? Default.gridColumns, 1, 12, Default.gridColumns)
        gridRows = Self.clamp(defaults.object(forKey: Key.gridRows) as? Double ?? Default.gridRows, 1, 16, Default.gridRows)
        cornerRadius = Self.clamp(defaults.object(forKey: Key.cornerRadius) as? Double ?? Default.cornerRadius, 0, 24, Default.cornerRadius)
        tabThickness = Self.clamp(defaults.object(forKey: Key.tabThickness) as? Double ?? Default.tabThickness, 24, 64, Default.tabThickness)
        fadedOpacity = Self.clamp(defaults.object(forKey: Key.fadedOpacity) as? Double ?? Default.fadedOpacity, 0.05, 0.9, Default.fadedOpacity)
        showTabLabels = defaults.object(forKey: Key.showTabLabels) as? Bool ?? Default.showTabLabels
        newTabOpenOnHover = defaults.object(forKey: Key.newTabOpenOnHover) as? Bool ?? Default.newTabOpenOnHover
        newTabAutoHide = defaults.object(forKey: Key.newTabAutoHide) as? Bool ?? Default.newTabAutoHide
        newTabConcealment = TabConcealment(rawValue: defaults.string(forKey: Key.newTabConcealment) ?? "") ?? Default.newTabConcealment
        revealAllConcealedTogether = defaults.object(forKey: Key.revealAllConcealedTogether) as? Bool ?? Default.revealAllConcealedTogether
        launchOnSingleClick = defaults.object(forKey: Key.launchOnSingleClick) as? Bool ?? Default.launchOnSingleClick
        animationMs = Self.clamp(defaults.object(forKey: Key.animationMs) as? Double ?? Default.animationMs, 0, 300, Default.animationMs)
        tabWindowLevel = TabWindowLevel(rawValue: defaults.string(forKey: Key.tabWindowLevel) ?? "") ?? Default.tabWindowLevel
        disconnectPolicy = DisconnectPolicy(rawValue: defaults.string(forKey: Key.disconnectPolicy) ?? "") ?? Default.disconnectPolicy

        launchAtLogin = Self.systemLaunchAtLoginEnabled()
            ?? (defaults.object(forKey: Key.launchAtLogin) as? Bool ?? false)
    }

    // MARK: Validation helpers

    /// Clamps `value` into `[lower, upper]`, falling back to `fallback` for
    /// non-finite (NaN/inf) input from corrupted defaults.
    private static func clamp(_ value: Double, _ lower: Double, _ upper: Double, _ fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return Swift.min(Swift.max(value, lower), upper)
    }

    /// Returns `hex` if it parses to a valid color, otherwise `default`.
    private static func validColor(_ hex: String?, default fallback: String) -> String {
        guard let hex, NSColor(hex: hex) != nil else { return fallback }
        return hex
    }

    /// The current login-item state from `SMAppService`, or `nil` if unavailable.
    private static func systemLaunchAtLoginEnabled() -> Bool? {
        guard #available(macOS 13.0, *) else { return nil }
        switch SMAppService.mainApp.status {
        case .enabled: return true
        case .notRegistered, .notFound: return false
        default: return nil
        }
    }

    // MARK: Launch at login

    /// Guards `launchAtLogin.didSet` against re-entrancy when we roll the toggle
    /// back after a failed `SMAppService` call.
    private var isSyncingLaunchAtLogin = false

    /// The most recent launch-at-login error, surfaced to Settings.
    @Published private(set) var launchAtLoginError: String?

    private func applyLaunchAtLogin(_ enabled: Bool) {
        guard #available(macOS 13.0, *) else { return }
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
            launchAtLoginError = nil
            defaults.set(enabled, forKey: Key.launchAtLogin)
        } catch {
            NSLog("Top Drawer: failed to update launch-at-login: \(error.localizedDescription)")
            launchAtLoginError = error.localizedDescription
            isSyncingLaunchAtLogin = true
            launchAtLogin = Self.systemLaunchAtLoginEnabled() ?? !enabled
            isSyncingLaunchAtLogin = false
            defaults.set(launchAtLogin, forKey: Key.launchAtLogin)
        }
    }

    /// Re-reads the authoritative login-item state (e.g. when Settings appears)
    /// so an external change in System Settings is reflected.
    func refreshLaunchAtLoginStatus() {
        guard let actual = Self.systemLaunchAtLoginEnabled(), actual != launchAtLogin else { return }
        isSyncingLaunchAtLogin = true
        launchAtLogin = actual
        isSyncingLaunchAtLogin = false
        defaults.set(actual, forKey: Key.launchAtLogin)
    }
}
