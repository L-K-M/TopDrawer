import Foundation

/// Per-tab appearance settings: how a drawer's items and the tab's own label
/// look. A pure value model — it names the choices and holds the numbers. The
/// `Preset` cases are named visual modes only; what they mean for translucency,
/// tab style and corner radius is resolved by the coordinator against the
/// global `Preferences`, which keeps this type free of AppKit.
///
/// Persisted on `Tab.appearance`. Decoding is lenient **per field** — a missing,
/// malformed, or newer-build value degrades to its `Default` while valid
/// siblings survive, so one bad field never costs the user the whole tab. See
/// `LenientDecoding`.
struct DrawerAppearance: Codable, Equatable {

    // MARK: Modes

    /// When item titles are visible in the drawer.
    enum TitleVisibility: String, Codable, CaseIterable, Identifiable {
        case always, onHover, never
        var id: Self { self }
        var displayName: String {
            switch self {
            case .always:  return "Always"
            case .onHover: return "On Hover"
            case .never:   return "Never"
            }
        }
    }

    /// Weight applied to item and tab label fonts.
    enum FontWeight: String, Codable, CaseIterable, Identifiable {
        case regular, medium, semibold, bold
        var id: Self { self }
        var displayName: String {
            switch self {
            case .regular:  return "Regular"
            case .medium:   return "Medium"
            case .semibold: return "Semibold"
            case .bold:     return "Bold"
            }
        }
    }

    /// How file extensions appear in item labels. `.system` leaves the stored
    /// name alone — the name already reflects the Finder show/hide setting from
    /// when the item was added; `.show` and `.hide` force the real extension on
    /// or off in `title(for:)`.
    enum FileExtensions: String, Codable, CaseIterable, Identifiable {
        case system, show, hide
        var id: Self { self }
        var displayName: String {
            switch self {
            case .system: return "System"
            case .show:   return "Show"
            case .hide:   return "Hide"
            }
        }
    }

    /// A named visual mode for the drawer. The model carries the choice only;
    /// `.system` follows the global appearance settings, and the concrete
    /// translucency/style/corner values behind `.glass`, `.flat` and
    /// `.highContrast` are resolved where the drawer is rendered.
    enum Preset: String, Codable, CaseIterable, Identifiable {
        case system, glass, flat, highContrast
        var id: Self { self }
        var displayName: String {
            switch self {
            case .system:       return "System"
            case .glass:        return "Glass"
            case .flat:         return "Flat"
            case .highContrast: return "High Contrast"
            }
        }
    }

    // MARK: Limits & defaults

    /// The valid range for `itemFontSize` and `tabFontSize`, in points. Enforced
    /// on init, assignment, and decode; also the bounds the Settings sliders use.
    static let fontSizeRange = 10.0...20.0

    /// Per-field defaults, named so the settings UI and tests read the same
    /// values instead of duplicating literals.
    enum Default {
        static let titleVisibility: TitleVisibility = .always
        static let itemFontSize = 12.0
        static let itemFontWeight: FontWeight = .regular
        static let tabFontSize = 12.0
        static let tabFontWeight: FontWeight = .semibold
        static let fileExtensions: FileExtensions = .system
        static let preset: Preset = .system
    }

    /// An appearance where every field holds its `Default`.
    static let `default` = DrawerAppearance()

    // MARK: Fields

    var titleVisibility: TitleVisibility

    /// Point size of item labels, clamped to `fontSizeRange`.
    var itemFontSize: Double {
        didSet {
            let clamped = Self.clamp(itemFontSize, fallback: Default.itemFontSize)
            if itemFontSize != clamped { itemFontSize = clamped }
        }
    }

    var itemFontWeight: FontWeight

    /// Point size of the tab pill's label, clamped to `fontSizeRange`.
    var tabFontSize: Double {
        didSet {
            let clamped = Self.clamp(tabFontSize, fallback: Default.tabFontSize)
            if tabFontSize != clamped { tabFontSize = clamped }
        }
    }

    var tabFontWeight: FontWeight
    var fileExtensions: FileExtensions
    var preset: Preset

    init(titleVisibility: TitleVisibility = Default.titleVisibility,
         itemFontSize: Double = Default.itemFontSize,
         itemFontWeight: FontWeight = Default.itemFontWeight,
         tabFontSize: Double = Default.tabFontSize,
         tabFontWeight: FontWeight = Default.tabFontWeight,
         fileExtensions: FileExtensions = Default.fileExtensions,
         preset: Preset = Default.preset) {
        self.titleVisibility = titleVisibility
        self.itemFontSize = Self.clamp(itemFontSize, fallback: Default.itemFontSize)
        self.itemFontWeight = itemFontWeight
        self.tabFontSize = Self.clamp(tabFontSize, fallback: Default.tabFontSize)
        self.tabFontWeight = tabFontWeight
        self.fileExtensions = fileExtensions
        self.preset = preset
    }

    /// Decodes forward-compatibly: each field degrades to its `Default` when
    /// missing, null, malformed, or an enum raw value written by a newer Top
    /// Drawer — matching how `Tab` protects its own fields. Sizes are clamped
    /// after decode so a persisted out-of-range value can't reach the UI.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        titleVisibility = c.decodeLenient(TitleVisibility.self, forKey: .titleVisibility,
                                          fallback: Default.titleVisibility)
        itemFontSize = Self.clamp(c.decodeLenient(Double.self, forKey: .itemFontSize,
                                                  fallback: Default.itemFontSize),
                                  fallback: Default.itemFontSize)
        itemFontWeight = c.decodeLenient(FontWeight.self, forKey: .itemFontWeight,
                                         fallback: Default.itemFontWeight)
        tabFontSize = Self.clamp(c.decodeLenient(Double.self, forKey: .tabFontSize,
                                                 fallback: Default.tabFontSize),
                                 fallback: Default.tabFontSize)
        tabFontWeight = c.decodeLenient(FontWeight.self, forKey: .tabFontWeight,
                                        fallback: Default.tabFontWeight)
        fileExtensions = c.decodeLenient(FileExtensions.self, forKey: .fileExtensions,
                                         fallback: Default.fileExtensions)
        preset = c.decodeLenient(Preset.self, forKey: .preset, fallback: Default.preset)
    }

    private enum CodingKeys: String, CodingKey {
        case titleVisibility, itemFontSize, itemFontWeight
        case tabFontSize, tabFontWeight, fileExtensions, preset
    }

    // MARK: Title formatting

    /// The item label to display, adjusting a **file** item's extension per
    /// `fileExtensions`. The adjustment applies only when `displayName` still
    /// matches the target's real name — its full `lastPathComponent` or the
    /// extension-stripped base — so a custom label, and every non-file kind
    /// (apps, folders, links, groups, …), is shown exactly as stored. `.hide`
    /// removes only the actual last suffix, so dotfiles keep their leading dot
    /// and "archive.tar.gz" becomes "archive.tar", never "archive". Pure: reads
    /// `item.url` only, never touching the filesystem.
    func title(for item: DrawerItem) -> String {
        guard item.kind == .file, let url = item.url else { return item.displayName }
        let fullName = url.lastPathComponent
        let baseName = url.deletingPathExtension().lastPathComponent
        guard item.displayName == fullName || item.displayName == baseName else {
            return item.displayName
        }
        switch fileExtensions {
        case .system: return item.displayName
        case .show:   return fullName
        case .hide:   return baseName
        }
    }

    /// Clamps a font size into `fontSizeRange`, substituting `fallback` for a
    /// non-finite input (NaN/±inf — not spellable in JSON, but reachable through
    /// `init` arguments and non-JSON decoders).
    private static func clamp(_ value: Double, fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return min(max(value, fontSizeRange.lowerBound), fontSizeRange.upperBound)
    }
}
