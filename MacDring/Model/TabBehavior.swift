import Foundation

/// Per-tab interaction behavior. The hover/auto-hide fields default to **following
/// the global defaults** in `Preferences` (`newTabOpenOnHover` / `newTabAutoHide`);
/// a tab can opt out and pin its own value via the `overrides…` flags (set in the
/// Tabs pane). This replaces the old "global toggle rewrites every tab" model — the
/// global setting is now a live default, overridable per tab. See ANALYSIS.md I3.
struct TabBehavior: Codable, Equatable {

    /// Open the drawer on hover instead of requiring a click. Honored only when
    /// `overridesOpenOnHover` is set; otherwise the global default wins (see
    /// `resolved(openOnHoverDefault:autoHideDefault:)`).
    var openOnHover: Bool

    /// Close the drawer automatically when focus leaves it. (Clicking outside or
    /// pressing Esc always closes it regardless.) Honored only when
    /// `overridesAutoHide` is set; otherwise the global default wins.
    var autoHide: Bool

    /// Keep the drawer open after launching an item instead of closing it.
    var keepOpenAfterLaunch: Bool

    /// How the tab's pill conceals itself when idle (Dock-style auto-hide /
    /// auto-fade), revealing on screen-edge hover. Distinct from `autoHide`, which
    /// governs the *drawer*. See `TabConcealment`.
    var concealment: TabConcealment

    /// When true, this tab uses its own `openOnHover` value; when false it follows
    /// the global default. Defaults to false ("follow global").
    var overridesOpenOnHover: Bool

    /// When true, this tab uses its own `autoHide` value; when false it follows the
    /// global default. Defaults to false ("follow global").
    var overridesAutoHide: Bool

    init(openOnHover: Bool = false, autoHide: Bool = true, keepOpenAfterLaunch: Bool = false,
         concealment: TabConcealment = .never,
         overridesOpenOnHover: Bool = false, overridesAutoHide: Bool = false) {
        self.openOnHover = openOnHover
        self.autoHide = autoHide
        self.keepOpenAfterLaunch = keepOpenAfterLaunch
        self.concealment = concealment
        self.overridesOpenOnHover = overridesOpenOnHover
        self.overridesAutoHide = overridesAutoHide
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        openOnHover = try c.decodeIfPresent(Bool.self, forKey: .openOnHover) ?? false
        autoHide = try c.decodeIfPresent(Bool.self, forKey: .autoHide) ?? true
        keepOpenAfterLaunch = try c.decodeIfPresent(Bool.self, forKey: .keepOpenAfterLaunch) ?? false
        // Lenient: a concealment mode added by a newer Top Drawer degrades to
        // `.never` instead of throwing the whole behavior (and with it the tab).
        concealment = c.decodeLenient(TabConcealment.self, forKey: .concealment, fallback: .never)
        // Older documents (no override keys) follow the global default — which, under
        // the old bulk-apply model, is the value those tabs already had.
        overridesOpenOnHover = try c.decodeIfPresent(Bool.self, forKey: .overridesOpenOnHover) ?? false
        overridesAutoHide = try c.decodeIfPresent(Bool.self, forKey: .overridesAutoHide) ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case openOnHover, autoHide, keepOpenAfterLaunch, concealment
        case overridesOpenOnHover, overridesAutoHide
    }

    /// The effective behavior for live use: fields this tab doesn't override fall
    /// back to the given global defaults. Pure, so it's unit-testable; the live
    /// defaults come from `Preferences.newTabOpenOnHover` / `newTabAutoHide`.
    func resolved(openOnHoverDefault: Bool, autoHideDefault: Bool) -> TabBehavior {
        var resolved = self
        if !overridesOpenOnHover { resolved.openOnHover = openOnHoverDefault }
        if !overridesAutoHide { resolved.autoHide = autoHideDefault }
        return resolved
    }

    static let `default` = TabBehavior()
}
